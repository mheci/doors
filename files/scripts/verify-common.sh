#!/usr/bin/env bash
# Shared build-time invariants. Desktop-specific scripts source this library.
# Hardware/Wayland behavior still requires docs/TEST-PLAN.md.
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

verify_common() {
  local unwanted unwanted_command rpm command removed_path unit

  for unwanted in \
    firefox firefox-langpacks brave-browser gamemode gamemode-libs \
    nodejs npm pnpm deno mise t3code opencode greenboot-default-health-checks; do
    if rpm -q "${unwanted}" >/dev/null 2>&1; then
      fail "explicitly excluded host RPM remains installed: ${unwanted}"
    fi
  done
  for unwanted_command in bun pi herdr; do
    if command -v "${unwanted_command}" >/dev/null 2>&1; then
      fail "AI harness must remain inside Doors AI Distrobox: ${unwanted_command}"
    fi
  done

  # This NVIDIA Open base does not ship the Bazzite Gamescope package. Doors
  # installs Fedora's signed Gamescope RPM and validates that shared contract.
  for rpm in \
    brave-origin zen-browser helium-bin steam heroic-games-launcher faugus-launcher \
    protonplus umu-launcher vesktop gamescope falcond falcond-profiles ananicy-cpp \
    cachyos-ananicy-rules scx-scheds scx-tools vicinae distrobox podman uupd greenboot \
    ghostty zed kitty \
    yaru-theme yaru-icon-theme yaru-sound-theme adw-gtk3-theme \
    rsms-inter-fonts jetbrains-mono-fonts fira-code-fonts cascadia-code-fonts \
    google-roboto-fonts google-noto-sans-cjk-fonts google-noto-emoji-fonts \
    papirus-icon-theme numix-icon-theme numix-gtk-theme breeze-icon-theme; do
    require_rpm "${rpm}"
  done

  for command in \
    wl-clip-persist vicinae gamescope scx_loader scxctl falcond ananicy-cpp \
    ghostty kitty distrobox podman uupd doors-ai doors-distrobox doors-secureboot; do
    require_command "${command}"
  done

  # brave-keyring is a compose-time dependency of Origin. Its unrelated
  # beta/nightly (or future auxiliary) keys and background updater must not
  # remain as runtime trust.
  shopt -s nullglob
  local auxiliary_brave_keys=(/etc/pki/rpm-gpg/RPM-GPG-KEY-brave-*)
  [[ "${#auxiliary_brave_keys[@]}" -eq 0 ]] \
    || fail "unapproved Brave key files remain: ${auxiliary_brave_keys[*]}"
  for removed_path in /usr/libexec/brave-key-updater /etc/cron.daily/brave-key-updater; do
    [[ ! -e "${removed_path}" ]] || fail "unapproved Brave keyring material remains: ${removed_path}"
  done

  # Doors owns one coordinated update transaction. uupd remains its reviewed
  # bootc/rpm-ostree engine only; all account-owned work is delegated through
  # doors-user-update.service instead of logind's active-user list.
  [[ -s /etc/uupd/config.json ]] || fail 'uupd configuration is missing'
  jq -e '
    .modules.brew.disable == true and
    .modules.distrobox.disable == true and
    .modules.flatpak.disable == true and
    .modules.system.disable == false
  ' /etc/uupd/config.json >/dev/null || fail 'uupd module policy changed unexpectedly'

  require_not_enabled uupd.timer
  require_not_enabled bootc-fetch-apply-updates.timer
  require_not_enabled flatpak-system-updates.timer
  require_not_enabled podman-auto-update.timer
  require_global_user_not_enabled flatpak-user-updates.timer
  require_global_user_not_enabled podman-auto-update.timer
  require_global_user_not_enabled doors-user-update.service

  # The AI payload is declarative, Arch Linux-based, CUDA-aware, and mounted
  # into a rootless user Distrobox rather than installed into the immutable host.
  [[ -r /usr/share/doors/distrobox/doors-ai.ini ]] || fail 'Doors AI Distrobox manifest is missing'
  grep -Fqx 'image=docker.io/library/archlinux:latest' /usr/share/doors/distrobox/doors-ai.ini \
    || fail 'Doors AI Distrobox must use Arch Linux'
  grep -Fqx 'nvidia=true' /usr/share/doors/distrobox/doors-ai.ini \
    || fail 'Doors AI Distrobox NVIDIA integration is not enabled'
  grep -Fqx 'init=true' /usr/share/doors/distrobox/doors-ai.ini \
    || fail 'Doors AI Distrobox init/systemd integration is not enabled'
  grep -Fqx 'start_now=true' /usr/share/doors/distrobox/doors-ai.ini \
    || fail 'Doors AI Distrobox start-now behavior is not enabled'
  grep -Fqx 'replace=false' /usr/share/doors/distrobox/doors-ai.ini \
    || fail 'Doors AI Distrobox must not silently replace user data'
  [[ -x /usr/share/doors/distrobox/bootstrap-ai.sh ]] \
    || fail 'Doors AI Distrobox bootstrap payload is missing'
  grep -Fqx '  archlinux-keyring \' /usr/share/doors/distrobox/bootstrap-ai.sh \
    || fail 'Doors AI bootstrap must refresh the Arch trust root'
  grep -Fqx '  base-devel git nodejs npm pnpm python python-pip deno mise opencode cuda' \
    /usr/share/doors/distrobox/bootstrap-ai.sh \
    || fail 'Doors AI bootstrap must install the supported Arch toolchain'
  [[ ! -e /usr/share/doors/distrobox/repos ]] \
    || fail 'obsolete external Distrobox repository definitions remain'
  [[ ! -e /usr/share/doors/distrobox/keys/RPM-GPG-KEY-NVIDIA-CUDA ]] \
    || fail 'obsolete Distrobox CUDA repository key remains'
  [[ ! -e /usr/share/doors/distrobox/keys/RPM-GPG-KEY-terra44 ]] \
    || fail 'obsolete Distrobox Terra repository key remains'
  [[ -s /usr/share/doors/distrobox/herdr/herdr-linux-x86_64 ]] \
    || fail 'attestation-verified Herdr Distrobox payload is missing'
  [[ -s /usr/share/doors/distrobox/herdr/herdr.json ]] \
    || fail 'Herdr Distrobox verification manifest is missing'

  # Performance policy remains host-owned and is desktop neutral.
  grep -qx 'default_sched = "scx_lavd"' /etc/scx_loader/config.toml \
    || fail 'scx_lavd is not the configured loader scheduler'
  grep -qx 'default_mode = "LowLatency"' /etc/scx_loader/config.toml \
    || fail 'LowLatency is not the configured loader mode'
  [[ -f /usr/lib/modules-load.d/vicinae.conf ]] || fail 'Vicinae uinput loader config is missing'
  grep -qx 'uinput' /usr/lib/modules-load.d/vicinae.conf || fail 'Vicinae did not request uinput'
  [[ -f /usr/lib/systemd/user/wl-clip-persist.service ]] || fail 'clipboard persistence user unit is missing'
  for unit in \
    falcond.service ananicy-cpp.service scx_loader.service doors-update.timer \
    doors-flatpak-bootstrap.service greenboot-healthcheck.service \
    greenboot-set-rollback-trigger.service; do
    require_system_enabled "${unit}"
  done
  for unit in doors-distrobox.service vicinae.service wl-clip-persist.service; do
    require_global_user_enabled "${unit}"
  done
  for update_path in \
    /usr/libexec/doors/update-system.sh \
    /usr/libexec/doors/update-user.sh \
    /usr/lib/systemd/system/doors-update.service \
    /usr/lib/systemd/system/doors-update.timer \
    /usr/lib/systemd/user/doors-user-update.service; do
    [[ -e "${update_path}" ]] || fail "managed-update payload is missing: ${update_path}"
  done
  [[ -x /usr/libexec/doors/update-system.sh && -x /usr/libexec/doors/update-user.sh ]] \
    || fail 'managed-update scripts are not executable'

  # Fedora's Rust Greenboot implementation protects a staged immutable
  # deployment after it reboots. Doors deliberately uses only a local,
  # bounded required check; the upstream generic DNS/watchdog package has
  # bootc-inapplicable assumptions and must remain absent.
  [[ -x /etc/greenboot/check/required.d/10-doors-deployment.sh ]] \
    || fail 'Doors required Greenboot deployment check is missing or not executable'
  for greenboot_dropin in \
    /etc/systemd/system/greenboot-healthcheck.service.d/10-doors-grub-only.conf \
    /etc/systemd/system/greenboot-set-rollback-trigger.service.d/10-doors-grub-only.conf; do
    [[ -f "${greenboot_dropin}" ]] || fail "Greenboot GRUB compatibility guard is missing: ${greenboot_dropin}"
    grep -Fqx 'ConditionPathExists=/boot/grub2/grubenv' "${greenboot_dropin}" \
      || fail "Greenboot GRUB compatibility guard is malformed: ${greenboot_dropin}"
  done
  grep -Fqx 'readonly status_timeout_seconds=60' /etc/greenboot/check/required.d/10-doors-deployment.sh \
    || fail 'Doors Greenboot check must keep a bounded deployment-status timeout'
  if grep -Eq '(curl|wget|getent|ping|bootc[[:space:]]+status)' /etc/greenboot/check/required.d/10-doors-deployment.sh; then
    fail 'Doors Greenboot check must not introduce boot-time network dependency'
  fi

  # The static Flathub remote and one owned bootstrap service may provision only
  # Bazaar, DistroShelf, Gear Lever, and their Flatpak-declared runtime dependencies.
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
  grep -Fqx "  'it.mijorus.gearlever'" /usr/libexec/doors/bootstrap-flatpaks.sh \
    || fail 'Doors bootstrap must target Gear Lever'
  grep -Fq 'flatpak run it.mijorus.gearlever --update --all --yes' \
    /usr/libexec/doors/update-user.sh \
    || fail 'managed AppImage updates must use Gear Lever without --force'
  if grep -Eq '^[^#]*it\.mijorus\.gearlever.*--force' /usr/libexec/doors/update-user.sh; then
    fail 'Gear Lever unattended updates must not use --force'
  fi
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
  [[ -s /usr/share/doors/third-party/wl-clip-persist.buildinfo ]] \
    || fail 'wl-clip-persist provenance record is missing'
}
