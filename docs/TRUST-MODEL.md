# Trust model

Doors fails closed when an approved source cannot compose or verify. Fedora 44 is the deliberate release stream for the host and AI Distrobox; it receives updates within that stream but does not advance to a future Fedora major automatically.

## Host RPM and image sources

| Source | Scope | Constraint |
|---|---|---|
| BlueBuild Fedora Silverblue NVIDIA Open `:44` | Kernel, NVIDIA Open modules/userspace, CUDA driver runtime, NVIDIA Container Toolkit | Official upstream base; Doors never adds a second driver, local akmods, kernel override, or Mesa synchronization path. Secure Boot requires BlueBuild MOK enrollment. |
| Fedora 44 | General host packages and Fedora Gamescope | Signed Fedora metadata/RPMs. |
| BlueBuild-managed Negativo17 Multimedia for Fedora 44 | Steam and matching multilib codec dependencies | Same signed-RPM multimedia source selected by the base; package signatures are required. Negativo17 does not sign repository metadata, so its replay/downgrade exposure is tracked below. |
| Terra 44 | Gaming/performance packages, Zen, Vicinae, Ghostty, Zed | Vendored complete GPG fingerprint set; `gpgcheck=1`, `repo_gpgcheck=1`, no availability bypass. |
| Brave official RPM | Brave Origin and required keyring only | Reviewed keys; RPM and repository metadata signatures required; package visibility restricted; unrelated keys/updater removed after compose. |
| Faugus COPR Fedora 44 | `faugus-launcher` only | Reviewed RPM key and package signature; `repo_gpgcheck=0` is an explicit COPR metadata-signing limitation. |
| Helium COPR Fedora 44 | `helium-bin` only | Reviewed RPM key and package signature; unsigned COPR metadata is an explicit limitation. |
| UBlue packages COPR Fedora 44 | `uupd` only | Reviewed RPM key and package signature; unsigned COPR metadata is an explicit limitation. |

All Fedora-specific endpoints in Doors’ repository configuration are literal Fedora 44 routes. Brave is vendor-generic rather than Fedora-streamed and is restricted to its reviewed package set.

## Distrobox trust boundary

`doors-ai` is a rootless Distrobox based on `registry.fedoraproject.org/fedora-toolbox:44`, with `nvidia=true`. Its bootstrap is immutable image content mounted read-only at `/opt/doors`.

| Input | Gate |
|---|---|
| Fedora 44/Terra 44 packages | DNF with fixed Fedora 44 stream, vendored Terra key, and signed metadata. |
| NVIDIA CUDA toolkit | NVIDIA Fedora 44 repo with vendored fingerprint `129994480EC63D2789BC98E490DFED2F73CD9B30`, package and repository metadata checks, and exclusions preventing driver replacement. |
| Bun | Official release ZIP accepted only after the reviewed Robobun key verifies its clear-signed checksum and reported version. |
| Pi coding agent | Canonical `https://registry.npmjs.org/` only; npm integrity metadata is honored and lifecycle hooks are disabled. |
| Herdr | CI resolves the immutable GitHub release, verifies its SHA-256 and `gh release verify-asset` attestation, then the Distrobox bootstrap rechecks the copied manifest/digest before installation. |

The host does not install Bun, Pi, Herdr, Node/npm/pnpm, Deno, mise, t3code, OpenCode, or the full CUDA toolkit. Their mutable tooling boundary is the Distrobox.

## Flatpak boundary

The static system Flathub descriptor contains the complete reviewed fingerprint set:

- `54A6CDDD8919FB204200D8AC562702E9E3ED7EE8`
- `6E5C05D979C76DAF93C081354184DD4D907A7CAE`

The owned bootstrap service uses that remote and explicitly names only Bazaar and DistroShelf. Flatpak can resolve only the runtime dependencies those applications declare.

## Release provenance

1. Pull requests compose with an ephemeral signing key and cannot publish or read `SIGNING_SECRET`.
2. Trusted release runs sign the OCI image, resolve its immutable digest, generate an SPDX SBOM using checksum-verified Trivy, and publish GitHub OIDC provenance and SBOM attestations.
3. GitHub Actions are commit-SHA pinned; BlueBuild CLI installation signature verification is enabled.
4. Any compose, scanner, signature, provenance, or attestation failure stops the release gate.

## Residual risk

- Negativo17 Multimedia and the three COPR routes above do not provide signed repository metadata; RPM signing reduces but does not eliminate replay/downgrade risk.
- A Fedora 44 tag is a stream pin, not an immutable digest. It avoids surprise major upgrades while accepting F44 updates.
- The AI Distrobox is user-space mutable by design. `uupd` can update it, and user-installed changes are outside immutable-image reproducibility.
- NVIDIA, Secure Boot, GPU container passthrough, performance services, and clipboard behavior require physical validation.
