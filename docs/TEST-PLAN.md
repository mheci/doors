# Mandatory physical validation plan

A green compose validates image construction—not a usable NVIDIA/Wayland system. Run the relevant profile plan on intended Turing-or-newer NVIDIA hardware before calling a release ready.

## 1. Provenance and deployment

- Verify the Cosign signature and GitHub provenance/SBOM attestations for the immutable digest of the selected image.
- On Secure-Boot-enforcing hardware, inspect `doors-secureboot fingerprint` and compare it with the release certificate record. Run `sudo doors-secureboot enroll`, reboot, and have the physical machine owner approve enrollment (and MOK trust, if requested) in MokManager. Do not disable Secure Boot; CI cannot complete this firmware-owner action.
- Run `ujust doors-image-status`, then use `ujust doors-image-switch gnome`, `cosmic`, or `kinoite` to stage a fixed Doors target. Confirm it retains the booted deployment, does not reboot automatically, and backs up/resets only the allowlisted desktop-shell/theme state for every regular local account. Repeat with `ujust doors-desktop-cleanup` on a two-account test host and inspect each private backup under `~/.local/state/doors/desktop-switch-backups/`.
- On disposable hardware, start from each Doors desktop and stage each of the three fixed targets (the full 3×3 same-image/cross-desktop matrix). Between attempts, retain or roll back to a known-good deployment. Confirm each permitted transition accepts the current signed digest, retains rollback, and does not reboot automatically.
- Inspect `/etc/containers/policy.json` and `/etc/containers/registries.d/doors-signatures.yaml`. The only added Doors scopes must be `ghcr.io/mheci/doors`, `ghcr.io/mheci/doors-cosmic`, and `ghcr.io/mheci/doors-kinoite`; each must require `sigstoreSigned`, `matchRepository`, `/etc/pki/containers/doors-shared.pub`, and sigstore-attachment discovery. The general Docker fallback must not be treated as trust for a Doors target.
- Confirm `doors-image` invokes `bootc switch --enforce-container-sigpolicy`. On a disposable host, attempt controlled unsigned, wrong-key-signed, and unlisted-repository targets directly with that flag; each must be rejected before it stages a deployment. The helper itself accepts only fixed Doors GHCR targets; still inspect the fixed target and release provenance before switching.
- Treat this enforcement as protection for an explicit `bootc switch` only. `bootc upgrade` currently has no equivalent container-signature-policy enforcement option, so do not claim that a successful enforced switch also verifies all later upgrade pulls. Track upstream bootc support and validate the deployed upgrade path separately before relying on it for that guarantee.
- Confirm `bootc status` retains a known-good rollback deployment after staging, then reboot manually only when ready. Test `bootc rollback` on a disposable deployment.
- Confirm Fedora 44 is the deployed stream and no unsupported kernel/driver route is layered.
- For staging, verify that the tested digest is `ghcr.io/mheci/doors:staging`, not the stable `latest` tag.

## 2. Updates

- Confirm `doors-update.timer` is enabled. Confirm `uupd.timer`, `bootc-fetch-apply-updates.timer`, `flatpak-system-updates.timer`, system/global-user `podman-auto-update.timer`, and global `flatpak-user-updates.timer` are not enabled.
- Create or identify at least two regular local accounts, with one logged out. Trigger `sudo systemctl start doors-update.service`; verify the host report at `/var/lib/doors/updates/latest.tsv` names both accounts and that each account has a fresh `~/.local/state/doors/update-report.tsv`.
- Verify `loginctl show-user USER -p Linger` reports `Linger=yes` for each account included by the coordinator, and inspect `journalctl -u doors-update.service` plus `journalctl --user -u doors-user-update.service` for failures/skips.
- Verify one run stages a bootc deployment through `uupd` without rebooting automatically, updates system/user Flatpaks in the correct ownership scope, and runs only explicitly label-managed Podman auto-updates when Podman is present.
- Install or identify Gear Lever-managed and unintegrated AppImages. Verify Gear Lever is provisioned, only its integrated AppImages are updated, a running AppImage is not forced closed/replaced, and unintegrated artifacts are reported rather than executed.
- If Homebrew or an optional adapter is present, test the approved root/explicit config path and verify an unsupported adapter line is reported rather than sourced. Test an unlabelled container and copied executable remain untouched.
- Reboot manually into a staged deployment. On the supported GRUB path, verify `greenboot-healthcheck.service` and `greenboot-set-rollback-trigger.service` are enabled, `greenboot-healthcheck.service` reaches `active`, and `journalctl -b -u greenboot-healthcheck.service` records a green health check. On a disposable test deployment, add a temporary failing required Greenboot check and verify the bounded retry/rollback path returns to the known-good deployment; remove that test check immediately afterward. Do not run an intentional rollback test on a machine with unbacked user data.
- If `/boot/grub2/grubenv` is absent, confirm the Greenboot units are skipped rather than failed; that bootloader is outside Greenboot’s current rollback backend, so retain and test manual `bootc rollback` instead.

## 3. Time, DNS, privilege, logging, and storage policy

- Confirm `chronyd.service`, `systemd-resolved.service`, and `unbound-anchor.timer` are enabled. Run `chronyc -N sources -v` and `chronyc -N authdata`; verify Chrony selects authenticated NTS sources and does not silently fall back to unauthenticated pool/DHCP sources.
- Run `ujust dns-status`, then test every reviewed selector mode: `resolved-quad9`, `resolved-cloudflare`, `unbound-quad9`, `unbound-cloudflare`, and `systemd-resolved-compat`. In strict modes, confirm NetworkManager has `dns=none`, resolved has DNS-over-TLS and DNSSEC enabled, and DHCP/VPN DNS cannot replace the selected resolver. In Unbound modes, verify `unbound-checkconf`, a loopback `127.0.0.1:5335` listener, a valid root trust anchor, DNSSEC validation, and a successful resolver query. Treat compatibility mode as an intentional privacy/control downgrade.
- Before changing DNS, put a test machine's `/etc/resolv.conf` in a nonstandard/custom state and confirm `doors-dns select …` refuses to overwrite it. Restore the conventional resolved-stub symlink before continuing.
- Use a disposable disk and a wheel test account to verify `run0` retains its administrator authentication as intended, `pkexec` is present, and all UDisks mount/format/disk actions are allowed without an additional polkit prompt. This is deliberately a destructive wheel trust boundary; do not test formatting on a disk with needed data.
- Confirm `coredumpctl` has no retained new core after a disposable crashing process, `systemctl show --property=DefaultLimitCORE` and `systemctl --user show --property=DefaultLimitCORE` report zero, and `journalctl` does not retain info/debug records under the Doors journald policy. Verify GTK/GDK/Qt debug noise remains suppressed in both a newly logged-in account and an existing user manager.
- Verify `sysctl vm.max_map_count vm.page_lock_unfairness kernel.split_lock_mitigate`; inspect `/proc/cmdline` for `nvme_core.default_ps_max_latency_us=0`; and confirm `modprobe -c | grep NVreg_EnableResizableBar` includes the NVIDIA ReBAR policy. Validate NVMe idle behavior, suspend/resume, and a game workload on real hardware.
- On a disposable encrypted-root test system only, run `ujust doors-luks-status`, then test `ujust doors-luks-tpm2-pin` with Secure Boot enabled and `ujust doors-luks-fido2` with one hmac-secret-capable FIDO2 key. Confirm the required typed confirmation, existing password fallback test, LUKS-header/crypttab backups, no destructive slot removal, PCR-7 TPM+PIN or FIDO2 client-PIN+touch metadata, retention of an already configured *other* hardware method, and staged initramfs inspection. Reboot manually and prove both hardware unlock and the retained manual password recovery path before modifying any LUKS token. Do not use this first on a machine without an offline recovery plan.

## 4. Secure Boot and CI boot validation

- After the MOK-enrollment reboot, run `doors-secureboot status` and `doors-secureboot verify`. Confirm Secure Boot is enabled, the tracked MOK is in MokList, every current kernel PE/COFF payload verifies with that certificate, and every current loadable module reports `Doors Secure Boot MOK` as its signer.
- Confirm the trusted publication logs show the late signer handling at least one kernel payload and one module, without printing a private key. Confirm no MOK PEM/key is present in the image filesystem, OCI artifact, or repository.
- For each PR or merge-queue matrix image, confirm the `verify` job generates a disposable MOK pair, passes it only to the two non-publishing compose attempts, removes its on-disk private files, and passes the direct serial `os-autoinst` boot gate after the exact composed OCI archive is converted to QCOW2.
- On a failure, retain and inspect the uploaded `doors-boot-*` artifact: candidate archive hash/inspect data, bootc-image-builder log, and os-autoinst serial/result evidence. The generated 40 GiB QCOW2 is deliberately excluded to preserve artifact storage; regenerate it from the recorded candidate identity when deeper disk inspection is necessary. Do not waive a timeout, kernel panic/oops, emergency-mode, mount/dependency, or service-start failure without root-cause investigation.
- Treat this as a fast early-runtime gate only. It does not replace Secure Boot/MOK, NVIDIA, graphical-session, suspend/resume, external-display, audio, or native CUDA validation on physical hardware.

## 5. Graphics, games, and browsers

- Confirm the selected GNOME, COSMIC, or Plasma session starts; BlueBuild NVIDIA Open modules load; `nvidia-smi` works; and Vulkan/OpenGL acceleration is available.
- Test cold boot, suspend/resume, external display, audio, login/logout, Steam, Heroic, Faugus, ProtonPlus, umu-launcher, Fedora Gamescope, and Vesktop.
- On actual HDA and NVIDIA HDMI/DisplayPort hardware, verify idle audio nodes do not suspend, then test repeated start/stop, display hotplug, and suspend/resume for pops, crackles, or lost output. Confirm 48 kHz/256-frame PipeWire behavior and a Proton/Wine title without underruns.
- Confirm no X11 alert bell is audible. With a real microphone, select **Anechoic Noise Suppression** as the application input, verify speech/noise behavior and latency, then confirm the original microphone remains available. Inspect the packaged plugin with `analyseplugin /usr/lib64/ladspa/libanechoic_ladspa.so` and retain the test result with the release record.
- Inspect Falcond, Ananicy-cpp, and scx_loader; confirm `scx_lavd` uses `LowLatency` mode. Verify GameMode remains absent.
- Launch Brave Origin, Zen, and Helium under the selected Wayland desktop. Test media, WebGL/WebGPU where available, downloads, and suspend/resume. Confirm Firefox and ordinary Brave are absent.

## 6. Native AI and CUDA

- On every desktop image, run `doors-ai status`, then run `nvcc --version`, `ncu --version`, `nsys --version`, `pi --version`, `t3 --help`, `opencode --version`, `herdr --version`, `bun --version`, `deno --version`, and `mise --version`. Confirm each is a native host command and no per-user setup or command-export step is needed.
- Verify `rpm -q bun-bin deno mise opencode-cli cuda-toolkit-13-4 cuda-nvcc-13-4 cuda-nsight-compute-13-4 cuda-nsight-systems-13-4`; then inspect `/usr/lib/doors/native-ai/t3/node_modules/t3/package.json` and run `t3 --help`. Confirm T3 and Pi remain at their lock-pinned versions with lifecycle scripts disabled during compose. Confirm `t3 update` refuses to create an unmanaged user-local replacement; a reviewed immutable rebase is the T3 update path.
- Run `gpg --show-keys --with-fingerprint /etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-cuda` and `sha256sum` on that key; require fingerprint `129994480EC63D2789BC98E490DFED2F73CD9B30` and digest `9221458f62030a18d5a28eecf44496016ff9c11548492ac2ce428f75c7513cab`. Inspect `/etc/yum.repos.d/cuda-fedora44.repo`; confirm `gpgcheck=1`, `repo_gpgcheck=1`, the Fedora 44 x86_64 endpoint, and exclusions for all NVIDIA driver/userspace replacement packages.
- Verify `/usr/lib/doors/cuda-13.4/bin/nvcc`, the relocated `nsight-compute-*` and `nsight-systems-*` payloads, `/usr/bin/nvcc`, `/usr/bin/ncu`, `/usr/bin/nsys`, and `/etc/profile.d/doors-cuda.sh`; confirm `/usr/local/cuda-13.4`, `/usr/local/cuda-13`, `/usr/local/cuda`, `/opt/nvidia/nsight-compute`, and `/opt/nvidia/nsight-systems` are absent. Open a fresh login shell and confirm `CUDA_HOME`, `PATH`, and `LD_LIBRARY_PATH` select CUDA 13.4.
- Verify `nvidia-smi`, a small native CUDA compile, and a CUDA device query/workload can access the host GPU. Confirm the image uses the BlueBuild NVIDIA Open driver path and has not installed `cuda-drivers` or another alternate driver route.
- Inspect `/usr/share/doors/native-ai/herdr/herdr.json`; verify its repository, asset, tag, and digest match the installed `/usr/bin/herdr`. Confirm a rebase does not delete unrelated existing user workloads automatically.

## 7. Desktop profile, Flatpak, and devices

### GNOME / Silverblue and staging

- Confirm Yaru dark, fonts, fixed left dock, no forced wallpaper, and the requested GNOME extensions.
- Test Vicinae hotkey/uinput, Clipboard Indicator, and `wl-clip-persist` for the regular clipboard only.

### COSMIC

- On a clean user account, confirm the first session starts in dark mode.
- Change COSMIC’s appearance preference, log out/in, and confirm the preference is not overwritten.
- Confirm GNOME Shell extensions and Doors GNOME dconf defaults are absent from this image.

### Kinoite / Plasma

- Confirm native Breeze Dark look-and-feel, color scheme, icons, and GTK integration are selected as defaults; set a user preference and confirm it overrides `/etc/xdg/kdeglobals`.
- Confirm Steam starts in normal desktop mode and that neither Big Picture nor Game Mode autostarts.
- Inspect deployed assets/settings to confirm no Valve-derived theme or SteamDeck asset is shipped.
- Confirm GNOME Shell extensions and Doors GNOME dconf defaults are absent from this image.

### Shared services

- Verify the static Flathub remote and `doors-flatpak-bootstrap.service`. It must remove inherited system remotes/static remote metadata, retain only the reviewed Flathub trust root by default, and install Bazaar and Gear Lever—and only their required runtime dependencies—after network availability.
- Inspect active `/etc/yum.repos.d/*.repo` files and `/var/cache/libdnf5/*/metalink.xml` after a refresh. Confirm active URLs are HTTPS, Fedora metalinks include `protocol=https`, and DNF TLS verification remains enabled. Test that a Fedora-repos refresh does not reintroduce HTTP candidates.
- Launch Bazaar and Gear Lever; test Gear Lever integration/update metadata for one disposable AppImage.
- Test Bluetooth, storage/GVFS, printers, user-local Flatpak behavior, and clipboard persistence.

Record image, digest, hardware, date, MOK result, update outcome, desktop result, native AI/CUDA result, failures, and rollback result in the release PR or security record. CI alone never passes these gates.
