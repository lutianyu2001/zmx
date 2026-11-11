# CLAUDE.md

This is lutianyu2001/zmx, Tianyu Lu's fork of neurosnap/zmx, the session manager.

## Branches

The fork follows gh-fork-layout: `upstream` mirrors neurosnap/zmx, `main` is ours, and feature branches start from
`upstream` and are kept after merging, so they can still be PRed to neurosnap/zmx. A change only for this fork, like
this file, is committed straight to main.

PRs are written in English, also into this fork, in the user's words "PR 全都用英语!" and "PR 的模板要按 /gen-tlu-pr
来". Keep talking to the user in Chinese.

## Releases

A release's tag is the next upstream version plus `-mod.X.Y` (decided 2026-11-11): Y counts the releases, and X goes
up, with Y back at 1, when a release breaks compatibility with the one before it (the IPC, file names, settings). The
numbering restarted at `v0.8.2-mod.1.1`: the releases `v0.8.2-mod.1` and `v0.8.2-mod.2` and their tags were deleted,
and the few machines that had them are reinstalled by hand. The version is in `build.zig.zon`, which the release
commit (`chore(release): release v<version>`) changes and the release workflow checks against the tag.

## How the user runs zmx

The user connects with Zap over SSH into the build machine and runs `zmx attach claudeN`. Each zmx session holds an
un-warpified bash running `claude --resume`, so this very session may be running inside one. Never disturb a live
session: test only with a throwaway `ZMX_DIR`, and only replace the installed zmx once those sessions can end, since
the IPC can change between versions.

## Building and testing

- Build with Zig 0.17.0 and `-Dtarget=x86_64-linux-musl`.
- Zig on this machine comes from pixi global, whose manifest pins an exact version, so `pixi global update zig` keeps
  it; move to a new one with `pixi global install "zig==<version>"` (seen with pixi 0.79.0).
- The bats suite fails with `NameTooLong` when `TMPDIR` is a long path (socket path limit), so run it with a short
  `TMPDIR`.

## Packages

zmx's recipe for q0wkp/pkgs is in that repository, `recipes/zmx/`, whose Sync workflow packages each release when the
`pkgs` job in `release.yml` asks it to (with the `PKGS_DISPATCH_TOKEN` secret). Sync has no schedule, so a release
that job didn't reach waits for Sync to be run by hand.
The pkgs README says how publishing works.

The recipe publishes `zmx-bin` (pacman, Pacstall) and the formula `zmx` (Homebrew), and beside them `zmx-git` for all
three, which the user's own machine builds from main (q0wkp/pkgs publishes only its PKGBUILD, pacscript and formula).
Those read `minimum_zig_version` from `build.zig.zon` and download that Zig themselves, so a new Zig needs no change
there; a change to how zmx is built does (the `zig build` options, where `LICENSE` and `packaging/third-party` are):
the three templates `recipes/zmx/zmx-git.*.in` and `homebrew-git.rb.in` in q0wkp/pkgs repeat it.
