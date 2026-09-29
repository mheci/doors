#!/usr/bin/env bash
# Prove the weekly checker does not install anything, and that apply refuses
# to run without a terminal.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
updater="${root}/files/common/usr/bin/doors-update"
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp}"' EXIT

mkdir -p "${tmp}/bin" "${tmp}/home/.local/bin" "${tmp}/runtime" "${tmp}/usr/bin"
trace="${tmp}/trace"
notify_log="${tmp}/notify.log"
: > "${trace}"

cat > "${tmp}/usr/bin/flatpak" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOORS_UPDATE_TRACE}"
if [[ "$*" == *'--noninteractive'* || "$*" == *'--update'* ]]; then
  printf 'flatpak applied: %s\n' "$*" >> "${DOORS_UPDATE_TRACE}.forbidden"
  exit 99
fi
if [[ "$1" == info ]]; then
  exit 1
fi
if [[ "$*" == *remotes* ]]; then
  exit 0
fi
exit 0
EOF

cat > "${tmp}/usr/bin/mise" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOORS_UPDATE_TRACE}"
if [[ "$1" == upgrade || "$1" == install ]]; then
  printf 'mise applied: %s\n' "$*" >> "${DOORS_UPDATE_TRACE}.forbidden"
  exit 99
fi
if [[ "$1" == outdated && "$2" == --json ]]; then
  printf '%s\n' '[{"name":"node","current":"24.1.0","latest":"24.11.0"}]'
  exit 0
fi
exit 0
EOF

mkdir -p "${tmp}/etc/mise"
printf '%s\n' '[tools]' 'node = "24"' > "${tmp}/etc/mise/config.toml"

cat > "${tmp}/usr/bin/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOORS_UPDATE_TRACE}"
if [[ "$1" == update ]]; then
  printf 'npm applied: %s\n' "$*" >> "${DOORS_UPDATE_TRACE}.forbidden"
  exit 99
fi
printf '%s\n' '{}'
exit 0
EOF

cat > "${tmp}/usr/bin/pip3" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOORS_UPDATE_TRACE}"
if [[ "$1" == install ]]; then
  printf 'pip applied: %s\n' "$*" >> "${DOORS_UPDATE_TRACE}.forbidden"
  exit 99
fi
printf '%s\n' '[]'
exit 0
EOF

cat > "${tmp}/usr/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify\n' >> "${DOORS_NOTIFY_LOG}"
exit 0
EOF

chmod 0755 "${tmp}/usr/bin/"*

export HOME="${tmp}/home"
export XDG_STATE_HOME="${tmp}/home/.local/state"
export XDG_RUNTIME_DIR="${tmp}/runtime"
export DOORS_UPDATE_TEST_ROOT="${tmp}"
export DOORS_UPDATE_TRACE="${trace}"
export DOORS_NOTIFY_LOG="${notify_log}"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${tmp}/runtime/bus"
export PATH="${tmp}/usr/bin:/usr/bin:/bin"

if "${updater}" apply </dev/null >"${tmp}/apply.out" 2>"${tmp}/apply.err"; then
  printf 'FAIL apply without a terminal succeeded\n' >&2
  exit 1
fi
if [[ -s "${DOORS_UPDATE_TRACE}.forbidden" ]]; then
  printf 'FAIL apply invoked an installer\n' >&2
  cat "${DOORS_UPDATE_TRACE}.forbidden" >&2
  exit 1
fi

: > "${trace}"
"${updater}" check --scope user --quiet
if [[ -s "${DOORS_UPDATE_TRACE}.forbidden" ]]; then
  printf 'FAIL check invoked an installer\n' >&2
  cat "${DOORS_UPDATE_TRACE}.forbidden" >&2
  exit 1
fi
if ! grep -q 'node  24.1.0 -> 24.11.0' "${XDG_STATE_HOME}/doors/summary.txt"; then
  printf 'FAIL check did not record the mise update\n' >&2
  cat "${XDG_STATE_HOME}/doors/summary.txt" >&2
  exit 1
fi
if grep -q 'hermes' "${XDG_STATE_HOME}/doors/summary.txt"; then
  printf 'FAIL check still recorded Hermes\n' >&2
  exit 1
fi
notify_count="$(wc -l < "${notify_log}")"
if [[ "${notify_count}" -ne 1 ]]; then
  printf 'FAIL expected one notification, got %s\n' "${notify_count}" >&2
  exit 1
fi

"${updater}" check --scope user --quiet
notify_count="$(wc -l < "${notify_log}")"
if [[ "${notify_count}" -ne 1 ]]; then
  printf 'FAIL repeated check notified again (%s)\n' "${notify_count}" >&2
  exit 1
fi

if grep -Eq 'uupd|noninteractive|mise upgrade' \
  "${root}/files/common/usr/libexec/doors/update-system.sh" \
  "${root}/files/common/usr/libexec/doors/update-user.sh"; then
  printf 'FAIL scheduled wrappers still apply updates\n' >&2
  exit 1
fi

printf 'doors-update contract passed\n'
