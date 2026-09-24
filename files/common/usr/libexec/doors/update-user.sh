#!/usr/bin/env bash
# Run managed user-space update adapters from a regular user's systemd manager.
# This never executes a discovered AppImage, tarball, copied binary, or a
# user-provided command. Optional package-manager adapters are fixed commands
# selected by name only after the account opts in.
set -uo pipefail

if (( EUID == 0 )); then
  echo 'doors-user-update must run as a regular user, not root' >&2
  exit 1
fi

readonly managed_path='/usr/local/bin:/usr/bin:/bin'
export PATH="${managed_path}"

readonly state_home="${XDG_STATE_HOME:-${HOME}/.local/state}"
readonly config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
readonly report_dir="${state_home}/doors"
readonly report_path="${report_dir}/update-report.tsv"
readonly config_path="${config_home}/doors/update-adapters.conf"
readonly runtime_dir="${XDG_RUNTIME_DIR:-${report_dir}}"
readonly lock_path="${runtime_dir}/doors-user-update.lock"

umask 077
install -d -m 0700 "${report_dir}"
temporary_report="$(mktemp "${report_dir}/update-report.XXXXXX")"

record() {
  local adapter="$1"
  local status="$2"
  printf '%s\t%s\t%s\n' "$(date --utc --iso-8601=seconds)" "${adapter}" "${status}" \
    | tee -a "${temporary_report}"
}

finish() {
  local rc="$1"
  record coordinator "finished-exit-${rc}"
  mv -f "${temporary_report}" "${report_path}"
  exit "${rc}"
}

exec 9>"${lock_path}"
if ! flock -n 9; then
  record coordinator 'skipped-already-running'
  finish 0
fi

failures=0
run_adapter() {
  local name="$1"
  shift
  record "adapter:${name}" 'started'
  if "$@"; then
    record "adapter:${name}" 'succeeded'
    return 0
  fi

  local rc=$?
  record "adapter:${name}" "failed-exit-${rc}"
  failures=1
  return 1
}

skip_adapter() {
  record "adapter:$1" "skipped-$2"
}

canonical_if_allowed() {
  local candidate="$1"
  shift
  local resolved root
  [[ -f "${candidate}" && -x "${candidate}" ]] || return 1
  resolved="$(readlink -f -- "${candidate}")" || return 1
  for root in "$@"; do
    case "${resolved}" in
      "${root}"/*|"${root}")
        printf '%s\n' "${resolved}"
        return 0
        ;;
    esac
  done
  return 1
}

first_managed_binary() {
  local candidate resolved
  while (($#)); do
    candidate="$1"
    shift
    if resolved="$(canonical_if_allowed "${candidate}" \
      /usr/bin /usr/local/bin /usr/lib /usr/lib64 /usr/share \
      "${HOME}/.local" "${HOME}/.cargo" "${HOME}/.linuxbrew" /home/linuxbrew/.linuxbrew)"; then
      printf '%s\n' "${resolved}"
      return 0
    fi
  done
  return 1
}

# Adapter names are deliberately declarative. Users may opt in to one or more
# known package-manager adapters, but cannot inject a command line into this
# service. Invalid lines stay visible in the report instead of being sourced.
declare -A requested=()
if [[ -e "${config_path}" ]]; then
  if [[ ! -f "${config_path}" ]]; then
    record policy 'invalid-adapter-config-not-a-regular-file'
  else
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line%%#*}"
      line="${line//[[:space:]]/}"
      [[ -z "${line}" ]] && continue
      case "${line}" in
        pipx|uv|npm|cargo-install-update|gem)
          requested["${line}"]=1
          ;;
        *)
          record "policy:${line}" 'unsupported-adapter-name'
          ;;
      esac
    done < "${config_path}"
  fi
fi

record coordinator 'started'
record policy 'metadata-free-artifacts-are-never-executed'

if [[ -x /usr/bin/flatpak ]]; then
  if /usr/bin/flatpak --user remotes --columns=name 2>/dev/null | grep -q '[^[:space:]]'; then
    run_adapter flatpak-user /usr/bin/flatpak --user update --noninteractive || true
  else
    skip_adapter flatpak-user 'no-user-remotes'
  fi

  # Gear Lever owns metadata for integrated AppImages. This fixed noninteractive
  # command updates only that managed inventory; --force would overwrite state
  # without a safe review and is intentionally never used.
  if /usr/bin/flatpak info it.mijorus.gearlever >/dev/null 2>&1; then
    run_adapter gearlever-appimages /usr/bin/flatpak run it.mijorus.gearlever --update --all --yes || true
  else
    skip_adapter gearlever-appimages 'gearlever-not-installed-yet'
  fi
else
  record adapter:flatpak-user 'failed-missing-command'
  failures=1
  record adapter:gearlever-appimages 'failed-missing-flatpak'
fi

brew_binary=''
brew_scope=''
for brew_candidate in "${HOME}/.linuxbrew/bin/brew" /home/linuxbrew/.linuxbrew/bin/brew; do
  if brew_binary="$(canonical_if_allowed "${brew_candidate}" "${HOME}/.linuxbrew" /home/linuxbrew/.linuxbrew)"; then
    case "${brew_binary}" in
      "${HOME}/.linuxbrew"/*) brew_scope='per-user' ;;
      /home/linuxbrew/.linuxbrew/*) brew_scope='shared' ;;
    esac
    break
  fi
done
if [[ -n "${brew_binary}" && "${brew_scope}" == 'shared' ]]; then
  if brew_owner_uid="$(stat -c '%u' -- "${brew_binary}")"; then
    if [[ "${brew_owner_uid}" != "${EUID}" ]]; then
      skip_adapter homebrew "shared-installation-owned-by-${brew_owner_uid}"
      brew_binary=''
    fi
  else
    record adapter:homebrew 'failed-determine-shared-installation-owner'
    failures=1
    brew_binary=''
  fi
fi
if [[ -n "${brew_binary}" ]]; then
  if run_adapter homebrew-update "${brew_binary}" update; then
    run_adapter homebrew-upgrade env HOMEBREW_NO_AUTO_UPDATE=1 "${brew_binary}" upgrade || true
  fi
elif [[ -z "${brew_scope}" ]]; then
  skip_adapter homebrew 'not-detected-in-approved-roots'
fi

pipx_binary="$(first_managed_binary /usr/bin/pipx "${HOME}/.local/bin/pipx" || true)"
uv_binary="$(first_managed_binary /usr/bin/uv "${HOME}/.local/bin/uv" || true)"
npm_binary="$(first_managed_binary /usr/bin/npm "${HOME}/.local/bin/npm" || true)"
cargo_update_binary="$(first_managed_binary /usr/bin/cargo-install-update "${HOME}/.cargo/bin/cargo-install-update" || true)"
gem_binary="$(first_managed_binary /usr/bin/gem || true)"

run_opt_in_adapter() {
  local name="$1"
  local binary="$2"
  shift 2
  if [[ -z "${binary}" ]]; then
    if [[ -n "${requested[${name}]:-}" ]]; then
      record "adapter:${name}" 'requested-but-not-detected'
    fi
    return
  fi
  if [[ -z "${requested[${name}]:-}" ]]; then
    record "adapter:${name}" 'available-requires-opt-in'
    return
  fi
  run_adapter "${name}" "${binary}" "$@" || true
}

run_opt_in_adapter pipx "${pipx_binary}" upgrade-all
run_opt_in_adapter uv "${uv_binary}" tool upgrade --all
# npm lifecycle scripts are disabled even after explicit opt-in.
run_opt_in_adapter npm "${npm_binary}" update --global --ignore-scripts
run_opt_in_adapter cargo-install-update "${cargo_update_binary}" -a
run_opt_in_adapter gem "${gem_binary}" update --no-document

# Report—not execute—common locations where copied artifacts tend to accumulate.
# Gear Lever-managed AppImages are handled above; a file found here has no
# automatically trusted update provenance merely because it is executable or a
# recognizable archive. The scan is intentionally shallow and user-visible.
for artifact_dir in "${HOME}/Applications" "${HOME}/AppImages" "${HOME}/Downloads" "${HOME}/bin" "${HOME}/.local/bin"; do
  [[ -d "${artifact_dir}" ]] || continue
  while IFS= read -r -d '' artifact; do
    display="${artifact#"${HOME}"/}"
    display="${display//$'\t'/ }"
    display="${display//$'\n'/ }"
    case "${artifact,,}" in
      *.appimage)
        record "unverified:${display}" 'appimage-not-proven-gearlever-managed'
        ;;
      *.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.zst|*.tzst|*.zip|*.7z)
        record "unsupported:${display}" 'archive-no-update-metadata'
        ;;
      *)
        [[ -x "${artifact}" ]] \
          && record "unsupported:${display}" 'copied-executable-no-update-metadata'
        ;;
    esac
  done < <(find "${artifact_dir}" -maxdepth 1 -type f -print0 2>/dev/null)
done

if (( failures )); then
  finish 1
fi
finish 0
