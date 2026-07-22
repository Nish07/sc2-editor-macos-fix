#!/bin/zsh
# Build and install the fix, then create a ~/sc2editor shortcut and a
# double-clickable app you can keep in the Dock.
# Nothing is installed system-wide and nothing runs at login.
set -e
cd "$(dirname "$0")"

DEST="$HOME/Library/Application Support/SC2EditorFix"
EDITOR="/Applications/StarCraft II/StarCraft II Editor.app/Contents/MacOS/StarCraft II Editor"
SRCAPP="/Applications/StarCraft II/StarCraft II Editor.app"
APPNAME="StarCraft II Editor (Fixed).app"

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

# --- Dock-able app -------------------------------------------------------
# A tiny wrapper bundle that launches the real Editor with the shim injected.
# Blizzard's own .app is never modified: patching its Info.plist would break
# its code signature and be reverted by the next Battle.net update.
APPDIR="/Applications"
[ -w "$APPDIR" ] || APPDIR="$HOME/Applications"
mkdir -p "$APPDIR"
APP="$APPDIR/$APPNAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/MacOS/launch" <<'WRAP'
#!/bin/sh
DYLIB="$HOME/Library/Application Support/SC2EditorFix/sc2ed_fix.dylib"
EDITOR="/Applications/StarCraft II/StarCraft II Editor.app/Contents/MacOS/StarCraft II Editor"
if [ ! -f "$DYLIB" ] || [ ! -f "$EDITOR" ]; then
  osascript -e 'display alert "StarCraft II Editor (Fixed)" message "The fix or the Editor is missing. Re-run install.sh from the sc2-editor-macos-fix repo."'
  exit 1
fi
cd "$(dirname "$EDITOR")"
exec env DYLD_INSERT_LIBRARIES="$DYLIB" "$EDITOR"
WRAP
chmod +x "$APP/Contents/MacOS/launch"

[ -f "$SRCAPP/Contents/Resources/Icon.icns" ] &&
  cp -f "$SRCAPP/Contents/Resources/Icon.icns" "$APP/Contents/Resources/Icon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>StarCraft II Editor (Fixed)</string>
    <key>CFBundleDisplayName</key>     <string>StarCraft II Editor (Fixed)</string>
    <key>CFBundleExecutable</key>      <string>launch</string>
    <key>CFBundleIconFile</key>        <string>Icon</string>
    <key>CFBundleIdentifier</key>      <string>com.sc2editorfix.launcher</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Nudge LaunchServices so the icon shows immediately.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" >/dev/null 2>&1 || true

cat <<DONE

  Installed.

  ┌────────────────────────────────────────────┐
  │                                            │
  │   To start the Editor, run:                │
  │                                            │
  │       ~/sc2editor                          │
  │                                            │
  │   ...or open "StarCraft II Editor (Fixed)" │
  │   and drag it to your Dock.                │
  │                                            │
  └────────────────────────────────────────────┘

DONE
echo "  App:          $APP"
echo "  Installed to: $DEST"
echo "  Log:          ~/Library/Logs/sc2ed-fix.log"
echo
