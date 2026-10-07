#!/usr/bin/env sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/bin" "$fixture/home"
export HOME="$fixture/home" XDG_DATA_HOME="$fixture/data" XDG_STATE_HOME="$fixture/state"
export PIN_FIXTURE="$fixture" PIN_REPO="$repo"
unset REPARO_URL REPARO_INSTALLER_URL REPARO_RELEASE_FILE
python3 - "$fixture" "$repo" <<'PY'
import hashlib, json, pathlib, re, sys
f, r = map(pathlib.Path, sys.argv[1:])
version = re.search("REPARO_LINUX_VERSION='([^']+)'", (r/'linux/reparo-linux').read_text())[1]
base = 'https://raw.githubusercontent.com/16thdoc/Reparo/' + 'a'*40 + '/'
m = {'version': version, 'commit': 'a'*40}
for url, sha, path in [('linuxUrl', 'linuxSha256', 'linux/reparo-linux'), ('linuxInstallerUrl', 'linuxInstallerSha256', 'deploy/install-reparo-linux.sh')]:
    m[url] = base + path
    m[sha] = hashlib.sha256((r/path).read_bytes()).hexdigest().upper()
(f/'valid.json').write_text(json.dumps(m))
for label, key, value in [('bad-url', 'linuxUrl', base+'other'), ('bad-commit', 'commit', 'main'), ('bad-hash', 'linuxSha256', '0'*64), ('bad-installer-hash', 'linuxInstallerSha256', '0'*64), ('wrong-version', 'version', '9.9.9.9')]:
    changed = dict(m); changed[key] = value; (f/(label+'.json')).write_text(json.dumps(changed))
(f/'duplicate.json').write_text(json.dumps(m)[:-1]+', "version": "1.0.0.0"}')
(f/'oversize.json').write_text(' '*16385)
PY
cat >"$fixture/bin/curl" <<'EOF'
#!/usr/bin/env sh
url=''; output=''
while [ "$#" -gt 0 ]; do
    case "$1" in -o) output=$2; shift 2 ;; https://*) url=$1; shift ;; *) shift ;; esac
done
case "$url" in
    */reparo-release.json) cp "$PIN_FIXTURE/${PIN_CASE:-valid}.json" "$output" ;;
    */install-reparo-linux.sh) cp "$PIN_REPO/deploy/install-reparo-linux.sh" "$output" ;;
    */reparo-linux*) cp "$PIN_REPO/linux/reparo-linux" "$output" ;;
    *) exit 1 ;;
esac
EOF
cat >"$fixture/bin/crontab" <<'EOF'
#!/usr/bin/env sh
if [ "$1" = -l ]; then cat "$PIN_FIXTURE/cron"; else cp "$1" "$PIN_FIXTURE/cron"; fi
EOF
chmod +x "$fixture/bin/curl" "$fixture/bin/crontab"
export PATH="$fixture/bin:$PATH"
printf '%s\n' '7 7 * * * unrelated-command' >"$fixture/cron"
sh "$repo/linux/reparo-linux" --new
cmp "$XDG_DATA_HOME/reparo/reparo-linux" "$repo/linux/reparo-linux"
cp "$fixture/cron" "$fixture/good-cron"
for bad in bad-url bad-commit bad-hash bad-installer-hash wrong-version duplicate oversize; do
    if PIN_CASE="$bad" sh "$repo/linux/reparo-linux" --new; then echo "Accepted invalid release: $bad" >&2; exit 1; fi
    cmp "$XDG_DATA_HOME/reparo/reparo-linux" "$repo/linux/reparo-linux"
    cmp "$fixture/cron" "$fixture/good-cron"
done
for bad in bad-url bad-commit bad-hash wrong-version duplicate oversize; do
    if PIN_CASE="$bad" sh "$repo/deploy/install-reparo-linux.sh" --verbose; then echo "Installer accepted invalid release: $bad" >&2; exit 1; fi
    cmp "$fixture/cron" "$fixture/good-cron"
done
sh "$repo/linux/reparo-linux" --latest
if sh "$repo/linux/reparo-linux" --task daily 5am --latest --preview; then echo 'Scheduled Latest accepted' >&2; exit 1; fi
printf '%s\n' 'Immutable native bootstrap/runtime pins, invalid manifests/digests/version, latest and preserved runtime/cron passed (isolated fixtures).'
