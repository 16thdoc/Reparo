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

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/reparo-install-linux.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
runtime_download="$tmp_dir/reparo-linux"
runtime_rollback="$tmp_dir/reparo-linux.rollback"
install_root="${XDG_DATA_HOME:-$HOME/.local/share}/reparo"
runtime_path="$install_root/reparo-linux"
shim_dir="$HOME/.local/bin"
shim_path="$shim_dir/reparo"

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

install -d -m 700 "$install_root"
mkdir -p "$shim_dir"
if [ -f "$runtime_path" ]; then
    cp "$runtime_path" "$runtime_rollback"
fi
if ! install -m 755 "$runtime_download" "$runtime_path"; then
    printf '%s\n' 'ERROR: Failed to stage the native Reparo runtime.' >&2
    exit 1
fi
if ! sh -n "$runtime_path" || ! "$runtime_path" --version >/dev/null 2>&1; then
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
cat >"$shim_path" <<EOF
#!/usr/bin/env sh
exec "$runtime_path" "\$@"
EOF
chmod 755 "$shim_path"

# Keep the installed native runner on the reviewed release channel. This mirrors the
# Windows self-update task, but remains a user crontab entry because Linux does not
# have a universal machine-wide task scheduler.
if command -v crontab >/dev/null 2>&1; then
    self_update_marker='# Reparo self-update task'
    self_update_crontab=$(mktemp "${TMPDIR:-/tmp}/reparo-self-update-crontab.XXXXXX")
    (crontab -l 2>/dev/null || true) | grep -F -v "$self_update_marker" >"$self_update_crontab" || true
    printf '%s\n' "0 10 * * 2 \"$shim_path\" --new $self_update_marker" >>"$self_update_crontab"
    if crontab "$self_update_crontab"; then
        printf '%s\n' 'Created/updated weekly self-update cron task: Tuesday 10:00 AM (reparo --new).'
    else
        printf '%s\n' 'WARNING: Could not create the Reparo weekly self-update cron task.' >&2
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
