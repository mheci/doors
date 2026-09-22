# Mandatory physical validation plan

A green compose validates image construction—not a usable NVIDIA/Wayland system. Run the relevant profile plan on intended Turing-or-newer NVIDIA hardware before calling a release ready.

## 1. Provenance and deployment

- Verify the Cosign signature and GitHub provenance/SBOM attestations for the immutable digest of the selected image.
- On Secure-Boot-enforcing hardware, complete BlueBuild’s MOK enrollment flow before switching deployments; do not disable Secure Boot.
- `bootc switch` to the selected Doors image, inspect `bootc status`, and preserve a known-good rollback deployment.
- Confirm Fedora 44 is the deployed stream and no unsupported kernel/driver route is layered.
- For staging, verify that the tested digest is `ghcr.io/mheci/doors:staging`, not the stable `latest` tag.

## 2. Updates

- Confirm `uupd.timer` is enabled.
- Confirm `bootc-fetch-apply-updates.timer`, `flatpak-system-updates.timer`, and global `flatpak-user-updates.timer` are not enabled.
- Trigger or observe one `uupd` run. Verify it stages a bootc deployment without rebooting automatically, updates Flatpaks, and safely handles the Doors AI Distrobox.
- Reboot manually into a staged deployment, then test `bootc rollback`.

## 3. Graphics, games, and browsers

- Confirm the selected GNOME, COSMIC, or Plasma session starts; BlueBuild NVIDIA Open modules load; `nvidia-smi` works; and Vulkan/OpenGL acceleration is available.
- Test cold boot, suspend/resume, external display, audio, login/logout, Steam, Heroic, Faugus, ProtonPlus, umu-launcher, Fedora Gamescope, and Vesktop.
- Inspect Falcond, Ananicy-cpp, and scx_loader; confirm `scx_lavd` uses `LowLatency` mode. Verify GameMode remains absent.
- Launch Brave Origin, Zen, and Helium under the selected Wayland desktop. Test media, WebGL/WebGPU where available, downloads, and suspend/resume. Confirm Firefox and ordinary Brave are absent.

## 4. AI Distrobox and CUDA

- On first graphical login, verify `doors-ai-distrobox.service` creates the rootless `doors-ai` container from `docker.io/library/archlinux:latest` with NVIDIA integration.
- Run `doors-ai run nvcc --version`, `doors-ai run pi --version`, `doors-ai run t3 --help`, `doors-ai run opencode --version`, and `doors-ai run herdr --version`.
- Verify `doors-ai run nvidia-smi` and a small CUDA device query/workload can access the host GPU.
- Inspect the container: `pacman` must use only signed official Arch repositories; `/opt/cuda` must exist; no AUR helper, external Distrobox repository, `nvidia-utils`, or driver package may be installed.
- Verify host `rpm -q` does not show Node/npm/pnpm, Deno, mise, t3code, OpenCode, or the full CUDA toolkit.
- For an existing pre-Arch box, export any container-local work, run `doors-ai recreate`, then repeat the checks. Confirm normal `doors-ai bootstrap` never deletes it silently.

## 5. Desktop profile, Flatpak, and devices

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

- Verify the static Flathub remote and `doors-flatpak-bootstrap.service`. It must install Bazaar and DistroShelf—and only their required runtime dependencies—after network availability.
- Launch Bazaar and DistroShelf; test DistroShelf management of the `doors-ai` container.
- Test Bluetooth, storage/GVFS, printers, user-local Flatpak behavior, and clipboard persistence.

Record image, digest, hardware, date, MOK result, update outcome, desktop result, Distrobox/CUDA result, failures, and rollback result in the release PR or security record. CI alone never passes these gates.
