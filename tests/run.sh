#!/bin/sh
# Runs every test against a stubbed WoW API. Needs lua5.1 (or lua in 5.1 mode).
cd "$(dirname "$0")" || exit 1
LUA=${LUA:-lua5.1}
status=0
for test in test_*.lua; do
    printf '%-24s ' "$test"
    $LUA "$test" .. || status=1
done
exit $status
