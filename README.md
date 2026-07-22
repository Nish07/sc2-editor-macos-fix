# sc2-editor-macos-fix

![Version](https://img.shields.io/badge/Version-1.2-blue?style=flat)
![SC2 Build](https://img.shields.io/badge/SC2%20Build-5.0.16%20(97563)-blue?style=flat)
![macOS](https://img.shields.io/badge/macOS-26.5-blue?style=flat)
![Platform](https://img.shields.io/badge/Platform-Apple%20Silicon-blue?style=flat)

Makes the **StarCraft II Editor** launch on Apple Silicon / modern macOS, instead of dying with:

> StarCraft II has encountered an error while initializing your videocard.

With the fix, the Editor opens normally — Terrain window, Help, Editor Tips — on its own
**OpenGL3** renderer.

Verified on **SC2 5.0.16.97563**, **macOS 26.5**, **M3 Pro** 

## What it does

A shim loaded into the Editor with `DYLD_INSERT_LIBRARIES`. It changes **seven bytes in the
Editor's memory** at startup — three to let it launch, and four to redirect one call so object
previews render. Nothing else in the Editor is altered.

- Never modifies your StarCraft II installation — no file is written or replaced.
- Affects only the Editor. Nothing to do with the game client, Battle.net, multiplayer, or
  anti-cheat.
- Source only, so you can read it before you build it.

## Requirements

| | |
|---|---|
| Mac | Apple Silicon (Intel untested) |
| macOS | 26.5 verified |
| Rosetta 2 | `softwareupdate --install-rosetta` |
| Xcode tools | `xcode-select --install` |
| StarCraft II | installed at `/Applications/StarCraft II/` |
| SC2 build | 5.0.16.97563 verified |

Installed elsewhere? Edit the `EDITOR=` lines in `install.sh` first.

## Install

```bash
git clone https://github.com/Nish07/sc2-editor-macos-fix
cd sc2-editor-macos-fix
./install.sh
~/sc2editor
```

`install.sh` builds the shim, copies it to `~/Library/Application Support/SC2EditorFix/`, creates
a `~/sc2editor` shortcut, and adds a **StarCraft II Editor (Fixed)** app you can drag to your Dock.
`./uninstall.sh` removes all of it — that is the entire footprint.

Launch it whichever way you prefer: the Dock app, or `~/sc2editor` from a terminal.

To open a map with the fixed Editor, right-click it → **Open With** → **StarCraft II Editor
(Fixed)**, and tick **Always Open With** to make it the default for `.SC2Map` files.

Note that Blizzard's own Editor icon still launches the *unfixed* Editor — the fix only applies
when started through one of these. Blizzard's app bundle is deliberately left untouched.

Nothing is installed system-wide and nothing runs at login. The Editor stays tied to the terminal
window that launched it; closing that window closes the Editor.

Log: `~/Library/Logs/sc2ed-fix.log`

## Caveats

- Addresses and signatures come from the build they were derived from. A new SC2 build may need the
  fix re-derived; the shim fails safe in the meantime.
- Apple has deprecated Rosetta, which the Editor depends on. This has a shelf life on future macOS
  releases regardless of what Blizzard does.
- Unofficial and unaffiliated with Blizzard Entertainment. Provided as-is, with no warranty.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). `master` is protected, so
changes land through pull requests. Fixes for newer SC2 builds and reports from other Macs are
especially useful.

## Licensing and ownership

StarCraft II and the StarCraft II Editor are the property of Blizzard Entertainment, Inc.

The MIT license in [LICENSE](LICENSE) applies **only to the original code, scripts, and
documentation in this repository**. It grants no rights in StarCraft II. This repository contains
and redistributes no Blizzard code, binaries, assets, or game data — you supply your own
legitimate installation, and nothing on disk is modified.
