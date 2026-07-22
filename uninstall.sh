#!/bin/sh
# Remove the fix. The SC2 installation was never modified, so this is all
# there is to undo.
DEST="$HOME/Library/Application Support/SC2EditorFix"
rm -f "$HOME/sc2editor"
rm -rf "$DEST"
rm -rf "/Applications/StarCraft II Editor (Fixed).app"
rm -rf "$HOME/Applications/StarCraft II Editor (Fixed).app"
echo "removed $DEST, ~/sc2editor and the Dock app"
echo "(SC2 itself was never modified - nothing else to undo)"
