# Doors — specification (grilling outcome)

Status: locked 2026-09-11 via grilling session. This document is the canonical plan for
`github.com/mheci/doors` and supersedes the Ryven plan. Ryven (`github.com/mheci/Ryven`,
audited in RYVEN-AUDIT.md) is a read-only lessons artifact and will be deleted (repo +
GHCR packages) once Doors passes the readiness gate in section 8.

## 1. Decision record (what was settled)

| # | Decision | Choice |
|---|---|---|
| D1 | Source of truth | `doors`. Ryven frozen, then deleted at the readiness gate |
| D2 | Images | 6 total: 3 desktops × (universal, nvidia) |
| D3 | Kernel | kernel-cachyos-lto (bieszczaders COPR) on all 6 |
| D4 | Scheduler | scx_loader (Terra `scx-tools`) → `scx_lavd` default; scx-scheds, scxctl, scxtui, scx-manager |
| D5 | Game daemon | falcond (+ falcond-gui, falcond-profiles) from Terra, preconfigured `scx_sched = lavd` |
| D6 | AI | pi (npm), OpenCode, llama.cpp (CUDA on -nvidia, ROCm on universal via Fedora ROCm), t3code |
| D7 | Repos | Terra (base + extras + mesa; NOT multimedia) + RPM Fusion OOTB; CachyOS COPRs for kernel/addons |
| D8 | Signing | v1: cosign only (ECDSA key already in doors). Secure Boot/MOK deferred to v2 |
| D9 | Display manager | lemurs v0.4.0 (prebuilt binary, pinned) on ALL images |
| D10 | Control plane | ujust recipes only (no D-Bus daemon / MCP / polkit tiers in v1) |
| D11 | Branding | "Doors — thresholds". Palette below, rose accent, door glyph, full Doors identity |
| D12 | Updates | Weekly background check (uupd), manual apply; never auto-apply |
| D13 | Build cadence | Weekly (Sat 03:00 UTC), base pinned to `44` |
| D14 | Renovate | Automerge everything except base-major (`44`→`45`), which opens a review PR |
| D15 | Modules | Use official BlueBuild modules wherever possible; custom only for akmods, llama.cpp, lemurs, verify |
| D16 | License / owners | MIT; CODEOWNERS = @mheci |
| D17 | Scope | Desktop gaming images, no ISOs (rebase only), x86-64-v3, no legacy NVIDIA (< Turing) |

## 2. Image matrix

Base images verified live on 2026-09-11 (all have a `44` tag):

| Name | Base | Desktop | GPU | llama.cpp backend |
|---|---|---|---|---|
| `doors` | `ghcr.io/ublue-os/kinoite-main:44` | KDE Plasma | universal (Intel+AMD) | ROCm (Fedora) |
| `doors-wl` | `ghcr.io/ublue-os/base-main:44` | Hyprland | universal | ROCm (Fedora) |
| `doors-cosmic` | `quay.io/fedora-ostree-desktops/cosmic-atomic:44` | COSMIC | universal | ROCm (Fedora) |
| `doors-nvidia` | `ghcr.io/ublue-os/kinoite-main:44` | KDE Plasma | NVIDIA Turing+ | CUDA (Terra) |
| `doors-wl-nvidia` | `ghcr.io/ublue-os/base-main:44` | Hyprland | NVIDIA Turing+ | CUDA (Terra) |
| `doors-cosmic-nvidia` | `quay.io/fedora-ostree-desktops/cosmic-atomic:44` | COSMIC | NVIDIA Turing+ | CUDA (Terra) |

Notes:
- `cosmic-atomic` (quay) is the Fedora-official bootc image. The ublue `cosmic-atomic-main`
  is deprecated at F42, so it is NOT used (decision made in grilling round 4).
- Universal = Terra mesa + Intel/AMD. NVIDIA = terra-nvidia userspace + nvidia-open kmod
  built in a stage against kernel-cachyos-lto.

## 3. Repository sources

| Source | Provides | Enable method |
|---|---|---|
| ublue/Fedora base | OS | base-image |
| bieszczaders/kernel-cachyos-lto | kernel | dnf `repos.copr` |
| bieszczaders/kernel-cachyos-addons | ananicy-cpp, cachyos-ananicy-rules, cachyos-settings | dnf `repos.copr` |
| Terra base | falcond, falcond-gui, falcond-profiles, scx-scheds, scx-tools, zen-browser, zed, ghostty, vesktop, heroic, t3code, umu | `terra.repo` + `terra-release` |
| Terra mesa | mesa (OGG-patched) | `terra-release-mesa` + replace from `terra-mesa` |
| Terra extras | patched wine, switcheroo-control | `terra-release-extras` |
| Terra nvidia | nvidia driver + CUDA + akmod-nvidia | `terra-release-nvidia` |
| RPM Fusion | codecs, steam, wine, dxvk, vkd3d (multimedia NOT via Terra per D7) | bling `rpmfusion` |
| COPRs | faugus-launcher, protonplus, zen-browser (sneexy) | dnf `repos.copr` |
| Brave | brave-browser | brave .repo + key |
| Fedora | ROCm 7.1 (rocm-hip-devel, hipblas-devel, rocblas-devel), nodejs, build toolchain | stock |

`terra-multimedia` is explicitly NOT enabled (D7); codecs come from RPM Fusion free+nonfree.

## 4. Package set (per D2 grilling answer, v1)

- Gaming: steam, faugus-launcher, heroic-games-launcher, protonplus, umu-launcher, vesktop, gamescope
- Wine/compat (kept from Ryven infra, cut if unwanted): wine-core + wine-core.i686, wine-mono, dxvk + i686, vkd3d + i686
- Browsers: firefox, zen-browser (Terra), brave-browser (Brave repo)
- Editors/terminals: zed (Terra), neovim, ghostty (Terra), kitty
- Media: mpv, libva-utils, vdpauinfo
- Desktop utils: pcmanfm-qt, ark, blueman, network-manager-applet, system-config-printer, udisks2, gvfs (+smb/mtp/afc), grim, slurp, swappy, wf-recorder, cliphist, nwg-displays, wlogout, p7zip, unar, unzip, xz, zstd
- CLI set (Ryven carryover): eza, bat, ripgrep, fd-find, fzf, zoxide, htop, btop, nvtop, starship, lazygit, direnv, git, git-lfs, gh, just, jq, yq, curl, wget, distrobox
- Fonts/theme: inter, jetbrains-mono (nerd via fonts module), fira-code, cascadia, iosevka, roboto, cantarell, noto-cjk, noto-emoji; bibata + capitaine cursors; papirus, breeze, tela, qogir, numix icons
- AI: nodejs, npm, t3code, pi (@earendil-works/pi-coding-agent, pinned), opencode (pinned), llama.cpp (stage-built, per-image backend)
- Audio mixer: pwvucontrol → Flathub `com.saivert.pwvucontrol` (author-recommended channel)

## 5. Module map (official BlueBuild modules used)

| Concern | Module(s) |
|---|---|
| RPM Fusion | `bling` (rpmfusion) |
| Repos + packages | `dnf` (copr, files, keys, install, remove, replace) |
| Kernel swap | `dnf` (remove stock kernel + install kernel-cachyos-lto). Fallback: `rpm-ostree` if dnf remove is rejected at first build |
| Mesa from Terra | `dnf` replace from `terra-mesa` |
| Config files | `files` |
| Units | `systemd` (enable/mask) |
| ujust recipes | `justfiles` |
| Kernel args | `kargs` (per-variant) |
| Initramfs regen | `initramfs` |
| Flatpaks | `default-flatpaks` |
| Fonts | `fonts` |
| GTK defaults | `gschema-overrides` |
| OS identity | `os-release` |
| Image signing | `signing` |
| NVIDIA kmod build | `stages` + `script` + `copy` (custom; akmods module can't do CachyOS-LTO) |
| llama.cpp build | `stages` + `script` + `copy` |
| lemurs install | `script` (pinned prebuilt tarball + sha256) |
| Prove-it-works | `script` (files/scripts/verify.sh) |

Custom scripts (the only non-official parts): `build-kmods-nvidia.sh`, `build-llama-cpp.sh`,
`install-kmods-nvidia.sh`, `install-llama-cpp.sh`, `install-lemurs.sh`, `verify.sh`.

## 6. Branding — "Doors — thresholds"

Palette (user-provided, derived):

| Token | Hex | Role |
|---|---|---|
| base | `#171216` | window/terminal bg |
| surface | `#1f171b` | panels, cards |
| surface+ | `#2a2026` | overlays |
| border | `#3a2d33` | hairlines, inactive border |
| text | `#f2ecea` | primary text |
| muted | `#b9a9ac` | secondary text |
| rose | `#f4acb7` | accent: focus, selection, active border |
| blush | `#ffcad4` | hover, subtle highlight |
| peach | `#ffe5d9` | warm secondary (warnings) |
| sage | `#d8e2dc` | cool tertiary (success) |

- Mark: minimal door glyph (SVG), opening + rose light spill. Same glyph all images.
- Type: Inter (UI), JetBrains Mono (mono).
- Identity: `ID=doors`, `PRETTY_NAME="Doors (Kinoite|Hyprland|Cosmic)"`, polkit vendor `Doors`.
- Surfaces: Hyprland colors + lemurs theme, KDE colorscheme + plasmalogin drop-in, COSMIC
  native accent = rose, GTK via gschema + gtk override. Six images identical.

## 7. First-boot / updates

- lemurs presents login on all images (TUI, PAM). Sessions: `/etc/lemurs/wayland/` scripts
  (Hyprland, kwin_wayland, cosmic-session).
- ublue-firstboot stays for user creation (inherited from ublue base).
- Updates: uupd weekly check + notification; user applies via `ujust doors-update`.
  No auto-apply, no auto-reboot. Gaming sessions never interrupted.

## 8. Readiness gate (falsifiable; triggers Ryven deletion)

1. All 6 images build green on weekly + tag runs.
2. cosign verify passes on every GHCR image.
3. All 6 boot to a working session (qemu smoke test minimum).
4. Rebase path tested (unsigned → signed) on a real atomic Fedora install.
5. v1 ujust recipe set present and exercised.
6. Zero "Ryven" strings in the doors repo; Ryven repo + GHCR packages deleted.
7. One immutable `v2026.MM.DD` tag published.

## 9. Known risks / first-build watchlist

- dnf remove of stock kernel in a bootc build (fallback: rpm-ostree module).
- Terra nvidia driver package names (Negativo17 layout) — verify at first build.
- scx_loader.service / falcond.service unit names — verify and adjust `systemd` module.
- pwvucontrol rpm availability — flatpak is the primary channel.
- ROCm build size/time — llama stage is the longest build step on universal images.
- Secure Boot (v2): MOK key generated offline, public `MOK.der` committed, private key in
  `UKI_SIGNING_KEY`; UKI signed with sbsign; kmods signed with CI key. Deferred per D8.
