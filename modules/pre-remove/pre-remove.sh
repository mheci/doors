#!/usr/bin/env bash
# falcond provides gamemode and conflicts with the package already installed on
# the NVIDIA bases. Remove that set before the shared install. A missing
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

if ((${#present[@]} == 0)); then
  printf 'Doors pre-remove: none of the conflicting packages are installed.\n'
  exit 0
fi

printf 'Doors pre-remove: removing %s\n' "${present[*]}"
dnf remove -y "${present[@]}"
