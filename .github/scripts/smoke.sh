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
for pkg in gh git just jq python3-ruamel-yaml mise bun-bin deno bootc greenboot \
  cuda-toolkit-13-4 cuda-nvcc-13-4 brave-browser; do
  check "rpm ${pkg}" rpm -q "${pkg}"
done
for absent in firefox firefox-langpacks; do
  if rpm -q "${absent}" >/dev/null 2>&1; then fail "rpm ${absent} should be removed"; else ok "rpm ${absent} absent"; fi
done

# --- Doors payload ----------------------------------------------------------------
for bin in doors-recipe doors-ai doors-image doors-dns doors-secureboot doors-desktop-cleanup doors-luks-enroll; do
  check "bin ${bin}" test -x "/usr/bin/${bin}"
done
for helper in hermes-install.sh update-user.sh; do
  check "libexec ${helper}" test -x "/usr/libexec/doors/${helper}"
done
check 'agent skill shipped' test -s /usr/share/doors/agent/skills/doors-recipe/SKILL.md
check 'doors-recipe imports' python3 -c 'import ruamel.yaml, tomllib'
check 'doors-recipe schema' /usr/bin/doors-recipe --json schema
check 'mise policy parses' python3 -c 'import tomllib; tomllib.load(open("/etc/mise/config.toml","rb"))'
check 'environment.d PATH' grep -q '.local/bin' /etc/environment.d/90-doors-mise.conf
if grep -rqs 't3' /etc/mise/config.toml; then fail 't3 still declared'; else ok 't3 removed'; fi

# --- systemd defaults ---------------------------------------------------------------
for unit in doors-hermes-install.service doors-mise-install.service doors-user-update.timer; do
  check "user unit ${unit} present" test -f "/usr/lib/systemd/user/${unit}"
  check "user unit ${unit} enabled" systemctl --global --root=/ is-enabled "${unit}"
done
for unit in doors-update.timer flatpak-system-updates.timer; do
  check "system unit ${unit} enabled" systemctl --root=/ is-enabled "${unit}"
done
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
