#!/usr/bin/env bash
# Coordinate managed host and per-account updates without treating arbitrary
# user files as executable updaters. User-owned work runs through each user's
# systemd manager, never as root.
set -uo pipefail

readonly managed_path='/usr/sbin:/usr/bin:/sbin:/bin'
export PATH="${managed_path}"

readonly lock_file='/run/doors-update.lock'
readonly state_dir='/var/lib/doors/updates'
readonly uid_min_default=1000
readonly uid_max_default=60000

install -d -m 0755 "${state_dir}"
report="${state_dir}/$(date --utc +%Y%m%dT%H%M%SZ)-$$-system.tsv"
touch "${report}"

record() {
  local scope="$1"
  local status="$2"
  printf '%s\t%s\t%s\n' "$(date --utc --iso-8601=seconds)" "${scope}" "${status}" \
    | tee -a "${report}"
}

finish() {
  local rc="$1"
  record coordinator "finished-exit-${rc}"
  ln -sfn "$(basename "${report}")" "${state_dir}/latest.tsv"
  exit "${rc}"
}

exec 9>"${lock_file}"
if ! flock -n 9; then
  # Preserve latest.tsv for the active transaction; this small report remains
  # as explicit evidence that a concurrent trigger was intentionally skipped.
  record coordinator 'skipped-already-running'
  exit 0
fi

failures=0
run_adapter() {
  local name="$1"
  shift
  record "system:${name}" 'started'
  if "$@"; then
    record "system:${name}" 'succeeded'
    return 0
  fi

  local rc=$?
  record "system:${name}" "failed-exit-${rc}"
  failures=1
  return 0
}

skip_adapter() {
  record "system:$1" "skipped-$2"
}

login_defs_value() {
  local key="$1"
  local fallback="$2"
  local value
  value="$(awk -v key="${key}" '$1 == key { print $2; exit }' /etc/login.defs 2>/dev/null || true)"
  [[ "${value}" =~ ^[0-9]+$ ]] && printf '%s\n' "${value}" || printf '%s\n' "${fallback}"
}

regular_local_users() {
  local uid_min uid_max
  uid_min="$(login_defs_value UID_MIN "${uid_min_default}")"
  uid_max="$(login_defs_value UID_MAX "${uid_max_default}")"

  # /etc/passwd intentionally limits this sweep to local accounts. Remote
  # identity-provider entries must not cause a host timer to create lingering
  # managers or run package tools on a network identity.
  awk -F: -v min="${uid_min}" -v max="${uid_max}" '
    $3 >= min && $3 <= max && $1 != "nobody" { print $1 ":" $3 ":" $6 ":" $7 }
  ' /etc/passwd
}

run_user_manager_update() {
  local user="$1"
  local uid="$2"
  local home="$3"
  local shell="$4"
  local bus="/run/user/${uid}/bus"

  case "${shell}" in
    */nologin|*/false|'')
      record "user:${user}" 'skipped-noninteractive-account'
      return
      ;;
  esac
  if [[ ! -d "${home}" ]]; then
    record "user:${user}" 'skipped-missing-home'
    return
  fi

  if ! loginctl enable-linger "${user}"; then
    record "user:${user}" 'failed-enable-linger'
    failures=1
    return
  fi
  if ! systemctl start "user@${uid}.service"; then
    record "user:${user}" 'failed-start-user-manager'
    failures=1
    return
  fi

  local attempt
  for ((attempt = 0; attempt < 20; ++attempt)); do
    [[ -S "${bus}" ]] && break
    sleep 1
  done
  if [[ ! -S "${bus}" ]]; then
    record "user:${user}" 'failed-user-bus-unavailable'
    failures=1
    return
  fi

  record "user:${user}" 'started'
  if runuser -u "${user}" -- env \
    HOME="${home}" \
    USER="${user}" \
    LOGNAME="${user}" \
    XDG_RUNTIME_DIR="/run/user/${uid}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=${bus}" \
    /usr/bin/systemctl --user start --wait doors-user-update.service; then
    record "user:${user}" 'succeeded'
  else
    local rc=$?
    record "user:${user}" "failed-exit-${rc}"
    failures=1
  fi
}

record coordinator 'started'

# uupd remains the trusted bootc/rpm-ostree engine, constrained to the immutable
# host module. Flatpaks, Distroboxes, Homebrew, containers, and AppImages are
# handled below in their correct ownership scope.
if [[ -x /usr/bin/uupd ]]; then
  run_adapter uupd-system /usr/bin/uupd \
    --disable-module-brew \
    --disable-module-distrobox \
    --disable-module-flatpak \
    --log-level=debug \
    --json
else
  record system:uupd-system 'failed-missing-command'
  failures=1
fi

if [[ -x /usr/bin/flatpak ]]; then
  if /usr/bin/flatpak --system remotes --columns=name 2>/dev/null | grep -q '[^[:space:]]'; then
    run_adapter flatpak-system /usr/bin/flatpak --system update --noninteractive
  else
    skip_adapter flatpak-system 'no-system-remotes'
  fi
else
  record system:flatpak-system 'failed-missing-command'
  failures=1
fi

if [[ -x /usr/bin/distrobox-upgrade ]]; then
  run_adapter distrobox-root /usr/bin/distrobox-upgrade --all --root --yes
else
  skip_adapter distrobox-root 'missing-command'
fi

if [[ -x /usr/bin/podman ]]; then
  # Podman only recreates containers carrying its explicit auto-update label.
  run_adapter podman-root-auto-update /usr/bin/podman auto-update
  if root_containers="$(/usr/bin/podman ps --all --format '{{.Names}}|{{.Label "io.containers.autoupdate"}}|{{.Label "manager"}}|{{.Label "distrobox.version"}}')"; then
    while IFS='|' read -r container_name auto_update_policy manager distrobox_version; do
      [[ -n "${container_name}" ]] || continue
      container_name="${container_name//$'\t'/ }"
      container_name="${container_name//$'\n'/ }"
      if [[ -n "${auto_update_policy}" ]]; then
        continue
      elif [[ "${manager}" == 'distrobox' || -n "${distrobox_version}" ]]; then
        record "managed:root-container:${container_name}" 'updated-by-distrobox-adapter'
      else
        record "unsupported:root-container:${container_name}" 'unlabelled-container-not-auto-updated'
      fi
    done <<< "${root_containers}"
  else
    record system:podman-root-inventory 'failed-list-containers'
    failures=1
  fi
else
  skip_adapter podman-root-auto-update 'missing-command'
fi

while IFS=: read -r user uid home shell; do
  run_user_manager_update "${user}" "${uid}" "${home}" "${shell}"
done < <(regular_local_users)

if (( failures )); then
  finish 1
fi
finish 0
