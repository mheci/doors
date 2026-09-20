# Image contract

This file is the concise, implementable contract for the only supported Doors image.

## Identity and base

| Property | Contract |
|---|---|
| Public image | `ghcr.io/mheci/doors:latest` only |
| Architecture | `linux/amd64` |
| Base | `ghcr.io/ublue-os/bazzite-gnome-nvidia-open:latest` |
| Desktop/session | GNOME + GDM only |
| GPU path | Upstream Bazzite GNOME NVIDIA Open base; matched NVIDIA Open driver/modules and userspace for Turing-or-newer GPUs |
| Kernel | Upstream Bazzite kernel; Doors adds no kernel or driver module. A failed base compose fails closed rather than being pinned, overridden, or supplemented. |
| Publication | Monday 00:00 UTC plus trusted `main`/manual-main runs |
| Artifact policy | No ISO and no desktop/hardware/image matrix |

## Non-negotiable removals

- custom CachyOS kernel, third-party kernel COPRs, manual NVIDIA userspace/kmods, NVIDIA `.run`, AUR/PPA/Snap routes;
- `--nogpgcheck`, `--nodeps`, `skip-unavailable`, `skip-broken`, and resolver-bypass scripts;
- Firefox, ordinary Brave, GameMode, Hermes, CUDA, Conda/source-built llama.cpp, Playwright;
- Lemurs, KDE, COSMIC, Hyprland, custom Doors branding/wallpapers, and legacy session configuration;
- Flatseal/pwvucontrol/default Flatpak provisioning.

## Runtime policy

- **Performance:** enable `falcond.service`, `ananicy-cpp.service`, and `scx_loader.service`; `scx_lavd` starts in `LowLatency` mode. Falcond conflicts with GameMode, so GameMode stays removed.
- **Updating:** `uupd.timer` stages; reboot is manual. The older bootc fetch/apply timer is masked to avoid competing updaters.
- **Flatpak:** Flathub capability remains; only Bazaar is declared for system provisioning.
- **Vicinae/clipboard:** global user service enabled; package-managed `uinput` load retained; Super+Shift+Space runs `vicinae toggle`; Vicinae monitoring is on. Clipboard Indicator is enabled too; its current upstream schema has no separate monitoring switch, and its enabled extension attaches regular-clipboard tracking with private mode initially off. `wl-clip-persist` is a global graphical user service for the regular clipboard only, with no content/size filter.
- **GNOME defaults:** system defaults, not locks. Users retain ownership of their dconf settings and wallpaper.

## Major-version safety stop

The base intentionally tracks `latest`, but the vendored Terra trust root is currently **Terra 44**. If Bazzite moves to a new Fedora major, `$releasever` makes the Terra repository request a corresponding key path that is not present. The build must fail until a reviewed PR refreshes the release-specific key, fingerprints, solver evidence, and physical test plan. It must never silently mix an older Terra repository with a new Fedora base.
