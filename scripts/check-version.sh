#!/bin/sh
# The version lives in src/sc2ed_fix.m. Everything else must agree with it.
# It has drifted twice before: the README badge, and a hardcoded copy in
# install.sh.
set -e
cd "$(dirname "$0")/.."

SRC=$(sed -n 's/.*SC2ED_FIX_VERSION "\([^"]*\)".*/\1/p' src/sc2ed_fix.m)
[ -n "$SRC" ] || { echo "could not read SC2ED_FIX_VERSION from src/sc2ed_fix.m"; exit 1; }

BADGE=$(sed -n 's|.*badge/Version-\([0-9][0-9.]*\)-.*|\1|p' README.md | head -1)
[ -n "$BADGE" ] || { echo "could not find the version badge in README.md"; exit 1; }

if [ "$SRC" != "$BADGE" ]; then
  echo "version mismatch:"
  echo "  src/sc2ed_fix.m : $SRC"
  echo "  README badge    : $BADGE"
  echo "Update the README badge to $SRC."
  exit 1
fi

# install.sh must derive the version, never hardcode it.
if grep -q 'CFBundleShortVersionString string "[0-9]' install.sh; then
  echo "install.sh hardcodes the version; it should derive it from src/sc2ed_fix.m"
  exit 1
fi

echo "version $SRC consistent"
