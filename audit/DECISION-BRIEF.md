# Doors decision brief

## Approved image policy

- Three AMD64 bootc images: stable GNOME `ghcr.io/mheci/doors:latest`, COSMIC `ghcr.io/mheci/doors-cosmic:latest`, and Kinoite `ghcr.io/mheci/doors-kinoite:latest`; the sole daily candidate is `ghcr.io/mheci/doors:staging`.
- Bases: the corresponding BlueBuild Fedora 44 NVIDIA Open images.
- BlueBuild owns the NVIDIA Open kernel/module/userspace path. Doors never adds an alternate driver, local akmods, custom kernel, or manual module build.
- Secure-Boot targets must enroll the Doors MOK before migration.

## Fedora 44 stream policy

The base, Fedora-specific RPM repositories, Terra endpoint, third-party COPR endpoints, UBlue packages endpoint, and NVIDIA CUDA toolkit endpoint are fixed to Fedora 44. This prevents a silent future-major jump while allowing maintained Fedora 44 package updates. A major-stream change requires a reviewed design/physical validation update.

## Updates

`uupd` is installed only from the narrow UBlue packages Fedora 44 COPR route and is used only for immutable host staging. Doors' timer coordinates system/user Flatpak work, explicitly label-managed Podman updates when present, Gear Lever-managed AppImages, and approved per-user adapters. BlueBuild’s individual bootc/system-Flatpak/user-Flatpak update timers are disabled to prevent competing transactions. The UBlue COPR RPM key is reviewed; its unsigned metadata is an accepted, documented limitation.

## Applications

- Browsers: Brave Origin, Zen, Helium. Firefox and ordinary Brave are removed.
- Gaming/performance: Steam, Heroic, Faugus, ProtonPlus, umu-launcher, Vesktop, Fedora Gamescope, Falcond, Ananicy-cpp, and scx.
- System Flatpaks: Bazaar and Gear Lever only, plus their declared runtimes.

## Native AI environment

Node/npm/pnpm, Deno, mise, T3 Code, OpenCode CLI, Bun, Pi, Herdr, compiler tools, Python tooling, and the full CUDA 13.4 toolkit are native image content across all desktop variants. Fedora supplies the baseline tools; Terra packages Bun, Deno, mise, OpenCode CLI, and Pi; the original `t3` CLI is installed from its tracked integrity-locked npm input with lifecycle scripts disabled; and the signed NVIDIA CUDA Fedora 44 route supplies only the toolkit and is excluded from replacing the base-owned driver/userspace stack. Herdr remains CI immutable-release-attestation verified and is rechecked before native installation.

## Release gate

Protected PR checks, signed image publication, SPDX SBOM, GitHub OIDC provenance/SBOM attestations, physical NVIDIA/Wayland/Secure-Boot validation, native CUDA validation, and rollback validation remain required. A build or validation failure fails closed; it does not authorize an unreviewed fallback, resolver bypass, driver workaround, or direct branch-protection bypass.
