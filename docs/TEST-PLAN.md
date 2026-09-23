# Mandatory physical validation plan

A green compose validates image construction—not a usable NVIDIA/Wayland system. Run the relevant profile plan on intended Turing-or-newer NVIDIA hardware before calling a release ready.

## 1. Provenance and deployment

- Verify the Cosign signature and GitHub provenance/SBOM attestations for the immutable digest of the selected image.
- On Secure-Boot-enforcing hardware, complete BlueBuild’s MOK enrollment flow before switching deployments; do not disable Secure Boot.
- `bootc switch` to the selected Doors image, inspect `bootc status`, and preserve a known-good rollback deployment.
- Confirm Fedora 44 is the deployed stream and no unsupported kernel/driver route is layered.
- For staging, verify that the tested digest is `ghcr.io/mheci/doors:staging`, not the stable `latest` tag.

## 2. Updates

- Confirm `doors-update.timer` is enabled. Confirm `uupd.timer`, `bootc-fetch-apply-updates.timer`, `flatpak-system-updates.timer`, system/global-user `podman-auto-update.timer`, and global `flatpak-user-updates.timer` are not enabled.
- Create or identify at least two regular local accounts, with one logged out. Trigger `sudo systemctl start doors-update.service`; verify the host report at `/var/lib/doors/updates/latest.tsv` names both accounts and that each account has a fresh `~/.local/state/doors/update-report.tsv`.
- Verify `loginctl show-user USER -p Linger` reports `Linger=yes` for each account included by the coordinator, and inspect `journalctl -u doors-update.service` plus `journalctl --user -u doors-user-update.service` for failures/skips.
- Verify one run stages a bootc deployment through `uupd` without rebooting automatically, updates system/user Flatpaks and Distroboxes in the correct ownership scope, and runs only label-managed Podman auto-updates.
- Install or identify Gear Lever-managed and unintegrated AppImages. Verify Gear Lever is provisioned, only its integrated AppImages are updated, a running AppImage is not forced closed/replaced, and unintegrated artifacts are reported rather than executed.
- If Homebrew or an optional adapter is present, test the approved root/explicit config path and verify an unsupported adapter line is reported rather than sourced. Test an unlabelled container and copied executable remain untouched.
- Reboot manually into a staged deployment, then test `bootc rollback`.

## 3. CI boot validation

- For each PR or merge-queue matrix image, confirm the `verify` job passes the direct serial `os-autoinst` boot gate after the exact composed OCI archive is converted to QCOW2.
- On a failure, retain and inspect the uploaded `doors-boot-*` artifact: candidate archive hash/inspect data, bootc-image-builder log, and os-autoinst serial/result evidence. The generated 40 GiB QCOW2 is deliberately excluded to preserve artifact storage; regenerate it from the recorded candidate identity when deeper disk inspection is necessary. Do not waive a timeout, kernel panic/oops, emergency-mode, mount/dependency, or service-start failure without root-cause investigation.
- Treat this as a fast early-runtime gate only. It does not replace Secure Boot/MOK, NVIDIA, graphical-session, suspend/resume, external-display, audio, or GPU-container validation on physical hardware.

## 4. Graphics, games, and browsers

- Confirm the selected GNOME, COSMIC, or Plasma session starts; BlueBuild NVIDIA Open modules load; `nvidia-smi` works; and Vulkan/OpenGL acceleration is available.
- Test cold boot, suspend/resume, external display, audio, login/logout, Steam, Heroic, Faugus, ProtonPlus, umu-launcher, Fedora Gamescope, and Vesktop.
- Inspect Falcond, Ananicy-cpp, and scx_loader; confirm `scx_lavd` uses `LowLatency` mode. Verify GameMode remains absent.
- Launch Brave Origin, Zen, and Helium under the selected Wayland desktop. Test media, WebGL/WebGPU where available, downloads, and suspend/resume. Confirm Firefox and ordinary Brave are absent.

## 5. AI Distrobox and CUDA

- On first graphical login, verify `doors-ai-distrobox.service` creates the rootless `doors-ai` container from `docker.io/library/archlinux:latest` with NVIDIA integration.
- Run `doors-ai run nvcc --version`, `doors-ai run pi --version`, `doors-ai run t3 --help`, `doors-ai run opencode --version`, and `doors-ai run herdr --version`.
- Verify `doors-ai run nvidia-smi` and a small CUDA device query/workload can access the host GPU.
- Inspect the container: `pacman` must use only signed official Arch repositories; `/opt/cuda` must exist; no AUR helper, external Distrobox repository, `nvidia-utils`, or driver package may be installed.
- Verify host `rpm -q` does not show Node/npm/pnpm, Deno, mise, t3code, OpenCode, or the full CUDA toolkit.
- For an existing pre-Arch box, export any container-local work, run `doors-ai recreate`, then repeat the checks. Confirm normal `doors-ai bootstrap` never deletes it silently.

## 6. Desktop profile, Flatpak, and devices

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

- Verify the static Flathub remote and `doors-flatpak-bootstrap.service`. It must install Bazaar, DistroShelf, and Gear Lever—and only their required runtime dependencies—after network availability.
- Launch Bazaar, DistroShelf, and Gear Lever; test DistroShelf management of the `doors-ai` container and Gear Lever integration/update metadata for one disposable AppImage.
- Test Bluetooth, storage/GVFS, printers, user-local Flatpak behavior, and clipboard persistence.

Record image, digest, hardware, date, MOK result, update outcome, desktop result, Distrobox/CUDA result, failures, and rollback result in the release PR or security record. CI alone never passes these gates.
