# Findings

## Update contract

The image rebuild stays weekly (`cron: 0 3 * * 0` in `.github/workflows/build.yml`).
`doors-update.timer` (Sunday 04:30) and `doors-user-update.timer` (Sunday 04:45)
only check. `bootc upgrade` without `--check`, `flatpak update --noninteractive`,
`mise upgrade`, and the other apply commands run only after someone types `APPLY`
at a terminal. The same pending set produces one notification; a later check
does not repeat it.

Checked managers: bootc, system and user Flatpak, mise, pip, npm, pnpm,
Zed, Gear Lever `--list-updates`, and Homebrew, pipx, uv, cargo, and gem when
those binaries are present. Gear Lever `--fetch-updates` is not used. GNOME
Software and Discover notifier autostart are disabled so they do not add a
second nag.

## User-level AI tooling

Node 24, pnpm, Bun, Deno, OpenCode, Pi, Codex, and Herdr are declared in
`/etc/mise/config.toml`. Zed v1.21.0 is installed per account from
`zed-linux-x86_64.tar.gz` with sha256
`b79a992e960ed4067cb2b50d66789ed8618eeb1780ed6a0f8f1e71dd80f74200`.
A later Zed release is unpacked only by `doors-update apply`, after the GitHub
release digest matches the download. Hermes Agent is not installed. A one-shot
user unit removes a launcher left by an older image and does not delete
`~/.hermes`.

Python, GCC, CMake, and CUDA 13.4 stay in the image. `kernel-cachyos` and the
Negativo17 open module are unchanged. Fedora `kernel-headers` also stays: the
CUDA toolkit cannot install GCC while that userspace package is excluded. It is
not the running kernel. The stock `kernel` packages stay excluded from installs,
but the kernel module removes them with `disable_excludes=*` because that filter
otherwise hides them from `dnf5 remove`. Image builds have SELinux disabled, so
`getsebool` cannot prove `domain_kernel_load_modules`. `setsebool -P` writes the
policy store, and `doors-selinux-module-load.service` applies the boolean before
modules load on a booted system. `akmod-nvidia` %post calls `akmodsbuild`, which
exits when `/var` is writable, and dnf5 aborts on that scriptlet. The NVIDIA
module installs `akmods` first, removes that check, installs `akmod-nvidia`
with `tsflags=noscripts`, and builds the open module itself. Do not delete
`/var/cache/libdnf5`: the builder bind-mounts it, and `rm` fails with
"Device or resource busy" after a successful build. Leave the CUDA repository
disabled after the toolkit install. A later `dnf` module refreshes every enabled
repository, prompts `Is this ok [y/N]` for the CUDA repo key, and fails closed.
Terra 44's `repomd.xml` and `repomd.xml.asc` can disagree; keep `gpgcheck=1`
and set `repo_gpgcheck=0` so an inconsistent metadata signature cannot fail
unrelated image publishes. The published CachyOS kernel is x86-64-v3. The boot
gate's default `qemu64` CPU lacks AVX2, so the kernel resets before printing a
banner and GRUB appears to loop. Boot it with `QEMUCPU=Haswell`. A quiet ostree
serial console then prints dracut and unit status, not `Linux version` or
`systemd[1]:`. Unit names are wrapped in SGR, so match `basic.target` and
`greenboot-success` with a short gap.

## Tiling images

`doors-hyprland` and `doors-sway` use
`ghcr.io/blue-build/base-images/fedora-base-nvidia-open`, not Silverblue or
Kinoite. Hyprland is not in Fedora 44. `eli-xciv/hyprland` has no successful
compositor build. `nett00n/hyprland` publishes `hyprland-0.56.2-17` for
`fedora-44-x86_64`. Vendor that COPR key, keep `gpgcheck=1` and
`repo_gpgcheck=0`, and Explicit `includepkgs` names, not globs: a glob in the repo file was treated
as an exclude and hid `hyprland`. The repo must not replace Fedora
`quickshell` or `waybar`. `kde-connect` pulls `kf6-kio-core`, which makes the
installed `ghostty` require Terra `ghostty-kio`. Re-open Terra for that
transaction. Official Fedora `quickshell` and `ly` stay. Sway and
waybar are official Fedora. Fedora 44 no longer ships `polkit-gnome`; Sway
uses `mate-polkit` at `/usr/libexec/polkit-mate-authentication-agent-1`.
BlueBuild passes a custom module's recipe entry as a JSON string in `$1`,
not as a config file. Fedora's `ly` unit is `ly@.service`. Enable
`ly@tty1.service` and mask `getty@tty1.service`. Do not overwrite
`/etc/ly/config.ini`; sessions come from the wayland-sessions desktop files.

Hyprland 0.56 still loads `hyprland.conf` with a deprecation warning. 0.57
drops it. The shipped session is `hyprland.lua`. `misc.vrr = 2` and per-monitor
`vrr = 2` are fullscreen-only. Do not set `GBM_BACKEND`. Hyprland 0.56.2 commits DPMS only when the `fadeDpms` animation ends. A
static lock screen never produces that frame, so `dpmsStatus` flips while
the panel stays lit. Disable `fadeDpms`, call
`hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'`, and set
`misc.key_press_enables_dpms` and `misc.mouse_move_enables_dpms`. Do not add `wlopm` for this image: the supported 0.56 path is the
dispatcher, and a missing protocol client would just fail the idle
command. The serial boot gate still does not prove the panel powered off. NVIDIA env is
`LIBVA_DRIVER_NAME`, `__GLX_VENDOR_LIBRARY_NAME`, and
`ELECTRON_OZONE_PLATFORM_HINT`. Software cursors stay on.

Firefox, Brave, and gamemode removal stays in the GNOME and Kinoite profiles.
`common.yml` must not `dnf remove` packages that desktop-less base-atomic does
not ship. `podman-auto-update.timer` is disabled only when the unit exists.
