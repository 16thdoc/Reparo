"""Execute the shipped POSIX cleanup guard against an isolated proc fixture.

No WSL distribution, package manager or host process is started/stopped by this test.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / 'Reparo.ps1').read_text(encoding='utf-8-sig')
snapshot = re.search(r'function Get-ReparoWslProcessSnapshotScript.*?@\x27\n(.*?)\n\x27@', source, re.S)[1]
probe = re.search(r'function Complete-ReparoWslDistro.*?\+ @\x27\n(.*?)\n\x27@', source, re.S)[1]
shell = os.environ.get('REPARO_TEST_SH', '/bin/sh')
with tempfile.TemporaryDirectory(prefix='reparo-wsl-guard-') as tmp:
    root = Path(tmp)
    proc = root / 'proc'
    proc.mkdir()
    # Git Bash accepts C:/ paths; Linux uses the same POSIX spelling here.
    proc_path = proc.as_posix()
    baseline = (root / 'baseline').as_posix()
    snapshot = snapshot.replace('/proc/[0-9]*/stat', f"'{proc_path}'/[0-9]*/stat")
    probe = probe.replace('BASELINE', f"'{baseline}'").replace('"/proc/$pid"', f'"{proc_path}/$pid"')

    def process(pid, start):
        d = proc / str(pid)
        d.mkdir(exist_ok=True)
        # Real proc stat layout, including a comm field with spaces and parentheses.
        fields = ['S', '1'] + ['0'] * 17 + [str(start)] + ['0'] * 8
        (d / 'stat').write_text(f'{pid} (fixture (worker)) ' + ' '.join(fields) + '\n')

    def run(command):
        return subprocess.run([shell, '-c', command], capture_output=True, text=True)

    def save_baseline():
        result = run(snapshot + f"\nsnapshot > '{baseline}'")
        assert result.returncode == 0, result.stderr

    process(900001, 123)
    save_baseline()
    assert Path(baseline).read_text().strip() == '900001:123', 'PID/start-time parsing failed'
    result = run(snapshot + '\n' + probe)
    assert result.returncode == 0, result.stderr
    assert not Path(baseline).exists(), 'Successful guard leaked its baseline'

    save_baseline()
    process(900002, 456)
    assert run(snapshot + '\n' + probe).returncode == 3, 'New workload was not protected'
    (proc / '900002' / 'stat').unlink()
    (proc / '900002').rmdir()

    save_baseline()
    process(900001, 789)
    assert run(snapshot + '\n' + probe).returncode == 3, 'PID reuse hid a new workload'
    assert run(snapshot + '\n' + probe).returncode == 4, 'Missing ownership baseline was accepted'
print('Shipped WSL cleanup shell: idle, new workload, PID reuse, missing baseline and artifact cleanup passed.')
