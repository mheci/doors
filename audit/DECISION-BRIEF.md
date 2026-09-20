# Doors rebuild — decision brief (audit stage)

**Status:** historical audit/research record. The approved one-image implementation now lives in the repository root; later decisions in this document and the final package manifest supersede preliminary proposals here.

This brief records the material choices and their supporting evidence. Raw evidence is in `audit/raw/`.

## Confirmed target retained

- One public image: `ghcr.io/mheci/doors:latest`, built every Monday; no ISO artifacts.
- Generic `ghcr.io/ublue-os/bluefin:latest`, GNOME/GDM only, stock kernel.
- Official BlueBuild `akmods`, `base: main`, `nvidia-driver: nvidia-open` for Turing-or-newer hardware.
- Native Steam; Flatpak capability/Flathub retained, but **only Bazaar** preinstalled (with its needed runtime).
- Updates staged automatically; reboot remains manual.
- No legacy custom CachyOS kernel, bespoke NVIDIA build, `--nogpgcheck`, `rpm --nodeps`, or source-built llama.cpp.

## Trust-delivery findings

| Component | Audited delivery candidate | Security status / limitation |
|---|---|---|
| Fedora / Bluefin | Native signed Fedora packages and official BlueBuild modules | Preferred route where available. |
| RPM Fusion | Official BlueBuild RPM Fusion support for Steam and related dependencies | User-approved. RPM packages are signed; normal RPM Fusion metadata is not separately signed. |
| Terra | Direct Terra 44 repository with a locally supplied, reviewed key; package and metadata checks both enabled | Verified. The vendored public signing material is fingerprinted as `AE09157A4DE88B497EA1D5D300CDAB43DE226D6F`. Production can vendor it and use a local `.repo` with `gpgcheck=1`, `repo_gpgcheck=1`, and no `skip_if_unavailable`. |
| Brave Origin | Official Brave RPM repo with a locally supplied reviewed `brave-core.asc` | Verified package **and metadata** signatures with `gpgcheck=1` and `repo_gpgcheck=1`. A real GNOME/Wayland/NVIDIA validation gate remains mandatory. |
| Faugus | Upstream-maintained `faugus/faugus-launcher` COPR, version `2.3.0-1.fc44` | Package signature verified with static COPR key `53B018C402631F2762A4091967B25E7ACBB697C6`. COPR does **not** publish signed `repomd.xml`; `repo_gpgcheck=1` fails with HTTP 404. Package integrity is protected, but metadata downgrade/replay protection is weaker. |
| Bun | Official `oven-sh/bun` release asset | Clear-signed release checksums verified with the audited Robobun key `F3DCC08A8572C0749B3E18888EAB4D40A7B22B59`. A static key plus pinned version/checksum can be used; never the curl-pipe installer. |
| Herdr | Official `herdrdev/herdr` immutable GitHub release binary | `v0.9.1` x86_64 asset SHA-256 verified: `2a02fed16beb651ef006e1d43f048f652ca4dc58ad053cd2d44450563d5c54b7`. The final implementation resolves the current release each build, checks GitHub's published asset SHA-256, then uses `gh release verify-asset` to verify GitHub's immutable-release attestation for that exact asset. |
| Hermes Agent | Official `NousResearch/hermes-agent` release tag/source plus upstream `uv.lock` | Current official `v2026.9.14` tag and target commit `345cd2b057a452236de401d3534b8502a7465e8d` are **unsigned** and have no binary asset. A pinned source/lockfile build can be reviewed and hash-pinned, but it is not a cryptographically signed upstream release artifact. This needs an explicit exception or deferral. |
| CUDA llama.cpp | Prebuilt `conda-forge::llama.cpp` CUDA package in a system-wide locked Conda environment | Suitable for the requested no-source-build design. Latest CUDA variants currently trail the CPU-only package: CUDA 13.0 build `llama.cpp 9923`; package locking/hashes should be committed and reviewed. |

## Gaming and performance decision

### Native gaming candidates now have viable routes

- Steam: RPM Fusion.
- Heroic, ProtonPlus, umu-launcher, Vesktop: signed Terra packages.
- Gamescope: Fedora.
- Faugus: the project’s own COPR, with the metadata-signature limitation above.

### Automatic tuning requires a choice

The only presently viable automatic stack under the requested trust policy is **Falcond + its `scx-scheds` dependency** from signed Terra. Falcond `2.0.14` is packaged, but its service:

- runs as `root`;
- has no upstream release binary or separately established upstream artifact signature;
- has no systemd sandboxing in the upstream RPM unit;
- depends on Terra `scx-scheds 1.1.3`.

`scx-loader` has no release binary and no qualifying RPM route. Ananicy-cpp has neither a latest upstream release nor an upstream-principal RPM/COPR route established. They should not be silently retained. Falcond should never be combined automatically with GameMode, scx-loader, or Ananicy.

## CUDA / llama.cpp choice

Recommended safe design: keep all NVIDIA driver/kernel work in the official BlueBuild `akmods` module; do **not** add NVIDIA’s driver/CUDA RPM repo. Install the requested prebuilt CUDA llama.cpp under an isolated system-wide Conda prefix (for example `/opt/doors/llama`) and provide user-facing wrappers such as `llama-cli` and `llama-server`. No server daemon would be enabled.

The main scope decision is whether CUDA means:

1. this isolated Conda CUDA environment (including `nvcc`/runtime needed by the prebuilt llama.cpp package), or
2. an additional general system-wide NVIDIA CUDA RPM toolkit.

Option 2 has more driver/package-conflict risk and is not recommended without a demonstrated need.

## Current image audit checkpoint

- The current published amd64 image is about **9.28 GiB compressed** across 296 layers and is based on Kinoite, not the requested Bluefin base.
- Its history exposes unsafe legacy repository/bootstrap and bespoke kernel/driver patterns. The rewrite will remove them.
- The current image’s provenance layer is now independently verified: the attestation-manifest signature verifies against this repository’s `cosign.pub`, its transparency-log claim validates, and its in-toto statement binds the current amd64 subject digest. This verifies a key-signed attestation manifest, **not** a GitHub Actions identity policy.
- The existing statement still has weak provenance characteristics: no protected ref, empty builder ID, mutable/latest inputs, and `resolvedDependencies=false`.
- Static workflow audit found unpinned top-level Actions and checkout credential persistence risk. The replacement will use immutable action SHAs, `persist-credentials: false`, least privilege, build attestations/SBOM, controlled Renovate, and a protected-main administrator runbook.

## Decisions received on 2026-09-20

- **Performance:** preinstall and enable Falcond, Ananicy-cpp with CachyOS Ananicy rules, `scx-scheds`, and `scx-tools` (the signed Terra package that contains `scx_loader`, `scxctl`, and `scx_loader.service`). Explicitly block GameMode.
  - A corrected direct Terra 44 audit established that all requested components are in **Terra main**, not a COPR: Falcond `2.0.14`, Ananicy-cpp `1.2.0`, CachyOS Ananicy rules `1.1.49`, scx-scheds `1.1.3`, and scx-tools `1.1.3`.
  - All six relevant RPMs were downloaded and signature-verified using the locally reviewed Terra key while `gpgcheck=1` and `repo_gpgcheck=1` were enforced.
  - Enable `falcond.service`, `ananicy-cpp.service`, and `scx_loader.service`; configure scx_loader to start **`scx_lavd` in LowLatency mode** at boot.
  - The packaged loader has an admin-authenticated Polkit action. Its default config otherwise starts no scheduler. The package service has material sandboxing; Falcond is still an unsandboxed root daemon. A real-machine sched-ext/NVIDIA/gaming stability gate is mandatory before routine use.
- **Faugus:** approved through its project-maintained COPR, using a static reviewed key and RPM package signature checks; its metadata-signature limitation remains documented.
- **CUDA / llama.cpp:** deferred. The new image must not include the prior source-built llama.cpp, a Conda CUDA environment, or a general CUDA RPM toolkit until a later explicit decision.
- **Hermes Agent:** remove it. Do not install its unsigned release source, PyPI package, gateway, daemon, or related service.

## Additional decisions received

- **Desktop:** Yaru dark, a compact always-visible left dock, no forced wallpaper, Inter UI / JetBrains Mono defaults, and the full requested safe font set installed.
- **Browsers:** retain Zen Browser alongside Brave Origin and add Helium. Helium will use its upstream-documented `imput/helium` COPR, with a local reviewed key and RPM package signature checks; as with Faugus, COPR does not sign repository metadata.
- **Extensions:** system-install and enable Dash-to-Dock, AppIndicator, GSConnect, Clipboard Indicator, Grand Theft Focus, Just Perfection, Alphabetical App Grid, Vicinae, and Emoji Copy by default. Fedora/Terra RPMs will supply components where available; the official BlueBuild `gnome-extensions` module will fetch the latest compatible official GNOME Extensions versions for Clipboard Indicator, Alphabetical App Grid, and Emoji Copy.
- **Vicinae:** enable its global user service at graphical login, retain `uinput` support, and keep both Vicinae and Clipboard Indicator clipboard monitoring enabled. Bind Vicinae toggle to **Super+Shift+Space**.
- **Clipboard persistence:** add `wl-clip-persist` as a globally enabled user service operating on the regular clipboard only, without MIME/size filters. Fedora/Terra do not package it and upstream offers no binary asset; the approved exception is an official Cargo package-manager build using its upstream lockfile.
- **Freshness:** each Monday build should use the freshest successfully verified inputs: latest RPMs, newest GNOME-extension release compatible with the image GNOME version, PGP-verified Bun, and attestation-verified Herdr. User-local self-updaters are permitted.
- **Release process:** publish at **00:00 UTC each Monday**. Use the accepted low-maintenance model: retain the existing BlueBuild-required Cosign key/secret, add GitHub OIDC provenance/SBOM attestations, protect `main` with PR + required CI but no mandated human review count, and let Renovate auto-merge only a narrowly allowlisted set of low-risk digest/patch updates after required checks.

A final reviewed package manifest follows before production recipe/workflow changes begin.

- **Pi delivery correction (implementation validation):** Terra's package named `pi` is not the requested coding agent and cannot solve on Fedora because its x86_64 build requires non-Linux `libsocket`/`libsendfile` APIs. The user approved retaining Pi through its official `@earendil-works/pi-coding-agent` npm package-manager route, resolving the newest registry release with npm integrity verification at each build. The Terra `pi` package is excluded.
- **NVIDIA upstream-alignment policy (implementation validation):** prefer the brain-off, fail-closed path. Retain generic Bluefin, the inherited stock kernel, and the unmodified official `akmods` module. If their mutable current artifacts temporarily have incompatible kernel ABIs, publish nothing and automatically retry at the next Monday schedule. Do not pin a historical akmods image, patch the official module, override kernel/kmods, or switch to a prebuilt NVIDIA base without a new explicit decision.

## Base-policy amendment — 2026-09-21

The owner explicitly superseded the generic Bluefin plus separately resolved BlueBuild `akmods` design. Doors now tracks `ghcr.io/ublue-os/bazzite-gnome-nvidia-open:latest`, consuming Bazzite’s upstream-matched GNOME, Bazzite kernel, NVIDIA Open driver/modules, and Mesa composition. The retired `akmods` module and its Bluefin-specific Mesa synchronization path are removed. Historical evidence above records the prior design; the new Bazzite base requires fresh CI composition and physical validation before release-ready status is claimed.
