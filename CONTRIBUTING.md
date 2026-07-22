# Contributing

Contributions are welcome — especially fixes for SC2 builds newer than the one this was
derived on, and reports from Macs other than the one it was tested on.

## Workflow

`master` is protected: all changes land through pull requests.

1. Fork the repo
2. Create a branch: `git checkout -b fix/short-description`
3. Make your change
4. Open a pull request against `master`

## Pre-commit hooks

This repo uses [pre-commit](https://pre-commit.com). Install the hooks once:

```bash
pip install pre-commit   # or: brew install pre-commit
pre-commit install
```

They then run on every commit, and you can run them over everything with
`pre-commit run --all-files`.

Alongside the usual hygiene checks (trailing whitespace, line endings, private keys, large files)
and `shellcheck`, three are specific to this repo:

- **Version is consistent** — `src/sc2ed_fix.m` holds the version and is the only place to edit
  it. `install.sh`, the runtime log line and the README badge all derive from it, and this hook
  rejects any hardcoded copy creeping back in. It drifted twice before that was true.
- **Shim compiles with no warnings** — the repo ships source only, so a build failure breaks
  every user.
- **No compiled binaries committed** — people must be able to read what they build and run.

## Releasing

The version lives in one place: `SC2ED_FIX_VERSION` in `src/sc2ed_fix.m`.

1. Bump that constant
2. Merge to `master`

That is the whole process. A workflow tags the merge commit automatically when the constant
changes, `install.sh` reads it when building the app bundle, the shim logs it at startup, and the
README badge follows the newest tag. Nothing else needs touching.

If you ever need to tag by hand, the workflow no-ops when the tag already exists.

## Before you open a PR

- `./build.sh` completes with no warnings
- `./install.sh` runs clean from a fresh checkout
- The Editor actually launches: `~/sc2editor`, then check `~/Library/Logs/sc2ed-fix.log`
- Say which SC2 build and macOS version you tested on

Please test on a real Editor session rather than only compiling. Several bugs here have only
shown up seconds after launch, or when clicking around the UI — a clean build proves very little.

## How the shim is organised

`src/sc2ed_fix.m` has two mechanisms:

**`FIXES[]`** — byte patches. Give a byte signature, the offset of the bytes to replace, and the
replacement. Use this when different bytes are all you need.

**`HOOKS[]`** — call redirects. Rewrites a `call`'s rel32 so it lands in one of our functions,
which calls the original and adjusts the result. Use this when you need behaviour, not just
different bytes.

Everything else — waiting for the image to decrypt, locating the site, `mprotect`, logging — is
shared, so a new fix is usually one table entry plus (for a hook) one function.

## Rules for a new fix

**Locate by signature, not by address.** The known address is only a fast-path hint. Signatures
survive SC2 patches that move code around; addresses do not.

**Fail safe, always.** A signature that matches nowhere, or matches more than once, must be
skipped rather than guessed at. Someone on an unrecognised build should get an Editor that behaves
exactly as if the shim were not installed — never a corrupted process.

**Never touch the SC2 installation.** Everything happens in the memory of a process we launch.
No file in the StarCraft II folder is written, patched, or replaced. This is what makes the
project safe to run and survive Battle.net updates, and it is not negotiable.

**Keep hooks defensive.** If the object is not what you expect, or anything throws, return the
original value untouched.

## Reporting a bug

Open an issue and include `~/Library/Logs/sc2ed-fix.log`. Its first lines identify the fix
version, SC2 build, macOS version and architecture, which is usually enough to tell a
new-SC2-build problem from an install problem.
