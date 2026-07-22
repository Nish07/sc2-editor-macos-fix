#!/bin/zsh
# Build the fix shim. Must be x86_64 -- the editor runs under Rosetta, so an
# arm64 dylib will not load into it.
set -e
cd "$(dirname "$0")"
mkdir -p build
clang -arch x86_64 -dynamiclib -O2 -Wall -fno-objc-arc -framework AppKit -framework Foundation -o build/sc2ed_fix.dylib src/sc2ed_fix.m
echo "built: build/sc2ed_fix.dylib"
file build/sc2ed_fix.dylib
