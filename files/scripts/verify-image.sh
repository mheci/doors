#!/usr/bin/env bash
# Build-time invariants. Hardware/Wayland behavior still requires the separate
# physical validation plan documented in docs/TEST-PLAN.md.
set -euo pipefail

fail() { echo "DOORS VERIFY FAIL: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }
require_rpm() { rpm -q "$1" >/dev/null 2>&1 || fail "missing RPM: $1"; }
require_system_enabled() {
  [[ "$(systemctl is-enabled "$1")" == 'enabled' ]] || fail "system unit is not enabled: $1"
}
require_global_user_enabled() {
  [[ "$(systemctl --global is-enabled "$1")" == 'enabled' ]] || fail "global user unit is not enabled: $1"
}

for unwanted in firefox brave-browser gamemode gamemode-libs; do
  if rpm -q "${unwanted}" >/dev/null 2>&1; then
    fail "explicitly excluded RPM remains installed: ${unwanted}"
  fi
done

# Bazzite supplies Gamescope through its matched Terra package. Verifying that
# component directly avoids requesting Fedora's mutually exclusive gamescope RPM.
for rpm in \
  brave-origin zen-browser helium-bin steam heroic-games-launcher faugus-launcher \
  protonplus umu-launcher vesktop terra-gamescope falcond falcond-profiles ananicy-cpp \
  cachyos-ananicy-rules scx-scheds scx-tools vicinae \
  deno mise t3code opencode zed ghostty kitty \
  yaru-theme yaru-icon-theme yaru-sound-theme adw-gtk3-theme \
  rsms-inter-fonts jetbrains-mono-fonts fira-code-fonts cascadia-code-fonts \
  google-roboto-fonts google-noto-sans-cjk-fonts google-noto-emoji-fonts \
  papirus-icon-theme numix-icon-theme numix-gtk-theme breeze-icon-theme \
  gnome-shell-extension-dash-to-dock gnome-shell-extension-appindicator \
  gnome-shell-extension-gsconnect gnome-shell-extension-just-perfection \
  gnome-shell-extension-vicinae gnome-shell-extension-grand-theft-focus; do
  require_rpm "${rpm}"
done

# Fedora resolves the generic Node requests to a supported, versioned Node RPM
# (currently nodejs22). Test the stable CLI contract rather than its mutable RPM
# name, alongside the requested pnpm executable.
for command in \
  bun pi herdr wl-clip-persist vicinae gamescope node npm pnpm scx_loader scxctl falcond ananicy-cpp \
  deno mise t3code opencode zed ghostty kitty; do
  require_command "${command}"
done

# brave-keyring is a compose-time dependency of Origin. Its unrelated
# beta/nightly (or future auxiliary) keys and background updater must not
# remain as runtime trust.
shopt -s nullglob
auxiliary_brave_keys=(/etc/pki/rpm-gpg/RPM-GPG-KEY-brave-*)
[[ "${#auxiliary_brave_keys[@]}" -eq 0 ]] \
  || fail "unapproved Brave key files remain: ${auxiliary_brave_keys[*]}"
for removed_path in /usr/libexec/brave-key-updater /etc/cron.daily/brave-key-updater; do
  [[ ! -e "${removed_path}" ]] || fail "unapproved Brave keyring material remains: ${removed_path}"
done

grep -qx 'default_sched = "scx_lavd"' /etc/scx_loader/config.toml \
  || fail 'scx_lavd is not the configured loader scheduler'
grep -qx 'default_mode = "LowLatency"' /etc/scx_loader/config.toml \
  || fail 'LowLatency is not the configured loader mode'
[[ -f /usr/lib/modules-load.d/vicinae.conf ]] || fail 'Vicinae uinput loader config is missing'
grep -qx 'uinput' /usr/lib/modules-load.d/vicinae.conf || fail 'Vicinae did not request uinput'
[[ -s /etc/dconf/db/local ]] || fail 'GNOME defaults database is missing'
[[ -f /usr/lib/systemd/user/wl-clip-persist.service ]] || fail 'clipboard persistence user unit is missing'
for extension in \
  dash-to-dock@micxgx.gmail.com appindicatorsupport@rgcjonas.gmail.com \
  gsconnect@andyholmes.github.io clipboard-indicator@tudmotu.com \
  grand-theft-focus@zalckos.github.com just-perfection-desktop@just-perfection \
  AlphabeticalAppGrid@stuarthayhurst vicinae@dagimg-dot.netlify.app \
  emoji-copy@felipeftn; do
  [[ -d "/usr/share/gnome-shell/extensions/${extension}" ]] \
    || fail "requested GNOME extension is missing: ${extension}"
done
for unit in falcond.service ananicy-cpp.service scx_loader.service uupd.timer flatpak-preinstall.service; do
  require_system_enabled "${unit}"
done
for unit in vicinae.service wl-clip-persist.service; do
  require_global_user_enabled "${unit}"
done
for unit in bootc-fetch-apply-updates.service bootc-fetch-apply-updates.timer; do
  [[ "$(systemctl is-enabled "${unit}")" == 'masked' ]] \
    || fail "competing bootc updater is not masked: ${unit}"
done

# Bazzite's preinstall hook and this image's BlueBuild configuration must not
# quietly provision any Flatpak other than Bazaar at first boot.
mapfile -t preinstall_files < <(find /usr/share/flatpak/preinstall.d -maxdepth 1 -type f -name '*.preinstall' -printf '%f\n' | sort)
[[ "${preinstall_files[*]}" == 'bazaar.preinstall' ]] \
  || fail 'Bazaar is not the sole Flatpak preinstall definition'
grep -Fqx '[Flatpak Preinstall io.github.kolunmi.Bazaar]' \
  /usr/share/flatpak/preinstall.d/bazaar.preinstall \
  || fail 'Bazaar Flatpak preinstall definition is missing'
grep -Fqx 'Branch=stable' /usr/share/flatpak/preinstall.d/bazaar.preinstall \
  || fail 'Bazaar Flatpak branch policy is missing'
grep -Fqx 'IsRuntime=false' /usr/share/flatpak/preinstall.d/bazaar.preinstall \
  || fail 'Bazaar must be the sole declared Flatpak application'
[[ ! -e /usr/share/ublue-os/privileged-setup.hooks.d/99-flatpaks.sh ]] \
  || fail 'Firefox first-login Flatpak hook remains'
[[ ! -e /usr/share/ublue-os/firefox-config ]] \
  || fail 'Firefox configuration payload remains'
[[ ! -e /usr/share/bluebuild/default-flatpaks/configuration.yaml ]] \
  || fail 'duplicate BlueBuild Flatpak configuration remains'
[[ ! -e /usr/lib/systemd/system/system-flatpak-setup.timer ]] \
  || fail 'duplicate BlueBuild system Flatpak timer remains'
[[ ! -e /usr/lib/systemd/user/user-flatpak-setup.timer ]] \
  || fail 'duplicate BlueBuild user Flatpak timer remains'
[[ -f /etc/flatpak/remotes.d/flathub.flatpakrepo ]] \
  || fail 'Flathub capability is missing'
[[ -s /usr/share/doors/third-party/herdr.json ]] || fail 'Herdr provenance manifest is missing'
[[ -s /usr/share/doors/third-party/wl-clip-persist.buildinfo ]] || fail 'wl-clip-persist provenance record is missing'
