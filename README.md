# Doors

Signed Fedora 44 NVIDIA Open desktop images for `linux/amd64` systems with a Turing-or-newer NVIDIA GPU.

| Image | Desktop |
| --- | --- |
| `ghcr.io/mheci/doors:latest` | GNOME (Silverblue) |
| `ghcr.io/mheci/doors:staging` | Daily GNOME candidate |
| `ghcr.io/mheci/doors-cosmic:latest` | COSMIC |
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
(OpenCode, Pi, Codex, T3, Herdr) are declared in `/etc/mise/config.toml`, installed per user on
first login, and upgraded in place by the hourly user update. No rebase or reboot is needed.

```bash
nvcc --version
ujust doors-ai-status
ujust doors-ai-upgrade      # or: mise upgrade
```

## Gaming

Steam, Heroic, Faugus, umu-launcher, ProtonPlus, Gamescope, and GameMode are native. The latest
**proton-cachyos** (x86_64_v3) is preinstalled system-wide and appears in Steam's compatibility
list; it advances with each weekly image. Installed build: `/usr/share/doors/proton-cachyos.version`.

## Updates

| Layer | Cadence | Mechanism |
| --- | --- | --- |
| Image builds | Weekly, Sunday 03:00 UTC (and on every merge to `main`) | `build.yml` schedule |
| Host image | Weekly, Sunday 04:30 local; staged, applied at next reboot | `doors-update.timer` → `uupd` |
| System Flatpaks | Hourly | `flatpak-system-updates.timer` |
| User Flatpaks, mise tools, Gear Lever AppImages | Hourly per logged-in user | `doors-user-update.timer` |

Flathub is added in its `verified` subset; Bazaar and Gear Lever are provisioned on first
networked boot. Run either stage on demand:

```bash
sudo systemctl start doors-update.service     # host + all local users
systemctl --user start doors-user-update.service
bootc status
```

Host reports: `/var/lib/doors/updates/latest.tsv`. Per-account reports:
`~/.local/state/doors/update-report.tsv`.

## Installer ISO

A GNOME installer ISO is produced from the published `ghcr.io/mheci/doors:latest` on the 1st of
each month (`iso.yml`; also on manual dispatch, never on commits). It is stored as a signed OCI
artifact in split parts.

```bash
month=$(date +%Y-%m)                          # or any published month, e.g. 2026-10
oras pull "ghcr.io/mheci/doors-iso:$month"    # doors-$month.iso.part00.., SHA256SUMS.parts, README
sha256sum --check SHA256SUMS.parts
cat "doors-$month.iso.part"* > "doors-$month.iso"
sha256sum --check "doors-$month.iso.sha256"
cosign verify --key cosign.pub ghcr.io/mheci/doors-iso:$month
```

Write the ISO to USB (`sudo dd if=doors-$month.iso of=/dev/sdX bs=4M status=progress oflag=sync`)
and boot it. Disk layout, encryption, and the first user are chosen in Anaconda; the installed
system follows the update cadence above.

## DNS

The image ships a compatibility default that preserves DHCP, captive-portal, and VPN-provided
resolvers. Strict modes are opt-in and never imposed at first boot.

```bash
ujust dns-status
run0 doors-dns select resolved-quad9      # or resolved-cloudflare, unbound-quad9, unbound-cloudflare
```

## Building

```bash
bluebuild build --push recipes/doors.yml
```

Recipes live in `recipes/`; custom BlueBuild modules live in `modules/`.
