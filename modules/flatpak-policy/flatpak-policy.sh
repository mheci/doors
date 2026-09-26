#!/usr/bin/env bash
# Strip the base image's preinstalled Flatpak application set and every retired
# competing installer path.
#
# Run this module BEFORE `default-flatpaks`: that module stores its own remote
# and configuration state under /usr/share/bluebuild/default-flatpaks, which is
# deliberately left untouched here. `default-flatpaks` then owns application
# provisioning declaratively, and removes the Fedora remote and its
# applications again at first boot from its own setup units.
set -euo pipefail

# A parent image must not preinstall a competing application set through
# Flatpak's preinstall-descriptor API.
if [[ -d /usr/share/flatpak/preinstall.d ]]; then
  find /usr/share/flatpak/preinstall.d -maxdepth 1 -type f -name '*.preinstall' -delete
fi
rm -f /usr/share/ublue-os/privileged-setup.hooks.d/99-flatpaks.sh
rm -rf /usr/share/ublue-os/firefox-config

printf 'Doors Flatpak policy: base preinstall set removed; default-flatpaks owns provisioning.\n'
