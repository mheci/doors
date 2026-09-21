# Mandatory physical validation plan

A green compose validates image construction—not a usable NVIDIA/Wayland system. Run this plan on the intended Turing-or-newer NVIDIA hardware before calling a release ready.

## 1. Provenance and deployment

- Verify the Cosign signature and GitHub provenance/SBOM attestations for the immutable digest.
- On Secure-Boot-enforcing hardware, complete BlueBuild’s MOK enrollment flow before switching deployments; do not disable Secure Boot.
- `bootc switch` to Doors, inspect `bootc status`, and preserve a known-good rollback deployment.
- Confirm Fedora 44 is the deployed base stream and no unsupported kernel/driver route is layered.

## 2. Updates

- Confirm `uupd.timer` is enabled.
- Confirm `bootc-fetch-apply-updates.timer`, `flatpak-system-updates.timer`, and global `flatpak-user-updates.timer` are not enabled.
- Trigger or observe one `uupd` run. Verify it stages a bootc deployment without rebooting automatically, updates Flatpaks, and safely handles the Doors AI Distrobox.
- Reboot manually into a staged deployment, then test `bootc rollback`.

## 3. Graphics, games, and browsers

- Confirm GNOME/GDM is the only session, BlueBuild NVIDIA Open modules load, `nvidia-smi` works, and Vulkan/OpenGL acceleration is available.
- Test cold boot, suspend/resume, external display, audio, login/logout, Steam, Heroic, Faugus, ProtonPlus, umu-launcher, Fedora Gamescope, and Vesktop.
- Inspect Falcond, Ananicy-cpp, and scx_loader; confirm `scx_lavd` uses `LowLatency` mode. Verify GameMode remains absent.
- Launch Brave Origin, Zen, and Helium under GNOME/Wayland/NVIDIA. Test media, WebGL/WebGPU where available, downloads, and suspend/resume. Confirm Firefox and ordinary Brave are absent.

## 4. AI Distrobox and CUDA

- On first graphical login, verify `doors-ai-distrobox.service` creates the rootless `doors-ai` container from `registry.fedoraproject.org/fedora-toolbox:44`.
- Run `doors-ai run nvcc --version`, `doors-ai run pi --version`, `doors-ai run herdr --version`, and the relevant Bun/Deno/OpenCode/t3code checks.
- Verify `doors-ai run nvidia-smi` and a small CUDA device query/workload can access the host GPU.
- Inspect the container’s repositories: Fedora/Terra/NVIDIA CUDA must be Fedora 44; CUDA must not have installed or replaced a host driver path.
- Verify host `rpm -q` does not show Node/npm/pnpm, Deno, mise, t3code, OpenCode, or the full CUDA toolkit.

## 5. Desktop, Flatpak, and devices

- Confirm Yaru dark, fonts, fixed left dock, no forced wallpaper, and the requested GNOME extensions.
- Test Vicinae hotkey/uinput, Clipboard Indicator, and `wl-clip-persist` for the regular clipboard only.
- Verify the static Flathub remote and `doors-flatpak-bootstrap.service`. It must install Bazaar and DistroShelf—and only their required runtime dependencies—after network availability.
- Launch Bazaar and DistroShelf; test DistroShelf management of the `doors-ai` container.
- Test GSConnect, Bluetooth, storage/GVFS, printers, and user-local Flatpak behavior.

Record hardware, digest, date, MOK result, update outcome, Distrobox/CUDA result, failures, and rollback result in the release PR or security record. CI alone never passes these gates.
