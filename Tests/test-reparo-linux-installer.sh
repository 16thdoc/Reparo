#!/usr/bin/env sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/bin"
export HOME="$fixture/home's \"quoted\" space" XDG_DATA_HOME="$fixture/data's \"quoted\" space" XDG_STATE_HOME="$fixture/state"
export FIXTURE_NATIVE_SOURCE="$repo/linux/reparo-linux" FIXTURE_INSTALL_CRON="$fixture/crontab"
export REPARO_URL='https://fixture.invalid/custom-runtime'
printf '%s\n' '7 7 * * * unrelated-command' '8 8 * * * echo protected # Reparo self-update task extra' >"$FIXTURE_INSTALL_CRON"
cp "$FIXTURE_INSTALL_CRON" "$fixture/original"
cat >"$fixture/bin/curl" <<'EOF'
#!/usr/bin/env sh
while [ "$#" -gt 0 ]; do case "$1" in -o) output=$2; shift 2 ;; *) shift ;; esac; done
cp "$FIXTURE_NATIVE_SOURCE" "$output"
EOF
cat >"$fixture/bin/crontab" <<'EOF'
#!/usr/bin/env sh
if [ "${1:-}" = -l ]; then
    if [ "${FIXTURE_INSTALL_READ_FAILURE:-0}" = 1 ]; then printf '%s\n' 'permission denied' >&2; exit 2; fi
    cat "$FIXTURE_INSTALL_CRON"
else
    [ "${FIXTURE_INSTALL_WRITE_FAILURE:-0}" = 0 ] || exit 1
    cp "$1" "$FIXTURE_INSTALL_CRON"
fi
EOF
chmod +x "$fixture/bin/curl" "$fixture/bin/crontab"
export PATH="$fixture/bin:$PATH"
installer="$repo/deploy/install-reparo-linux.sh"
if FIXTURE_INSTALL_READ_FAILURE=1 sh "$installer" --verbose; then echo 'Installer accepted unknown crontab state' >&2; exit 1; fi
[ ! -f "$XDG_DATA_HOME/reparo/reparo-linux" ]
cmp "$FIXTURE_INSTALL_CRON" "$fixture/original"
sh "$installer" --verbose
"$HOME/.local/bin/reparo" --version
grep -q 'echo protected # Reparo self-update task extra' "$FIXTURE_INSTALL_CRON"
cp "$FIXTURE_INSTALL_CRON" "$fixture/installed-cron"
cp "$XDG_DATA_HOME/reparo/reparo-linux" "$fixture/installed-runtime"
sh "$installer" --verbose
cmp "$FIXTURE_INSTALL_CRON" "$fixture/installed-cron"
printf '%s\n' '#!/usr/bin/env sh' "REPARO_LINUX_VERSION='1.4.1.2'" 'exit 1' >"$fixture/broken-runtime"
if FIXTURE_NATIVE_SOURCE="$fixture/broken-runtime" sh "$installer" --verbose; then echo 'Broken candidate accepted' >&2; exit 1; fi
cmp "$XDG_DATA_HOME/reparo/reparo-linux" "$fixture/installed-runtime"
cmp "$FIXTURE_INSTALL_CRON" "$fixture/installed-cron"
if FIXTURE_INSTALL_WRITE_FAILURE=1 sh "$installer" --verbose; then echo 'Installer falsely succeeded without scheduling' >&2; exit 1; fi
cmp "$FIXTURE_INSTALL_CRON" "$fixture/installed-cron"
if HOME="$fixture/unsafe%home" sh "$installer" --verbose; then echo 'Unsafe cron shim path accepted' >&2; exit 1; fi
printf '%s\n' 'Native installer quoted paths, reruns, rollback, read/write failure and unrelated-cron preservation passed; all state isolated/mocked.'
