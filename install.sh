#!/bin/zsh
# Build and install the fix, then create a ~/sc2editor shortcut.
# Nothing is installed system-wide and nothing runs at login.
set -e
cd "$(dirname "$0")"

DEST="$HOME/Library/Application Support/SC2EditorFix"
EDITOR="/Applications/StarCraft II/StarCraft II Editor.app/Contents/MacOS/StarCraft II Editor"

fail() { echo "error: $1" >&2; exit 1; }

# --- prerequisites -------------------------------------------------------
[ -f "$EDITOR" ] || fail "SC2 Editor not found at:
  $EDITOR
If StarCraft II is installed somewhere else, edit the EDITOR= lines in this script."

command -v clang >/dev/null 2>&1 || fail "clang not found.
Install the Xcode Command Line Tools:  xcode-select --install"

if [ "$(uname -m)" = "arm64" ] && ! /usr/bin/pgrep -q oahd; then
  echo "warning: Rosetta 2 does not appear to be installed."
  echo "         The Editor is an x86_64 binary and needs it:"
  echo "           softwareupdate --install-rosetta"
fi

# --- build and install ---------------------------------------------------
BUILD_LOG="$(mktemp -t sc2edbuild)"
printf 'Building... '
if ! ./build.sh >"$BUILD_LOG" 2>&1; then
  echo "failed:"; cat "$BUILD_LOG"; rm -f "$BUILD_LOG"; exit 1
fi
rm -f "$BUILD_LOG"
echo "done"

mkdir -p "$DEST"
cp -f build/sc2ed_fix.dylib "$DEST/sc2ed_fix.dylib"

cat > "$DEST/launch-sc2-editor.command" <<'LAUNCH'
#!/bin/zsh
# Launch the SC2 Editor with the fix shim injected.
DYLIB="$HOME/Library/Application Support/SC2EditorFix/sc2ed_fix.dylib"
EDITOR="/Applications/StarCraft II/StarCraft II Editor.app/Contents/MacOS/StarCraft II Editor"
[ -f "$DYLIB" ]  || { echo "missing shim: $DYLIB"; exit 1; }
[ -f "$EDITOR" ] || { echo "missing editor: $EDITOR"; exit 1; }
cd "$(dirname "$EDITOR")"
echo "Launching SC2 Editor with fixes applied..."
echo "(Closing this window also closes the editor.)"
exec env DYLD_INSERT_LIBRARIES="$DYLIB" "$EDITOR"
LAUNCH
chmod +x "$DEST/launch-sc2-editor.command"

ln -sfn "$DEST/launch-sc2-editor.command" "$HOME/sc2editor"

cat <<'DONE'

  Installed.

  ┌────────────────────────────────────────────┐
  │                                            │
  │   To start the Editor, run:                │
  │                                            │
  │       ~/sc2editor                          │
  │                                            │
  └────────────────────────────────────────────┘

  Keep that terminal window open while you use the Editor —
  closing it closes the Editor.

DONE
echo "  Installed to: $DEST"
echo "  Log:          ~/Library/Logs/sc2ed-fix.log"
echo
