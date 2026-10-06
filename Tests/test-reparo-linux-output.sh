#!/usr/bin/env sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
runtime="$repo/linux/reparo-linux"
esc=$(printf '\033')
NO_COLOR=1 XDG_STATE_HOME="$fixture/state" sh "$runtime" --preview --include Npm >"$fixture/plain"
if grep -F "$esc" "$fixture/plain"; then echo 'ANSI in redirected/no-color output' >&2; exit 1; fi
if command -v script >/dev/null 2>&1; then
    script -q -e -c "env -u NO_COLOR TERM=xterm XDG_STATE_HOME='$fixture/state' sh '$runtime' --preview --include Npm" /dev/null >"$fixture/interactive"
    grep -F "${esc}[31mNpm" "$fixture/interactive" >/dev/null || { cat "$fixture/interactive"; echo 'Missing interactive red package/section name' >&2; exit 1; }
    script -q -e -c "env NO_COLOR=1 TERM=xterm XDG_STATE_HOME='$fixture/state' sh '$runtime' --preview --include Npm" /dev/null >"$fixture/no-color"
    if grep -F "$esc" "$fixture/no-color"; then echo 'NO_COLOR ignored in PTY' >&2; exit 1; fi
fi
if grep -r -F "$esc" "$fixture/state"; then echo 'ANSI leaked into logs' >&2; exit 1; fi
printf '%s\n' 'Native interactive red emphasis, PTY NO_COLOR, redirected output and plain logs passed.'
