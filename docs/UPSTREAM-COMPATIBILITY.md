# Upstream compatibility and fail-closed rebuild policy

Doors consumes `ghcr.io/blue-build/base-images/fedora-silverblue-nvidia-open:44`. The Fedora 44 tag is a deliberate major-stream pin: it accepts current Fedora 44 updates but does not move to Fedora 45+ until a reviewed change refreshes trust material, solves dependencies, and passes physical validation.

## Base responsibilities

BlueBuild composes and signs the Fedora kernel, NVIDIA Open modules, NVIDIA userspace, CUDA driver runtime, and NVIDIA Container Toolkit. Doors does not layer a local `akmods` module, alternate driver repository, custom kernel, manual kmod, or a Mesa-synchronization transaction.

Fedora’s signed `gamescope` RPM is layered because this base does not inherit Bazzite’s `terra-gamescope` package.

## Update responsibilities

The owner selected `uupd` as Doors’ single automatic coordinator. It is installed from the narrow UBlue packages COPR Fedora 44 route with RPM signature checking and enabled as `uupd.timer`. Its system, Flatpak, and Distrobox modules are enabled; Homebrew is disabled.

To prevent competing deployment/Flatpak transactions, Doors disables BlueBuild’s `bootc-fetch-apply-updates.timer`, `flatpak-system-updates.timer`, and `flatpak-user-updates.timer`. This is a reviewed change from the earlier BlueBuild-timer contract, not a disabled-update workaround: uupd retains the bootc, Flatpak, and Distrobox update responsibilities.

## Distrobox/CUDA compatibility

The `doors-ai` Distrobox uses Fedora Toolbox 44 and NVIDIA integration. Its Fedora/Terra/CUDA endpoints are all Fedora 44 routes. Full CUDA development tooling is contained there; the NVIDIA Fedora 44 repo excludes driver packages so it cannot replace BlueBuild’s host driver path.

The initial container creation and GPU passthrough require hardware validation. A failed container bootstrap, package solve, or signature check fails visibly and must not be worked around by tracking `latest`, a kernel pin, a driver fallback, a repository bypass, or a Secure Boot disablement.

## Secure Boot

BlueBuild documents a distinct MOK for its signed kernel/modules. Before switching a Secure-Boot-enforcing system, enroll that MOK using the [upstream migration guide](https://github.com/blue-build/base-images#migration-from-ublue-base-images). Doors does not automate or bypass this firmware security boundary.

## Escalation

If the BlueBuild 44 base, a Fedora 44 repository, uupd, or CUDA toolkit becomes incompatible, stop the release gate and investigate upstream. A future Fedora-major move, immutable-digest policy, updater replacement, driver-flavor change, or repo trust change is material and requires a reviewed decision.
