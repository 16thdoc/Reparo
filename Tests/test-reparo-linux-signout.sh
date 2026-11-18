#!/usr/bin/env sh
# SignOut is a Windows desktop-session action. Every native spelling must fail
# before maintenance, log creation or cron registration, including after --task.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
runtime="$repo/linux/reparo-linux"
index=0
mkdir -p "$fixture/tools"
# Keep the regression harmless even if a future parser accidentally reaches a
# maintenance, schedule or sign-out path. Every mutating boundary is a sentinel.
for tool in apt-get dnf pacman zypper flatpak snap fwupdmgr npm opencode pipx pnpm yarn dotnet rustup conda gem composer sudo crontab shutdown logoff loginctl; do
    cat >"$fixture/tools/$tool" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$0 $*" >>"$REPARO_SIGNOUT_SENTINEL"
exit 91
EOF
    chmod +x "$fixture/tools/$tool"
done

assert_windows_only() {
    index=$((index + 1))
    state="$fixture/state-$index"
    result=0
    REPARO_SIGNOUT_SENTINEL="$fixture/executed" PATH="$fixture/tools:$PATH" \
        XDG_STATE_HOME="$state" XDG_DATA_HOME="$fixture/data-$index" \
        sh "$runtime" "$@" >"$fixture/output-$index" 2>&1 || result=$?
    if [ "$result" -ne 2 ]; then
        cat "$fixture/output-$index"
        printf '%s\n' "Expected native Windows-only rejection for: $*" >&2
        exit 1
    fi
    grep -F 'Windows-only' "$fixture/output-$index" >/dev/null || {
        cat "$fixture/output-$index"
        printf '%s\n' "Missing explicit platform boundary for: $*" >&2
        exit 1
    }
    if [ -e "$fixture/executed" ]; then
        cat "$fixture/executed"
        printf '%s\n' "SignOut reached an execution boundary: $*" >&2
        exit 1
    fi
    if [ -e "$state" ] || [ -e "$fixture/data-$index" ]; then
        printf '%s\n' "SignOut created native state before rejection: $*" >&2
        exit 1
    fi
}

assert_windows_only --signout
assert_windows_only -SignOut
assert_windows_only SignOut
assert_windows_only --SIGNOUT
assert_windows_only --force --signout
assert_windows_only --preview --force -SignOut
assert_windows_only --task daily 6am --signout
assert_windows_only --task daily 6am SignOut
assert_windows_only --help --signout

printf '%s\n' "Native SignOut Windows-only boundary passed ($index cases); no maintenance, state or schedule created."
