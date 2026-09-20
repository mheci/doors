# Mandatory physical validation plan

A green container/CI build proves composition, not a usable graphics/gaming desktop. Run this plan on the intended **Turing-or-newer NVIDIA** target after every material base, driver, performance-stack, browser, extension, or session change and before describing an image as release-ready.

## 1. Provenance and deployment

- Verify `cosign verify --key cosign.pub ghcr.io/mheci/doors:latest`.
- Verify GitHub provenance/SBOM attestations against the immutable image digest.
- `bootc switch` to the image, inspect `bootc status`, and preserve a working rollback deployment.
- Confirm the only intended image/tag is used; no ISO/variant behavior is introduced.

## 2. Boot, graphics, suspend

- Confirm GNOME/GDM is the only session offered.
- Confirm stock kernel, `nvidia-open` modules, DRM modesetting, GPU acceleration, Vulkan/OpenGL, and `nvidia-smi` behavior.
- Test cold boot, suspend/resume, external display, audio, and repeated login/logout.
- Confirm no unexpected listener/service and that the legacy bootc updater remains masked while `uupd.timer` stages updates without rebooting.

## 3. Performance and gaming

- Inspect `falcond.service`, `ananicy-cpp.service`, and `scx_loader.service`; confirm `scx_loader` uses `scx_lavd` in `LowLatency` mode.
- Exercise idle, desktop workloads, CPU/GPU load, a game launch, suspend/resume, and recovery after a failed game/launcher process.
- Test Steam, Heroic, Faugus, ProtonPlus, umu-launcher, Gamescope, and Vesktop. Confirm GameMode is absent and no component expects it.
- Look for priority/cgroup/scheduler regressions, stalls, input latency, GPU resets, and boot failures. Keep a rollback path ready.

## 4. Browsers and desktop

- Launch Brave Origin, Zen, and Helium under GNOME/Wayland/NVIDIA.
- Test media playback, WebGL/WebGPU where available, hardware-acceleration behavior, downloads, profile creation, and suspend/resume around active browser use.
- Specifically gate Brave Origin before calling it supported.
- Confirm Firefox and ordinary Brave are absent.
- Confirm Yaru dark, Inter, JetBrains Mono, a compact fixed left dock, no forced wallpaper, and no Doors/Ubuntu artwork.

## 5. Extensions, launcher, clipboard, devices

- Confirm all nine requested extensions load on the current GNOME version and do not crash/restart Shell.
- Confirm Vicinae starts on graphical login, `<Super><Shift>space` toggles it, `uinput` paste works, and user overrides remain possible.
- Verify Vicinae + Clipboard Indicator monitoring simultaneously, then test `wl-clip-persist` across source-app exit for **regular** clipboard data only. Confirm primary selection is unaffected and observe memory behavior with text, images, large data, and sensitive-looking inputs.
- Test GSConnect pairing, Bluetooth, storage/GVFS, printers, Bazaar/Flathub, Flatpak runtime provisioning, and user-local updater behavior.

## 6. Update and rollback

- Let `uupd.timer` stage a newer image; confirm it does not initiate a reboot.
- Reboot manually, confirm the staged deployment activates, and verify `bootc rollback` recovery.
- Confirm updates to RPMs, Bun, Pi, Herdr, wl-clip-persist, and EGO extensions followed their declared freshness/verification paths in CI logs.

Record hardware, image digest, test date, successes, failures, and rollback outcome in a release PR or security record. Do not mark the physical gates as passed from CI alone.
