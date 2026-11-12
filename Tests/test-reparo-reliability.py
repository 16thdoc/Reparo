"""Execute only fake managers in disposable HOME/XDG/TEMP roots.

Runs on native Linux CI; --shell also permits an explicitly labeled MSYS check.
No installer, distribution, network, service or real manager is touched.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
SHELL = "/bin/sh"


class NativeReceipts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="reparo-reliability-")
        self.root = Path(self.temp.name)
        self.tools = self.root / "bin"
        self.tools.mkdir()
        self.env = dict(os.environ, HOME=str(self.root / "home"),
                        XDG_DATA_HOME=str(self.root / "data"),
                        XDG_STATE_HOME=str(self.root / "state"),
                        TMPDIR=str(self.root / "tmp"), NO_COLOR="1",
                        REPARO_REPORT_SKIP="1", REPARO_FAULT="",
                        REPARO_SENTINEL=str(self.root / "calls"))
        for folder in ("home", "tmp"):
            (self.root / folder).mkdir()
        self.env["PATH"] = str(self.tools) + os.pathsep + os.environ["PATH"]
        # On Windows/MSYS, PATH and argv conversion belongs to bash. Feed the
        # prepend as a shell assignment rather than a Windows PATH delimiter.
        self.write("apt-get", '''printf '%s\n' "$*" >>"$REPARO_SENTINEL"
printf '%s\n' 'fixture manager stdout'
printf '%s\n' 'fixture warning only' >&2
case "$*:$REPARO_FAULT" in *upgrade:command) exit 37 ;; esac
exit 0
''')
        self.write("sudo", '''case "${1-}" in -n) shift ;; esac
case "${1-}" in -l) exit 0 ;; esac
exec "$@"
''')
        self.write("logger", "exit 0\n")
        self.write("dpkg-query", "printf 'fixture-package\\t1.0\\n'\n")
        # Every other mutation entry point is a hard-failing sentinel.
        for tool in ("dnf", "pacman", "zypper", "flatpak", "snap", "fwupdmgr", "npm", "opencode", "pipx", "pnpm", "yarn", "dotnet", "rustup", "conda", "gem", "composer"):
            self.write(tool, "printf 'UNEXPECTED %s\\n' \"$0\" >>\"$REPARO_SENTINEL\"; exit 99\n")
        for tool, fault in (("tee", "tee"), ("mv", "mv"), ("mktemp", "mktemp")):
            actual = self.shell_output(f"command -v {tool}")
            condition = '[ "$REPARO_FAULT" = "' + fault + '" ]'
            if tool == "mktemp":
                condition += ' && case "$*" in *stdout*) true ;; *) false ;; esac'
            self.write(tool, f"if {condition}; then exit 73; fi\nexec '{actual}' \"$@\"\n")
        if os.name == "nt":
            executable = str(Path(sys.executable)).replace("\\", "/")
            self.write("python3", f"exec '{executable}' \"$@\"\n")

    def shell_output(self, command):
        return subprocess.check_output([SHELL, "-c", command], text=True).strip()

    def write(self, name, content):
        path = self.tools / name
        path.write_text("#!/usr/bin/env sh\n" + content, encoding="utf-8", newline="\n")
        path.chmod(0o755)

    def tearDown(self):
        self.temp.cleanup()

    def run_fixture(self, fault=""):
        self.env["REPARO_FAULT"] = fault
        # The wrapper invokes sh explicitly and quotes every path as an argv.
        setup = 'tools=$2; if command -v cygpath >/dev/null 2>&1; then tools=$(cygpath -u "$tools"); fi; PATH="$tools:$PATH"; export PATH; sh "$1/linux/reparo-linux" --include Apt'
        result = subprocess.run([SHELL, "-c", setup, "fixture", str(REPO).replace("\\", "/"), str(self.tools).replace("\\", "/")],
                                env=self.env, text=True, capture_output=True, timeout=45)
        receipts = list((self.root / "state").rglob("*_repair.json"))
        self.assertEqual(len(receipts), 1, result.stdout + result.stderr)
        view = json.loads(receipts[0].read_text(encoding="utf-8"))
        self.assertIn("REPARO-REPAIR-HANDOFF/1", result.stdout)
        self.assertNotIn("UNEXPECTED", (self.root / "calls").read_text() if (self.root / "calls").exists() else "")
        return result, view

    def test_partial_failure_preserves_prior_command(self):
        process, view = self.run_fixture("command")
        self.assertEqual(process.returncode, 1)
        codes = [x["exit_code"] for x in view["commands"].values()]
        self.assertEqual(sorted(codes), [0, 37])
        self.assertEqual(view["counts"]["failed"], 1)
        self.assertEqual(view["counts"]["command_success"], 1)
        self.assertEqual(view["counts"]["confirmed_changes"], 0)
        self.assertIsNone(view["parent"]["exit_code"])
        self.assertIn("FAILED", view["parent"]["reported_status"])

    def test_warning_only_success(self):
        process, view = self.run_fixture()
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertEqual(view["counts"]["command_success"], 3)
        self.assertEqual(view["counts"]["failed"], 0)
        self.assertEqual(view["counts"]["confirmed_changes"], 0)

    def test_tee_failure_does_not_change_child_exit(self):
        process, view = self.run_fixture("tee")
        self.assertEqual(process.returncode, 0)
        self.assertGreater(view["counts"]["evidence_gaps"], 0)
        self.assertTrue(all(c["exit_code"] == 0 for c in view["commands"].values()))
        self.assertFalse(view["finality"]["settled"])

    def test_temporary_spool_failure_blocks_launch(self):
        process, view = self.run_fixture("mktemp")
        self.assertEqual(process.returncode, 1)
        self.assertTrue(all(c["exit_code"] is None for c in view["commands"].values()))
        self.assertFalse((self.root / "calls").exists())

    def test_terminal_log_rename_failure_is_honest(self):
        process, view = self.run_fixture("mv")
        self.assertEqual(process.returncode, 0)
        self.assertGreater(view["counts"]["evidence_gaps"], 0)
        self.assertIn("retained working log", process.stderr)
        self.assertTrue(list((self.root / "state").rglob("*_RUNNING.log")))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--shell", default="/bin/sh")
    args, remainder = parser.parse_known_args()
    SHELL = args.shell
    unittest.main(argv=[sys.argv[0]] + remainder)
