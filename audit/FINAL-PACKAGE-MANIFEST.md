# Doors — final package/service manifest

**Status:** implemented repository contract. This manifest records the approved
configuration now represented by `recipes/doors.yml` and its supporting
scripts/workflows. It is not evidence that an image has composed, published,
or passed hardware validation: the documented upstream Bluefin/akmods ABI gate
and the mandatory physical test plan remain release blockers.

**Freshness rule:** every Monday 00:00 UTC build resolves the newest successfully verified version available from the approved source. RPMs resolve from their signed repositories at build time; official GNOME Extensions resolve to the newest compatible GNOME release; custom external artifacts must pass their verification gate. A failed verification fails the build rather than publishing an older/unverified substitute.

## Image foundation

- `ghcr.io/ublue-os/bluefin:latest`, AMD64, generic Bluefin GNOME.
- Official BlueBuild `akmods` module with `base: main` and `nvidia-driver: nvidia-open`.
- Stock Bluefin/Fedora kernel only; no custom kernel or manual NVIDIA module build.
- GNOME/GDM only. No Lemurs, KDE, COSMIC, Hyprland, or alternate display/session manager.
- Automatic update staging with manual reboot only; no unattended reboot.

## Repositories and trust boundaries

| Source | Scope in image | Trust configuration |
|---|---|---|
| Fedora | Default source for packages available there | Native signed Fedora metadata/packages. |
| RPM Fusion nonfree | Steam and allowed multimedia/gaming dependencies | Official BlueBuild module; signed packages. |
| Terra 44 main | Gaming, performance, developer tools, Zen/Vicinae/extensions | Local reviewed key; `gpgcheck=1`, `repo_gpgcheck=1`, `skip_if_unavailable=False`. |
| Brave official RPM | Brave Origin only | Local reviewed keys; package **and metadata** signature checks enabled. Its required keyring dependency is constrained to Origin and stripped of unrelated beta/nightly key material after compose. |
| Faugus COPR | Faugus only | Project-maintained COPR; static key and RPM signatures. COPR metadata is not signed. |
| Helium COPR | Helium only | Official upstream-documented `imput/helium` COPR; static key and RPM signatures. COPR metadata is not signed. |
| GNOME Extensions | Clipboard Indicator, Alphabetical App Grid, Emoji Copy | Official BlueBuild module, latest compatible official GNOME Extensions release. |
| Bun upstream | Bun only | Vended Robobun key; PGP-verified release checksum. |
| Herdr upstream | Herdr only | Latest immutable GitHub release asset accepted only after its SHA-256 plus `gh release verify-asset` immutable-release attestation verification. |
| Official upstream Git/Cargo | wl-clip-persist only | Official Cargo build route from the latest upstream release commit using its lockfile; no Fedora/Terra RPM or upstream binary exists. |
| npm registry | Pi coding agent only | Official `@earendil-works/pi-coding-agent` package-manager route with npm registry integrity verification. Terra's unrelated `pi` package was solver-incompatible and is explicitly not used. |

## Core gaming and performance

| Package/component | Source | State |
|---|---|---|
| Steam | RPM Fusion | Installed. |
| Heroic, ProtonPlus, umu-launcher, Vesktop | Terra | Installed. |
| Faugus | Faugus COPR | Installed. |
| Gamescope | Fedora | Installed. |
| Falcond + profiles | Terra | Installed; `falcond.service` enabled. |
| Ananicy-cpp + CachyOS Ananicy rules | Terra | Installed; `ananicy-cpp.service` enabled. |
| scx-scheds + scx-tools | Terra | Installed; `scx_loader.service` enabled. The loader config starts `scx_lavd` in `LowLatency` mode at boot. |
| GameMode | — | Explicitly removed/blocked because it conflicts with Falcond. |

## Browsers

- **Brave Origin stable:** official Brave signed RPM, not ordinary Brave; physical GNOME/Wayland/NVIDIA validation gate required.
- **Zen Browser:** signed Terra package.
- **Helium:** official upstream Helium COPR package (`helium-bin`).
- **Firefox and ordinary Brave:** removed/not installed.

## Developer, terminal, and application tooling

### Fedora-first baseline

`nodejs`, `npm`, `pnpm`, `neovim`, `kitty`, `git`, `git-lfs`, `gh`, `just`, `jq`, `yq`, `curl`, `wget`, `distrobox`, `eza`, `bat`, `ripgrep`, `fd-find`, `fzf`, `zoxide`, `htop`, `btop`, `nvtop`, `starship`, `lazygit`, `direnv`, `mpv`, `p7zip`, `unar`, `unzip`, `xz`, `zstd`, `grim`, `slurp`, `swappy`, `wf-recorder`, `cliphist`, `wl-clipboard`, and GNOME desktop/device/printer integration packages where Bluefin does not already provide them.

### Terra baseline

`deno`, `mise`, `t3code`, `opencode`, `ghostty`, `zed`, `vicinae`, `gnome-shell-extension-vicinae`, and `gnome-shell-extension-grand-theft-focus`.

### Verified package-manager/binary routes

- **Bun:** latest upstream release with PGP-verified checksum.
- **Herdr:** latest upstream release after SHA-256 and GitHub attestation verification.
- **Pi coding agent:** freshest successful official npm package-manager install of `@earendil-works/pi-coding-agent`, using npm registry integrity data. The Terra package named `pi` is not the coding agent and fails the Fedora solver; it is excluded.
- **wl-clip-persist:** freshest successful official Cargo build from the upstream latest-release commit, using its upstream lockfile.

### Explicit exclusions/deferments

- Hermes Agent: removed.
- CUDA and llama.cpp: deferred; no CUDA RPM repository, Conda environment, or source-built llama.cpp.
- Playwright: excluded.

## GNOME desktop defaults

- Yaru dark GTK/icon/sound styling; compact, always-visible, left Dash-to-Dock.
- Inter UI/default document font; JetBrains Mono default monospace/terminal font.
- Install all requested safe font/theme choices: Inter, JetBrains Mono, Fira Code, Cascadia Code, Roboto, Noto Sans CJK, Noto Emoji; Yaru, Adwaita GTK3, Papirus, Numix GTK/icons, and Breeze icons.
- No forced wallpaper; no Doors artwork/desktop branding; no Ubuntu wallpaper.
- System-install and enable for new users:
  - Dash-to-Dock;
  - AppIndicator and KStatusNotifierItem Support;
  - GSConnect;
  - Clipboard Indicator;
  - Grand Theft Focus;
  - Just Perfection;
  - Alphabetical App Grid;
  - Vicinae GNOME extension;
  - Emoji Copy.
- Vicinae user daemon enabled globally at graphical login; `uinput` support retained; default hotkey **Super+Shift+Space**.
- Vicinae, Clipboard Indicator, and `wl-clip-persist` all monitor the regular clipboard as explicitly requested. `wl-clip-persist` runs unfiltered for the regular clipboard only, not the primary selection.

## Flatpak policy

- Keep Flatpak capability and Flathub for deliberate manual use.
- Preinstall only `io.github.kolunmi.Bazaar` plus exactly its required runtime(s).
- Do not provision Flatseal, pwvucontrol, or any other Flatpak application/runtime.

## Removal / hygiene

- Delete legacy multi-image recipes, custom CachyOS kernel code, custom driver/kmod logic, direct unverified installers, `--nogpgcheck`, `--nodeps`, and `--noscripts` workaround paths.
- Remove Firefox, ordinary Brave, Flatseal/pwvucontrol provisioning, Lemurs, and legacy KDE/COSMIC/Hyprland configuration.
- Do not use `skip-unavailable`, `skip-broken`, or GPG-check bypasses in the release image.

## Release and repository controls

- Public `ghcr.io/mheci/doors:latest`; Monday 00:00 UTC scheduled release; no ISO artifacts.
- Retain the existing Cosign key required by BlueBuild (`SIGNING_SECRET`); add GitHub OIDC provenance/SBOM attestations.
- Protected `main`: pull request + required CI; block force-push/deletion and unsafe direct production publishes; tuned for solo, agent-assisted maintenance.
- Renovate: maximize automated upkeep, but auto-merge only an explicit allowlist of low-risk patch/digest updates after required checks. Workflows, build chain, keys, repositories, major updates, and security-policy changes remain review-gated.

## Mandatory physical validation gate before declaring release ready

Test the produced image on Turing-or-newer NVIDIA hardware using GNOME/Wayland: driver load, suspend/resume, Steam/Gamescope/Heroic/Faugus, performance services and `scx_lavd`, browser launch/media/WebGL for Brave Origin/Zen/Helium, clipboard behavior, Vicinae, GSConnect, Flatpak/Bazaar, update staging/manual reboot, and no unwanted service/network listener.
