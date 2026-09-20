# Upstream base compatibility and fail-closed rebuild policy

Doors tracks the current upstream `ghcr.io/ublue-os/bazzite-gnome-nvidia-open:latest` image. This is the GNOME desktop Bazzite variant for Turing-or-newer NVIDIA hardware using NVIDIA Open kernel modules. Bazzite publishes its kernel, matching NVIDIA Open modules, userspace, and Mesa stack together; Doors intentionally does **not** compose a separate BlueBuild `akmods` module or independently synchronize Mesa packages.

## Automatic, no-workaround behavior

- The Monday `00:00 UTC` trusted build always resolves current upstream inputs.
- Pull-request verification and trusted publication each retry once after a five-minute delay when the first compose attempt fails. Before the second BlueBuild invocation, the workflow discards only the action-owned SLSA verifier cache so the retry verifies a fresh tool rather than inheriting a non-writable cache.
- If Bazzite or another signed upstream input still cannot compose, the workflow fails closed. It does **not** publish a partial image, move `latest`, create an attestation, pin an old base, add a second driver route, change the Bazzite kernel, inject a kmod, or bypass package verification.
- The existing published `ghcr.io/mheci/doors:latest` remains unchanged after a failed build. The next scheduled rebuild uses fresh upstream inputs.

## Why the base changed

On 2026-09-20, the retired generic Bluefin plus mutable BlueBuild `akmods` design encountered a real kernel-module solver conflict: the base resolved `kernel-modules-core-7.2.5-200.fc44` while the available official akmods dependency set resolved older `7.1.x` module packages. The owner explicitly selected the Bazzite GNOME NVIDIA Open base instead.

This is a deliberate architectural change, not a solver bypass: NVIDIA Open support now arrives as part of Bazzite's upstream-tested image composition rather than from a separately resolved module at Doors build time.

Bazzite also preinstalls its matched `terra-gamescope` implementation. Doors must use that upstream component rather than request Fedora's distinct `gamescope` RPM: the two packages conflict, and the strict solver correctly rejects an image that tries to layer both. Removing the redundant Fedora request preserves Gamescope while retaining fail-closed resolution; it is not a skip, replacement driver path, or package-verification exception.

## Escalation

If the Bazzite base itself has an upstream availability or compatibility problem, wait for or investigate the upstream Bazzite release before changing the image policy. Any pin, driver flavor change, base fallback, kernel override, manual driver/module build, or repository bypass remains a material design change requiring an explicit reviewed decision.
