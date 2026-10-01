#!/bin/sh
# Runs the standalone tests (LuaJIT only, no KOReader): sh tests/run.sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for test in credentials fast_download redaction; do
    mkdir "$tmp/$test"
    luajit "tests/$test.lua" "$tmp/$test"
done
luajit tests/transport.lua
