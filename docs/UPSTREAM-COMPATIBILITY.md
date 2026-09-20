# Upstream compatibility and fail-closed rebuild policy

Doors intentionally combines the current generic `ghcr.io/ublue-os/bluefin:latest` base with the official BlueBuild `akmods` module (`base: main`, `nvidia-driver: nvidia-open`). Those upstream artifacts must agree on an exact stock-kernel ABI.

## Automatic, no-workaround behavior

- The Monday `00:00 UTC` trusted build always asks upstream for its current inputs.
- If Bluefin and `ublue-os/akmods:main-<Fedora version>` are temporarily out of sync, the official module must fail. The workflow does **not** publish a partial image, move `latest`, create an attestation, swap to a prebuilt NVIDIA base, pin an old akmods artifact, or override the inherited kernel/kmods.
- The existing published `ghcr.io/mheci/doors:latest` remains unchanged. The next scheduled build automatically retries once upstream aligns.
- This is deliberate: an unavailable fresh image is safer than a nominally successful image with a mismatched NVIDIA kernel module.

## Observed validation case

On 2026-09-20, the generated local build exercised the real source stage and official module. The then-current Bluefin base carried `7.1.13-200.fc44`, while mutable `ublue-os/akmods:main-44` supplied NVIDIA/kmods for `7.2.5-200.fc44`. The official module stopped on that ABI mismatch. The registry retained an exact historical `main-44-7.1.13-200.fc44` artifact, but Doors deliberately does not bypass the official module to select it.

A separate, narrow Mesa synchronization step remains before the module: paired x86_64 Mesa packages are updated through the already enabled signed Bluefin/Fedora path before the official installer adds their i686 counterparts. It prevents a packaging file-conflict race; it never changes kernel flavor or builds/injects a driver.

## Escalation

If a mismatch persists across scheduled runs, treat it as an upstream availability issue and investigate upstream Bluefin/akmods status before changing the image policy. Any proposed pin, kernel override, or switch to a prebuilt NVIDIA base is a material design change requiring an explicit reviewed decision.
