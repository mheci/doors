---
name: doors-recipe
description: Change the Doors OS image definition from the running system.
version: 1.0.0
author: mheci + Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [doors, bootc, bluebuild, image, packages, systemd]
    category: devops
---

# Doors Recipe Skill

Edit the declarative BlueBuild recipes that define this Doors image (RPMs,
Flathub apps, kernel arguments, systemd defaults, mise tools, shipped files),
validate them, and ship the change as a pull request that CI builds and
auto-merges. It does not layer packages onto the booted deployment; `try`
gives a reboot-transient test install only.

## When to Use

- The user wants software, a kernel argument, a service default, or a config
  file to be part of the image for every Doors machine and every reboot.
- The user asks what the image currently declares, or why a build failed.
- Do not use it for one-off, per-user software: prefer `flatpak --user`,
  `mise use -g`, or Gear Lever for that.

## Prerequisites

- `doors-recipe` and `gh` are on PATH on every Doors image.
- One-time: `doors-recipe init` clones `mheci/doors` into
  `~/.local/share/doors/repo` and runs the `gh` device-flow login in the
  user's browser. Never run it unattended without telling the user.
- Every command accepts `--json` anywhere and returns `{ok, command, ...}`;
  a non-zero exit with `ok: false` carries `error`.

## How to Run

Use the `terminal` tool. Typical flow:

```
doors-recipe --json sync                 # start from origin/main
doors-recipe --json add rpm htop tmux    # declare change(s)
doors-recipe --json diff                 # show the user what will ship
doors-recipe --json validate
doors-recipe --json ship -m "feat(recipe): add htop and tmux"
doors-recipe --json status               # PR + build progress
```

## Quick Reference

| Goal | Command |
| --- | --- |
| Declared state | `doors-recipe show` |
| RPM (all images / one desktop) | `add rpm PKG [--profile gnome\|kinoite]` / `remove rpm PKG` |
| Flathub app | `add flatpak org.example.App [--scope user]` |
| Kernel argument | `add karg foo=bar` / `remove karg foo=bar` |
| Service default | `enable unit x.service [--user]` / `disable unit ...` |
| Per-user mise tool | `add mise ripgrep [VERSION]` / `remove mise ripgrep` |
| Ship a file | `add file ./local.conf /etc/foo/local.conf [--executable]` |
| Test now (transient) | `try rpm PKG` (bootc usr-overlay) / `try flatpak ID` |
| Land it | `ship -m "feat(recipe): ..."` (opens labelled PR, auto-merge) |
| Follow up | `prs`, `builds`, `status` |
| Get the new image | `pull` (stages it; reboot afterwards) |
| Abort | `discard` |
| Command map | `schema` |

## Procedure

1. `sync` so the working copy matches `origin/main`; if it reports local
   changes, show `diff` to the user and ask whether to `discard` or `ship`.
2. Make the smallest declarative change that satisfies the request. Prefer
   `--profile common` unless the package only makes sense on GNOME or KDE.
3. Run `validate`; read the `error` text back to the user if it fails.
4. Optionally `try rpm ...` when the user wants to check the package now.
5. `ship -m "<type>(recipe): <summary>"` with `feat`, `fix`, or `chore`.
   The PR carries the `doors-agent` label and squash auto-merge, so it lands
   once the `validate`, `image`, and `dependency-review` checks pass.
6. Report the PR URL. Builds take roughly 30-45 minutes; `status` shows the
   PR checks and the latest main builds. The host applies the new image on
   its weekly schedule, or immediately with `pull` followed by a reboot.

## Pitfalls

- `ship` refuses when nothing changed, when the recipe fails validation, or
  when the commit message lacks a conventional prefix.
- Packages listed in the recipe's `exclude`/`remove` sets (for example
  `firefox`) are refused on purpose; explain rather than work around it.
- Only `/etc` and `/usr` destinations are accepted for `add file`.
- `try rpm` needs polkit authentication (`run0`); it disappears on reboot and
  is not a substitute for shipping.
- Human pull requests still need manual review; only labelled agent PRs
  auto-merge.

## Verification

- `doors-recipe --json validate` reports `"valid": true`.
- `doors-recipe --json prs` lists the PR; `builds` shows the main build that
  follows the merge as `success`.
- After `pull` and a reboot, `doors-recipe status` shows the new
  `booted_digest`.
