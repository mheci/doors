#!/usr/bin/env bash
# Provision the two explicitly approved system Flatpaks after the first
# networked boot. Static Flathub configuration supplies the reviewed key;
# completion is recorded only after both application transactions succeed.
set -euo pipefail

readonly state_dir='/var/lib/doors'
readonly completion_marker="${state_dir}/flatpaks-provisioned"
readonly remote='flathub'
readonly -a app_ids=(
  'io.github.kolunmi.Bazaar'
  'com.ranfdev.DistroShelf'
)

[[ -e "${completion_marker}" ]] && exit 0
install -d -m 0755 "${state_dir}"

# Resolve each explicit app from the one reviewed remote before changing the
# system installation. Dependencies are limited to Flatpak-declared runtimes.
for app_id in "${app_ids[@]}"; do
  /usr/bin/flatpak --system remote-info "${remote}" "${app_id}" >/dev/null
done
/usr/bin/flatpak --system install --noninteractive --or-update "${remote}" "${app_ids[@]}"
touch "${completion_marker}"
