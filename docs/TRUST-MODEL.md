# Trust model

Doors fails closed when an approved source cannot compose or verify. Fedora 44 is the deliberate host release stream: it receives updates within that stream but never advances to a future Fedora major automatically.

## Host image and RPM sources

| Source | Scope | Constraint |
|---|---|---|
| BlueBuild Fedora Silverblue, COSMIC, and Kinoite NVIDIA Open `:44` | Desktop base, kernel, NVIDIA Open modules/userspace, driver runtime, NVIDIA Container Toolkit | Official upstream bases. Doors adds no second driver, local akmods, kernel override, or Mesa synchronization path. Secure Boot requires BlueBuild MOK enrollment. |
| Fedora 44 | General host packages, including Gamescope | Signed Fedora metadata and RPMs. |
| BlueBuild-managed Negativo17 Multimedia for Fedora 44 | Steam and compatible multilib codec dependencies | Signed RPMs from the multimedia source selected by the base. Repository metadata is not signed; its replay/downgrade exposure is tracked below. |
| Terra 44 | Gaming/performance packages, Zen, Vicinae, Ghostty, Zed | Vendored complete GPG fingerprint set; `gpgcheck=1`, `repo_gpgcheck=1`, no availability bypass. |
| Brave official RPM | Brave Origin and needed keyring only | Reviewed keys; RPM and repository metadata signatures required; package visibility is restricted and unrelated keys/updater are removed after compose. |
| Faugus COPR Fedora 44 | `faugus-launcher` only | Reviewed RPM key and package signature; `repo_gpgcheck=0` is an explicit COPR metadata-signing limitation. |
| Helium COPR Fedora 44 | `helium-bin` only | Reviewed RPM key and package signature; unsigned COPR metadata is an explicit limitation. |
| UBlue packages COPR Fedora 44 | `uupd` only | Reviewed RPM key and package signature; unsigned COPR metadata is an explicit limitation. |

All Fedora-specific endpoints are literal Fedora 44 routes. Brave is vendor-generic rather than Fedora-streamed and is restricted to its reviewed package set.

## Distrobox trust boundary

`doors-ai` is a rootless, GPU-aware Distrobox based on `docker.io/library/archlinux:latest`, with `nvidia=true`. Its bootstrap is immutable image content mounted read-only at `/opt/doors`.

| Input | Gate |
|---|---|
| Arch Linux packages | One full `pacman -Syu --needed` transaction using Arch’s signed official repositories and refreshed `archlinux-keyring`. No AUR helper, third-party repository, `nvidia-utils`, or driver package is installed. |
| CUDA toolkit | Official Arch `cuda`, which supplies `/opt/cuda` and `nvcc`. Host GPU/driver access is provided by Distrobox NVIDIA integration. |
| Bun | Official release ZIP accepted only after the reviewed Robobun key verifies its clear-signed checksum and reported version. |
| Pi coding agent and T3 Code | Canonical `https://registry.npmjs.org/` only; npm integrity metadata is honored and lifecycle hooks are disabled. |
| OpenCode | Signed official Arch package. |
| Herdr | CI resolves the immutable GitHub release, verifies its SHA-256 and `gh release verify-asset` attestation, then the Distrobox bootstrap rechecks the mounted manifest/digest before installation. |

The host does not install Bun, Pi, T3 Code, Herdr, Node/npm/pnpm, Deno, mise, OpenCode, or the full CUDA toolkit. Their mutable tooling boundary is the Distrobox. Existing Fedora-based containers require the explicit `doors-ai recreate` migration command rather than silent replacement.

## Flatpak boundary

The static system Flathub descriptor contains the complete reviewed fingerprint set:

- `54A6CDDD8919FB204200D8AC562702E9E3ED7EE8`
- `6E5C05D979C76DAF93C081354184DD4D907A7CAE`

The owned bootstrap service uses that remote and explicitly names only Bazaar and DistroShelf. Flatpak can resolve only the runtime dependencies those applications declare.

## Release provenance

1. Pull requests and merge-queue entries compose all three stable desktop recipes with ephemeral signing keys. They cannot publish or read `SIGNING_SECRET`; the non-matrix `image` aggregate remains the protected check.
2. Trusted `main` runs independently sign and publish `doors`, `doors-cosmic`, and `doors-kinoite`. The daily staging workflow alone signs `doors:staging`; it does not create a separate package.
3. Each publishing worker records its package name and immutable digest in a short-lived workflow artifact. A distinct fresh runner validates that identity, generates an SPDX SBOM with checksum-verified Trivy, and publishes GitHub OIDC provenance and SBOM attestations for that exact digest.
4. GitHub Actions are commit-SHA pinned; BlueBuild CLI installation signature verification is enabled. Any compose, scanner, signature, provenance, or attestation failure stops its release path.

## Residual risk

- Negativo17 Multimedia and the three COPR routes above do not provide signed repository metadata; RPM signing reduces but does not eliminate replay/downgrade risk.
- Fedora 44 image tags are stream pins, not immutable digests. They avoid surprise major upgrades while accepting Fedora 44 updates.
- The Arch Distrobox is user-space mutable by design. `uupd` can update it, and user-installed changes are outside immutable-image reproducibility.
- NVIDIA, Secure Boot, GPU container passthrough, performance services, COSMIC/Plasma behavior, and clipboard persistence require physical validation.
