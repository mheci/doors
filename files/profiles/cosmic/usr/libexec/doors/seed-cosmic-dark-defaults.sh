#!/usr/bin/env bash
# Seed a first-run COSMIC preference without overwriting a user's later choice.
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
target="${config_home}/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"
[[ -e "${target}" ]] && exit 0

install -d -m 0700 "$(dirname "${target}")"
temporary="$(mktemp "${target}.XXXXXX")"
trap 'rm -f "${temporary}"' EXIT
printf '%s\n' true > "${temporary}"
chmod 0600 "${temporary}"

# A hard-link creation is atomic and fails when another process (or the user)
# wrote the preference first. Never replace an existing preference; fail loudly
# if the target is still absent so an unexpected filesystem error is visible.
if ! ln "${temporary}" "${target}" 2>/dev/null; then
  [[ -e "${target}" ]] && exit 0
  echo "cannot seed COSMIC dark preference: ${target}" >&2
  exit 1
fi
rm -f "${temporary}"
trap - EXIT
