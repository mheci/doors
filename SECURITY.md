# Security policy

## Supported release surface

The supported releases are `ghcr.io/mheci/doors:latest` (GNOME) and
`ghcr.io/mheci/doors-kinoite:latest` (Plasma). Both ship `kernel-cachyos` and a
Negativo17 NVIDIA open module built for that kernel, signed by the Doors MOK.

## Accepted risks

These are deliberate, reviewed design decisions rather than defects:

- **Secure Boot enrollment is not exercised by CI.** Hosted runners cannot present UEFI
  Secure Boot, so the weekly boot test runs with `UEFI_SECURE_BOOT=0`. MOK signing failures
  are not detectable by CI and must be validated on physical hardware.
- **Hermes Agent and Zed are installed per user, not from the signed image.** Hermes
  uses a checksum-pinned bootstrap and a tagged commit. Zed's first login installs a
  digest-pinned stable tarball. A newer release is installed only after `doors-update apply`.
- **CachyOS COPR metadata is unsigned.** Package signatures are required, and the compose
  repo allowlists only `kernel-cachyos` and its matching header packages. The repo file is
  not left enabled in the image.

## Report a vulnerability

Do **not** publish suspected credential exposure, signing-key compromise, image-signing bypass,
malicious package/repository behavior, or a remotely exploitable image defect in a public issue.

Instead, submit a [private vulnerability report](https://github.com/mheci/doors/security/advisories/new)
for `mheci/doors`. Include:

- affected image digest/tag and installation context;
- reproducible steps and expected/actual result;
- whether a signature/provenance/SBOM verification was performed;
- sensitive evidence only through the private channel.

We aim to acknowledge within **7 days**, privately assess and begin mitigation within
**30 days**, and coordinate disclosure with the reporter. Public disclosure is normally no
later than **90 days**. Never attach a Cosign private key, `SIGNING_SECRET`, registry token,
generated Herdr artifact, or a live attestation download URL to an issue or PR.

## Verification expectations

Consumers should verify both the maintained Cosign key signature and the GitHub OIDC
attestations before rebasing. See `README.md`.
