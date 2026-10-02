#!/bin/sh
# Runs the standalone tests (LuaJIT only, no KOReader): sh tests/run.sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
luajit tests/fast_download.lua "$tmp"
luajit tests/redaction.lua
