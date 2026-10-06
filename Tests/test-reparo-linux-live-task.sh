#!/usr/bin/env sh
# Explicit opt-in: real user crontab management, no maintenance or power commands.
set -eu
[ "${REPARO_NATIVE_LIVE_PROBE:-0}" = 1 ] || { printf '%s\n' 'Set REPARO_NATIVE_LIVE_PROBE=1 for this disposable real-crontab probe.' >&2; exit 2; }
command -v crontab >/dev/null
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_runtime="$repo/linux/reparo-linux"
fixture=$(mktemp -d)
runtime="$fixture/probe-runtime.sh"
# Schedule against a private runtime copy that exits before ALL maintenance.
# Utility/task branches still use the actual scheduler code unchanged.
sed '/^ensure_log_root$/i\
printf "%s\\n" "No-maintenance cron probe worker."\
exit 0
' "$source_runtime" >"$runtime"
sh -n "$runtime"
name="live-probe-$$-$(date +%s)"
created=0
cleanup() {
    if [ "$created" = 1 ]; then
        if LC_ALL=C crontab -l >"$fixture/cleanup-state" 2>"$fixture/cleanup-read-error"; then :
        elif grep -Eq '^(no crontab for|crontab: no crontab for) ' "$fixture/cleanup-read-error"; then : >"$fixture/cleanup-state"
        else printf '%s\n' "WARNING: cleanup state unreadable; private runtime retained at $fixture." >&2; return; fi
        if grep -q "# Reparo managed task v2:$name$" "$fixture/cleanup-state"; then
            XDG_STATE_HOME="$fixture/state" sh "$runtime" --task --task-name "$name" --task-action remove >"$fixture/cleanup.log" 2>&1 || { printf '%s\n' "WARNING: owned probe $name needs cleanup; private runtime retained at $fixture." >&2; return; }
        fi
    fi
    rm -rf "$fixture"
}
trap cleanup EXIT HUP INT TERM
umask 077
if LC_ALL=C crontab -l >"$fixture/before" 2>"$fixture/read-error"; then :
elif grep -Eq '^(no crontab for|crontab: no crontab for) ' "$fixture/read-error"; then : >"$fixture/before"
else printf '%s\n' 'Existing crontab unreadable; probe aborted.' >&2; exit 1; fi
export XDG_STATE_HOME="$fixture/state" NO_COLOR=1
created=1
# Day 31 is future for this pilot; the private worker cannot perform maintenance.
sh "$runtime" --task '31st at 23:59' --task-name "$name" --include Npm
sh "$runtime" --task --task-name "$name" --task-action show
sh "$runtime" --task --task-name "$name" --task-action disable
LC_ALL=C crontab -l | grep -q "^# DISABLED .*# Reparo managed task v2:$name$"
sh "$runtime" --task --task-name "$name" --task-action enable
sh "$runtime" --task --task-name "$name" --task-action remove
created=0
LC_ALL=C crontab -l >"$fixture/after"
if ! cmp -s "$fixture/before" "$fixture/after"; then printf '%s\n' 'Unrelated cron changed concurrently; preserved as found, not overwritten with a snapshot.' >&2; exit 1; fi
printf '%s\n' 'Real current-user cron create/show/disable/enable/remove passed; original entries byte-preserved. No maintenance, daemon change or power action.'
