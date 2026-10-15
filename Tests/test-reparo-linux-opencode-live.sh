#!/usr/bin/env sh
# Real npm/network pilot, isolated installation. Never starts an OpenCode service.
set -eu
[ "${REPARO_OPENCODE_LIVE_PROBE:-0}" = 1 ] || exit 2
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/home"
export HOME="$fixture/home" XDG_DATA_HOME="$fixture/data" XDG_STATE_HOME="$fixture/state"
export npm_config_cache="$fixture/cache" NO_COLOR=1
npm install --global --prefix "$fixture/prefix" opencode-ai@1.19.0
export PATH="$fixture/prefix/bin:$PATH"
opencode --version
sh "$repo/linux/reparo-linux" --include Opencode
[ ! -e "$fixture/prefix/lib/node_modules/opencode-ai" ]
[ -f "$fixture/prefix/lib/node_modules/@opencode/cli/package.json" ]
opencode --version | grep -E '(^|v)2\.'
sh "$repo/linux/reparo-linux" --include Opencode
opencode --version | grep -E '(^|v)2\.'
printf '%s\n' 'Actual Linux npm V1-to-V2 migration and V2 rerun passed in a disposable prefix; no shared installation or service changed.'
