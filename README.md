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
first login, and upgraded in place by the daily user update. No rebase or reboot is needed.

```bash
nvcc --version
ujust doors-ai-status
ujust doors-ai-upgrade      # or: mise upgrade
```

## Updates

`doors-update.timer` is the sole daily coordinator: `uupd` stages the immutable host, then each
user's systemd manager updates Flatpaks, mise tools, and other account-owned tooling. Flathub is added in its `verified`
subset; Bazaar and Gear Lever are provisioned on first networked boot.

```bash
sudo systemctl start doors-update.service
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

## Building

```bash
bluebuild build --push recipes/doors.yml
```

Recipes live in `recipes/`; custom BlueBuild modules live in `modules/`.
