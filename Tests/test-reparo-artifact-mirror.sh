#!/usr/bin/env sh
# Public artifact routing with real installer code, mocked HTTPS/cron and disposable state.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
python3 - "$repo" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1])
runtime = (repo / 'linux/reparo-linux').read_bytes()
installer = (repo / 'deploy/install-reparo-linux.sh').read_bytes()
version = re.search(rb"^REPARO_LINUX_VERSION='([^']+)'$", runtime, re.M)[1].decode()
commit = 'a' * 40
github = 'https://raw.githubusercontent.com/16thdoc/Reparo/'
mirror = 'https://file.thetechnologist.io/reparo/' + commit + '/'
ua_install = 'Reparo-Download/Linux/Install'
ua_update = 'Reparo-Download/Linux/Update'
original_cron = b'7 7 * * * unrelated-command\n'
cases = 0

curl_stub = r'''#!/usr/bin/env python3
import json, os
from pathlib import Path
import sys
a = sys.argv[1:]; url = ''; out = ''; ua = ''
while a:
    item = a.pop(0)
    if item == '-o': out = a.pop(0)
    elif item in ('-A', '--user-agent'): ua = a.pop(0)
    elif item in ('--proto', '--proto-redir', '--connect-timeout', '--max-time', '-H'): a.pop(0)
    elif item.startswith('https://'): url = item
root = Path(os.environ['MIRROR_TEST_ROOT'])
with (root/'requests.jsonl').open('a') as log: log.write(json.dumps({'url':url, 'ua':ua})+'\n')
if url.endswith('/deploy/reparo-release.json'):
    Path(out).write_bytes((root/'release.json').read_bytes()); sys.exit(0)
is_mirror = url.startswith('https://file.thetechnologist.io/')
if is_mirror and os.environ.get('MIRROR_TEST_ERROR'): sys.exit(int(os.environ['MIRROR_TEST_ERROR']))
if is_mirror and os.environ.get('MIRROR_TEST_TAMPER') and url.endswith(os.environ['MIRROR_TEST_TAMPER']):
    Path(out).write_bytes(b'not the reviewed artifact\n'); sys.exit(0)
if url.endswith('/install-reparo-linux.sh') or url == 'https://custom.invalid/installer':
    Path(out).write_bytes((root/'installer-payload').read_bytes()); sys.exit(0)
if '/reparo-linux' in url or url == 'https://custom.invalid/runtime':
    Path(out).write_bytes((root/'runtime-payload').read_bytes()); sys.exit(0)
raise SystemExit('Unexpected fixture request: '+url)
'''
cron_stub = '''#!/usr/bin/env sh
if [ "$1" = -l ]; then cat "$MIRROR_TEST_ROOT/cron"; else cp "$1" "$MIRROR_TEST_ROOT/cron"; fi
'''


def run(label, entry='new', error=None, tamper=None, invalid=None, payload=None,
        installer_payload=None, success=True, source=None, offline=False, latest=False):
    global cases
    with tempfile.TemporaryDirectory(prefix='reparo-mirror-') as folder:
        root = Path(folder)
        (root/'bin').mkdir(); (root/'home').mkdir()
        (root/'tmp').mkdir()
        (root/'runtime-payload').write_bytes(payload if payload is not None else runtime)
        (root/'installer-payload').write_bytes(installer_payload if installer_payload is not None else installer)
        manifest = {
            'version':version, 'commit':commit,
            'reparoUrl':github+commit+'/Reparo.ps1', 'sha256':'A'*64,
            'linuxUrl':github+commit+'/linux/reparo-linux',
            'linuxSha256':hashlib.sha256((root/'runtime-payload').read_bytes()).hexdigest().upper(),
            'linuxInstallerUrl':github+commit+'/deploy/install-reparo-linux.sh',
            'linuxInstallerSha256':hashlib.sha256((root/'installer-payload').read_bytes()).hexdigest().upper(),
        }
        if invalid:
            manifest[invalid] = 'https://attacker.invalid/' + commit + '/reparo-linux'
        (root/'release.json').write_text(json.dumps(manifest))
        (root/'cron').write_bytes(original_cron)
        for name, content in [('curl',curl_stub), ('crontab',cron_stub)]:
            path = root/'bin'/name
            path.write_text(content); path.chmod(0o755)
        env = {k:v for k,v in os.environ.items() if not k.startswith('REPARO_')}
        env.update(HOME=str(root/'home'), XDG_DATA_HOME=str(root/'data'),
                   XDG_STATE_HOME=str(root/'state'), TMPDIR=str(root/'tmp'),
                   PATH=str(root/'bin')+os.pathsep+env['PATH'], MIRROR_TEST_ROOT=str(root),
                   REPARO_REPORT_SKIP='1')
        if error: env['MIRROR_TEST_ERROR'] = str(error)
        if tamper: env['MIRROR_TEST_TAMPER'] = tamper
        if source:
            env['REPARO_URL' if entry == 'install' else 'REPARO_INSTALLER_URL'] = source
        if offline: env['REPARO_RELEASE_FILE'] = str(root/'release.json')
        installed = root/'data/reparo/reparo-linux'
        shim = root/'home/.local/bin/reparo'
        if not success:
            installed.parent.mkdir(parents=True); installed.write_bytes(b'preserved-runtime\n')
            shim.parent.mkdir(parents=True); shim.write_bytes(b'preserved-shim\n')
        script = repo/('deploy/install-reparo-linux.sh' if entry == 'install' else 'linux/reparo-linux')
        args = ['--verbose'] if entry == 'install' else ['--new']
        if latest: args = ['--verbose','--latest'] if entry == 'install' else ['--latest']
        result = subprocess.run(['sh', str(script), *args], env=env, capture_output=True, text=True)
        output = result.stdout + result.stderr
        assert (result.returncode == 0) == success, (label, result.returncode, output[-4000:])
        requests = [json.loads(line) for line in (root/'requests.jsonl').read_text().splitlines()]
        artifacts = [q for q in requests if not q['url'].endswith('/deploy/reparo-release.json')]
        if success:
            assert installed.read_bytes() == (root/'runtime-payload').read_bytes(), label
            assert original_cron in (root/'cron').read_bytes(), label
            assert (root/'cron').read_text().count('# Reparo self-update task') == 1, label
        else:
            assert installed.read_bytes() == b'preserved-runtime\n', label
            assert shim.read_bytes() == b'preserved-shim\n', label
            assert (root/'cron').read_bytes() == original_cron, label
        if invalid:
            assert not artifacts, (label, artifacts)
        elif source or latest:
            assert not any(q['url'].startswith(mirror) for q in requests), (label, requests)
            assert not any(q['url'].endswith('/deploy/reparo-release.json') for q in requests), label
        else:
            expected_first = mirror + ('reparo-linux' if entry == 'install' else 'install-reparo-linux.sh')
            assert artifacts[0]['url'] == expected_first, (label, artifacts)
            assert artifacts[0]['ua'] == (ua_install if entry == 'install' else ua_update), label
            assert all(q['url'].startswith(mirror) or q['url'].startswith(github+commit+'/') for q in artifacts), (label, artifacts)
            assert all(q['ua'] == (ua_update if q['url'].endswith('/install-reparo-linux.sh') else ua_install) for q in artifacts), (label, artifacts)
            if error in (7,22):
                expected_fallback = github+commit+('/linux/reparo-linux' if entry == 'install' else '/deploy/install-reparo-linux.sh')
                assert artifacts[1]['url'] == expected_fallback, (label, artifacts)
                assert 'download observation omitted' in output, label
            else:
                assert not any(q['url'].startswith(github) for q in artifacts), (label, artifacts)
            if offline:
                assert not any(q['url'].endswith('/deploy/reparo-release.json') for q in requests), label
            elif entry == 'new' and success:
                # The downloaded installer must reuse the exact validated snapshot.
                assert sum(q['url'].endswith('/deploy/reparo-release.json') for q in requests) == 1, label
        cases += 1
        print('PASS '+label)


run('self-update uses both commit-bound mirror artifacts')
run('first installer uses commit-bound runtime mirror', entry='install')
run('offline validated snapshot is reused', entry='install', offline=True)
for entry in ('new','install'):
    for code in (7,22):
        run(entry+' exact immutable GitHub availability fallback '+str(code), entry=entry, error=code)
    run(entry+' local write error never falls back', entry=entry, error=23, success=False)
    run(entry+' rejects manifest artifact host', entry=entry,
        invalid='linuxInstallerUrl' if entry == 'new' else 'linuxUrl', success=False)
    run(entry+' rejects mirror hash mismatch without fallback', entry=entry,
        tamper='install-reparo-linux.sh' if entry == 'new' else 'reparo-linux', success=False)
run('nested runtime hash mismatch never falls back', tamper='reparo-linux', success=False)
run('matching hash cannot bypass runtime shell syntax', entry='install',
    payload=b'#!/bin/sh\nREPARO_LINUX_VERSION=\''+version.encode()+b'\'\nif\n', success=False)
run('matching hash cannot bypass runtime version', entry='install',
    payload=runtime.replace(("REPARO_LINUX_VERSION='"+version+"'").encode(), b"REPARO_LINUX_VERSION='9.9.9.9'",1), success=False)
run('matching hash cannot bypass installer shell syntax',
    installer_payload=b'#!/bin/sh\nif\n', success=False)
run('explicit custom installer is unchanged', source='https://custom.invalid/installer')
run('explicit custom runtime is unchanged', entry='install', source='https://custom.invalid/runtime')
run('latest self-update remains explicitly unpinned', latest=True)
run('latest installer remains explicitly unpinned', entry='install', latest=True)
print(str(cases)+' isolated artifact mirror cases passed; no real network, host installation, cron, or maintenance.')
PY
