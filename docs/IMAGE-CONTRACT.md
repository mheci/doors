# Image contract

## Identity and publication

| Image | Fedora 44 base | Desktop / tag policy |
|---|---|---|
| `ghcr.io/mheci/doors:latest` | `fedora-silverblue-nvidia-open:44` | GNOME stable release. |
| `ghcr.io/mheci/doors:staging` | `fedora-silverblue-nvidia-open:44` | GNOME candidate rebuilt daily from trusted `main`; it remains in the `doors` package and is not published by stable pushes. |
| `ghcr.io/mheci/doors-cosmic:latest` | `fedora-cosmic-nvidia-open:44` | COSMIC release. |
| `ghcr.io/mheci/doors-kinoite:latest` | `fedora-kinoite-nvidia-open:44` | Plasma/Kinoite release. |

All images are `linux/amd64` only and use BlueBuild’s upstream NVIDIA Open composition for Turing-or-newer GPUs. Doors adds no kernel, local akmods module, driver repository, or manual driver/module build.

Stable images publish only from trusted `main` after the repository contract passes. The daily staging workflow is isolated from normal stable pushes. Every trusted image build is Cosign-signed, resolves its own immutable digest, then hands that identity to a fresh runner for Trivy SPDX generation and GitHub OIDC provenance/SBOM attestations. No matrix output is used to relay digest identities.

The base and every Fedora-specific host RPM route are pinned to Fedora 44. This prevents an automatic Fedora-major transition without freezing Fedora 44 updates.

## Shared host policy

- Firefox, Firefox language packs, ordinary Brave, GameMode, and GameMode libraries are removed.
- Supported browsers are Brave Origin, Zen, and Helium.
- Fedora-signed Gamescope, Steam, Heroic, Faugus, ProtonPlus, umu-launcher, Vesktop, Falcond, Ananicy-cpp, scx, native development/AI tools, Bazaar, and Gear Lever support are shared across the family.
- GNOME dconf defaults and GNOME Shell extensions are confined to `doors` and `doors:staging`.
- COSMIC seeds `is_dark=true` only when its per-user preference does not exist. It never overwrites a later user choice.
- Kinoite supplies user-overridable `/etc/xdg/kdeglobals` defaults for native Breeze Dark. Its SteamOS-inspired desktop mode uses no Valve assets and does not autostart Steam Big Picture or Game Mode.
- `doors-update.timer` is the single daily update coordinator; competing `uupd`, bootc, Flatpak, and Podman automatic-update timers are disabled.
- `uupd` remains the immutable-host engine under that coordinator. It arrives only from the narrow `ublue-os/packages` Fedora 44 COPR route with RPM GPG verification. COPR metadata is not signed, so that residual replay/downgrade limitation is explicit.
- Fedora’s `greenboot` package (the `greenboot-rs` implementation) complements staged immutable updates with a GRUB-backed health/rollback guard. Doors installs only the core package and one bounded, offline deployment-status check—never `greenboot-default-health-checks`, whose generic DNS, update-platform, and watchdog checks are not reliable bootc policy. Both Greenboot units skip cleanly if `/boot/grub2/grubenv` is absent; on a non-GRUB system, manual `bootc rollback` remains the supported recovery path.

## Managed updates

`doors-update.service` first invokes `uupd` with only its system module enabled, preserving its hardware/network safety checks while staging immutable bootc/rpm-ostree updates without rebooting automatically. It then serializes system Flatpaks and explicitly label-managed root Podman auto-update workloads when Podman is present.

For every regular **local** account in the configured UID range that has an interactive shell and existing home directory, the coordinator enables linger, starts that account’s systemd user manager, and waits for `doors-user-update.service`. This covers accounts that are not logged in when the timer fires. The per-user service updates user Flatpaks, label-managed rootless Podman containers, and Homebrew installations in the approved `~/.linuxbrew` or `/home/linuxbrew/.linuxbrew` roots.

The fixed Gear Lever adapter runs `flatpak run it.mijorus.gearlever --update --all --yes` without `--force`; it updates only AppImages Gear Lever has integrated and leaves running AppImages alone. A shared `/home/linuxbrew/.linuxbrew` installation is run only by the regular account that owns its `brew` binary, avoiding duplicate or unauthorized Homebrew transactions. Optional user package-manager adapters (`pipx`, `uv`, global `npm` with lifecycle scripts disabled, `cargo-install-update`, and `gem`) require one exact adapter name per line in `~/.config/doors/update-adapters.conf`. The service never sources that file or executes arbitrary commands from it.

A report is written after every host transaction at `/var/lib/doors/updates/latest.tsv` and after every user transaction at `~/.local/state/doors/update-report.tsv`; system/user journals retain command output and failures. Arbitrary copied binaries, tarballs, unintegrated AppImages, unlabelled containers, and package managers outside the supported adapters are **not** safely auto-updatable. They are reported rather than executed or silently represented as updated.

## Native development, AI, and CUDA

Every image layers Node/npm/pnpm, Python/pip, C/C++ build tools, Bun, Deno, mise, OpenCode CLI, Pi, the T3 Code CLI, CUDA Toolkit 13.4, and Herdr. Fedora supplies the compiler/runtime baseline; Terra’s signed Fedora 44 route supplies Bun, Deno, mise, and OpenCode CLI; tracked npm locks install native Pi and `t3` with pinned tarball identities and lifecycle scripts disabled; NVIDIA’s signed Fedora 44 route supplies the version-pinned toolkit-only `cuda-toolkit-13-4` meta package.

The NVIDIA CUDA route has RPM and repository-metadata signature checks and excludes `cuda-drivers*`, `nvidia-driver*`, and related driver/userspace packages. It cannot replace the NVIDIA Open stack owned by the base. Because Atomic Fedora maps the vendor RPM’s `/usr/local` payload and Nsight’s `/opt/nvidia` payload to mutable `/var`, the compose transaction copies CUDA, Nsight Compute, and Nsight Systems in the same signed-RPM layer to immutable `/usr/lib/doors/cuda-13.4` and removes both mutable sources. `/etc/profile.d/doors-cuda.sh` exports that environment; `/usr/bin/nvcc`, `/usr/bin/ncu`, and `/usr/bin/nsys` give non-login processes stable compiler/profiler paths.

Herdr enters only as the CI-generated, immutable-release-attestation-verified artifact. Compose validates its manifest and digest before installing it natively. `doors-ai` retains `status`, `shell`, and direct `run` conveniences, but it does not create, enter, export, or update a separate user environment. Existing user-owned workloads are never deleted by an image rebase and are outside the native toolchain contract.

## Flatpak policy

Flathub is statically configured with its reviewed complete GPG-fingerprint set. `doors-flatpak-bootstrap.service` runs after a networked boot and installs exactly:

- `io.github.kolunmi.Bazaar`
- `it.mijorus.gearlever` (the approved AppImage-management path)

plus only the runtime dependencies Flatpak declares. No Bazzite preinstall descriptor, BlueBuild `default-flatpaks` manager, Flatseal, pwvucontrol, or additional application-preinstall path remains.

## Secure Boot and validation

A late common compose module signs and verifies every kernel `vmlinuz*` and EFI payload below `/usr/lib/modules` plus every `.ko`, `.ko.xz`, `.ko.zst`, and `.ko.gz` module. It compares the BuildKit-mounted private key against the tracked public DER before touching payloads, verifies PE signatures with `sbverify`, verifies module signer names with `modinfo`, and refreshes `depmod` metadata. If a base lacks `sign-file`, the no-cache signing RUN transiently installs standalone Fedora `kernel-devel`, uses its version-independent signer, and removes it before the layer commits; headers do not inflate the shipped OCI archive or test disk. The image contains only `doors-mok.der` and its SHA-256 fingerprint manifest; no private MOK material is copied into a layer, artifact, source tree, or target filesystem.

Trusted `main` and the trusted daily-staging job can read `DOORS_MOK_SIGNING_KEY` only from the protected `ghcr-publish` environment, and pass it only to the late BlueBuild signing action. Pull-request and merge-queue candidates generate disposable Cosign and 4096-bit MOK key material on the runner, replace both MOK public certificate files only in that checkout, mask every private PEM line before placing candidate keys in the ephemeral runner environment for their non-publishing compose attempts, then clear and delete them before boot materialization. This keeps production MOK material outside untrusted workflow scopes while still exercising the complete signer on every candidate.

A target owner compares `doors-secureboot fingerprint`, runs `sudo doors-secureboot enroll`, then approves enrollment and MOK trust locally in MokManager after reboot. That physical firmware-owner approval cannot be automated remotely; `doors-secureboot status` and `doors-secureboot verify` make the post-boot state observable.

Untrusted pull-request and merge-queue CI composes each exact candidate into a BlueBuild OCI archive, imports that archive into root Podman storage, converts that same candidate to QCOW2 with a pinned bootc-image-builder, and boots it with repository-local direct `os-autoinst`/QEMU under a pinned `isotovideo` image. The runner explicitly marks that container as CI so os-autoinst does not reserve a separate default scratch disk alongside the already-materialized candidate. The tracked empty `boot-test/needles` directory satisfies os-autoinst initialization while the serial-only gate deliberately avoids visual matching. It has bounded waits for kernel output, systemd PID 1, a login/boot-target marker, and fatal panic/oops/emergency/mount/service-start signatures; the sole QEMU capability exception is the GPU-less `nvidia-cdi-refresh` unit, while every other failed service remains fatal. Failed runs upload conversion, serial, and test diagnostics while excluding the oversized generated QCOW2 disk. This is direct os-autoinst test execution, not a persistent openQA scheduler/UI/worker deployment.

CI still cannot validate firmware enrollment, NVIDIA/Wayland behavior, native CUDA GPU execution, or hardware suspend/resume; those remain mandatory physical release gates.
