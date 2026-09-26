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
otherwise hides them from `dnf5 remove`.
