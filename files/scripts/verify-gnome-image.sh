#!/usr/bin/env bash
# GNOME-only Doors image invariants.
set -euo pipefail
# shellcheck source=verify-common.sh
source "$(dirname "$0")/verify-common.sh"

verify_common

for rpm in \
  gnome-shell-extension-dash-to-dock gnome-shell-extension-appindicator \
  gnome-shell-extension-gsconnect gnome-shell-extension-just-perfection \
  gnome-shell-extension-vicinae gnome-shell-extension-grand-theft-focus; do
  require_rpm "${rpm}"
done

[[ -s /etc/dconf/db/local ]] || fail 'GNOME defaults database is missing'
for extension in \
  dash-to-dock@micxgx.gmail.com appindicatorsupport@rgcjonas.gmail.com \
  gsconnect@andyholmes.github.io clipboard-indicator@tudmotu.com \
  grand-theft-focus@zalckos.github.com just-perfection-desktop@just-perfection \
  AlphabeticalAppGrid@stuarthayhurst vicinae@dagimg-dot.netlify.app \
  emoji-copy@felipeftn; do
  [[ -d "/usr/share/gnome-shell/extensions/${extension}" ]] \
    || fail "requested GNOME extension is missing: ${extension}"
done
