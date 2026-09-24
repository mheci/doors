# Security policy

## Supported release surface

The supported release is **only** `ghcr.io/mheci/doors:latest`, after it has passed the
physical boot gate in CI. Legacy image variants, custom kernels, manual NVIDIA module paths,
and alternative desktop configurations are intentionally retired.

## Accepted risks

These are deliberate, reviewed design decisions rather than defects:

- **`wheel` retains passwordless UDisks2 authorization.** Any member of `wheel` can format,
  mount, or unlock any disk without a further prompt. Wheel membership is treated as a
  full-disk-administration trust boundary.
- **The journal stores `warning` and above only.** Info and notice records — including
  authentication, privilege, and network events — are not retained.
- **Secure Boot enrollment is not exercised by CI.** Hosted runners cannot present UEFI
  Secure Boot, so the boot gate runs with `UEFI_SECURE_BOOT=0`. MOK signing failures are not
  detectable by CI and must be validated on physical hardware.

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
