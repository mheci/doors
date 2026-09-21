# Image contract

## Identity

| Property | Contract |
|---|---|
| Public image | `ghcr.io/mheci/doors:latest` |
| Architecture | `linux/amd64` only |
| Base | `ghcr.io/blue-build/base-images/fedora-silverblue-nvidia-open:44` |
| Desktop | GNOME + GDM only |
| GPU | BlueBuild’s upstream NVIDIA Open composition for Turing-or-newer GPUs; Doors adds no kernel, local akmods module, driver repository, or manual module build |
| Publication | Monday 00:00 UTC, trusted `main`, or manual `main` |

The base and every Fedora-specific RPM route are intentionally pinned to Fedora 44. This prevents an automatic jump to a future Fedora major; it does **not** freeze Fedora 44 security/package updates. A separate reviewed change is required for a future major stream.

## Host policy

- Firefox, Firefox language packs, ordinary Brave, GameMode, and GameMode libraries are removed.
- The supported browsers are Brave Origin, Zen, and Helium.
- Fedora’s signed `gamescope`, Steam, Heroic, Faugus, ProtonPlus, umu-launcher, Vesktop, Falcond, Ananicy-cpp, scx, GNOME integration, and requested desktop tooling remain host packages.
- `uupd.timer` is the **single** automatic update coordinator. Its system, Flatpak, and Distrobox modules are enabled; Homebrew updates are disabled. BlueBuild’s `bootc-fetch-apply-updates.timer`, `flatpak-system-updates.timer`, and `flatpak-user-updates.timer` are disabled so no deployment or Flatpak manager races uupd.
- `uupd` arrives only from the narrow `ublue-os/packages` Fedora 44 COPR route with RPM GPG verification. Its metadata is not signed by COPR, so that residual replay/downgrade limitation is explicit.

## AI Distrobox and CUDA

The image supplies `podman`, `distrobox`, the `doors-ai` launcher, and a global user unit that initializes one rootless `doors-ai` container at first graphical login.

- The container image is `registry.fedoraproject.org/fedora-toolbox:44`, GPU-enabled with Distrobox’s `nvidia=true` integration.
- It installs Node/npm/pnpm, Deno, mise, t3code, OpenCode, Bun, Pi, Herdr, Python tooling, compiler tools, and the full CUDA toolkit **inside the container**, not into the immutable host deployment.
- Bun verifies a clear-signed upstream checksum. Pi uses only npm’s canonical registry with integrity data and lifecycle hooks disabled. Herdr is fetched and immutable-release-attestation-verified in CI, mounted read-only into the container setup, verified again, then installed only in the container.
- The CUDA repository is NVIDIA’s Fedora 44 endpoint with a vendored reviewed GPG key and signed metadata. Driver, driver-CUDA, persistence, settings, and container-toolkit packages are excluded: BlueBuild’s base remains the only host-driver path.

## Flatpak policy

Flathub is statically configured with its reviewed complete GPG-fingerprint set. `doors-flatpak-bootstrap.service` runs after a networked boot and installs exactly:

- `io.github.kolunmi.Bazaar`
- `com.ranfdev.DistroShelf`

plus only the runtime dependencies Flatpak declares. No Bazzite preinstall descriptor, BlueBuild `default-flatpaks` manager, Flatseal, pwvucontrol, or other application preinstall path remains.

## Secure Boot and validation

BlueBuild signs its NVIDIA kernel/modules with its own MOK. A Secure-Boot-enforcing target must complete BlueBuild’s documented MOK enrollment before migration. CI verifies composition and provenance but cannot validate firmware enrollment, NVIDIA/Wayland behavior, Distrobox GPU passthrough, or hardware suspend/resume; those remain mandatory physical release gates.
