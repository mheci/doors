#!/usr/bin/env bash
# falcond provides gamemode and conflicts with the package already installed on
# the NVIDIA bases. cachyos-settings conflicts with zram-generator-defaults and
# provides that name. Remove either set before the shared install. A missing
# package must not fail the desktop-less images.
set -euo pipefail

candidates=(
  firefox
  firefox-langpacks
  brave-browser
  gamemode
  gamemode-libs
)
present=()
for pkg in "${candidates[@]}"; do
  if rpm -q "${pkg}" >/dev/null 2>&1; then
    present+=("${pkg}")
  fi
done

if ((${#present[@]})); then
  printf 'Doors pre-remove: removing %s\n' "${present[*]}"
  dnf remove -y "${present[@]}"
else
  printf 'Doors pre-remove: none of the desktop conflicts are installed.\n'
fi

# Keep zram-generator. cachyos-settings conflicts with the defaults package
# and provides that name; autoremove would also drop the generator it needs.
if rpm -q zram-generator-defaults >/dev/null 2>&1; then
  printf 'Doors pre-remove: replacing zram-generator-defaults\n'
  dnf remove -y --no-autoremove zram-generator-defaults
fi
