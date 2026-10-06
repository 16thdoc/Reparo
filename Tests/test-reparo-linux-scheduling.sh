#!/usr/bin/env sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/bin"
export FIXTURE_CRON="$fixture/crontab"
printf '%s\n' '7 7 * * * unrelated-command' '8 8 * * * old-command # Reparo managed task' >"$FIXTURE_CRON"
cp "$FIXTURE_CRON" "$fixture/original"
cat >"$fixture/bin/crontab" <<'EOF'
#!/usr/bin/env sh
if [ "${1:-}" = -l ]; then cat "$FIXTURE_CRON"; else cp "$1" "$FIXTURE_CRON"; fi
EOF
chmod +x "$fixture/bin/crontab"
export PATH="$fixture/bin:$PATH" XDG_STATE_HOME="$fixture/state" NO_COLOR=1
runtime="$repo/linux/reparo-linux"
sh "$runtime" --task 'weekdays at 5am,5pm' --preview >"$fixture/preview"
cmp "$FIXTURE_CRON" "$fixture/original"
grep -q '0 5 \* \* 1,2,3,4,5' "$fixture/preview"
sh "$runtime" --task '15th at 5am' --task-name fixture --force --include Apt Npm
grep -q -- "--force --include 'Apt' 'Npm'" "$FIXTURE_CRON"
if sh "$runtime" --task daily 6am --task-name fixture; then echo 'Implicit replacement accepted' >&2; exit 1; fi
sh "$runtime" --task --task-name fixture --task-action disable
grep -q '^# DISABLED .*# Reparo managed task v2:fixture$' "$FIXTURE_CRON"
sh "$runtime" --task --task-name fixture --task-action enable
sh "$runtime" --task --task-name fixture --task-action show
sh "$runtime" --task --task-name fixture --task-action remove
cmp "$FIXTURE_CRON" "$fixture/original"
mkdir -p "$fixture/owner's spaced path"
cp "$runtime" "$fixture/owner's spaced path/reparo-linux"
sh "$fixture/owner's spaced path/reparo-linux" --task daily 6am --task-name quoted
# Parse the generated command without executing maintenance, proving quote syntax.
command=$(sed -n '/# Reparo managed task v2:quoted$/s/^[^ ]* [^ ]* [^ ]* [^ ]* [^ ]* //p' "$FIXTURE_CRON")
command=${command% # Reparo managed task v2:quoted}
sh -n -c "$command --preview"
sh "$runtime" --task --task-name quoted --task-action remove
cmp "$FIXTURE_CRON" "$fixture/original"
for bad in 'first Monday at 5am' 'every 2 days at 5am' '32nd at 5am' 'Monday 25am' '5am Monday; echo injected'; do
    if sh "$runtime" --task "$bad" --preview; then echo "Invalid recurrence accepted: $bad" >&2; exit 1; fi
done
if sh "$runtime" --task --new; then echo 'Lifecycle scheduling accepted' >&2; exit 1; fi
if sh "$runtime" --new --task; then echo 'Reversed lifecycle scheduling accepted' >&2; exit 1; fi
if sh "$runtime" --task-name accidental; then echo 'Missing task flag ran maintenance' >&2; exit 1; fi
printf '%s\n' 'Native scheduling preview, flag preservation, management, collision and unsupported-boundary tests passed.'
