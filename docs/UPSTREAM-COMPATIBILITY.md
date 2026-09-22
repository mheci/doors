# Upstream compatibility and fail-closed rebuild policy

Doors consumes these deliberate Fedora 44 stream pins:

- `ghcr.io/blue-build/base-images/fedora-silverblue-nvidia-open:44`
- `ghcr.io/blue-build/base-images/fedora-cosmic-nvidia-open:44`
- `ghcr.io/blue-build/base-images/fedora-kinoite-nvidia-open:44`

They accept current Fedora 44 updates but do not move to Fedora 45+ until a reviewed change refreshes trust material, solves dependencies, and passes physical validation.

## Base responsibilities

BlueBuild composes and signs the Fedora kernel, NVIDIA Open modules, NVIDIA userspace, CUDA driver runtime, and NVIDIA Container Toolkit for each desktop family. Doors does not layer local `akmods`, an alternate driver repository, a custom kernel, manual kmods, or a Mesa-synchronization transaction.

Fedora’s signed `gamescope` RPM is layered because these NVIDIA Open bases do not inherit Bazzite’s `terra-gamescope` package. Steam uses BlueBuild’s supported `negativo17` nonfree route instead of RPM Fusion. The base already carries the matching codec stack; enabling its Fedora 44 multilib route lets DNF solve Steam dependencies without replacing that stack.

GNOME dconf/default extensions, COSMIC theme seeding, and Plasma defaults are separate profile payloads. The COSMIC profile writes dark mode only if absent. The Kinoite profile uses existing KDE Breeze assets and leaves Steam in normal desktop mode.

## Update responsibilities

The owner selected `uupd` as Doors’ single automatic coordinator. It is installed from the narrow UBlue packages COPR Fedora 44 route with RPM signature checking and enabled as `uupd.timer`. Its system, Flatpak, and Distrobox modules are enabled; Homebrew is disabled.

To prevent competing deployment/Flatpak transactions, Doors disables BlueBuild’s `bootc-fetch-apply-updates.timer`, `flatpak-system-updates.timer`, and `flatpak-user-updates.timer`. This is a reviewed coordination decision, not a disabled-update workaround: `uupd` retains the bootc, Flatpak, and Distrobox responsibilities.

## Distrobox/CUDA compatibility

`doors-ai` uses `docker.io/library/archlinux:latest` with Distrobox NVIDIA integration. Its bootstrap refreshes the Arch keyring and installs development tooling, OpenCode, and the full CUDA toolkit from signed official Arch repositories. It uses no AUR helper, Terra/Fedora repository, NVIDIA CUDA repository, container driver package, or `nvidia-utils` package.

Arch `cuda` supplies `/opt/cuda` and `nvcc`; the host’s NVIDIA path remains authoritative through Distrobox GPU integration. Bun checksum verification, npm lifecycle hardening for Pi/T3 Code, and the attestation-verified Herdr payload remain unchanged. Existing pre-Arch boxes require explicit `doors-ai recreate`, preventing silent deletion of user-space mutable data.

The initial container creation and GPU passthrough require hardware validation. A failed container bootstrap, package solve, or signature check fails visibly and must not be worked around with a kernel pin, driver fallback, repository bypass, or Secure Boot disablement.

## Secure Boot

BlueBuild documents a distinct MOK for its signed kernel/modules. Before switching a Secure-Boot-enforcing system, enroll that MOK using the [upstream migration guide](https://github.com/blue-build/base-images#migration-from-ublue-base-images). Doors does not automate or bypass this firmware security boundary.

## Escalation

If a BlueBuild Fedora 44 base, Fedora 44 repository, Arch CUDA/OpenCode package, `uupd`, or GPU passthrough becomes incompatible, stop that release path and investigate upstream. A future Fedora-major move, immutable-base policy, updater replacement, driver-flavor change, desktop-profile trust change, or repository trust change is material and requires review.
