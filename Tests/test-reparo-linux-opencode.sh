#!/usr/bin/env sh
set -eu
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
export OC_FIXTURE="$fixture"
mkdir -p "$fixture/tools" "$fixture/owning prefix/bin" "$fixture/state"
cat >"$fixture/tools/npm" <<'EOF'
#!/usr/bin/env sh
case "$1" in
    ls)
        printf '%s\n' "$OC_FIXTURE/owning prefix/lib" \
            "$OC_FIXTURE/owning prefix/lib/node_modules/opencode-ai" \
            "$OC_FIXTURE/owning prefix/lib/node_modules/@opencode/cli" \
            "$OC_FIXTURE/owning prefix/lib/node_modules/@example/other" \
            "$OC_FIXTURE/owning prefix/lib/node_modules/other"
        exit "${OC_INVENTORY_STATUS:-0}" ;;
    root) printf '%s\n' "$OC_FIXTURE/owning prefix/lib/node_modules" ;;
    config) printf '%s\n' "$OC_FIXTURE/different prefix" ;;
    *)
        printf '%s\n' "$@" >>"$OC_FIXTURE/calls"
        if [ "$1" = install ] && [ "$5" = @opencode/cli@latest ]; then exit "${OC_NPM_STATUS:-0}"; fi
        if [ "$1" = install ] && [ "$5" = opencode-ai@1.19.0 ]; then exit "${OC_ROLLBACK_STATUS:-0}"; fi
        exit 0 ;;
esac
EOF
cat >"$fixture/tools/pgrep" <<'EOF'
#!/usr/bin/env sh
exit "${OC_PROCESS_STATUS:-1}"
EOF
chmod +x "$fixture/tools/"*
export PATH="$fixture/owning prefix/bin:$fixture/tools:$PATH" XDG_STATE_HOME="$fixture/state" NO_COLOR=1
for package in opencode-ai @opencode/cli; do
    mkdir -p "$fixture/owning prefix/lib/node_modules/$package/bin"
    printf '%s\n' '{"version":"1.19.0"}' >"$fixture/owning prefix/lib/node_modules/$package/package.json"
    printf '%s\n' '#!/usr/bin/env sh' 'echo opencode v2.0.29' >"$fixture/owning prefix/lib/node_modules/$package/bin/opencode"
    chmod +x "$fixture/owning prefix/lib/node_modules/$package/bin/opencode"
done
for package in opencode-ai @opencode/cli; do
    if [ "$package" = opencode-ai ]; then
        rm "$fixture/owning prefix/lib/node_modules/@opencode/cli/package.json"
    else
        printf '%s\n' '{"version":"2.0.29"}' >"$fixture/owning prefix/lib/node_modules/@opencode/cli/package.json"
    fi
    ln -sfn "../lib/node_modules/$package/bin/opencode" "$fixture/owning prefix/bin/opencode"
    rm -f "$fixture/calls"
    sh "$repo/linux/reparo-linux" --include Opencode >"$fixture/output"
    : >"$fixture/expected"
    if [ "$package" = opencode-ai ]; then
        printf '%s\n' uninstall --global --prefix "$fixture/owning prefix" opencode-ai >>"$fixture/expected"
    fi
    printf '%s\n' install --global --prefix "$fixture/owning prefix" @opencode/cli@latest >>"$fixture/expected"
    cmp "$fixture/expected" "$fixture/calls"
done
# V1 migration failure restores the exact old version; rollback failure stays a failure.
ln -sfn '../lib/node_modules/opencode-ai/bin/opencode' "$fixture/owning prefix/bin/opencode"
rm "$fixture/owning prefix/lib/node_modules/@opencode/cli/package.json"
for rollback_status in 0 19; do
    rm -f "$fixture/calls"
    OC_NPM_STATUS=17 OC_ROLLBACK_STATUS=$rollback_status sh "$repo/linux/reparo-linux" --include Opencode >"$fixture/output" 2>&1 || true
    grep -q '^opencode-ai@1.19.0$' "$fixture/calls"
    grep -q '\[FAIL\] Opencode exited 17' "$fixture/output"
    if [ "$rollback_status" -eq 0 ]; then grep -q 'Restored opencode-ai 1.19.0' "$fixture/output"
    else grep -q 'rollback also failed' "$fixture/output"; fi
done
# Mixed legacy-active installs are refused rather than deleting an existing V2.
printf '%s\n' '{"version":"2.0.29"}' >"$fixture/owning prefix/lib/node_modules/@opencode/cli/package.json"
rm "$fixture/calls"
sh "$repo/linux/reparo-linux" --include Opencode >"$fixture/output"
[ ! -e "$fixture/calls" ]
grep -q 'mixed V1/V2' "$fixture/output"
ln -sfn '../lib/node_modules/@opencode/cli/bin/opencode' "$fixture/owning prefix/bin/opencode"
for status in 0 2; do
    rm -f "$fixture/calls"
    OC_PROCESS_STATUS=$status sh "$repo/linux/reparo-linux" --include Opencode >"$fixture/output"
    [ ! -e "$fixture/calls" ]
    grep -q 'OpenCode running or process state unknown' "$fixture/output"
done
rm -f "$fixture/calls"
sh "$repo/linux/reparo-linux" --preview --include Opencode >"$fixture/output"
[ ! -e "$fixture/calls" ]
rm "$fixture/owning prefix/bin/opencode"
printf '%s\n' '#!/usr/bin/env sh' 'exit 99' >"$fixture/owning prefix/bin/opencode"
chmod +x "$fixture/owning prefix/bin/opencode"
sh "$repo/linux/reparo-linux" --include Opencode >"$fixture/output"
[ ! -e "$fixture/calls" ]
grep -q 'not a standard npm global installation' "$fixture/output"
ln -sf "../lib/node_modules/@opencode/cli/bin/opencode" "$fixture/owning prefix/bin/opencode"
OC_NPM_STATUS=17 sh "$repo/linux/reparo-linux" --include Opencode >"$fixture/output" || true
grep -q '\[FAIL\] Opencode exited 17' "$fixture/output"
rm "$fixture/calls"
sh "$repo/linux/reparo-linux" --include Npm >"$fixture/output"
printf '%s\n' update -g -- @example/other other >"$fixture/expected"
cmp "$fixture/expected" "$fixture/calls"
rm "$fixture/calls"
OC_INVENTORY_STATUS=1 sh "$repo/linux/reparo-linux" --include Npm >"$fixture/output" || true
[ ! -e "$fixture/calls" ]
grep -q 'cannot enumerate global npm packages' "$fixture/output"
printf '%s\n' 'Native OpenCode V2 migration/rollback, ownership/coexistence, running/unknown process state, preview, standalone, failure, npm exclusion and inventory failure tests passed.'
