#!/bin/zsh
# Remove the fix. The SC2 installation was never modified, so this is all
# there is to undo.
DEST="$HOME/Library/Application Support/SC2EditorFix"
rm -f "$HOME/sc2editor"
rm -rf "$DEST"
echo "removed $DEST and ~/sc2editor"
echo "(SC2 itself was never modified - nothing else to undo)"
