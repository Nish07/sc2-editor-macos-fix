#!/bin/sh
# The shim must compile cleanly. This repo ships source only, so a build
# failure means every user is broken.
set -e
cd "$(dirname "$0")/.."

command -v clang >/dev/null 2>&1 || { echo "clang not found; skipping build check"; exit 0; }

OUT=$(mktemp -t sc2edcheck)
if ! clang -arch x86_64 -dynamiclib -O2 -Wall -Wextra -fno-objc-arc \
     -framework AppKit -framework Foundation \
     -o /dev/null src/sc2ed_fix.m 2>"$OUT"; then
  echo "build failed:"; cat "$OUT"; rm -f "$OUT"; exit 1
fi
if [ -s "$OUT" ]; then
  echo "build produced warnings:"; cat "$OUT"; rm -f "$OUT"; exit 1
fi
rm -f "$OUT"
echo "shim builds clean"
