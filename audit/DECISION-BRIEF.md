# Doors decision brief

## Approved image policy

- One AMD64 bootc image: `ghcr.io/mheci/doors:latest`.
- Base: `ghcr.io/blue-build/base-images/fedora-silverblue-nvidia-open:44`.
- GNOME/GDM only; no ISO or desktop/architecture matrix.
- BlueBuild owns the NVIDIA Open kernel/module/userspace path. Doors never adds an alternate driver, local akmods, custom kernel, or manual module build.
- Secure-Boot targets must enroll BlueBuild’s MOK before migration.

## Fedora 44 stream policy

The base, Fedora-specific RPM repositories, Fedora Toolbox Distrobox, Terra endpoint, third-party COPR endpoints, UBlue packages endpoint, and NVIDIA CUDA endpoint are fixed to Fedora 44. This prevents a silent future-major jump while allowing maintained Fedora 44 package updates. A major-stream change requires a reviewed design/physical validation update.

## Updates

`uupd` is installed only from the narrow UBlue packages Fedora 44 COPR route and `uupd.timer` is enabled. It coordinates bootc, Flatpak, and Distrobox updates. BlueBuild’s individual bootc/system-Flatpak/user-Flatpak update timers are disabled to prevent competing transactions. The UBlue COPR RPM key is reviewed; its unsigned metadata is an accepted, documented limitation.

## Applications

- Browsers: Brave Origin, Zen, Helium. Firefox and ordinary Brave are removed.
- Gaming/performance: Steam, Heroic, Faugus, ProtonPlus, umu-launcher, Vesktop, Fedora Gamescope, Falcond, Ananicy-cpp, and scx.
- System Flatpaks: Bazaar and DistroShelf only, plus their declared runtimes.

## AI environment

`doors-ai` is a rootless GPU-enabled Fedora Toolbox 44 Distrobox. Node/npm/pnpm, Deno, mise, t3code, OpenCode, Bun, Pi, Herdr, compiler tools, Python tooling, and the full CUDA toolkit live in that container rather than the immutable host. NVIDIA’s Fedora 44 CUDA repository is key-validated and configured not to replace the host driver.

## Release gate

Protected PR checks, signed image publication, SPDX SBOM, GitHub OIDC provenance/SBOM attestations, physical NVIDIA/Wayland/Secure-Boot validation, Distrobox GPU validation, and rollback validation remain required. A build or validation failure fails closed; it does not authorize an unreviewed fallback, resolver bypass, driver workaround, or direct branch-protection bypass.
