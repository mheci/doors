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
- Fedora-signed Gamescope, Steam, Heroic, Faugus, ProtonPlus, umu-launcher, Vesktop, Falcond, Ananicy-cpp, scx, developer tools, Bazaar, and DistroShelf support are shared across the family.
- GNOME dconf defaults and GNOME Shell extensions are confined to `doors` and `doors:staging`.
- COSMIC seeds `is_dark=true` only when its per-user preference does not exist. It never overwrites a later user choice.
- Kinoite supplies user-overridable `/etc/xdg/kdeglobals` defaults for native Breeze Dark. Its SteamOS-inspired desktop mode uses no Valve assets and does not autostart Steam Big Picture or Game Mode.
- `doors-update.timer` is the single daily update coordinator; competing `uupd`, bootc, Flatpak, and Podman automatic-update timers are disabled.
- `uupd` remains the immutable-host engine under that coordinator. It arrives only from the narrow `ublue-os/packages` Fedora 44 COPR route with RPM GPG verification. COPR metadata is not signed, so that residual replay/downgrade limitation is explicit.
- Fedora’s `greenboot` package (the `greenboot-rs` implementation) complements staged immutable updates with a GRUB-backed health/rollback guard. Doors installs only the core package and one bounded, offline deployment-status check—never `greenboot-default-health-checks`, whose generic DNS, update-platform, and watchdog checks are not reliable bootc policy. Both Greenboot units skip cleanly if `/boot/grub2/grubenv` is absent; on a non-GRUB system, manual `bootc rollback` remains the supported recovery path.

## Managed updates

`doors-update.service` first invokes `uupd` with only its system module enabled, preserving its hardware/network safety checks while staging immutable bootc/rpm-ostree updates without rebooting automatically. It then serializes system Flatpaks, root-owned Distroboxes, and root Podman auto-update containers.

For every regular **local** account in the configured UID range that has an interactive shell and existing home directory, the coordinator enables linger, starts that account’s systemd user manager, and waits for `doors-user-update.service`. This covers accounts that are not logged in when the timer fires. The per-user service updates user Flatpaks, all rootless Distroboxes, label-managed rootless Podman containers, and Homebrew installations in the approved `~/.linuxbrew` or `/home/linuxbrew/.linuxbrew` roots.

The fixed Gear Lever adapter runs `flatpak run it.mijorus.gearlever --update --all --yes` without `--force`; it updates only AppImages Gear Lever has integrated and leaves running AppImages alone. A shared `/home/linuxbrew/.linuxbrew` installation is run only by the regular account that owns its `brew` binary, avoiding duplicate or unauthorized Homebrew transactions. Optional user package-manager adapters (`pipx`, `uv`, global `npm` with lifecycle scripts disabled, `cargo-install-update`, and `gem`) require one exact adapter name per line in `~/.config/doors/update-adapters.conf`. The service never sources that file or executes arbitrary commands from it.

A report is written after every host transaction at `/var/lib/doors/updates/latest.tsv` and after every user transaction at `~/.local/state/doors/update-report.tsv`; system/user journals retain command output and failures. Arbitrary copied binaries, tarballs, unintegrated AppImages, unlabelled containers, and package managers outside the supported adapters are **not** safely auto-updatable. They are reported rather than executed or silently represented as updated.

## AI Distrobox and CUDA

Each image supplies `podman`, `distrobox`, `doors-distrobox`, `doors-ai`, and the global `doors-distrobox.service` user unit. At every user-manager startup it scans the root-owned Doors manifest inventory and creates **only missing** boxes; it does not use `--replace` or silently delete user data.

- Every current and future Doors manifest is contract-checked to declare `nvidia=true`, `init=true`, `start_now=true`, and `replace=false`. Initful Arch boxes include `systemd` in `additional_packages`.
- The `doors-ai` manifest uses `docker.io/library/archlinux:latest` and Distrobox NVIDIA integration. Its bootstrap runs one signed official-Arch `pacman -Syu` transaction for Arch keyring, development tools, Node/npm/pnpm, Deno, mise, OpenCode, Python tooling, and `cuda`. It installs no AUR helper, external repository definition, `nvidia-utils`, or driver package.
- Arch `cuda` supplies `/opt/cuda` and `nvcc`; Distrobox NVIDIA integration exposes the host GPU/driver stack.
- `ujust` recipes and the `doors-ai` wrapper support shell/run, application export/unexport, binary export/unexport, `export-all`, and export listing. Exported applications use Distrobox desktop-entry wrappers; exported binaries are intentionally written to the user's `~/.local/bin`.
- Bun verifies a clear-signed upstream checksum. Pi and T3 Code use npm’s canonical registry with integrity metadata and lifecycle scripts disabled. Herdr is immutable-release-attestation-verified in CI, mounted read-only, digest-checked again, and installed only in the container.
- Existing pre-Arch containers are not silently replaced. `doors-ai recreate` is the explicit, destructive migration operation after users export container-local work.

The immutable host never layers Bun, Pi, T3 Code, Herdr, Node/npm/pnpm, Deno, mise, OpenCode, or the CUDA toolkit.

## Flatpak policy

Flathub is statically configured with its reviewed complete GPG-fingerprint set. `doors-flatpak-bootstrap.service` runs after a networked boot and installs exactly:

- `io.github.kolunmi.Bazaar`
- `com.ranfdev.DistroShelf`
- `it.mijorus.gearlever` (the approved AppImage-management path)

plus only the runtime dependencies Flatpak declares. No Bazzite preinstall descriptor, BlueBuild `default-flatpaks` manager, Flatseal, pwvucontrol, or additional application-preinstall path remains.

## Secure Boot and validation

A late common compose module signs and verifies every kernel `vmlinuz*` and EFI payload below `/usr/lib/modules` plus every `.ko`, `.ko.xz`, `.ko.zst`, and `.ko.gz` module. It compares the BuildKit-mounted private key against the tracked public DER before touching payloads, verifies PE signatures with `sbverify`, verifies module signer names with `modinfo`, and refreshes `depmod` metadata. If a base lacks `sign-file`, the no-cache signing RUN transiently installs standalone Fedora `kernel-devel`, uses its version-independent signer, and removes it before the layer commits; headers do not inflate the shipped OCI archive or test disk. The image contains only `doors-mok.der` and its SHA-256 fingerprint manifest; no private MOK material is copied into a layer, artifact, source tree, or target filesystem.

Trusted `main` and the trusted daily-staging job can read `DOORS_MOK_SIGNING_KEY` only from the protected `ghcr-publish` environment, and pass it only to the late BlueBuild signing action. Pull-request and merge-queue candidates generate a disposable 4096-bit key/certificate pair on the runner, replace both public certificate files only in that checkout, and give its private half only to their two non-publishing compose attempts. Candidate keys are deleted before boot materialization. This keeps production MOK material outside untrusted workflow scopes while still exercising the complete signer on every candidate.

A target owner compares `doors-secureboot fingerprint`, runs `sudo doors-secureboot enroll`, then approves enrollment and MOK trust locally in MokManager after reboot. That physical firmware-owner approval cannot be automated remotely; `doors-secureboot status` and `doors-secureboot verify` make the post-boot state observable.

Untrusted pull-request and merge-queue CI composes each exact candidate into a BlueBuild OCI archive, imports that archive into root Podman storage, converts that same candidate to QCOW2 with a pinned bootc-image-builder, and boots it with repository-local direct `os-autoinst`/QEMU under a pinned `isotovideo` image. The runner explicitly marks that container as CI so os-autoinst does not reserve a separate default scratch disk alongside the already-materialized candidate. The tracked empty `boot-test/needles` directory satisfies os-autoinst initialization while the serial-only gate deliberately avoids visual matching. It has bounded waits for kernel output, systemd PID 1, a login/boot-target marker, and fatal panic/oops/emergency/mount/service-start signatures; the sole QEMU capability exception is the GPU-less `nvidia-cdi-refresh` unit, while every other failed service remains fatal. Failed runs upload conversion, serial, and test diagnostics while excluding the oversized generated QCOW2 disk. This is direct os-autoinst test execution, not a persistent openQA scheduler/UI/worker deployment.

CI still cannot validate firmware enrollment, NVIDIA/Wayland behavior, Distrobox GPU passthrough, or hardware suspend/resume; those remain mandatory physical release gates.
