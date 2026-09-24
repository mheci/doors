# Doors package and service manifest

**Status:** source contract only. It is not evidence that a compose, publication, or hardware validation has passed.

## Foundation

- Bases: BlueBuild Fedora Silverblue, COSMIC, and Kinoite NVIDIA Open `:44`, AMD64 only.
- BlueBuild supplies the Fedora kernel, NVIDIA Open modules/userspace, CUDA driver runtime, and NVIDIA Container Toolkit. Doors adds no akmods, alternate driver route, custom kernel, or manual module build.
- Fedora-specific host and third-party RPM routes are pinned to Fedora 44. The tag accepts current F44 updates but cannot advance to a new Fedora major without review.
- Secure-Boot-enforcing systems require Doors MOK enrollment.

## Host repositories and packages

| Source | Approved scope |
|---|---|
| Fedora 44 | Host desktop/CLI/device packages, compiler/runtime baseline, Fedora Gamescope, themes, fonts, GNOME integration. |
| BlueBuild-managed Negativo17 Multimedia Fedora 44 | Steam and matching multilib codec dependencies. |
| Terra 44 | Heroic, ProtonPlus, umu-launcher, Vesktop, Falcond, Ananicy-cpp/rules, scx, Ghostty, Zed, Zen, Vicinae, Bun, Deno, mise, and OpenCode CLI. |
| npm registry | Tracked, integrity-locked native Pi and `t3` CLI packages and their Linux x86_64 platform payloads; lifecycle scripts are disabled. |
| NVIDIA CUDA Fedora 44 x86_64 | `cuda-toolkit-13-4` only; driver-runtime/replacement packages are excluded while toolkit development headers and stubs resolve transitively. |
| Faugus COPR Fedora 44 | `faugus-launcher` only. |
| Helium COPR Fedora 44 | `helium-bin` only. |
| Brave official RPM | `brave-origin` and its constrained keyring dependency only. |
| UBlue packages COPR Fedora 44 | `uupd` only. |

Every route has `gpgcheck=1`; Terra, NVIDIA CUDA, and Brave metadata is signed. Negativo17 Multimedia plus Faugus, Helium, and UBlue COPR metadata is not signed, an explicit residual risk. Firefox, Firefox language packs, ordinary Brave, GameMode, and GameMode libraries are removed. Supported browsers are Brave Origin, Zen, and Helium.

## Automatic updates

- `uupd` is restricted to its system module; Homebrew and Flatpak modules are disabled.
- BlueBuild’s `bootc-fetch-apply-updates.timer`, `flatpak-system-updates.timer`, and global `flatpak-user-updates.timer` are disabled to avoid concurrent managers.
- Performance services `falcond.service`, `ananicy-cpp.service`, and `scx_loader.service` remain enabled.

## Native development and AI tools

Every image contains, on the immutable host:

- Node/npm/pnpm, Python/pip, and C/C++ build tools;
- Bun, Deno, mise, and OpenCode CLI as signed Terra RPMs; Pi coding agent from its tracked npm lock;
- the original T3 Code CLI from a tracked npm lock that pins its tarball identities and SRI digests, installed with lifecycle scripts disabled;
- full CUDA Toolkit 13.4, Nsight Compute, and Nsight Systems at `/usr/lib/doors/cuda-13.4`, relocated in the same signed-RPM compose layer from the vendor’s mutable `/usr/local` and `/opt/nvidia` payloads, with `/usr/bin/nvcc`, `/usr/bin/ncu`, `/usr/bin/nsys`, and an environment profile;
- Herdr from the CI GitHub immutable-release-attestation-verified artifact, rechecked by manifest and digest before installation at `/usr/bin/herdr`.

No per-user setup, command export, or container-managed toolchain is part of the image contract. Rebase never destroys existing user data or workloads.

## Flatpak

A static Flathub remote with the reviewed complete key set is installed. `doors-flatpak-bootstrap.service` provisions exactly:

- `io.github.kolunmi.Bazaar`
- `it.mijorus.gearlever`

and their required runtimes. No other automatic Flatpak provisioner is permitted.

## Other controlled routes

- `wl-clip-persist` is built from a hash-verified upstream source archive pinned to release `v0.5.0` and immutable commit `e26fde01c13922e3a65049dafb7d5adfbc52626e`, using its Cargo lockfile.
- Clipboard Indicator, Alphabetical App Grid, and Emoji Copy use the official GNOME Extensions route.
- Vicinae and `wl-clip-persist` remain global graphical user services; clipboard persistence is regular-clipboard-only.

## Release controls

Pull requests receive a real non-publishing BlueBuild compose with an ephemeral key. Trusted releases sign the OCI image, resolve an immutable digest, generate a Trivy SPDX SBOM, and upload GitHub OIDC provenance/SBOM attestations. Protected PR checks and native bot auto-merge remain required.
