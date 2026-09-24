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

The owner selected `doors-update.timer` as Doors’ single automatic coordinator. `uupd`, installed from the narrow UBlue packages COPR Fedora 44 route with RPM signature checking, remains the coordinator’s immutable-host engine; its Flatpak and Homebrew modules are disabled so they cannot race the cross-account transaction.

The coordinator stages bootc/rpm-ostree updates through `uupd`, then handles system/user Flatpaks, explicitly label-managed Podman containers when present, supported Homebrew roots, Gear Lever-managed AppImages, and opt-in user package managers in the correct ownership scope. It starts a lingering systemd user manager for each eligible regular local account, including accounts not logged in at timer time.

To prevent competing transactions, Doors disables `uupd.timer`, BlueBuild’s `bootc-fetch-apply-updates.timer`, `flatpak-system-updates.timer`, `flatpak-user-updates.timer`, and system/user Podman auto-update timers. This is a reviewed coordination decision, not a disabled-update workaround: each supported responsibility is retained by `doors-update.service` and recorded in host or per-user reports.

## Boot health and rollback

Fedora 44 provides the Rust rewrite as the `greenboot` RPM package. It is valuable here because `uupd` stages an immutable bootc/rpm-ostree deployment for a later manual reboot: Greenboot’s paired health-check and staged-deployment trigger can then retry and roll back a deployment that cannot become healthy. Doors enables both upstream units and supplies one required check that is deliberately local and bounded: it confirms that `/run/ostree-booted` exists and that `rpm-ostree status --json` identifies exactly one booted deployment. It makes no DNS, OCI-registry, watchdog, desktop-session, or user-workload assertion at boot.

Doors intentionally does **not** install `greenboot-default-health-checks`. Upstream’s current [issue 212](https://github.com/fedora-iot/greenboot-rs/issues/212) documents why its inherited DNS, OSTree-remote/update-platform, and watchdog defaults are not universally meaningful for bootc. The Doors check has its own 60-second command bound, avoiding the unbounded-health-check failure mode tracked upstream in [issue 83](https://github.com/fedora-iot/greenboot-rs/issues/83). Administrators may add their own `/etc/greenboot` checks, but they must keep them local, deterministic, and bounded; an unbounded required check can otherwise delay recovery.

Current Greenboot rollback state is GRUB-specific (`/boot/grub2/grubenv`), as upstream records in [issue 175](https://github.com/fedora-iot/greenboot-rs/issues/175). Doors is `linux/amd64`, its bootc-image-builder QEMU gate uses the supported GRUB path, and the packaged units are conditionally skipped when that path is absent. A system converted to systemd-boot/UKI or another bootloader does not receive a misleading partial rollback promise; retain and use `bootc rollback` manually until Greenboot gains a supported bootloader backend.

## Native toolchain and CUDA compatibility

Fedora supplies Node/npm/pnpm, Python/pip, and build tooling. Terra 44 supplies Bun, Deno, mise, OpenCode CLI, and Pi through its signed RPM metadata and package route. The original T3 Code CLI is installed natively from a tracked npm lock with exact HTTPS tarball URLs/SRI digests and lifecycle scripts disabled; Terra's distinct `t3code` desktop GUI is not substituted for that CLI. Doors does not run a mutable per-user setup; the published native toolchain changes only through a reviewed, signed image rebuild.

NVIDIA’s Fedora 44 x86_64 repository supplies only `cuda-toolkit-13-4`. Both RPM and repository metadata signatures are required; the repository excludes driver, persistence, settings, and X configuration packages so BlueBuild’s NVIDIA Open path stays authoritative. The toolkit is expected at `/usr/local/cuda-13.4`, with `nvcc` exposed through `/usr/local/bin` and the system profile.

Herdr remains a CI-verified immutable GitHub release artifact. The target image rechecks the supplied manifest/digest before installation. A failed package solve, key check, toolkit verification, or Herdr check stops the compose; do not work around it with a kernel pin, driver fallback, repository bypass, or Secure Boot disablement.

## Secure Boot

Doors adds its own late compose signer after the desktop profile and before OCI signing. It signs every shipped kernel image/EFI payload under `/usr/lib/modules` and each supported compressed or uncompressed kernel module with a dedicated Doors MOK, then verifies signatures before the image is published. The public DER and a checked SHA-256 fingerprint ship with the image; the matching private PEM is a protected `ghcr-publish` environment secret mounted as a BuildKit secret only for the signer RUN. It is not baked into an image layer or made available to pull-request/merge-queue publication scopes.

Candidate jobs generate a fresh disposable MOK pair, replace only their checkout-local public certificate/fingerprint, and use it only for their non-publishing compose attempts. This tests the same kernel/module signing path without disclosing the production key. A trusted image still requires target-owner action: run `doors-secureboot enroll`, reboot, and approve enrollment and any MOK-trust request in MokManager. Firmware confirmation is intentionally neither CI-automated nor remotely bypassed.

## Escalation

If a BlueBuild Fedora 44 base, Fedora 44 repository, Terra native-tool RPM, NVIDIA CUDA toolkit route, `uupd`, or GPU path becomes incompatible, stop that release path and investigate upstream. A future Fedora-major move, immutable-base policy, updater replacement, driver-flavor change, desktop-profile trust change, or repository trust change is material and requires review.
