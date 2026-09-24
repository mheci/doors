# Doors

Doors is a signed Fedora 44 NVIDIA Open desktop-image family for `linux/amd64` systems with a Turing-or-newer NVIDIA GPU. Every published digest is Cosign-signed, scanned, supplied with an SPDX SBOM, and attested through GitHub OIDC.

## Images

| Image | Desktop and release channel |
| --- | --- |
| [`ghcr.io/mheci/doors:latest`](https://github.com/mheci/doors/pkgs/container/doors) | Stable GNOME / Fedora Silverblue release. |
| `ghcr.io/mheci/doors:staging` | Daily GNOME candidate rebuilt from trusted `main`; it is not published on normal stable pushes. |
| `ghcr.io/mheci/doors-cosmic:latest` | Fedora COSMIC release with a dark first-run preference that remains user-overridable. |
| `ghcr.io/mheci/doors-kinoite:latest` | Fedora Kinoite / Plasma release with a SteamOS-inspired desktop mode using native Breeze assets. Steam remains a normal desktop application; Big Picture and Game Mode do not autostart. |

All images share the native gaming, development, AI, update, Flatpak, and signing contract. GNOME Shell defaults and extensions ship only in the GNOME images.

## Native development and AI tools

The toolchain is layered directly into every immutable image: Node/npm/pnpm, Python/pip and C/C++ build tools; Bun, Deno, mise, OpenCode, Pi, and the pinned T3 Code CLI; CUDA Toolkit 13.4; and attestation-verified Herdr. No per-user setup, export wrapper, or container runtime is required.

```bash
doors-ai status
doors-ai run nvcc --version
opencode --version
herdr --version
```

`doors-ai` is a convenience wrapper; every listed command is also available directly on the native host. The native CUDA profile exports `CUDA_HOME=/usr/local/cuda-13.4`; `nvcc` is also available in `/usr/local/bin`.

## Rebase and Secure Boot

Doors CI signs the fully composed kernel PE/COFF payloads and loadable modules with the public Doors MOK shipped in each image. For a release, the matching private PEM exists only as the protected `DOORS_MOK_SIGNING_KEY` GitHub environment secret during trusted publication; it is not in Git, an image layer, a log, or a release artifact.

Before booting a Secure-Boot-enforcing target, compare the release certificate identity with `doors-secureboot fingerprint`, then queue it and reboot:

```bash
sudo doors-secureboot enroll
```

At the next boot, the physical machine owner must approve enrollment (and MOK trust, if requested) in **MokManager** using the one-time password. CI cannot complete that firmware-owner action. After booting, run `doors-secureboot status` and `sudo doors-secureboot verify`. `ujust doors-secureboot-enroll` and `ujust doors-secureboot-status` provide the same convenience entry points. Maintainers must follow the [MOK operations runbook](docs/SECURE-BOOT-OPERATIONS.md) before a release key is activated or rotated.

Select one image, verify it, then switch:

```bash
image=ghcr.io/mheci/doors:latest
cosign verify --key cosign.pub "$image"
gh attestation verify "oci://$image" --owner mheci
sudo bootc switch "$image"
sudo systemctl reboot
```

Use any image from the table in place of `doors:latest`. After rebooting, inspect the active deployment with `bootc status`.

## Updates and recovery

`doors-update.timer` is the daily system-wide coordinator. It uses `uupd` for immutable-host staging, then updates supported system and regular-user scopes through each user’s systemd manager. Bazaar and [Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) are provisioned as system Flatpaks on first networked boot. Gear Lever updates AppImages it manages; copied binaries, tarballs, and AppImages without update metadata are reported, never executed as updaters.

```bash
sudo systemctl start doors-update.service
sudo systemctl status doors-update.service
bootc status
sudo bootc rollback
sudo systemctl reboot
```

Per-account reports are at `~/.local/state/doors/update-report.tsv`; the host coordinator report is `/var/lib/doors/updates/latest.tsv`.

See the [image contract](docs/IMAGE-CONTRACT.md) and [test plan](docs/TEST-PLAN.md) for release and hardware-validation details.
