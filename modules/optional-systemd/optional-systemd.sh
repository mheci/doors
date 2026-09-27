#!/usr/bin/env bash
# systemctl disable fails when the unit file is absent. base-atomic does not
# ship every timer that Silverblue and Kinoite do.
set -euo pipefail

disable_system() {
  local unit="$1"
  if [[ -e "/usr/lib/systemd/system/${unit}" || -e "/etc/systemd/system/${unit}" ]]; then
    systemctl disable "${unit}"
  fi
}

disable_user() {
  local unit="$1"
  if [[ -e "/usr/lib/systemd/user/${unit}" || -e "/etc/systemd/user/${unit}" ]]; then
    systemctl --global disable "${unit}"
  fi
}

disable_system podman-auto-update.timer
disable_user podman-auto-update.timer
printf 'Doors optional-systemd: absent update timers were left untouched.\n'
