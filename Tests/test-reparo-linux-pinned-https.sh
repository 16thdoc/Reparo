#!/usr/bin/env sh
# Real HTTPS release pilot, entirely disposable HOME/XDG and mocked cron.
set -eu
[ "${REPARO_NATIVE_HTTPS_PROBE:-0}" = 1 ] || exit 2
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/bin" "$fixture/home"
export HOME="$fixture/home" XDG_DATA_HOME="$fixture/data" XDG_STATE_HOME="$fixture/state" HTTPS_FIXTURE="$fixture"
unset REPARO_URL REPARO_INSTALLER_URL REPARO_RELEASE_FILE REPARO_RELEASE_URL
printf '%s\n' '7 7 * * * unrelated-command' >"$fixture/cron"
cat >"$fixture/bin/crontab" <<'EOF'
#!/usr/bin/env sh
if [ "$1" = -l ]; then cat "$HTTPS_FIXTURE/cron"; else cp "$1" "$HTTPS_FIXTURE/cron"; fi
EOF
chmod +x "$fixture/bin/crontab"
export PATH="$fixture/bin:$PATH"
sh "$repo/linux/reparo-linux" --new
cmp "$XDG_DATA_HOME/reparo/reparo-linux" "$repo/linux/reparo-linux"
"$HOME/.local/bin/reparo" --version
cp "$fixture/cron" "$fixture/first-cron"
"$HOME/.local/bin/reparo" --new
cmp "$XDG_DATA_HOME/reparo/reparo-linux" "$repo/linux/reparo-linux"
cmp "$fixture/cron" "$fixture/first-cron"
grep -Fx '7 7 * * * unrelated-command' "$fixture/cron"
printf '%s\n' 'Actual HTTPS pinned bootstrap/runtime install and installed-shim rerun passed; all install/cron state disposable. No maintenance executed.'
