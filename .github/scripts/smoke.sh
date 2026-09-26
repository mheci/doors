#!/usr/bin/env bash
# In-image smoke checks. Runs INSIDE a freshly built Doors container
# (`podman run --rm -v smoke.sh:/smoke.sh:ro IMAGE bash /smoke.sh`) and fails
# on any missing payload, unit, binary, or policy the recipes promise.
set -uo pipefail
status=0
ok() { printf 'ok   %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*" >&2; status=1; }
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then ok "${desc}"; else fail "${desc}"; fi; }

# --- packages -----------------------------------------------------------------
for pkg in gh git just jq python3-ruamel-yaml mise bootc greenboot libnotify \
  cuda-toolkit-13-4 cuda-nvcc-13-4 helium-bin brave-origin steam kitty neovim; do
  check "rpm ${pkg}" rpm -q "${pkg}"
done
check 'rpm kernel-headers' rpm -q kernel-headers
for absent in firefox firefox-langpacks brave-browser kernel kernel-core kernel-devel \
  nodejs24 nodejs24-npm pnpm bun-bin deno zed; do
  if rpm -q "${absent}" >/dev/null 2>&1; then fail "rpm ${absent} should be removed"; else ok "rpm ${absent} absent"; fi
done
for pkg in kernel-cachyos kernel-cachyos-core kernel-cachyos-modules kernel-cachyos-devel kernel-cachyos-devel-matched; do
  check "rpm ${pkg}" rpm -q "${pkg}"
done
kver="$(rpm -q kernel-cachyos-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}' 2>/dev/null || true)"
if [[ -n "${kver}" && -d "/usr/src/kernels/${kver}" ]]; then
  ok "cachyos headers ${kver}"
else
  fail "cachyos headers ${kver:-missing}"
fi
nvidia_module=''
for candidate in \
  "/usr/lib/modules/${kver}/extra/nvidia/nvidia.ko.xz" \
  "/usr/lib/modules/${kver}/extra/nvidia/nvidia.ko.zst" \
  "/usr/lib/modules/${kver}/extra/nvidia/nvidia.ko.gz" \
  "/usr/lib/modules/${kver}/extra/nvidia/nvidia.ko"; do
  if [[ -s "${candidate}" ]]; then nvidia_module="${candidate}"; break; fi
done
if [[ -n "${nvidia_module}" ]]; then ok "nvidia module ${nvidia_module}"; else fail "nvidia module for ${kver:-missing}"; fi
if rpm -qa | grep -Eq '^kernel-cachyos-(lts|rt|server|nvidia-open)-'; then
  fail 'unexpected cachyos kernel variant installed'
else
  ok 'only the desktop cachyos kernel is installed'
fi

# --- Doors payload ----------------------------------------------------------------
for bin in doors-recipe doors-ai doors-image doors-dns doors-secureboot doors-desktop-cleanup doors-luks-enroll doors-update; do
  check "bin ${bin}" test -x "/usr/bin/${bin}"
done
for helper in hermes-install.sh zed-install.sh update-user.sh update-system.sh; do
  check "libexec ${helper}" test -x "/usr/libexec/doors/${helper}"
done
check 'agent skill shipped' test -s /usr/share/doors/agent/skills/doors-recipe/SKILL.md
check 'doors-recipe imports' python3 -c 'import ruamel.yaml, tomllib'
check 'doors-recipe schema' /usr/bin/doors-recipe --json schema
check 'mise policy parses' python3 -c 'import tomllib; tomllib.load(open("/etc/mise/config.toml","rb"))'
check 'environment.d PATH' grep -q '.local/bin' /etc/environment.d/90-doors-mise.conf
if grep -rqs 't3' /etc/mise/config.toml; then fail 't3 still declared'; else ok 't3 removed'; fi
for tool in node pnpm bun deno opencode pi codex herdr; do
  if grep -Eq "^${tool} = " /etc/mise/config.toml; then ok "mise declares ${tool}"; else fail "mise missing ${tool}"; fi
done
if grep -q 'b79a992e960ed4067cb2b50d66789ed8618eeb1780ed6a0f8f1e71dd80f74200' /usr/libexec/doors/zed-install.sh; then
  ok 'zed installer pin'
else
  fail 'zed installer pin'
fi
check 'doors-update status' /usr/bin/doors-update

# --- systemd defaults ---------------------------------------------------------------
for unit in doors-hermes-install.service doors-mise-install.service doors-zed-install.service \
  doors-user-update.timer doors-update-notify.service; do
  check "user unit ${unit} present" test -f "/usr/lib/systemd/user/${unit}"
  check "user unit ${unit} enabled" systemctl --global --root=/ is-enabled "${unit}"
done
check 'system unit doors-update.timer enabled' systemctl --root=/ is-enabled doors-update.timer
if systemctl --root=/ is-enabled flatpak-system-updates.timer >/dev/null 2>&1; then
  fail 'flatpak-system-updates.timer should be disabled'
else
  ok 'flatpak-system-updates.timer disabled'
fi
if grep -q 'OnUnitActiveSec=1h' /usr/lib/systemd/user/doors-user-update.timer \
  || [[ -f /etc/systemd/system/flatpak-system-updates.timer.d/90-doors-hourly.conf ]]; then
  fail 'hourly update schedule still present'
else
  ok 'no hourly update schedule'
fi
check 'unit syntax' systemd-analyze verify --recursive-errors=no \
  /usr/lib/systemd/user/doors-hermes-install.service /usr/lib/systemd/user/doors-user-update.service

# --- signature policy ---------------------------------------------------------------
check 'policy.json trusts doors' grep -q 'ghcr.io/mheci/doors"' /etc/containers/policy.json
check 'policy.json trusts doors-kinoite' grep -q 'ghcr.io/mheci/doors-kinoite' /etc/containers/policy.json
if grep -q 'doors-cosmic' /etc/containers/policy.json; then fail 'policy.json still lists doors-cosmic'; else ok 'no cosmic policy'; fi
check 'shared cosign key' test -s /etc/pki/containers/doors-shared.pub

# --- desktop-specific ------------------------------------------------------------------
if rpm -q gnome-shell >/dev/null 2>&1; then
  check 'gnome: extensions dir' test -d /usr/share/gnome-shell/extensions
elif rpm -q plasma-desktop >/dev/null 2>&1; then
  check 'kinoite: breeze-gtk' rpm -q breeze-gtk
else
  fail 'neither GNOME nor Plasma is installed'
fi

if (( status == 0 )); then echo 'smoke: all checks passed'; else echo 'smoke: FAILED' >&2; fi
exit "${status}"
