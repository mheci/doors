#!/usr/bin/env bash
# Keep the automatic system Flatpak policy explicit and singular. Fedora
# Silverblue's Flatpak preinstall descriptor API is not assumed; Doors owns one
# first-networked-boot service that installs only Bazaar, DistroShelf, and
# Gear Lever from the statically configured, GPG-verified Flathub remote.
set -euo pipefail

readonly flathub_repo='/etc/flatpak/remotes.d/flathub.flatpakrepo'
readonly flathub_url='https://dl.flathub.org/repo/'

[[ -f "${flathub_repo}" ]] || {
  echo "Doors' reviewed Flathub static remote is missing" >&2
  exit 1
}
grep -Fqx '[Flatpak Repo]' "${flathub_repo}"
grep -Fqx "Url=${flathub_url}" "${flathub_repo}"
grep -Eq '^GPGKey=.+$' "${flathub_repo}"

# Remove every inherited system installation remote except the explicitly
# reviewed Flathub remote. A same-named inherited remote is not trusted merely
# because it is called "flathub": delete it if its endpoint is not the reviewed
# static descriptor. Users may still add personal remotes later; Doors simply
# publishes a single verified default trust root. Remove matching static metadata
# as well, otherwise a base update could reintroduce a remote.
while IFS= read -r remote; do
  [[ -n "${remote}" ]] || continue
  if [[ "${remote}" == 'flathub' ]]; then
    remote_url="$(/usr/bin/flatpak --system remote-url "${remote}" 2>/dev/null || true)"
    [[ "${remote_url%/}/" == "${flathub_url}" ]] && continue
  fi
  /usr/bin/flatpak --system remote-delete --force "${remote}"
done < <(/usr/bin/flatpak remotes --system --columns=name 2>/dev/null || true)
if [[ -d /etc/flatpak/remotes.d ]]; then
  find /etc/flatpak/remotes.d -maxdepth 1 -type f -name '*.flatpakrepo' ! -name 'flathub.flatpakrepo' -delete
fi
if [[ -d /usr/share/flatpak/remotes.d ]]; then
  # The sole approved static remote lives in /etc, with its reviewed key.
  find /usr/share/flatpak/remotes.d -maxdepth 1 -type f -name '*.flatpakrepo' -delete
fi

# A parent image must not preinstall a competing application set. The Doors
# bootstrap service is the only automatic application provisioner.
if [[ -d /usr/share/flatpak/preinstall.d ]]; then
  find /usr/share/flatpak/preinstall.d -maxdepth 1 -type f -name '*.preinstall' -delete
fi
rm -f /usr/share/ublue-os/privileged-setup.hooks.d/99-flatpaks.sh
rm -rf /usr/share/ublue-os/firefox-config

# Remove only the retired independent BlueBuild default-flatpaks mechanism,
# never the base image's Flatpak update timers. This retains upstream security
# and runtime updates while avoiding a second application installer.
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
