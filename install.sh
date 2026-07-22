#!/bin/zsh
# Build and install the fix, then create a ~/sc2editor shortcut and a
# double-clickable app you can keep in the Dock and open maps with.
# Nothing is installed system-wide and nothing runs at login.
set -e
cd "$(dirname "$0")"

DEST="$HOME/Library/Application Support/SC2EditorFix"
SC2="/Applications/StarCraft II"
EDITOR="$SC2/StarCraft II Editor.app/Contents/MacOS/StarCraft II Editor"
SRCAPP="$SC2/StarCraft II Editor.app"
APPNAME="StarCraft II Editor (Fixed).app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

fail() { echo "error: $1" >&2; exit 1; }

# --- prerequisites -------------------------------------------------------
[ -f "$EDITOR" ] || fail "SC2 Editor not found at:
  $EDITOR
If StarCraft II is installed somewhere else, edit the paths at the top of this script."

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

# --- Dock-able app that can also open maps -------------------------------
# Built with osacompile rather than as a shell script: only a real app can
# receive the Apple Event Finder sends when you open a document with it, which
# is what lets "Open With" and double-clicking a .SC2Map work.
#
# Blizzard's own .app is never modified. Adding LSEnvironment to its Info.plist
# would make its icon work directly, but that breaks its code signature and is
# reverted by the next Battle.net update.
APPDIR="/Applications"
[ -w "$APPDIR" ] || APPDIR="$HOME/Applications"
mkdir -p "$APPDIR"
APP="$APPDIR/$APPNAME"

SRC="$(mktemp -t sc2edwrap).applescript"
cat > "$SRC" <<'APPLESCRIPT'
-- StarCraft II Editor (Fixed)
-- Launches the real Editor with the fix shim injected, and forwards any
-- document you open to it.

on run
	launchEditor("")
end run

on open theFiles
	repeat with f in theFiles
		launchEditor(POSIX path of (f as alias))
	end repeat
end open

on launchEditor(mapPath)
	set dylib to (POSIX path of (path to home folder)) & "Library/Application Support/SC2EditorFix/sc2ed_fix.dylib"
	set editorBin to "/Applications/StarCraft II/StarCraft II Editor.app/Contents/MacOS/StarCraft II Editor"

	tell application "System Events"
		set alreadyRunning to (exists (processes where name is "StarCraft II Editor"))
	end tell

	-- Reuse a running (already patched) Editor rather than starting a second one.
	if alreadyRunning and mapPath is not "" then
		try
			tell application id "com.blizzard.starcraft2.editor" to open (POSIX file mapPath)
			return
		end try
	end if

	set cmd to "DYLD_INSERT_LIBRARIES=" & quoted form of dylib & " " & quoted form of editorBin
	if mapPath is not "" then set cmd to cmd & " " & quoted form of mapPath
	do shell script cmd & " > /dev/null 2>&1 &"
end launchEditor
APPLESCRIPT

rm -rf "$APP"
osacompile -o "$APP" "$SRC" >/dev/null 2>&1 || fail "osacompile failed"
rm -f "$SRC"

[ -f "$SRCAPP/Contents/Resources/Icon.icns" ] &&
  cp -f "$SRCAPP/Contents/Resources/Icon.icns" "$APP/Contents/Resources/applet.icns"

PL="$APP/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PL" >/dev/null 2>&1 || true; }
pb "Set :CFBundleIdentifier com.sc2editorfix.launcher"
pb "Set :CFBundleName StarCraft II Editor (Fixed)"
pb "Add :CFBundleDisplayName string StarCraft II Editor (Fixed)"
pb "Set :CFBundleShortVersionString 1.2"

# Declare the same document types the Editor claims, so Finder offers this app
# under "Open With" instead of burying it behind "All Applications".
pb "Delete :CFBundleDocumentTypes"
pb "Add :CFBundleDocumentTypes array"
i=0
for ext in SC2Map SC2Components SC2Mod SC2Campaign SC2Lighting SC2Layout; do
  pb "Add :CFBundleDocumentTypes:$i dict"
  pb "Add :CFBundleDocumentTypes:$i:CFBundleTypeName string StarCraft II $ext"
  pb "Add :CFBundleDocumentTypes:$i:CFBundleTypeExtensions array"
  pb "Add :CFBundleDocumentTypes:$i:CFBundleTypeExtensions:0 string $ext"
  pb "Add :CFBundleDocumentTypes:$i:CFBundleTypeRole string Editor"
  pb "Add :CFBundleDocumentTypes:$i:LSHandlerRank string Alternate"
  [ "$ext" = "SC2Mod" ] && pb "Add :CFBundleDocumentTypes:$i:LSTypeIsPackage bool true"
  i=$((i+1))
done

touch "$APP"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true

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

  To open .SC2Map files with the fixed Editor, right-click a map ->
  Open With -> StarCraft II Editor (Fixed). Tick "Always Open With"
  to make it the default.

DONE
echo "  App:          $APP"
echo "  Installed to: $DEST"
echo "  Log:          ~/Library/Logs/sc2ed-fix.log"
echo
