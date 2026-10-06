#!/usr/bin/env sh
# Installs the native Reparo Linux runtime. No PowerShell required.

set -eu

REPARO_URL="${REPARO_URL:-https://raw.githubusercontent.com/16thdoc/Reparo/main/linux/reparo-linux}"
REPARO_QUIET="${REPARO_QUIET:-1}"
REPARO_INSTALL_LOG="${REPARO_INSTALL_LOG:-${TMPDIR:-/tmp}/reparo-install-linux.log}"

for arg in "$@"; do
    case "$arg" in
        -q|--quiet|--silent|-quiet|-silent) REPARO_QUIET=1 ;;
        -v|--verbose|-verbose) REPARO_QUIET=0 ;;
        *) printf '%s\n' "ERROR: Unknown installer option: $arg" >&2; exit 2 ;;
    esac
done

if [ "$REPARO_QUIET" = "1" ]; then
    exec >"$REPARO_INSTALL_LOG" 2>&1
fi

for required in curl mktemp install; do
    if ! command -v "$required" >/dev/null 2>&1; then
        printf '%s\n' "ERROR: $required is required to install Reparo Linux." >&2
        exit 1
    fi
done

quote_shell() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

read_crontab_state() {
    errors=$(mktemp "${TMPDIR:-/tmp}/reparo-install-cron-read.XXXXXX") || return 1
    if state=$(LC_ALL=C crontab -l 2>"$errors"); then
        rm -f "$errors"; printf '%s' "$state"; return 0
    else read_status=$?; fi
    if [ "$read_status" -eq 1 ] && [ "$(wc -l <"$errors")" -eq 1 ] && grep -Eq '^(no crontab for|crontab: no crontab for) ' "$errors"; then
        rm -f "$errors"; return 0
    fi
    rm -f "$errors"
    printf '%s\n' 'ERROR: Existing crontab unreadable; self-update installation aborted without overwriting jobs.' >&2
    return 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/reparo-install-linux.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
runtime_download="$tmp_dir/reparo-linux"
runtime_rollback="$tmp_dir/reparo-linux.rollback"
install_root="${XDG_DATA_HOME:-$HOME/.local/share}/reparo"
runtime_path="$install_root/reparo-linux"
shim_dir="$HOME/.local/bin"
shim_path="$shim_dir/reparo"

# Preflight before replacing runtime/shim: absence is distinct from read failure.
self_update_existing=''
if command -v crontab >/dev/null 2>&1; then
    case "$shim_path" in *%*|*'
'*) printf '%s\n' 'ERROR: Cron shim paths cannot contain percent or newline.' >&2; exit 1 ;; esac
    command -v flock >/dev/null 2>&1 || { printf '%s\n' 'ERROR: flock is required for safe self-update scheduling.' >&2; exit 1; }
    state_root="${XDG_STATE_HOME:-$HOME/.local/state}/reparo"
    install -d -m 700 "$state_root"
    exec 9>"$state_root/task-management.lock"
    flock -n 9 || { printf '%s\n' 'ERROR: Another Reparo task manager owns the crontab; install deferred.' >&2; exit 1; }
    self_update_existing=$(read_crontab_state) || exit 1
fi

printf '%s\n' '=== Reparo Linux installer ==='
printf '%s\n' "Source:  $REPARO_URL"
printf '%s\n' "Runtime: $runtime_path"
printf '%s\n' 'Downloading native runtime...'
download_url="$REPARO_URL"
case "$download_url" in
    https://raw.githubusercontent.com/*)
        case "$download_url" in *\?*) separator='&' ;; *) separator='?' ;; esac
        download_url="${download_url}${separator}x=$(date +%s)"
        ;;
esac
curl -fsSL -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' "$download_url" -o "$runtime_download"

if [ ! -s "$runtime_download" ] || ! sh -n "$runtime_download"; then
    printf '%s\n' 'ERROR: Downloaded runtime is empty or fails POSIX shell syntax validation.' >&2
    exit 1
fi
expected_version=$(sed -n "s/^REPARO_LINUX_VERSION='\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)'$/\1/p" "$runtime_download")
case "$expected_version" in ''|*'
'*) printf '%s\n' 'ERROR: Downloaded runtime has no unique four-part release identity.' >&2; exit 1 ;; esac

install -d -m 700 "$install_root"
mkdir -p "$shim_dir"
if [ -f "$runtime_path" ]; then
    cp "$runtime_path" "$runtime_rollback"
fi
if ! install -m 755 "$runtime_download" "$runtime_path"; then
    printf '%s\n' 'ERROR: Failed to stage the native Reparo runtime.' >&2
    exit 1
fi
if ! sh -n "$runtime_path" || ! version_output=$("$runtime_path" --version 2>/dev/null) || ! printf '%s\n' "$version_output" | grep -Fx "Reparo Linux $expected_version" >/dev/null; then
    if [ -f "$runtime_rollback" ]; then
        cp "$runtime_rollback" "$runtime_path"
        printf '%s\n' "ERROR: Native runtime post-install validation failed; restored previous runtime: $runtime_path" >&2
    else
        rm -f "$runtime_path"
        printf '%s\n' "ERROR: Native runtime post-install validation failed; removed incomplete first install: $runtime_path" >&2
    fi
    exit 1
fi
legacy_runtime="$install_root/Reparo.ps1"
if [ -f "$legacy_runtime" ]; then
    rm -f "$legacy_runtime"
    printf '%s\n' "Removed legacy PowerShell runtime: $legacy_runtime"
fi
printf '#!/usr/bin/env sh\nexec %s "$@"\n' "$(quote_shell "$runtime_path")" >"$shim_path"
chmod 755 "$shim_path"

# Keep the native runner updated weekly. It currently follows main, unlike the
# Windows manifest-pinned release; do not claim immutable native install receipts.
# A user crontab entry is used because Linux has no universal machine scheduler.
if command -v crontab >/dev/null 2>&1; then
    self_update_marker='# Reparo self-update task'
    self_update_crontab=$(mktemp "${TMPDIR:-/tmp}/reparo-self-update-crontab.XXXXXX")
    if [ -n "$self_update_existing" ]; then
        printf '%s\n' "$self_update_existing" | awk -v marker="$self_update_marker" 'substr($0,length($0)-length(marker)+1)!=marker' >"$self_update_crontab"
    else : >"$self_update_crontab"; fi
    printf '%s\n' "0 10 * * 2 $(quote_shell "$shim_path") --new $self_update_marker" >>"$self_update_crontab"
    current=$(read_crontab_state) || { rm -f "$self_update_crontab"; exit 1; }
    [ "$current" = "$self_update_existing" ] || { rm -f "$self_update_crontab"; printf '%s\n' 'ERROR: Crontab changed concurrently; runtime installed but self-update schedule not replaced.' >&2; exit 1; }
    if crontab "$self_update_crontab"; then
        registered=$(read_crontab_state) || { rm -f "$self_update_crontab"; exit 1; }
        expected_crontab=$(cat "$self_update_crontab")
        [ "$registered" = "$expected_crontab" ] || { rm -f "$self_update_crontab"; printf '%s\n' 'ERROR: Runtime installed, but self-update crontab verification failed.' >&2; exit 1; }
        printf '%s\n' 'Created/updated weekly self-update cron task: Tuesday 10:00 AM (reparo --new).'
    else
        rm -f "$self_update_crontab"
        printf '%s\n' 'ERROR: Runtime installed, but weekly self-update registration failed; installation is incomplete.' >&2
        exit 1
    fi
    rm -f "$self_update_crontab"
else
    printf '%s\n' 'WARNING: crontab is unavailable; skipped the Reparo weekly self-update schedule.' >&2
fi

hash -r 2>/dev/null || true
case ":$PATH:" in
    *":$shim_dir:"*) printf '%s\n' "PATH already includes $shim_dir." ;;
    *)
        printf '%s\n' "NOTE: Add this to your shell profile if 'reparo' is not found:"
        printf '%s\n' '  export PATH="$HOME/.local/bin:$PATH"'
        ;;
esac

printf '%s\n' 'Reparo Linux is installed/updated.'
"$shim_path" --version
printf '%s\n' 'You can now run: reparo --preview, reparo --update, reparo --status, or reparo --tail.'

if [ "$REPARO_QUIET" = "1" ]; then
    printf '%s\n' "Quiet install log: $REPARO_INSTALL_LOG"
fi
