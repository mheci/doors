# Doors package and service manifest

**Status:** source contract only. It is not evidence that a compose, publication, or hardware validation has passed.

## Foundation

- Base: `ghcr.io/blue-build/base-images/fedora-silverblue-nvidia-open:44`, AMD64 only.
- BlueBuild supplies the Fedora kernel, NVIDIA Open modules/userspace, CUDA driver runtime, and NVIDIA Container Toolkit. Doors adds no akmods, alternate driver route, custom kernel, or manual module build.
- Fedora-specific host, Distrobox, and third-party RPM routes are pinned to Fedora 44. The tag accepts current F44 updates but cannot advance to a new Fedora major without review.
- Secure-Boot-enforcing systems require BlueBuild MOK enrollment.

## Host repositories and packages

| Source | Approved scope |
|---|---|
| Fedora 44 | Host desktop/CLI/device packages, Podman, Distrobox, Fedora Gamescope, themes, fonts, GNOME integration. |
| BlueBuild-managed Negativo17 Multimedia Fedora 44 | Steam and matching multilib codec dependencies. |
| Terra 44 | Heroic, ProtonPlus, umu-launcher, Vesktop, Falcond, Ananicy-cpp/rules, scx, Ghostty, Zed, Zen, Vicinae, requested RPM extensions. |
| Faugus COPR Fedora 44 | `faugus-launcher` only. |
| Helium COPR Fedora 44 | `helium-bin` only. |
| Brave official RPM | `brave-origin` and its constrained keyring dependency only. |
| UBlue packages COPR Fedora 44 | `uupd` only. |

Every route has `gpgcheck=1`; Terra/Brave metadata is signed. Negativo17 Multimedia plus Faugus, Helium, and UBlue COPR metadata is not signed, an explicit residual risk. Firefox, Firefox language packs, ordinary Brave, GameMode, and GameMode libraries are removed. Supported browsers are Brave Origin, Zen, and Helium.

## Automatic updates

- `uupd.timer` is enabled with its system, Flatpak, and Distrobox modules enabled; Homebrew is disabled.
- BlueBuild’s `bootc-fetch-apply-updates.timer`, `flatpak-system-updates.timer`, and global `flatpak-user-updates.timer` are disabled to avoid concurrent managers.
- Performance services `falcond.service`, `ananicy-cpp.service`, and `scx_loader.service` remain enabled.

## AI Distrobox

`doors-ai-distrobox.service` initializes one rootless GPU-aware `doors-ai` Distrobox from `registry.fedoraproject.org/fedora-toolbox:44`.

Inside it, not the host image:

- Node/npm/pnpm, Deno, mise, t3code, OpenCode, Python/pip, compiler tools;
- Bun with a PGP-verified release checksum;
- Pi coding agent from the canonical npm registry with integrity verification and lifecycle hooks disabled;
- Herdr from CI’s GitHub immutable-release-attestation-verified artifact;
- full CUDA toolkit from NVIDIA’s signed Fedora 44 repository.

The CUDA repository excludes host-driver packages. The base image remains the only NVIDIA host driver source.

## Flatpak

A static Flathub remote with the reviewed complete key set is installed. `doors-flatpak-bootstrap.service` provisions exactly:

- `io.github.kolunmi.Bazaar`
- `com.ranfdev.DistroShelf`

and their required runtimes. No other automatic Flatpak provisioner is permitted.

## Other controlled routes

- `wl-clip-persist` is built from the resolved immutable upstream release commit using its Cargo lockfile.
- Clipboard Indicator, Alphabetical App Grid, and Emoji Copy use the official GNOME Extensions route.
- Vicinae and `wl-clip-persist` remain global graphical user services; clipboard persistence is regular-clipboard-only.

## Release controls

Pull requests receive a real non-publishing BlueBuild compose with an ephemeral key. Trusted releases sign the OCI image, resolve an immutable digest, generate a Trivy SPDX SBOM, and upload GitHub OIDC provenance/SBOM attestations. Protected PR checks and native bot auto-merge remain required.
