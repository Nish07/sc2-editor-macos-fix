#!/bin/sh
# Source only: users must be able to read what they build and run. A committed
# dylib would defeat that, and .gitignore alone is not a guarantee.
set -e
cd "$(dirname "$0")/.."

FOUND=$(git ls-files | grep -E '\.(dylib|o|a|so)$' || true)
if [ -n "$FOUND" ]; then
  echo "compiled binaries are tracked in git:"
  echo "$FOUND" | sed 's/^/  /'
  exit 1
fi
echo "no binaries tracked"
