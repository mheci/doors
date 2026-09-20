#!/usr/bin/env bash
# Keep Bazzite's native first-boot Flatpak preinstaller, but make its declared
# set explicit and singular. Do not use BlueBuild's separate default-flatpaks
# timer as that would duplicate Bazaar provisioning and add another manager.
set -euo pipefail

readonly preinstall_dir='/usr/share/flatpak/preinstall.d'
readonly bazaar_file="${preinstall_dir}/bazaar.preinstall"

install -d -m 0755 "${preinstall_dir}"
find "${preinstall_dir}" -maxdepth 1 -type f -name '*.preinstall' ! -name 'bazaar.preinstall' -delete

cat > "${bazaar_file}" <<'EOF'
[Flatpak Preinstall io.github.kolunmi.Bazaar]
Branch=stable
IsRuntime=false
EOF
chmod 0644 "${bazaar_file}"

# Bazzite's current privileged Flatpak hook only materializes Firefox defaults.
# Firefox is intentionally absent from Doors, so do not retain its first-login
# configuration hook or its unused configuration payload.
rm -f /usr/share/ublue-os/privileged-setup.hooks.d/99-flatpaks.sh
rm -rf /usr/share/ublue-os/firefox-config

# A previous base layer or recipe must not leave BlueBuild's independent
# default-flatpaks manager/configuration behind. Doors relies exclusively on
# the already-enabled native flatpak-preinstall.service above.
rm -rf /usr/share/bluebuild/default-flatpaks
rm -f /usr/lib/systemd/system/system-flatpak-setup.service
rm -f /usr/lib/systemd/system/system-flatpak-setup.timer
rm -f /usr/lib/systemd/user/user-flatpak-setup.service
rm -f /usr/lib/systemd/user/user-flatpak-setup.timer
rm -f /usr/libexec/bluebuild/default-flatpaks/system-flatpak-setup
rm -f /usr/libexec/bluebuild/default-flatpaks/user-flatpak-setup
rm -f /usr/bin/bluebuild-flatpak-manager
rm -f /etc/systemd/system/timers.target.wants/system-flatpak-setup.timer
rm -f /etc/systemd/user/timers.target.wants/user-flatpak-setup.timer
