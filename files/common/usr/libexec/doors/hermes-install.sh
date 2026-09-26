#!/usr/bin/env bash
# Install or repair Hermes Agent (CLI + desktop app) for the calling account
# through the upstream Tier-1 Linux path. Nothing is baked into the image:
# the source checkout, its uv-managed Python, Node, and the Electron desktop
# build all live under ~/.hermes and follow Hermes' own stable release channel.
#
# Idempotent: a finished install returns quickly. Interrupted or stale installs
# are completed by re-running the same installer, which is upstream's documented
# repair path. Unattended: no prompts, no setup wizard, no gateway autostart.
set -uo pipefail

if (( EUID == 0 )); then
  echo 'doors-hermes-install must run as a regular user, not root' >&2
  exit 1
fi

readonly installer_url='https://hermes-agent.nousresearch.com/install.sh'
readonly hermes_home="${HERMES_HOME:-${HOME}/.hermes}"
readonly launcher="${HOME}/.local/bin/hermes"
readonly skill_source='/usr/share/doors/agent/skills'
readonly skill_target="${hermes_home}/skills"
readonly state_home="${XDG_STATE_HOME:-${HOME}/.local/state}"
readonly stamp="${state_home}/doors/hermes-installed"

export PATH="/usr/local/bin:/usr/bin:/bin:${HOME}/.local/bin"
# Installer output streams in full when CI is set; keep journal logs readable.
export CI=1 NO_COLOR=1

log() { printf 'doors-hermes-install: %s\n' "$*"; }

install_skills() {
  # Ship the Doors agent skills into the account's Hermes skill directory so
  # the agent can drive doors-recipe/doors-image without extra setup.
  local skill
  [[ -d "${skill_source}" ]] || return 0
  install -d -m 0700 "${skill_target}"
  for skill in "${skill_source}"/*/; do
    [[ -d "${skill}" ]] || continue
    rm -rf -- "${skill_target:?}/$(basename "${skill}")"
    cp -R -- "${skill}" "${skill_target}/"
  done
}

if [[ -x "${launcher}" && -f "${stamp}" ]]; then
  install_skills
  log 'already installed'
  exit 0
fi

command -v git >/dev/null || { log 'git is missing from the image'; exit 1; }
command -v curl >/dev/null || { log 'curl is missing from the image'; exit 1; }

log "running the upstream installer (${installer_url})"
installer="$(mktemp --tmpdir doors-hermes-install.XXXXXX.sh)"
trap 'rm -f -- "${installer}"' EXIT
if ! curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  --retry 5 --retry-delay 15 --output "${installer}" "${installer_url}"; then
  log 'download failed; will retry on the next login or hourly update'
  exit 1
fi

# --non-interactive skips the setup wizard and gateway install;
# --include-desktop builds the Electron desktop app for this account.
if ! bash "${installer}" --non-interactive --include-desktop; then
  log 'installer failed; see ~/.hermes/logs/install.log'
  exit 1
fi
[[ -x "${launcher}" ]] || { log "installer finished but ${launcher} is missing"; exit 1; }

# Follow published stable releases instead of the main branch tip, so the
# hourly update rebuilds the desktop app only when a release lands.
"${launcher}" update --yes --set-channel stable --no-backup >/dev/null 2>&1 \
  || log 'could not pin the stable channel yet; the hourly update retries'

# Register the XDG desktop entry without launching a window.
"${launcher}" desktop --build-only >/dev/null 2>&1 \
  || log 'desktop entry registration deferred to the first launch'

install_skills
install -d -m 0700 "$(dirname "${stamp}")"
date --utc --iso-8601=seconds > "${stamp}"
log "installed $("${launcher}" --version 2>/dev/null | head -1)"
