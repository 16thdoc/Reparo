#!/usr/bin/env sh
# Native Slicer is an explicit early platform boundary, never a maintenance lane.
set -eu
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
runtime="$repo/linux/reparo-linux"
temp_parent=$(CDPATH='' cd -- "${TMPDIR:-/tmp}" && pwd -P)
fixture=$(mktemp -d "$temp_parent/reparo-slicer-boundary.XXXXXXXXXX")
remove=$(command -v rm)
cleanup() {
    if [ "$(dirname -- "$fixture")" != "$temp_parent" ] || [ -L "$fixture" ]; then
        printf '%s\n' 'Refusing unexpected Slicer boundary fixture cleanup' >&2
        exit 1
    fi
    case "${fixture##*/}" in
        reparo-slicer-boundary.??????????) "$remove" -rf -- "$fixture" ;;
        *) printf '%s\n' 'Refusing unexpected Slicer boundary fixture cleanup' >&2; exit 1 ;;
    esac
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$fixture/tools" "$fixture/output" "$fixture/watched"
for directory in home data state cache temp localappdata programdata; do
    mkdir -p "$fixture/watched/$directory"
    printf '%s\n' 'KEEP EXACT: synthetic Slicer boundary fixture' >"$fixture/watched/$directory/keep.txt"
done

# These probes fail closed before any real privilege, transport, package, task,
# filesystem mutation or telemetry command could execute if rejection regresses.
for tool in sudo su doas curl wget gh gh.exe git ssh scp sftp pwsh pwsh.exe powershell powershell.exe \
    apt apt-get dnf pacman zypper flatpak snap fwupdmgr npm opencode pipx pnpm \
    yarn dotnet rustup conda gem composer crontab logger systemctl service \
    ps pgrep id whoami python python3 mkdir touch cp mv rm chmod; do
    cat >"$fixture/tools/$tool" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "${0##*/}" >>"$REPARO_SLICER_BOUNDARY_CALLS"
exit 91
EOF
    chmod +x "$fixture/tools/$tool"
done

snapshot() {
    find "$fixture/watched" -printf '%y %m %P %l\n' | LC_ALL=C sort
    find "$fixture/watched" -type f -exec sha256sum {} \; | LC_ALL=C sort
}
snapshot >"$fixture/before"
checks=0
check_rejected() {
    checks=$((checks+1))
    result=0
    env HOME="$fixture/watched/home" XDG_DATA_HOME="$fixture/watched/data" \
        XDG_STATE_HOME="$fixture/watched/state" XDG_CACHE_HOME="$fixture/watched/cache" \
        TMPDIR="$fixture/watched/temp" TEMP="$fixture/watched/temp" TMP="$fixture/watched/temp" \
        LOCALAPPDATA="$fixture/watched/localappdata" ProgramData="$fixture/watched/programdata" \
        GH_CONFIG_DIR="$fixture/watched/home/.gh" GH_TOKEN='' GITHUB_TOKEN='' \
        GH_PROMPT_DISABLED=1 GIT_TERMINAL_PROMPT=0 NO_COLOR=1 \
        REPARO_SLICER_BOUNDARY_CALLS="$fixture/calls" PATH="$fixture/tools:$PATH" \
        sh "$runtime" "$@" >"$fixture/output/$checks.stdout" 2>"$fixture/output/$checks.stderr" || result=$?
    if [ "$result" -ne 2 ]; then
        cat "$fixture/output/$checks.stdout" "$fixture/output/$checks.stderr" >&2
        printf '%s\n' "Slicer boundary case $checks did not reject with exit 2" >&2
        exit 1
    fi
    grep -F 'Slicer management is Windows-only' "$fixture/output/$checks.stderr" >/dev/null
    [ ! -s "$fixture/output/$checks.stdout" ] || { printf '%s\n' 'Slicer rejection entered a normal output lane' >&2; exit 1; }
    [ ! -e "$fixture/calls" ] || { cat "$fixture/calls" >&2; printf '%s\n' 'Slicer rejection invoked an operational boundary' >&2; exit 1; }
    snapshot >"$fixture/after"
    cmp "$fixture/before" "$fixture/after"
}

check_rejected --slicer Status
check_rejected -Slicer Check
check_rejected Slicer SelfTest
check_rejected --sLiCeR Install
check_rejected --SLICER Update
check_rejected --slicer
check_rejected --force --preview --slicer Update
check_rejected --new --slicer Repair
check_rejected --task daily 6am --slicer Status
check_rejected --include Slicer
check_rejected -Include sLiCeR
check_rejected Include Slicer
check_rejected --include Apt Slicer
check_rejected -C Npm SLICER
check_rejected c Slicer Npm
check_rejected --task daily --include Slicer
check_rejected --preview --include Slicer
printf '%s\n' "PASS: $checks native Slicer selector cases reject before maintenance/auth/cache, with unchanged isolated filesystem and no operational calls."
