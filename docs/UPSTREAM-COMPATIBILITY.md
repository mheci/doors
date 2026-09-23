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

The owner selected `doors-update.timer` as Doors’ single automatic coordinator. `uupd`, installed from the narrow UBlue packages COPR Fedora 44 route with RPM signature checking, remains the coordinator’s immutable-host engine; its Flatpak, Distrobox, and Homebrew modules are disabled so they cannot race the cross-account transaction.

The coordinator stages bootc/rpm-ostree updates through `uupd`, then handles system/user Flatpaks, root and rootless Distroboxes, label-managed Podman containers, supported Homebrew roots, Gear Lever-managed AppImages, and opt-in user package managers in the correct ownership scope. It starts a lingering systemd user manager for each eligible regular local account, including accounts not logged in at timer time.

To prevent competing transactions, Doors disables `uupd.timer`, BlueBuild’s `bootc-fetch-apply-updates.timer`, `flatpak-system-updates.timer`, `flatpak-user-updates.timer`, and system/user Podman auto-update timers. This is a reviewed coordination decision, not a disabled-update workaround: each supported responsibility is retained by `doors-update.service` and recorded in host or per-user reports.

## Boot health and rollback

Fedora 44 provides the Rust rewrite as the `greenboot` RPM package. It is valuable here because `uupd` stages an immutable bootc/rpm-ostree deployment for a later manual reboot: Greenboot’s paired health-check and staged-deployment trigger can then retry and roll back a deployment that cannot become healthy. Doors enables both upstream units and supplies one required check that is deliberately local and bounded: it confirms that `/run/ostree-booted` exists and that `rpm-ostree status --json` identifies exactly one booted deployment. It makes no DNS, OCI-registry, watchdog, desktop-session, or user-workload assertion at boot.

Doors intentionally does **not** install `greenboot-default-health-checks`. Upstream’s current [issue 212](https://github.com/fedora-iot/greenboot-rs/issues/212) documents why its inherited DNS, OSTree-remote/update-platform, and watchdog defaults are not universally meaningful for bootc. The Doors check has its own 60-second command bound, avoiding the unbounded-health-check failure mode tracked upstream in [issue 83](https://github.com/fedora-iot/greenboot-rs/issues/83). Administrators may add their own `/etc/greenboot` checks, but they must keep them local, deterministic, and bounded; an unbounded required check can otherwise delay recovery.

Current Greenboot rollback state is GRUB-specific (`/boot/grub2/grubenv`), as upstream records in [issue 175](https://github.com/fedora-iot/greenboot-rs/issues/175). Doors is `linux/amd64`, its bootc-image-builder QEMU gate uses the supported GRUB path, and the packaged units are conditionally skipped when that path is absent. A system converted to systemd-boot/UKI or another bootloader does not receive a misleading partial rollback promise; retain and use `bootc rollback` manually until Greenboot gains a supported bootloader backend.

## Distrobox/CUDA compatibility

`doors-ai` uses `docker.io/library/archlinux:latest` with Distrobox NVIDIA integration. Its bootstrap refreshes the Arch keyring and installs development tooling, OpenCode, and the full CUDA toolkit from signed official Arch repositories. It uses no AUR helper, Terra/Fedora repository, NVIDIA CUDA repository, container driver package, or `nvidia-utils` package.

Arch `cuda` supplies `/opt/cuda` and `nvcc`; the host’s NVIDIA path remains authoritative through Distrobox GPU integration. Bun checksum verification, npm lifecycle hardening for Pi/T3 Code, and the attestation-verified Herdr payload remain unchanged. Existing pre-Arch boxes require explicit `doors-ai recreate`, preventing silent deletion of user-space mutable data.

The initial container creation and GPU passthrough require hardware validation. A failed container bootstrap, package solve, or signature check fails visibly and must not be worked around with a kernel pin, driver fallback, repository bypass, or Secure Boot disablement.

## Secure Boot

BlueBuild documents a distinct MOK for its signed kernel/modules. Before switching a Secure-Boot-enforcing system, enroll that MOK using the [upstream migration guide](https://github.com/blue-build/base-images#migration-from-ublue-base-images). Doors does not automate or bypass this firmware security boundary.

## Escalation

If a BlueBuild Fedora 44 base, Fedora 44 repository, Arch CUDA/OpenCode package, `uupd`, or GPU passthrough becomes incompatible, stop that release path and investigate upstream. A future Fedora-major move, immutable-base policy, updater replacement, driver-flavor change, desktop-profile trust change, or repository trust change is material and requires review.
