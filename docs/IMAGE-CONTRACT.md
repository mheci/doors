# Image contract

## Identity and publication

| Image | Fedora 44 base | Desktop / tag policy |
|---|---|---|
| `ghcr.io/mheci/doors:latest` | `fedora-silverblue-nvidia-open:44` | GNOME stable release. |
| `ghcr.io/mheci/doors:staging` | `fedora-silverblue-nvidia-open:44` | GNOME candidate rebuilt daily from trusted `main`; it remains in the `doors` package and is not published by stable pushes. |
| `ghcr.io/mheci/doors-cosmic:latest` | `fedora-cosmic-nvidia-open:44` | COSMIC release. |
| `ghcr.io/mheci/doors-kinoite:latest` | `fedora-kinoite-nvidia-open:44` | Plasma/Kinoite release. |

All images are `linux/amd64` only and use BlueBuild’s upstream NVIDIA Open composition for Turing-or-newer GPUs. Doors adds no kernel, local akmods module, driver repository, or manual driver/module build.

Stable images publish only from trusted `main` after the repository contract passes. The daily staging workflow is isolated from normal stable pushes. Every trusted image build is Cosign-signed, resolves its own immutable digest, then hands that identity to a fresh runner for Trivy SPDX generation and GitHub OIDC provenance/SBOM attestations. No matrix output is used to relay digest identities.

The base and every Fedora-specific host RPM route are pinned to Fedora 44. This prevents an automatic Fedora-major transition without freezing Fedora 44 updates.

## Shared host policy

- Firefox, Firefox language packs, ordinary Brave, GameMode, and GameMode libraries are removed.
- Supported browsers are Brave Origin, Zen, and Helium.
- Fedora-signed Gamescope, Steam, Heroic, Faugus, ProtonPlus, umu-launcher, Vesktop, Falcond, Ananicy-cpp, scx, developer tools, Bazaar, and DistroShelf support are shared across the family.
- GNOME dconf defaults and GNOME Shell extensions are confined to `doors` and `doors:staging`.
- COSMIC seeds `is_dark=true` only when its per-user preference does not exist. It never overwrites a later user choice.
- Kinoite supplies user-overridable `/etc/xdg/kdeglobals` defaults for native Breeze Dark. Its SteamOS-inspired desktop mode uses no Valve assets and does not autostart Steam Big Picture or Game Mode.
- `uupd.timer` is the single automatic update coordinator. Its system, Flatpak, and Distrobox modules are enabled; Homebrew updates are disabled. BlueBuild’s competing bootc/Flatpak timers are disabled.
- `uupd` arrives only from the narrow `ublue-os/packages` Fedora 44 COPR route with RPM GPG verification. COPR metadata is not signed, so that residual replay/downgrade limitation is explicit.

## AI Distrobox and CUDA

Each image supplies `podman`, `distrobox`, `doors-ai`, and a global user unit that initializes one rootless GPU-aware `doors-ai` container at graphical login.

- The container image is `docker.io/library/archlinux:latest` with Distrobox `nvidia=true` integration.
- Its bootstrap runs one signed official-Arch `pacman -Syu` transaction for Arch keyring, development tools, Node/npm/pnpm, Deno, mise, OpenCode, Python tooling, and `cuda`. It installs no AUR helper, external repository definition, `nvidia-utils`, or driver package.
- Arch `cuda` supplies `/opt/cuda` and `nvcc`; Distrobox NVIDIA integration exposes the host GPU/driver stack.
- Bun verifies a clear-signed upstream checksum. Pi and T3 Code use npm’s canonical registry with integrity metadata and lifecycle scripts disabled. Herdr is immutable-release-attestation-verified in CI, mounted read-only, digest-checked again, and installed only in the container.
- Existing pre-Arch containers are not silently replaced. `doors-ai recreate` is the explicit, destructive migration operation after users export container-local work.

The immutable host never layers Bun, Pi, T3 Code, Herdr, Node/npm/pnpm, Deno, mise, OpenCode, or the CUDA toolkit.

## Flatpak policy

Flathub is statically configured with its reviewed complete GPG-fingerprint set. `doors-flatpak-bootstrap.service` runs after a networked boot and installs exactly:

- `io.github.kolunmi.Bazaar`
- `com.ranfdev.DistroShelf`

plus only the runtime dependencies Flatpak declares. No Bazzite preinstall descriptor, BlueBuild `default-flatpaks` manager, Flatseal, pwvucontrol, or additional application-preinstall path remains.

## Secure Boot and validation

BlueBuild signs its NVIDIA kernel/modules with its own MOK. A Secure-Boot-enforcing target must complete BlueBuild’s documented MOK enrollment before migration. CI verifies composition and provenance but cannot validate firmware enrollment, NVIDIA/Wayland behavior, Distrobox GPU passthrough, or hardware suspend/resume; those remain mandatory physical release gates.
