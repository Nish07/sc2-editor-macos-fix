#!/bin/sh
# src/sc2ed_fix.m holds the version and is the single source of truth.
#
# The README badge reads the latest git tag from GitHub, and install.sh and the
# runtime log line both derive from the constant, so nothing else should ever
# carry a hardcoded copy. This guards that.
set -e
cd "$(dirname "$0")/.."

SRC=$(sed -n 's/.*SC2ED_FIX_VERSION "\([^"]*\)".*/\1/p' src/sc2ed_fix.m)
[ -n "$SRC" ] || { echo "could not read SC2ED_FIX_VERSION from src/sc2ed_fix.m"; exit 1; }

# install.sh must derive the version, never hardcode it.
if grep -q 'CFBundleShortVersionString string "[0-9]' install.sh; then
  echo "install.sh hardcodes the version; it should derive it from src/sc2ed_fix.m"
  exit 1
fi

# The badge must stay dynamic; a hardcoded one goes stale (it has, twice).
if grep -q 'img.shields.io/badge/Version-' README.md; then
  echo "README uses a hardcoded version badge; use the dynamic tag badge instead:"
  echo "  https://img.shields.io/github/v/tag/OWNER/REPO?label=Version"
  exit 1
fi

echo "version $SRC; no hardcoded copies"
