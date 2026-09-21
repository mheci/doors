# Trust model and delivery paths

Doors accepts only the sources below. A build failure is preferred to silently skipping a requested component or weakening verification.

## RPM repositories

| Source | Components | Verification and constraint |
|---|---|---|
| Fedora | General desktop/developer packages | Native signed Fedora metadata and RPMs. |
| RPM Fusion nonfree | Steam / allowed dependency set | Official BlueBuild `dnf.nonfree: rpmfusion` path. |
| Bazzite GNOME NVIDIA Open base | Matched Bazzite kernel, NVIDIA Open driver/modules, userspace, and Mesa stack | Doors consumes the signed upstream base as published and does not add an `akmods` module, driver repository, kernel override, or separate Mesa-synchronization transaction. |
| Terra main | Gaming/performance/developer packages, Zen, Vicinae | Vendored Terra 44 key `AE09157A4DE88B497EA1D5D300CDAB43DE226D6F`; `gpgcheck=1`, `repo_gpgcheck=1`, no skip-on-error. |
| Brave official RPM | Brave Origin | Three reviewed keys (`DBF1…8257`, `47D3…CD96`, `B2A3…DCA0`); package and repository metadata signatures required. Repository visibility is limited to `brave-origin` and its signed `brave-keyring` dependency. After compose, Doors verifies those Origin keys and removes that dependency’s unrelated beta/nightly key files, imported key records, and updater. |
| Faugus COPR | `faugus-launcher` | Reviewed key `53B018C402631F2762A4091967B25E7ACBB697C6`; RPM signature required. COPR does not publish signed `repomd.xml`, so `repo_gpgcheck=0` is an explicit, documented replay/downgrade limitation. Repository visibility is limited to the launcher. |
| Helium COPR | `helium-bin` | Reviewed key `07BCFCA30AC7E51BCFEDFFF74A3186EA47912C39`; RPM signature required. The upstream-documented COPR likewise lacks signed metadata; repository visibility is limited to the browser package. |

Custom repo configuration is used only during the compose transaction and is cleaned afterward. Their keys remain in the image for provenance/verification.

## Non-RPM exceptions

| Component | Route | Gate |
|---|---|---|
| Bun | Official GitHub release | Static reviewed Robobun primary key `F3DCC08A8572C0749B3E18888EAB4D40A7B22B59`; latest stable release checksum must clear-sign verify before the ZIP hash and binary version are accepted. |
| Herdr | Official GitHub immutable release | CI fetches the current `herdr-linux-x86_64`, matches GitHub’s release SHA-256, then requires `gh release verify-asset` against the named immutable `herdrdev/herdr` release. It fails if the runner CLI is older than patched `gh` 2.93.0 (GHSA-8xvp-7hj6-mcj9). The binary/manifest are ephemeral CI inputs and never committed. |
| Pi coding agent | Official npm package | The installer explicitly uses `https://registry.npmjs.org/`; npm verifies registry integrity metadata for `@earendil-works/pi-coding-agent`, its audited shrinkwrap is honored, and lifecycle hooks are disabled. The incompatible Terra package named `pi` is unrelated and excluded. |
| wl-clip-persist | Official upstream Git + Cargo | Upstream supplies source rather than an RPM/binary. The build resolves the latest release, pins its resolved immutable commit for the build, and uses its `Cargo.lock`. This is an approved source-build exception with no current upstream tag signature. |
| Clipboard Indicator, Alphabetical App Grid, Emoji Copy | Official GNOME Extensions registry through BlueBuild | Latest release compatible with the base GNOME shell. These are GNOME Shell code, not signed RPMs; the scope is strictly these three IDs. |
| Bazaar | Flatpak-native `flatpak-preinstall.service` + Flathub | Bazzite supplies Flatpak's native preinstall API but not its boot unit, so Doors vendors the minimal service that runs `flatpak preinstall -y`, enables it, and owns the sole `bazaar.preinstall` descriptor. The native resolver installs only `io.github.kolunmi.Bazaar` and its required runtime extensions; it does not use BlueBuild's separate `default-flatpaks` manager. |

## Image and CI provenance

1. BlueBuild’s pinned `image-publish` job receives `SIGNING_SECRET` only through the trusted `ghcr-publish` environment and signs the image with the existing repository key. `cosign.pub` is the user-facing verification key.
2. `image-publish` resolves the pushed immutable manifest digest and passes only that name/digest pair to the dependent `publish` release gate. The latter starts on a fresh runner, so its registry scan cannot compete with BlueBuild's large builder cache.
3. `publish` creates the SPDX SBOM from that immutable digest with the reviewed serial Syft cataloger policy, then uploads GitHub OIDC build-provenance and SBOM attestations to the registry. A failure in any of those steps fails the `publish` release gate.
4. The CLI version is explicitly selected (`v0.9.37`) and BlueBuild CLI installation verification is enabled. GitHub Actions are commit-SHA pinned.
5. Pull requests never push an image or read `SIGNING_SECRET`; their build uses a temporary signing key.

## Intentional residual risk

- COPR metadata is unsigned for Faugus and Helium; static key/RPM checking cannot prevent metadata replay/downgrade. Weekly fresh builds and physical validation reduce—not eliminate—that risk.
- Falcond, Ananicy, scx_loader, and `uinput` are privileged or high-impact components. Their behavior is explicitly user-approved but must be physically tested.
- Clipboard persistence/monitoring retains regular clipboard contents in memory as requested; this is not appropriate for users who require clipboard secrecy.
- Dynamic `latest` inputs prioritize freshness. Every external route has a fail-closed verification step where one exists; the documented source-build/npm/EGO exceptions do not have RPM-equivalent signatures.
