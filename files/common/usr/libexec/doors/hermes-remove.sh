#!/usr/bin/env bash
# Remove a Hermes Agent install from this account. The image no longer
# installs or updates it. ~/.hermes is left in place so history and
# credentials are not deleted without an explicit request.
set -euo pipefail

if (( EUID == 0 )); then
  echo 'doors-hermes-remove must run as a regular user, not root' >&2
  exit 1
fi

readonly state_home="${XDG_STATE_HOME:-${HOME}/.local/state}"
readonly stamp="${state_home}/doors/hermes-removed"
readonly apps="${XDG_DATA_HOME:-${HOME}/.local/share}/applications"
readonly user_units="${HOME}/.config/systemd/user"

log() { printf 'doors-hermes-remove: %s\n' "$*"; }

[[ -f "${stamp}" ]] && { log 'already removed'; exit 0; }

rm -f -- "${HOME}/.local/bin/hermes"
rm -f -- "${state_home}/doors/hermes-installed"
rm -rf -- "${HOME}/.hermes/skills/doors-recipe"

if [[ -d "${apps}" ]]; then
  while IFS= read -r -d '' entry; do
    rm -f -- "${entry}"
    log "removed $(basename "${entry}")"
  done < <(find "${apps}" -maxdepth 1 -type f -iname '*hermes*.desktop' -print0)
fi

if [[ -d "${user_units}" ]]; then
  while IFS= read -r -d '' unit; do
    name="$(basename "${unit}")"
    systemctl --user disable --now "${name}" >/dev/null 2>&1 || true
    rm -f -- "${unit}"
    log "removed ${name}"
  done < <(find "${user_units}" -type f -iname '*hermes*' -print0)
fi

if command -v pkill >/dev/null 2>&1; then
  pkill -x hermes >/dev/null 2>&1 || true
fi

install -d -m 0700 "$(dirname "${stamp}")"
date --utc --iso-8601=seconds > "${stamp}"
log 'launcher and desktop entry removed'
