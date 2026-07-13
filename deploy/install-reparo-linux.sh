#!/usr/bin/env bash
set -euo pipefail

REPARO_URL="${REPARO_URL:-https://raw.githubusercontent.com/16thdoc/Reparo/main/Reparo.ps1}"

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
curl -fsSL "$REPARO_URL" -o "$bootstrap"

echo "Installing/updating Reparo runtime..."
pwsh -NoProfile -File "$bootstrap" -New

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
