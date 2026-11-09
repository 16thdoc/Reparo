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
# Force must retain an explicit dry-run. Fake every maintenance entry point so
# this regression cannot run a real package manager if preview ever regresses.
mkdir -p "$fixture/tools"
for tool in apt-get dnf pacman zypper flatpak snap fwupdmgr npm opencode pipx pnpm yarn dotnet rustup conda gem composer; do
    cat >"$fixture/tools/$tool" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$0 $*" >>"$REPARO_PREVIEW_SENTINEL"
exit 91
EOF
    chmod +x "$fixture/tools/$tool"
done
NO_COLOR=1 REPARO_PREVIEW_SENTINEL="$fixture/executed" PATH="$fixture/tools:$PATH" XDG_STATE_HOME="$fixture/force-state" sh "$runtime" --force --preview >"$fixture/force-preview"
grep -F 'force=1 preview=1' "$fixture/force-preview" >/dev/null
grep -F '[DRY-RUN]' "$fixture/force-preview" >/dev/null
if [ -e "$fixture/executed" ]; then cat "$fixture/executed"; echo 'Force preview executed a maintenance tool' >&2; exit 1; fi
printf '%s\n' 'Native interactive red emphasis, PTY NO_COLOR, redirected output and plain logs passed.'
