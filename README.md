# Doors

> A gaming-tuned Fedora Atomic desktop. Built with [BlueBuild](https://blue-build.org/).

Doors is a set of six OCI images built from Fedora 44 atomic bases, tuned for gaming and local AI:

- **Kernel**: `kernel-cachyos-lto` (x86-64-v3, Clang + ThinLTO, 1000Hz, BORE, sched_ext, ntsync)
- **Scheduler**: sched-ext with `scx_lavd` as the default, managed by `scx_loader`
- **Game tuning**: [`falcond`](https://github.com/PikaOS-Linux/falcond) (Terra) + ananicy-cpp gaming rules
- **GPU**: Terra Mesa everywhere; NVIDIA images use Terra's `nvidia-open` driver + CUDA
- **Local AI**: `llama.cpp` compiled in-image (CUDA on NVIDIA, HIP/ROCm on universal images), plus [`pi`](https://github.com/...), [`opencode`](https://opencode.ai), and `t3code`
- **Display manager**: [lemurs](https://github.com/coastalwhite/lemurs) on all images
- **Branding**: a soft rose / peach / sage / mauve palette (see [`branding/`](branding/))

## Image matrix

| Image | Base | Desktop | GPU | llama.cpp backend |
|---|---|---|---|---|
| `doors` | `ghcr.io/ublue-os/kinoite-main:44` | KDE Plasma | universal (Intel/AMD) | ROCm (HIP) |
| `doors-wl` | `ghcr.io/ublue-os/base-main:44` | Hyprland | universal (Intel/AMD) | ROCm (HIP) |
| `doors-cosmic` | `quay.io/fedora-ostree-desktops/cosmic-atomic:44` | COSMIC | universal (Intel/AMD) | ROCm (HIP) |
| `doors-nvidia` | `ghcr.io/ublue-os/kinoite-main:44` | KDE Plasma | NVIDIA Turing+ | CUDA |
| `doors-wl-nvidia` | `ghcr.io/ublue-os/base-main:44` | Hyprland | NVIDIA Turing+ | CUDA |
| `doors-cosmic-nvidia` | `quay.io/fedora-ostree-desktops/cosmic-atomic:44` | COSMIC | NVIDIA Turing+ | CUDA |

Universal images ship Terra Mesa; NVIDIA images ship Terra's `nvidia-driver` (open modules) + CUDA.

## Installation

> [!WARNING]
> Rebase at your own risk. Atomic rebases replace your current desktop packages.

Doors images are signed with cosign (v1; Secure Boot/MOK is deferred to v2). Verify before rebasing:

```bash
cosign verify --key cosign.pub ghcr.io/mheci/doors:44
```

Rebase an existing atomic Fedora installation (KDE example; swap the image for your variant):

```bash
# bootc-based (Fedora 41+)
sudo bootc switch ghcr.io/mheci/doors:44

# rpm-ostree-based
rpm-ostree rebase ostree-unverified-registry:ghcr.io/mheci/doors:44
sudo systemctl reboot
```

The `:latest` tag tracks the newest `44` build. Base-image major bumps (Fedora `44` → `45`) are **not** auto-merged and ship as review-tagged PRs.

## What's inside

- **Gaming**: Steam, Faugus, Heroic, ProtonPlus, umu-launcher, Vesktop, gamescope, wine + DXVK/vkd3d (RPM Fusion)
- **AI**: llama.cpp (CUDA/HIP), `pi`, `opencode`, `t3code` — versions pinned and bumped by Renovate
- **Browsers**: Firefox, Zen, Brave
- **Terminals/editors**: Ghostty, Kitty, Zed, Neovim
- **Utilities**: pcmanfm-qt, ark, blueman, pwvucontrol (flatpak), Bazaar, Flatseal
- **CLI**: eza, bat, ripgrep, fd, fzf, zoxide, btop, nvtop, starship, lazygit, direnv, gh, just, distrobox …
- **Fonts/themes**: Inter, JetBrains Mono (Nerd Font), Fira Code, Cascadia, Noto CJK + emoji, Bibata/Papirus/Qogir themes, Doors GTK/KDE/Hyprland branding

Codecs come from RPM Fusion (Terra Multimedia is **not** enabled — it is unstable).

## Recipes / control plane

Every image is defined by one file in [`recipes/`](recipes/) plus shared module files. The control plane is **ujust recipes only** — see [`files/justfiles/`](files/justfiles/):

- `just` — list recipes
- `just update` / `just upgrade` — **check** for updates / **manually** apply (never auto-applied)
- `just sched` — scx scheduler status / `just sched set lavd`
- `just llm` — llama-server / ask / quantize helpers
- `just gaming` — gamescope, Heroic, GPU info

## Repository layout

```
recipes/           one recipe per image + shared modules (repos, kernel, gpu-*, packages, ai, desktop-*, branding)
files/scripts/     build scripts (llama.cpp, NVIDIA kmods, opencode install, verify)
files/justfiles/   ujust recipes (control plane)
files/gschema-overrides/
files/system/      lemurs, falcond, scx_loader, hyprland defaults, skel, wallpapers, icons
files/system-kde/  KDE colorscheme
files/system-nvidia/ NVIDIA modprobe/env (shipped only on -nvidia images)
branding/          full branding kit (palette, SVG logo/wallpaper, per-desktop theming)
docs/DOORS-SPEC.md the full design specification
```

## Building

Locally with BlueBuild CLI:

```bash
bluebuild build recipes/doors.yml
```

CI builds all six images weekly (Sunday 06:00 UTC) plus on every push/PR. Each recipe compiles `llama.cpp` and (for `-nvidia`) the NVIDIA kmods in dedicated build stages against `kernel-cachyos-lto`, so the final images stay slim and the kmods always match the shipped kernel.

## Updates & Renovate

- `pi`, `opencode`, and `llama.cpp` pins are bumped by Renovate and auto-merged.
- Base-image digests/tags are auto-merged; base-image **major** bumps need review.
- `falcond`, `scx-*`, and the rest of the Terra stack update automatically via image rebuilds against Terra's repos (no source builds).

## Roadmap

- **v1** (now): cosign signing, ujust control plane, weekly manual updates.
- **v2**: Secure Boot + MOK-enrolled signing key, `scx` mode presets UI, installer ISO.

## License

[Apache-2.0](LICENSE). Doors builds on Fedora, [BlueBuild](https://blue-build.org/), [Terra](https://terrapkg.com/), [CachyOS](https://cachyos.org/), and the sched-ext ecosystem — see each project for its own license.
