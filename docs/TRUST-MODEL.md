# Trust model

Doors fails closed when an approved source cannot compose or verify. Fedora 44 is the deliberate host release stream: it receives updates within that stream but never advances to a future Fedora major automatically.

## Host image and RPM sources

| Source | Scope | Constraint |
|---|---|---|
| BlueBuild Fedora Silverblue, COSMIC, and Kinoite NVIDIA Open `:44` | Desktop base, kernel, NVIDIA Open modules/userspace, driver runtime, NVIDIA Container Toolkit | Official upstream bases. Doors adds no second driver, local akmods, kernel override, or Mesa synchronization path. Secure Boot requires BlueBuild MOK enrollment. |
| Fedora 44 | General host packages and compiler/runtime baseline | Signed Fedora metadata and RPMs. |
| BlueBuild-managed Negativo17 Multimedia for Fedora 44 | Steam and compatible multilib codec dependencies | Signed RPMs from the multimedia source selected by the base. Repository metadata is not signed; its replay/downgrade exposure is tracked below. |
| Terra 44 | Gaming/performance packages, Zen, Vicinae, Ghostty, Zed, Bun, Deno, mise, OpenCode CLI, and Pi | Vendored complete GPG fingerprint set; `gpgcheck=1`, `repo_gpgcheck=1`, no availability bypass. |
| npm registry | Native `t3` CLI and its Linux x86_64 platform package | Tracked lock pins exact HTTPS tarballs and SRI SHA-512 identities; compose uses `npm ci --ignore-scripts --omit=dev`, so package lifecycle code cannot run. |
| NVIDIA CUDA Fedora 44 x86_64 | Toolkit-only CUDA 13.4 | Vendored key fingerprint `129994480EC63D2789BC98E490DFED2F73CD9B30` and SHA-256 `9221458f62030a18d5a28eecf44496016ff9c11548492ac2ce428f75c7513cab`; RPM and repository metadata signatures are required. The repository excludes all NVIDIA driver/userspace replacement packages. |
| Brave official RPM | Brave Origin and needed keyring only | Reviewed keys; RPM and repository metadata signatures required; package visibility is restricted and unrelated keys/updater are removed after compose. |
| Faugus COPR Fedora 44 | `faugus-launcher` only | Reviewed RPM key and package signature; `repo_gpgcheck=0` is an explicit COPR metadata-signing limitation. |
| Helium COPR Fedora 44 | `helium-bin` only | Reviewed RPM key and package signature; unsigned COPR metadata is an explicit limitation. |
| UBlue packages COPR Fedora 44 | `uupd` only | Reviewed RPM key and package signature; unsigned COPR metadata is an explicit limitation. |

All Fedora-specific endpoints are literal Fedora 44 routes. Brave is vendor-generic rather than Fedora-streamed and is restricted to its reviewed package set.

## Native AI and CUDA boundary

All supported development and AI tools are native image content. DNF composes Node/npm/pnpm, Python/pip, C/C++ build tools, Bun, Deno, mise, OpenCode CLI, Pi, and `cuda-toolkit-13-4` before the image is signed. The tracked `t3` lock adds the original native T3 Code CLI through exact HTTPS tarball URLs and SRI SHA-512 digests; `npm ci` verifies the lock and runs with lifecycle scripts disabled. The fixed toolkit major receives only NVIDIA CUDA 13.4 updates; it does not bring a driver route into the image. `/usr/local/cuda-13.4` provides the toolkit and `/usr/local/bin/nvcc` is an explicit stable command path.

Herdr is the sole CI-generated executable input. CI resolves its immutable GitHub release asset, verifies the release SHA-256 and `gh release verify-asset` attestation, then passes only that ephemeral artifact and manifest to the compose. The image validates the repository, release tag, asset name, and digest again before installing `/usr/local/bin/herdr`.

No native tool is installed or updated by a user-manager bootstrap. Rebuilding a reviewed image is the update boundary for the shipped toolchain. Doors never deletes an existing user-owned workload while rebasing; unrelated containers remain outside its ownership and are not represented as native-tool state.

## Flatpak boundary

The static system Flathub descriptor contains the complete reviewed fingerprint set:

- `54A6CDDD8919FB204200D8AC562702E9E3ED7EE8`
- `6E5C05D979C76DAF93C081354184DD4D907A7CAE`

The owned bootstrap service uses that remote and explicitly names only Bazaar and Gear Lever (`it.mijorus.gearlever`). Flatpak can resolve only the runtime dependencies those applications declare.

## Managed-update boundary

`doors-update.service` is the sole coordinator: `uupd` is restricted to immutable-host updates, and the coordinator starts every eligible local account’s lingering user manager before invoking its fixed user-space adapters. This avoids using only whichever users happen to be logged in.

The coordinator deliberately trusts only known package-manager commands in known roots. Gear Lever is the AppImage adapter and is called with `--update --all --yes`, never `--force`; it relies on update metadata from AppImages it has integrated. Podman auto-update is label-driven. Homebrew is limited to approved roots. Optional `pipx`, `uv`, global `npm`, Cargo, and RubyGems adapters are selected by fixed names in a user-owned configuration file, never by sourcing that file or running a user-supplied command.

No updater can safely infer a source or replacement policy for copied executables, tarballs, arbitrary AppImages, unlabelled containers, or unknown package managers. The service reports those artifacts and adapter failures instead of executing them. This is a coverage boundary, not a claim that all bytes in a home directory are automatically maintained.

## Release provenance

1. Pull requests and merge-queue entries compose all three stable desktop recipes with ephemeral signing keys. They cannot publish or read `SIGNING_SECRET`; the non-matrix `image` aggregate remains the protected check.
2. Each untrusted candidate composition writes a local OCI archive. CI imports that exact archive into root Podman, converts it to QCOW2 with a pinned bootc-image-builder, and runs the repository-local serial `os-autoinst` gate through a pinned `isotovideo` image. It is a direct test backend invocation, not a long-lived openQA deployment.
3. Trusted `main` runs independently sign and publish `doors`, `doors-cosmic`, and `doors-kinoite`. The daily staging workflow alone signs `doors:staging`; it does not create a separate package.
4. Each publishing worker records its package name and immutable digest in a short-lived workflow artifact. A distinct fresh runner validates that identity, generates an SPDX SBOM with checksum-verified Trivy, and publishes GitHub OIDC provenance and SBOM attestations for that exact digest.
5. GitHub Actions are commit-SHA pinned; BlueBuild CLI installation signature verification is enabled. Any compose, boot gate, scanner, signature, provenance, or attestation failure stops its release path.

## Residual risk

- Negativo17 Multimedia and the three COPR routes above do not provide signed repository metadata; RPM signing reduces but does not eliminate replay/downgrade risk.
- Fedora 44 image tags are stream pins, not immutable digests. They avoid surprise major upgrades while accepting Fedora 44 updates.
- Native CUDA tooling requires compatible NVIDIA hardware/driver behavior and physical validation.
- NVIDIA, Secure Boot, performance services, COSMIC/Plasma behavior, and clipboard persistence require physical validation.
