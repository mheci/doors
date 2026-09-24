#!/usr/bin/env bash
# Kinoite-only Doors image invariants.
set -euo pipefail
# shellcheck source=verify-common.sh
source "$(dirname "$0")/verify-common.sh"

verify_common

require_rpm breeze-gtk
require_command plasmashell
[[ ! -e /etc/dconf/db/local.d/00-doors ]] \
  || fail 'GNOME dconf defaults must not ship in the Kinoite image'
[[ -f /etc/xdg/kdeglobals ]] || fail 'Plasma defaults are missing'
grep -Fqx 'LookAndFeelPackage=org.kde.breezedark.desktop' /etc/xdg/kdeglobals \
  || fail 'Kinoite must default to the native Breeze Dark look and feel'
grep -Fqx 'ColorScheme=BreezeDark' /etc/xdg/kdeglobals \
  || fail 'Kinoite must default to the native Breeze Dark color scheme'
grep -Fqx 'Theme=breeze-dark' /etc/xdg/kdeglobals \
  || fail 'Kinoite must default to native Breeze Dark icons'
grep -Fqx '[KDE Action Restrictions][$i]' /etc/xdg/kdeglobals \
  || fail 'Kinoite must retain immutable KDE action restrictions'
grep -Fqx 'ghns=false' /etc/xdg/kdeglobals \
  || fail 'Kinoite must disable Get Hot New Stuff by default'
[[ -d /usr/share/plasma/look-and-feel/org.kde.breezedark.desktop ]] \
  || fail 'native Breeze Dark look-and-feel assets are missing'
for forbidden_autostart in \
  /etc/xdg/autostart/steam.desktop \
  /etc/xdg/autostart/steam-big-picture.desktop \
  /etc/xdg/autostart/steam-bpm.desktop; do
  [[ ! -e "${forbidden_autostart}" ]] \
    || fail "Steam desktop-mode image must not autostart Big Picture/Game Mode: ${forbidden_autostart}"
done
