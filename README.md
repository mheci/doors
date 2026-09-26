# Doors

Signed Fedora 44 NVIDIA Open desktop images for `linux/amd64` systems with a Turing-or-newer NVIDIA GPU.

| Image | Desktop |
| --- | --- |
| `ghcr.io/mheci/doors:latest` | GNOME (Silverblue) |
| `ghcr.io/mheci/doors-kinoite:latest` | Plasma (Kinoite) |

## Rebase

Verify, then switch. Use any image from the table as `$image`.

```bash
image=ghcr.io/mheci/doors:latest
cosign verify --key cosign.pub "$image"
gh attestation verify "oci://$image" --owner mheci
sudo bootc switch "$image"
sudo systemctl reboot
```

After rebooting, inspect the deployment with `bootc status`. Roll back with
`sudo bootc rollback && sudo systemctl reboot`.

## Secure Boot

Composed kernel payloads and modules are signed with the public Doors MOK shipped in each image.
Compare the release certificate, queue enrollment, then approve it in **MokManager** at the next boot:

```bash
doors-secureboot fingerprint
sudo doors-secureboot enroll
doors-secureboot status
sudo doors-secureboot verify
```

`ujust doors-secureboot-enroll` and `ujust doors-secureboot-status` are equivalent entry points.

## Toolchain

CUDA 13.4, Node 24, Bun, Deno, and mise are part of the immutable image. The agent CLIs
(OpenCode, Pi, Codex, Herdr) are declared in `/etc/mise/config.toml`, installed per user on
first login, and upgraded in place by the hourly user update. No rebase or reboot is needed.

```bash
nvcc --version
ujust doors-ai-status
ujust doors-ai-upgrade      # or: mise upgrade
```

## Hermes Agent

`doors-hermes-install.service` runs the upstream installer for each account on first login
(`~/.hermes`, launcher `~/.local/bin/hermes`, desktop app + `hermes.desktop` entry, stable release
channel, no gateway). The hourly user update runs `hermes update`. Configure a provider once:

```bash
hermes setup                 # or: hermes model / hermes config set
hermes                       # CLI;  hermes desktop  # Electron app
ujust doors-hermes-install   # re-run the installer now
```

## Changing the image from a running system

`doors-recipe` edits the recipes declaratively, validates them, and ships a pull request that CI
builds, lints (`bootc container lint` + smoke checks), and auto-merges. Every command takes
`--json`; `doors-recipe schema` lists the command map for agents. A Hermes skill is preinstalled.

```bash
doors-recipe init                                  # clone + gh device login (once)
doors-recipe add rpm htop tmux
doors-recipe add flatpak org.gnome.Boxes
doors-recipe enable unit foo.service --user
doors-recipe try rpm htop                          # transient bootc usr-overlay test
doors-recipe ship -m "feat(recipe): add htop and tmux"
doors-recipe status                                # PR checks and main builds
```

## Gaming

Steam, Heroic, Faugus, umu-launcher, ProtonPlus, Gamescope, and GameMode are native. The latest
**proton-cachyos** (x86_64_v3) is preinstalled system-wide and appears in Steam's compatibility
list; it advances with each weekly image. Installed build: `/usr/share/doors/proton-cachyos.version`.

## Updates

| Layer | Cadence | Mechanism |
| --- | --- | --- |
| Image builds | Weekly, Sunday 03:00 UTC (and on every merge to `main`) | `build.yml` |
| Boot test of published images | Weekly, Sunday 06:00 UTC | `boot-test.yml` |
| Host image | Weekly, Sunday 04:30 local; staged, applied at next reboot | `doors-update.timer` → `uupd` |
| System Flatpaks | Hourly | `flatpak-system-updates.timer` |
| User Flatpaks, mise tools, Hermes, Gear Lever AppImages | Hourly per logged-in user | `doors-user-update.timer` |

Flathub is added in its `verified` subset; Bazaar and Gear Lever are provisioned on first
networked boot. Run either stage on demand:

```bash
sudo systemctl start doors-update.service     # host + all local users
systemctl --user start doors-user-update.service
bootc status
```

Host reports: `/var/lib/doors/updates/latest.tsv`. Per-account reports:
`~/.local/state/doors/update-report.tsv`.

## DNS

The image ships a compatibility default that preserves DHCP, captive-portal, and VPN-provided
resolvers. Strict modes are opt-in and never imposed at first boot.

```bash
ujust dns-status
run0 doors-dns select resolved-quad9      # or resolved-cloudflare, unbound-quad9, unbound-cloudflare
```

## Building and CI

```bash
.github/scripts/validate.sh              # schema, policy, tests, lint (no build)
bluebuild build recipes/doors.yml
```

Recipes live in `recipes/`, custom BlueBuild modules in `modules/`. Pull requests run `validate`
then a no-push build of both images with `bootc container lint` and `.github/scripts/smoke.sh`;
merges to `main` publish, sign, attest (provenance + SPDX SBOM), and re-run the smoke checks on
the published digest. Dependabot and `doors-recipe` PRs auto-merge when green; human PRs need a
review.
