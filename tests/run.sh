#!/bin/sh
# Runs every test against a stubbed WoW API. Needs lua5.1 (or lua in 5.1 mode).
# Pass an addon folder to test that instead of the source tree, e.g. a release:
#   tests/run.sh dist/SpellbookExtended-v0-1-0/SpellbookExtended
cd "$(dirname "$0")" || exit 1
ROOT=..
[ -n "$1" ] && ROOT=$(cd "$OLDPWD" && cd "$1" && pwd)
LUA=${LUA:-lua5.1}
status=0
for test in test_*.lua; do
    printf '%-24s ' "$test"
    output=$($LUA "$test" "$ROOT" 2>&1) || status=1
    printf '%s\n' "$output" | grep -v '^|cff'

done
exit $status
