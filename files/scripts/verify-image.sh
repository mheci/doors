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
require_not_enabled() {
  [[ "$(systemctl is-enabled "$1" 2>/dev/null || true)" != 'enabled' ]] \
    || fail "competing system unit remains enabled: $1"
}
require_global_user_not_enabled() {
  [[ "$(systemctl --global is-enabled "$1" 2>/dev/null || true)" != 'enabled' ]] \
    || fail "competing global user unit remains enabled: $1"
}

for unwanted in \
  firefox firefox-langpacks brave-browser gamemode gamemode-libs \
  nodejs npm pnpm deno mise t3code opencode; do
  if rpm -q "${unwanted}" >/dev/null 2>&1; then
    fail "explicitly excluded host RPM remains installed: ${unwanted}"
  fi
done
for unwanted_command in bun pi herdr; do
  if command -v "${unwanted_command}" >/dev/null 2>&1; then
    fail "AI harness must remain inside Doors AI Distrobox: ${unwanted_command}"
  fi
done

# The BlueBuild Fedora Silverblue base does not ship Bazzite's Terra Gamescope
# package. Doors installs Fedora's signed Gamescope RPM and verifies that exact
# package plus the stable executable contract below.
for rpm in \
  brave-origin zen-browser helium-bin steam heroic-games-launcher faugus-launcher \
  protonplus umu-launcher vesktop gamescope falcond falcond-profiles ananicy-cpp \
  cachyos-ananicy-rules scx-scheds scx-tools vicinae distrobox podman uupd \
  ghostty zed kitty \
  yaru-theme yaru-icon-theme yaru-sound-theme adw-gtk3-theme \
  rsms-inter-fonts jetbrains-mono-fonts fira-code-fonts cascadia-code-fonts \
  google-roboto-fonts google-noto-sans-cjk-fonts google-noto-emoji-fonts \
  papirus-icon-theme numix-icon-theme numix-gtk-theme breeze-icon-theme \
  gnome-shell-extension-dash-to-dock gnome-shell-extension-appindicator \
  gnome-shell-extension-gsconnect gnome-shell-extension-just-perfection \
  gnome-shell-extension-vicinae gnome-shell-extension-grand-theft-focus; do
  require_rpm "${rpm}"
done

for command in \
  wl-clip-persist vicinae gamescope scx_loader scxctl falcond ananicy-cpp \
  ghostty kitty distrobox podman uupd doors-ai; do
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

# uupd owns automatic bootc, Flatpak, and Distrobox updates. It must be the
# only enabled coordinator, and its configured modules must retain that scope.
[[ -s /etc/uupd/config.json ]] || fail 'uupd configuration is missing'
jq -e '
  .modules.brew.disable == true and
  .modules.distrobox.disable == false and
  .modules.flatpak.disable == false and
  .modules.system.disable == false
' /etc/uupd/config.json >/dev/null || fail 'uupd module policy changed unexpectedly'

require_not_enabled bootc-fetch-apply-updates.timer
require_not_enabled flatpak-system-updates.timer
require_global_user_not_enabled flatpak-user-updates.timer

# The AI payload is declarative, Fedora-44-only, CUDA-aware, and mounted into
# a rootless user Distrobox rather than installed into the immutable host.
[[ -r /usr/share/doors/distrobox/doors-ai.ini ]] || fail 'Doors AI Distrobox manifest is missing'
grep -Fqx 'image=registry.fedoraproject.org/fedora-toolbox:44' /usr/share/doors/distrobox/doors-ai.ini \
  || fail 'Doors AI Distrobox must use Fedora Toolbox 44'
grep -Fqx 'nvidia=true' /usr/share/doors/distrobox/doors-ai.ini \
  || fail 'Doors AI Distrobox NVIDIA integration is not enabled'
[[ -x /usr/share/doors/distrobox/bootstrap-ai.sh ]] \
  || fail 'Doors AI Distrobox bootstrap payload is missing'
[[ -s /usr/share/doors/distrobox/herdr/herdr-linux-x86_64 ]] \
  || fail 'attestation-verified Herdr Distrobox payload is missing'
[[ -s /usr/share/doors/distrobox/herdr/herdr.json ]] \
  || fail 'Herdr Distrobox verification manifest is missing'

# Performance/GNOME policy remains host-owned.
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
for unit in \
  falcond.service ananicy-cpp.service scx_loader.service uupd.timer \
  doors-flatpak-bootstrap.service; do
  require_system_enabled "${unit}"
done
for unit in doors-ai-distrobox.service vicinae.service wl-clip-persist.service; do
  require_global_user_enabled "${unit}"
done

# The static Flathub remote and one owned bootstrap service may provision only
# Bazaar and DistroShelf, plus their Flatpak-declared runtime dependencies.
if [[ -d /usr/share/flatpak/preinstall.d ]] \
  && find /usr/share/flatpak/preinstall.d -maxdepth 1 -type f -name '*.preinstall' -print -quit | grep -q .; then
  fail 'unexpected Flatpak preinstall descriptor remains'
fi
[[ -f /etc/flatpak/remotes.d/flathub.flatpakrepo ]] \
  || fail 'reviewed Flathub static remote is missing'
grep -Fqx '[Flatpak Repo]' /etc/flatpak/remotes.d/flathub.flatpakrepo \
  || fail 'Flathub remote metadata is malformed'
grep -Fqx 'Url=https://dl.flathub.org/repo/' /etc/flatpak/remotes.d/flathub.flatpakrepo \
  || fail 'Flathub remote URL changed unexpectedly'
grep -Eq '^GPGKey=.+$' /etc/flatpak/remotes.d/flathub.flatpakrepo \
  || fail 'Flathub remote signing key is missing'
[[ -x /usr/libexec/doors/bootstrap-flatpaks.sh ]] \
  || fail 'Doors Flatpak bootstrap script is missing'
grep -Fqx "  'io.github.kolunmi.Bazaar'" /usr/libexec/doors/bootstrap-flatpaks.sh \
  || fail 'Doors bootstrap must target Bazaar'
grep -Fqx "  'com.ranfdev.DistroShelf'" /usr/libexec/doors/bootstrap-flatpaks.sh \
  || fail 'Doors bootstrap must target DistroShelf'
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
[[ -s /usr/share/doors/third-party/wl-clip-persist.buildinfo ]] || fail 'wl-clip-persist provenance record is missing'
