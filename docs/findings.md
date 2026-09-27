# Findings

## Update contract

The image rebuild stays weekly (`cron: 0 3 * * 0` in `.github/workflows/build.yml`).
`doors-update.timer` (Sunday 04:30) and `doors-user-update.timer` (Sunday 04:45)
only check. `bootc upgrade` without `--check`, `flatpak update --noninteractive`,
`mise upgrade`, and the other apply commands run only after someone types `APPLY`
at a terminal. The same pending set produces one notification; a later check
does not repeat it.

Checked managers: bootc, system and user Flatpak, mise, pip, npm, pnpm, Hermes,
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
release digest matches the download. Hermes remains pinned to tag `v2026.9.24`
(`f97608f`) and bootstrap sha256
`b6d77a3491ab1d8e842071a8d92f76ae118836479b1ac69436e00f85f541d5a1`.

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
`systemd[1]:`. Match those status lines.
