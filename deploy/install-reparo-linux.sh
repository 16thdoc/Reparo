#!/usr/bin/env bash
set -euo pipefail

REPARO_URL="${REPARO_URL:-https://api.github.com/repos/16thdoc/Reparo/contents/Reparo.ps1?ref=main}"
REPARO_QUIET="${REPARO_QUIET:-1}"
REPARO_INSTALL_LOG="${REPARO_INSTALL_LOG:-${TMPDIR:-/tmp}/reparo-install-linux.log}"

for arg in "$@"; do
  case "$arg" in
    -q|--quiet|--silent|-quiet|-silent)
      REPARO_QUIET=1
      ;;
    -v|--verbose|-verbose)
      REPARO_QUIET=0
      ;;
  esac
done

if [ "$REPARO_QUIET" = "1" ]; then
  exec >"$REPARO_INSTALL_LOG" 2>&1
fi

if ! command -v pwsh >/dev/null 2>&1; then
  echo "ERROR: PowerShell 7+ is required. Install 'pwsh' first, then rerun this installer." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required to download Reparo." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

bootstrap="$tmp_dir/Reparo.ps1"

echo
echo "=== Reparo Linux installer ==="
echo "Source:    $REPARO_URL"
echo "Bootstrap: $bootstrap"
echo

echo "Downloading Reparo..."
download_url="$REPARO_URL"
case "$download_url" in
  https://raw.githubusercontent.com/*)
    sep='?'
    case "$download_url" in *\?*) sep='&' ;; esac
    download_url="${download_url}${sep}x=$(date +%s)"
    ;;
esac
curl -fsSL -H 'Accept: application/vnd.github.raw' -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' "$download_url" -o "$bootstrap"

echo "Installing/updating Reparo runtime..."
pwsh -NoProfile -File "$bootstrap" -New -SourceUrl "$bootstrap"

install_root="${XDG_DATA_HOME:-$HOME/.local/share}/reparo"
shim_path="$HOME/.local/bin/reparo"

if [ ! -f "$install_root/Reparo.ps1" ]; then
  echo "ERROR: Expected installed script was not found:" >&2
  echo "  $install_root/Reparo.ps1" >&2
  exit 1
fi

if [ ! -x "$shim_path" ]; then
  echo "WARNING: Expected executable shim was not found:" >&2
  echo "  $shim_path" >&2
fi

# Refresh bash/zsh command caches for the current installer process. This cannot
# remove a shell function or alias from the parent interactive shell, but it does
# make PATH checks below honest for normal command lookup.
hash -r 2>/dev/null || true

case ":$PATH:" in
  *":$HOME/.local/bin:"*)
    echo "PATH already includes $HOME/.local/bin."
    ;;
  *)
    echo
    echo "NOTE: Add this to your shell profile if 'reparo' is not found:"
    echo '  export PATH="$HOME/.local/bin:$PATH"'
    ;;
esac

resolved_reparo="$(command -v reparo 2>/dev/null || true)"
if [ "$resolved_reparo" = "$shim_path" ]; then
  echo "Command lookup resolves 'reparo' to $shim_path."
else
  echo
  echo "WARNING: Your current shell may not resolve 'reparo' to the installed shim." >&2
  if [ -n "$resolved_reparo" ]; then
    echo "  command -v reparo => $resolved_reparo" >&2
  else
    echo "  command -v reparo did not find a PATH command." >&2
  fi
  echo "  Expected shim: $shim_path" >&2
  echo "  Diagnostic: type -a reparo" >&2
  echo "  If a shell function or alias appears first, remove/rename it or run:" >&2
  echo "    unset -f reparo 2>/dev/null || unalias reparo 2>/dev/null || true" >&2
  echo "  Temporary bypass: command reparo -Version" >&2
fi

echo
echo "Reparo is installed/updated."
echo "Current window test:"
"$shim_path" -Version || pwsh -NoProfile -File "$install_root/Reparo.ps1" -Version

echo
echo "You can now run:"
echo "  reparo"
echo "  reparo -Update"
echo "  reparo -Status"
echo "  reparo -Tail"
echo

if [ "$REPARO_QUIET" = "1" ]; then
  echo "Quiet install log: $REPARO_INSTALL_LOG"
fi
