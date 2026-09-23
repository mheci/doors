# Security policy

## Supported release surface

The supported release is **only** `ghcr.io/mheci/doors:latest`, after it has passed the physical test gate described in `docs/TEST-PLAN.md`. Legacy image variants, custom kernels, manual NVIDIA module paths, source-built llama.cpp, and alternative desktop configurations are intentionally retired.

## Report a vulnerability

Do **not** publish suspected credential exposure, signing-key compromise, image-signing bypass, malicious package/repository behavior, or a remotely exploitable image defect in a public issue.

Instead, submit a [private vulnerability report](https://github.com/mheci/doors/security/advisories/new) for `mheci/doors`. Include:

- affected image digest/tag and installation context;
- reproducible steps and expected/actual result;
- whether a signature/provenance/SBOM verification was performed;
- any potentially sensitive evidence only through the private channel.

We aim to acknowledge a vulnerability report within **7 days**, privately assess and begin mitigation within **30 days**, and coordinate disclosure with the reporter. A public disclosure target is normally no later than **90 days**, unless mitigation, active exploitation, or reporter coordination requires a different timeline. Never attach a Cosign private key, `SIGNING_SECRET`, registry token, generated Herdr artifact, or a live attestation download URL to an issue/PR.

## Verification expectations

Consumers should verify both the maintained Cosign key signature and GitHub OIDC attestations before rebasing. See `README.md` and `docs/TRUST-MODEL.md`.
