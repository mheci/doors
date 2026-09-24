#!/usr/bin/env bash
# Shared build-time invariants. Desktop-specific scripts source this library.
# Hardware/Wayland behavior still requires docs/TEST-PLAN.md.
set -euo pipefail

fail() { echo "DOORS VERIFY FAIL: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }
require_rpm() { rpm -q "$1" >/dev/null 2>&1 || fail "missing RPM: $1"; }
require_rpm_provider() {
  rpm -q --whatprovides "$1" >/dev/null 2>&1 || fail "missing RPM provider: $1"
}
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
  local unwanted rpm command removed_path unit wl_clip_persist_buildinfo flatpak_remote_url \
    cuda_key cuda_repo cuda_fingerprint actual_cuda_fingerprint cuda_key_sha256 actual_cuda_key_sha256 cuda_repo_line \
    herdr_dir herdr_artifact herdr_manifest expected_herdr_sha256 actual_herdr_sha256 \
    t3_prefix t3_package

  for unwanted in \
    firefox firefox-langpacks brave-browser gamemode gamemode-libs distrobox t3code \
    greenboot-default-health-checks; do
    if rpm -q "${unwanted}" >/dev/null 2>&1; then
      fail "explicitly excluded host RPM remains installed: ${unwanted}"
    fi
  done

  # This NVIDIA Open base does not ship the Bazzite Gamescope package. Doors
  # installs Fedora's signed Gamescope RPM and validates that shared contract.
  for rpm in \
    brave-origin zen-browser helium-bin steam heroic-games-launcher faugus-launcher \
    protonplus umu-launcher vesktop gamescope falcond falcond-profiles ananicy-cpp \
    cachyos-ananicy-rules scx-scheds scx-tools vicinae uupd greenboot \
    ghostty zed kitty \
    nodejs nodejs-devel npm pnpm python3 python3-devel python3-pip \
    gcc gcc-c++ make cmake pkgconf-pkg-config \
    bun-bin deno mise opencode-cli pi cuda-toolkit-13-4 \
    yaru-theme yaru-icon-theme yaru-sound-theme adw-gtk3-theme \
    rsms-inter-fonts jetbrains-mono-fonts fira-code-fonts cascadia-code-fonts \
    google-roboto-fonts google-noto-sans-cjk-fonts google-noto-emoji-fonts \
    papirus-icon-theme numix-icon-theme numix-gtk-theme breeze-icon-theme \
    ladspa lsp-plugins-ladspa \
    chrony unbound unbound-anchor polkit cryptsetup dracut tpm2-tss tpm2-tools \
    libfido2 dconf dbus-daemon; do
    require_rpm "${rpm}"
  done

  for command in \
    wl-clip-persist vicinae gamescope scx_loader scxctl falcond ananicy-cpp \
    ghostty kitty uupd doors-ai doors-secureboot \
    node npm pnpm python3 pip3 gcc g++ make cmake pkg-config \
    bun deno mise opencode pi t3 nvcc herdr \
    analyseplugin pw-config chronyc unbound-checkconf unbound-anchor resolvectl run0 pkexec \
    doors-dns doors-desktop-cleanup doors-image doors-luks-enroll; do
    require_command "${command}"
  done
  for provider in nodejs nodejs-devel npm; do
    require_rpm_provider "${provider}"
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
    .modules.flatpak.disable == true and
    .modules.system.disable == false and
    (.modules | has("distrobox") | not)
  ' /etc/uupd/config.json >/dev/null || fail 'uupd module policy changed unexpectedly'

  require_not_enabled uupd.timer
  require_not_enabled bootc-fetch-apply-updates.timer
  require_not_enabled flatpak-system-updates.timer
  require_not_enabled podman-auto-update.timer
  require_global_user_not_enabled flatpak-user-updates.timer
  require_global_user_not_enabled podman-auto-update.timer
  require_global_user_not_enabled doors-user-update.service

  # The development/AI stack is native image content. Terra supplies the
  # reviewed fast-moving CLIs; Fedora provides the compiler/runtime baseline;
  # NVIDIA's toolkit-only Fedora 44 route supplies nvcc without a driver route.
  for removed_path in \
    /usr/share/doors/distrobox \
    /usr/bin/doors-distrobox \
    /usr/lib/systemd/user/doors-distrobox.service; do
    [[ ! -e "${removed_path}" ]] \
      || fail "retired Distrobox payload remains in the image: ${removed_path}"
  done

  cuda_key='/etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-cuda'
  cuda_repo='/etc/yum.repos.d/cuda-fedora44.repo'
  cuda_fingerprint='129994480EC63D2789BC98E490DFED2F73CD9B30'
  cuda_key_sha256='9221458f62030a18d5a28eecf44496016ff9c11548492ac2ce428f75c7513cab'
  [[ -s "${cuda_key}" ]] || fail 'reviewed NVIDIA CUDA repository key is missing'
  [[ -s "${cuda_repo}" ]] || fail 'reviewed NVIDIA CUDA repository definition is missing'
  actual_cuda_key_sha256="$(sha256sum "${cuda_key}" | awk '{print $1}')"
  [[ "${actual_cuda_key_sha256}" == "${cuda_key_sha256}" ]] \
    || fail 'NVIDIA CUDA repository key digest changed unexpectedly'
  actual_cuda_fingerprint="$(gpg --show-keys --with-colons "${cuda_key}" 2>/dev/null \
    | awk -F: '$1 == "fpr" { print $10; exit }')"
  [[ "${actual_cuda_fingerprint}" == "${cuda_fingerprint}" ]] \
    || fail 'NVIDIA CUDA repository key fingerprint changed unexpectedly'
  for cuda_repo_line in \
    'baseurl=https://developer.download.nvidia.com/compute/cuda/repos/fedora44/x86_64' \
    'gpgcheck=1' \
    'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-cuda' \
    'repo_gpgcheck=1' \
    'excludepkgs=cuda-drivers* nvidia-driver* nvidia-modprobe* nvidia-persistenced* nvidia-settings* nvidia-libXNVCtrl* nvidia-xconfig*'; do
    grep -Fqx "${cuda_repo_line}" "${cuda_repo}" \
      || fail "NVIDIA CUDA repository policy is missing: ${cuda_repo_line}"
  done
  [[ -x /usr/local/cuda-13.4/bin/nvcc && -x /usr/local/bin/nvcc ]] \
    || fail 'native CUDA Toolkit 13.4 compiler is missing'
  grep -Fqx 'if [[ -d /usr/local/cuda-13.4 ]]; then' /etc/profile.d/doors-cuda.sh \
    || fail 'native CUDA shell profile is missing'

  herdr_dir='/usr/share/doors/native-ai/herdr'
  herdr_artifact="${herdr_dir}/herdr-linux-x86_64"
  herdr_manifest="${herdr_dir}/herdr.json"
  [[ -s "${herdr_artifact}" ]] \
    || fail 'attestation-verified native Herdr artifact is missing'
  [[ -s "${herdr_manifest}" ]] \
    || fail 'native Herdr verification manifest is missing'
  jq -e '
    .repository == "herdrdev/herdr" and
    .asset == "herdr-linux-x86_64" and
    (.tag | test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$")) and
    (.sha256 | test("^[0-9a-f]{64}$"))
  ' "${herdr_manifest}" >/dev/null \
    || fail 'native Herdr verification manifest has an unexpected identity or shape'
  expected_herdr_sha256="$(jq --raw-output '.sha256' "${herdr_manifest}")"
  actual_herdr_sha256="$(sha256sum "${herdr_artifact}" | awk '{print $1}')"
  [[ "${actual_herdr_sha256}" == "${expected_herdr_sha256}" ]] \
    || fail 'native Herdr artifact digest differs from its attestation-verified manifest'
  herdr --version >/dev/null || fail 'native Herdr does not execute'
  nvcc --version >/dev/null || fail 'native nvcc does not execute'
  doors-ai status >/dev/null || fail 'native Doors AI helper does not report its toolchain'

  t3_prefix='/usr/local/lib/doors/native-ai/t3'
  t3_package="${t3_prefix}/node_modules/t3/package.json"
  [[ -x "${t3_prefix}/node_modules/.bin/t3" && -s "${t3_package}" ]] \
    || fail 'pinned native T3 CLI installation is missing'
  node -e '
    const pkg = require(process.argv[1]);
    process.exit(pkg.name === "t3" && pkg.version === "0.0.42" ? 0 : 1);
  ' "${t3_package}" \
    || fail 'native T3 CLI package identity changed unexpectedly'
  t3 --help >/dev/null || fail 'native T3 CLI does not execute'

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
    greenboot-set-rollback-trigger.service chronyd.service systemd-resolved.service \
    unbound-anchor.timer; do
    require_system_enabled "${unit}"
  done
  for unit in vicinae.service wl-clip-persist.service; do
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

  # Host integrations are intentionally common to all desktops. They are
  # configured here but network/hardware/destructive-operation behavior remains
  # covered by the physical release test plan.
  for host_path in \
    /etc/chrony.conf \
    /etc/systemd/resolved.conf.d/90-doors-dns.conf \
    /etc/NetworkManager/conf.d/90-doors-dns.conf \
    /etc/unbound/conf.d/90-doors.conf \
    /etc/polkit-1/rules.d/49-doors-wheel-admin.rules \
    /etc/systemd/coredump.conf.d/90-doors.conf \
    /etc/systemd/system.conf.d/90-doors-coredump.conf \
    /etc/systemd/user.conf.d/90-doors-coredump.conf \
    /etc/systemd/journald.conf.d/90-doors-retention.conf \
    /etc/environment.d/90-doors-log-noise.conf \
    /etc/sysctl.d/90-doors-gaming.conf \
    /etc/modprobe.d/nvidia-rebar.conf \
    /usr/lib/bootc/kargs.d/90-doors-nvme.toml; do
    [[ -s "${host_path}" ]] || fail "Doors host policy is missing: ${host_path}"
  done
  for helper in doors-dns doors-desktop-cleanup doors-image doors-luks-enroll; do
    [[ -x "/usr/bin/${helper}" ]] || fail "Doors host helper is missing: ${helper}"
    "/usr/bin/${helper}" --help >/dev/null || fail "Doors host helper --help failed: ${helper}"
  done
  grep -Fqx 'server time.cloudflare.com iburst nts' /etc/chrony.conf \
    || fail 'Chrony Cloudflare NTS source is missing'
  grep -Fqx 'authselectmode require' /etc/chrony.conf \
    || fail 'Chrony must require authenticated NTS sources'
  grep -Fqx 'DNSOverTLS=yes' /etc/systemd/resolved.conf.d/90-doors-dns.conf \
    || fail 'systemd-resolved DNS-over-TLS default is missing'
  grep -Fqx 'DNSSEC=yes' /etc/systemd/resolved.conf.d/90-doors-dns.conf \
    || fail 'systemd-resolved DNSSEC default is missing'
  grep -Fqx 'dns=none' /etc/NetworkManager/conf.d/90-doors-dns.conf \
    || fail 'strict NetworkManager DNS policy is missing'
  grep -Fqx '    port: 5335' /etc/unbound/conf.d/90-doors.conf \
    || fail 'Unbound loopback listener port is missing'
  grep -Fqx 'Storage=none' /etc/systemd/coredump.conf.d/90-doors.conf \
    || fail 'coredump storage remains enabled'
  grep -Fqx 'MaxLevelStore=warning' /etc/systemd/journald.conf.d/90-doors-retention.conf \
    || fail 'journald warning/error retention policy is missing'
  grep -Fqx 'QT_LOGGING_RULES=*.debug=false' /etc/environment.d/90-doors-log-noise.conf \
    || fail 'Qt debug suppression is missing'
  for sysctl_line in \
    'vm.max_map_count = 1048576' \
    'vm.page_lock_unfairness = 1' \
    'kernel.split_lock_mitigate = 0'; do
    grep -Fqx "${sysctl_line}" /etc/sysctl.d/90-doors-gaming.conf \
      || fail "gaming sysctl is missing: ${sysctl_line}"
  done
  grep -Fqx 'options nvidia NVreg_EnableResizableBar=1' /etc/modprobe.d/nvidia-rebar.conf \
    || fail 'NVIDIA ReBAR policy is missing'
  grep -Fqx 'kargs = ["nvme_core.default_ps_max_latency_us=0"]' /usr/lib/bootc/kargs.d/90-doors-nvme.toml \
    || fail 'NVMe APST kernel-argument policy is missing'
  grep -Fq 'org.freedesktop.systemd1.manage-units' /etc/polkit-1/rules.d/49-doors-wheel-admin.rules \
    || fail 'retained run0 systemd authorization is missing'
  grep -Fq 'AUTH_ADMIN_KEEP' /etc/polkit-1/rules.d/49-doors-wheel-admin.rules \
    || fail 'run0 authorization is not retained'
  grep -Fq 'org.freedesktop.udisks2.' /etc/polkit-1/rules.d/49-doors-wheel-admin.rules \
    || fail 'wheel UDisks authorization is missing'
  if grep -Fq -- '--wipe-slot' /usr/bin/doors-luks-enroll; then
    fail 'LUKS enrollment helper must never wipe an existing recovery slot'
  fi

  # Runtime DNF configuration must retain TLS verification and request only
  # HTTPS Fedora mirrors even after fedora-repos updates in the base image.
  grep -Fqx 'sslverify=True' /etc/dnf/libdnf5.conf.d/90-doors-https.conf \
    || fail 'DNF TLS verification policy is missing'
  while IFS= read -r -d '' repo_file; do
    if grep -Eq '^[[:space:]]*(baseurl|mirrorlist|metalink)[[:space:]]*=[[:space:]]*http://' "${repo_file}"; then
      fail "active RPM repository retains HTTP transport: ${repo_file}"
    fi
    if grep -Eq '^[[:space:]]*metalink[[:space:]]*=[[:space:]]*https://mirrors\.fedoraproject\.org/metalink\?' "${repo_file}" \
      && ! grep -Eq '^[[:space:]]*metalink[[:space:]]*=.*([?&])protocol=https([&#]|$)' "${repo_file}"; then
      fail "Fedora metalink does not enforce HTTPS mirrors: ${repo_file}"
    fi
  done < <(find /etc/yum.repos.d -type f -name '*.repo' -print0)

  # PipeWire/WirePlumber policy is shared across all desktop images. It keeps
  # ALSA devices live, silences only the X11 alert bell, and exposes the audited
  # Anechoic microphone source without a desktop-specific configuration fork.
  for audio_config in \
    /etc/pipewire/pipewire.conf.d/20-doors-audio.conf \
    /etc/pipewire/pipewire-pulse.conf.d/20-doors-proton-wine.conf \
    /etc/pipewire/pipewire.conf.d/99-doors-anechoic.conf; do
    [[ -s "${audio_config}" ]] || fail "Doors PipeWire policy is missing: ${audio_config}"
    pw-config supported "${audio_config}" >/dev/null \
      || fail "Doors PipeWire policy is not supported: ${audio_config}"
  done
  [[ -s /etc/wireplumber/wireplumber.conf.d/20-doors-alsa-no-suspend.conf ]] \
    || fail 'Doors WirePlumber no-suspend policy is missing'
  grep -Fqx '    module.x11.bell = false' /etc/pipewire/pipewire.conf.d/20-doors-audio.conf \
    || fail 'PipeWire X11 alert bell remains enabled'
  for line in \
    '    default.clock.rate = 48000' \
    '    default.clock.quantum = 256' \
    '    default.clock.min-quantum = 64' \
    '    default.clock.max-quantum = 1024' \
    '    resample.quality = 10'; do
    grep -Fqx "${line}" /etc/pipewire/pipewire.conf.d/20-doors-audio.conf \
      || fail "Doors audio baseline is missing: ${line}"
  done
  grep -Fqx '                session.suspend-timeout-seconds = 0' \
    /etc/wireplumber/wireplumber.conf.d/20-doors-alsa-no-suspend.conf \
    || fail 'WirePlumber must keep ALSA nodes unsuspended'
  grep -Fqx 'options snd_hda_intel power_save=0 power_save_controller=N' /etc/modprobe.d/doors-audio.conf \
    || fail 'HDA codec power saving remains enabled'
  readonly anechoic_plugin='/usr/lib64/ladspa/libanechoic_ladspa.so'
  [[ -s "${anechoic_plugin}" ]] || fail 'Anechoic LADSPA plugin is missing'
  analyseplugin "${anechoic_plugin}" | grep -Fq 'noise_suppressor_mono' \
    || fail 'Anechoic LADSPA mono suppressor descriptor is missing'
  grep -Fqx '                        plugin = ladspa/libanechoic_ladspa' /etc/pipewire/pipewire.conf.d/99-doors-anechoic.conf \
    || fail 'PipeWire does not load the audited Anechoic plugin'
  grep -Fqx '                        label = noise_suppressor_mono' /etc/pipewire/pipewire.conf.d/99-doors-anechoic.conf \
    || fail 'PipeWire does not expose the Anechoic mono suppressor'
  for anechoic_path in \
    /usr/share/licenses/anechoic/LICENSE \
    /usr/share/doors/anechoic/anechoic-061038dd98d45abef5fc22ae9c27b289b50b180c.tar.gz \
    /usr/share/doors/anechoic/buildinfo \
    /usr/share/doc/doors/AUDIO.md; do
    [[ -s "${anechoic_path}" ]] || fail "Anechoic source/license documentation is missing: ${anechoic_path}"
  done
  grep -Fqx 'commit=061038dd98d45abef5fc22ae9c27b289b50b180c' /usr/share/doors/anechoic/buildinfo \
    || fail 'Anechoic build record has an unexpected source commit'
  grep -Fqx 'source_sha256=40bc93f8fa4b99205ecc5a948f4edceb52f9d54098ed5cd62a4ad42372ff9ad4' \
    /usr/share/doors/anechoic/buildinfo \
    || fail 'Anechoic build record has an unexpected source hash'
  echo '40bc93f8fa4b99205ecc5a948f4edceb52f9d54098ed5cd62a4ad42372ff9ad4  /usr/share/doors/anechoic/anechoic-061038dd98d45abef5fc22ae9c27b289b50b180c.tar.gz' \
    | sha256sum --check --status \
    || fail 'Anechoic source archive does not match the audited build record'
  grep -Fq 'GNU GENERAL PUBLIC LICENSE' /usr/share/licenses/anechoic/LICENSE \
    || fail 'Anechoic GPL license text is missing'

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
  # Bazaar, Gear Lever, and their Flatpak-declared runtime dependencies.
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
  if find /etc/flatpak/remotes.d -maxdepth 1 -type f -name '*.flatpakrepo' ! -name 'flathub.flatpakrepo' -print -quit | grep -q .; then
    fail 'unapproved static Flatpak remote metadata remains under /etc'
  fi
  if [[ -d /usr/share/flatpak/remotes.d ]] \
    && find /usr/share/flatpak/remotes.d -maxdepth 1 -type f -name '*.flatpakrepo' -print -quit | grep -q .; then
    fail 'unapproved vendor static Flatpak remote metadata remains'
  fi
  while IFS= read -r remote; do
    [[ -z "${remote}" || "${remote}" == 'flathub' ]] \
      || fail "unapproved system Flatpak remote remains: ${remote}"
  done < <(/usr/bin/flatpak remotes --system --columns=name 2>/dev/null || true)
  # Flatpak normalizes a configured trailing slash away in `remote-url` output.
  # Compare the canonicalized endpoint while keeping the reviewed descriptor's
  # exact URL (and its signing key) above as the source of truth.
  flatpak_remote_url="$(/usr/bin/flatpak --system remote-url flathub 2>/dev/null || true)"
  [[ -n "${flatpak_remote_url}" ]] \
    || fail 'reviewed system Flathub remote is missing'
  [[ "${flatpak_remote_url%/}/" == 'https://dl.flathub.org/repo/' ]] \
    || fail 'system Flathub remote is not bound to the reviewed HTTPS endpoint'
  [[ -x /usr/libexec/doors/bootstrap-flatpaks.sh ]] \
    || fail 'Doors Flatpak bootstrap script is missing'
  grep -Fqx "  'io.github.kolunmi.Bazaar'" /usr/libexec/doors/bootstrap-flatpaks.sh \
    || fail 'Doors bootstrap must target Bazaar'
  if grep -Fq 'DistroShelf' /usr/libexec/doors/bootstrap-flatpaks.sh; then
    fail 'Doors bootstrap must not provision the retired Distrobox manager'
  fi
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
  wl_clip_persist_buildinfo='/usr/share/doors/third-party/wl-clip-persist.buildinfo'
  [[ -s "${wl_clip_persist_buildinfo}" ]] \
    || fail 'wl-clip-persist provenance record is missing'
  for provenance_line in \
    'repository=Linus789/wl-clip-persist' \
    'tag=v0.5.0' \
    'commit=e26fde01c13922e3a65049dafb7d5adfbc52626e' \
    'source_url=https://github.com/Linus789/wl-clip-persist/archive/e26fde01c13922e3a65049dafb7d5adfbc52626e.tar.gz' \
    'source_sha256=4f57033dae159b887168210bcc69de84ba5f43e7e39444e483297e6ccb4b747c'; do
    grep -Fqx "${provenance_line}" "${wl_clip_persist_buildinfo}" \
      || fail "wl-clip-persist provenance record is missing: ${provenance_line}"
  done
}
