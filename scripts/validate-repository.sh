#!/usr/bin/env bash
# Fast, dependency-light invariants for local use and required CI.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "${root}"

fail() { echo "VALIDATION FAIL: $*" >&2; exit 1; }
need_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
need_line() { grep -Fqx -- "$2" "$1" || fail "missing expected line in $1: $2"; }

# BlueBuild recipes and workflow validation below intentionally depend on the
# same YAML parser available on Fedora and GitHub-hosted runners.
python3 -c 'import yaml' >/dev/null 2>&1 || fail 'PyYAML is required for repository validation'

# Parse every YAML document before inspecting its semantics.
while IFS= read -r -d '' yaml_file; do
  python3 - "$yaml_file" <<'PY'
import pathlib
import sys
import yaml
list(yaml.safe_load_all(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')))
PY
done < <(find recipes .github -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)

# Recipe/module semantics: four public recipe entry points, shared common
# modules, and strictly isolated desktop payloads.
python3 - <<'PY'
from pathlib import Path
import re
import yaml

root = Path('.')
recipe_dir = root / 'recipes'
expected_files = {
    'doors.yml', 'doors-staging.yml', 'doors-cosmic.yml', 'doors-kinoite.yml',
}
actual_files = {p.name for p in recipe_dir.glob('*.yml')}
if actual_files != expected_files:
    raise SystemExit(f'expected exactly four public recipe files, found {sorted(actual_files)}')


def load(path):
    data = yaml.safe_load(Path(path).read_text(encoding='utf-8'))
    if not isinstance(data, dict):
        raise SystemExit(f'{path} must contain one YAML mapping')
    return data

recipes = {name: load(recipe_dir / name) for name in expected_files}
modules = {name: load(recipe_dir / 'modules' / name) for name in (
    'common.yml', 'gnome.yml', 'cosmic.yml', 'kinoite.yml',
)}

specs = {
    'doors.yml': {
        'name': 'doors',
        'base': 'ghcr.io/blue-build/base-images/fedora-silverblue-nvidia-open',
        'tag': 'latest', 'profile': 'gnome.yml',
    },
    'doors-staging.yml': {
        'name': 'doors',
        'base': 'ghcr.io/blue-build/base-images/fedora-silverblue-nvidia-open',
        'tag': 'staging', 'profile': 'gnome.yml',
    },
    'doors-cosmic.yml': {
        'name': 'doors-cosmic',
        'base': 'ghcr.io/blue-build/base-images/fedora-cosmic-nvidia-open',
        'tag': 'latest', 'profile': 'cosmic.yml',
    },
    'doors-kinoite.yml': {
        'name': 'doors-kinoite',
        'base': 'ghcr.io/blue-build/base-images/fedora-kinoite-nvidia-open',
        'tag': 'latest', 'profile': 'kinoite.yml',
    },
}
for filename, spec in specs.items():
    recipe = recipes[filename]
    if recipe.get('version') != 1:
        raise SystemExit(f'{filename} must remain a version 1 recipe')
    if recipe.get('name') != spec['name']:
        raise SystemExit(f'{filename} has an unexpected OCI package name')
    if recipe.get('base-image') != spec['base'] or recipe.get('image-version') != 44:
        raise SystemExit(f'{filename} must use its exact Fedora 44 NVIDIA Open base')
    if recipe.get('blue-build-tag') != 'none' or recipe.get('platforms') != ['linux/amd64']:
        raise SystemExit(f'{filename} must remain BlueBuild-none and amd64-only')
    if recipe.get('alt-tags') != [spec['tag']]:
        raise SystemExit(f'{filename} must expose exactly its approved public tag')
    labels = recipe.get('labels', {})
    if labels.get('org.opencontainers.image.source') != 'https://github.com/mheci/doors':
        raise SystemExit(f'{filename} must retain the public source OCI label')
    if labels.get('org.opencontainers.image.licenses') != 'Apache-2.0':
        raise SystemExit(f'{filename} must retain the license OCI label')
    stages = recipe.get('stages')
    if not isinstance(stages, list) or len(stages) != 1:
        raise SystemExit(f'{filename} must contain exactly one disposable build stage')
    stage = stages[0]
    if stage.get('name') != 'wl-clip-persist-build' or stage.get('from') != f"{spec['base']}:44":
        raise SystemExit(f'{filename} must pin its wl-clip-persist stage to its Fedora 44 base')
    stage_modules = stage.get('modules', [])
    if stage_modules != [{'type': 'script', 'scripts': ['build-wl-clip-persist.sh']}]:
        raise SystemExit(f'{filename} has an unexpected disposable build-stage contract')
    expected_recipe_modules = [
        {'from-file': 'modules/common.yml'},
        {'from-file': f"modules/{spec['profile']}"},
        {'type': 'signing'},
    ]
    if recipe.get('modules') != expected_recipe_modules:
        raise SystemExit(f'{filename} must compose common, its isolated profile, then signing')
    raw = (recipe_dir / filename).read_text(encoding='utf-8')
    if ':latest' in raw:
        raise SystemExit(f'{filename} must pin every base/stage image to Fedora 44, not latest')
    if re.search(r'(^|\s)type:\s*akmods\b|synchronize-nvidia-mesa\.sh', raw):
        raise SystemExit(f'{filename} must not layer a second akmods/Mesa path')
    if 'bazzite' in raw.lower():
        raise SystemExit(f'{filename} must use the approved BlueBuild NVIDIA Open base, not Bazzite')

stable = recipes['doors.yml']
staging = recipes['doors-staging.yml']
for key in ('name', 'base-image', 'image-version', 'blue-build-tag', 'platforms', 'labels', 'stages', 'modules'):
    if staging.get(key) != stable.get(key):
        raise SystemExit(f'doors-staging.yml must match stable GNOME composition for {key}')
if 'latest' in staging.get('alt-tags', []):
    raise SystemExit('staging must not mutate the stable latest tag')

common = modules['common.yml'].get('modules')
if not isinstance(common, list):
    raise SystemExit('common module list is missing')
common_files = [entry for entry in common if entry.get('type') == 'files']
if len(common_files) != 2:
    raise SystemExit('common module must own only shared payload and generated Herdr files')
common_sources = [entry.get('files', [{}])[0].get('source') for entry in common_files]
if common_sources != ['common', 'generated/herdr']:
    raise SystemExit('common file modules must not copy a desktop-profile tree')
if any(entry.get('type') == 'gnome-extensions' for entry in common):
    raise SystemExit('common module must not install GNOME Shell extensions')
common_dnf = next((entry for entry in common if entry.get('type') == 'dnf'), None)
if not isinstance(common_dnf, dict):
    raise SystemExit('common RPM module is missing')
repos = common_dnf.get('repos', {})
if repos.get('nonfree') != 'negativo17' or repos.get('cleanup') is not True:
    raise SystemExit('common RPM module must retain the reviewed Negativo17 repository policy')
if repos.get('files') != ['terra.repo', 'brave-origin.repo', 'faugus.repo', 'helium.repo', 'ublue-packages.repo']:
    raise SystemExit('common RPM module has an unexpected repository set')
if repos.get('keys') != ['terra44.gpg', 'brave.gpg', 'faugus.gpg', 'helium.gpg', 'ublue-packages.gpg']:
    raise SystemExit('common RPM module has an unexpected signing-key set')
remove = common_dnf.get('remove', {})
if remove.get('auto-remove') is not False or remove.get('packages') != [
    'firefox', 'firefox-langpacks', 'brave-browser', 'gamemode', 'gamemode-libs',
]:
    raise SystemExit('common RPM removal policy changed unexpectedly')
common_packages = common_dnf.get('install', {}).get('packages', [])
required_common = {
    'gamescope', 'steam', 'distrobox', 'podman', 'uupd', 'vicinae', 'ghostty',
    'zed', 'breeze-icon-theme', 'brave-origin', 'helium-bin', 'faugus-launcher',
}
if not required_common <= set(common_packages):
    raise SystemExit('common RPM baseline is missing a required host package')
for forbidden in ('nodejs', 'npm', 'pnpm', 'deno', 'mise', 't3code', 'opencode', 'cuda', 'cuda-toolkit'):
    if forbidden in common_packages:
        raise SystemExit(f'AI package is layered on the immutable host: {forbidden}')
if any('gnome-shell-extension-' in str(package) for package in common_packages):
    raise SystemExit('GNOME Shell extension RPMs must stay in the GNOME profile')
common_systemd = next((entry for entry in common if entry.get('type') == 'systemd'), None)
if not isinstance(common_systemd, dict):
    raise SystemExit('common systemd policy is missing')
expected_system_enabled = {
    'falcond.service', 'ananicy-cpp.service', 'scx_loader.service', 'doors-update.timer',
    'doors-flatpak-bootstrap.service',
}
if set(common_systemd.get('system', {}).get('enabled', [])) != expected_system_enabled:
    raise SystemExit('common systemd enabled units changed unexpectedly')
if set(common_systemd.get('system', {}).get('disabled', [])) != {
    'uupd.timer', 'bootc-fetch-apply-updates.timer', 'flatpak-system-updates.timer',
    'podman-auto-update.timer',
}:
    raise SystemExit('common systemd disabled timer policy changed unexpectedly')
if set(common_systemd.get('user', {}).get('enabled', [])) != {
    'doors-ai-distrobox.service', 'vicinae.service', 'wl-clip-persist.service',
}:
    raise SystemExit('common user-unit policy changed unexpectedly')
if set(common_systemd.get('user', {}).get('disabled', [])) != {
    'flatpak-user-updates.timer', 'podman-auto-update.timer',
}:
    raise SystemExit('common user automatic-update timer policy changed unexpectedly')

profile_expectations = {
    'gnome.yml': ('profiles/gnome', 'verify-gnome-image.sh'),
    'cosmic.yml': ('profiles/cosmic', 'verify-cosmic-image.sh'),
    'kinoite.yml': ('profiles/kinoite', 'verify-kinoite-image.sh'),
}
for profile, (source, verifier) in profile_expectations.items():
    entries = modules[profile].get('modules')
    if not isinstance(entries, list) or not entries:
        raise SystemExit(f'{profile} profile module is empty')
    files_entry = entries[0]
    if files_entry.get('type') != 'files' or files_entry.get('files') != [{'source': source, 'destination': '/'}]:
        raise SystemExit(f'{profile} must copy only its profile source tree')
    rendered = (recipe_dir / 'modules' / profile).read_text(encoding='utf-8')
    if verifier not in rendered:
        raise SystemExit(f'{profile} must run its own image verifier')

# GNOME-only packages/configuration cannot leak into COSMIC or Plasma.
gnome_entries = modules['gnome.yml']['modules']
gnome_dnf = next((entry for entry in gnome_entries if entry.get('type') == 'dnf'), {})
if 'dconf' not in gnome_dnf.get('install', {}).get('packages', []):
    raise SystemExit('GNOME profile must own dconf')
if gnome_dnf.get('repos') != {'cleanup': True, 'files': ['terra.repo'], 'keys': ['terra44.gpg']}:
    raise SystemExit('GNOME profile must re-open only the reviewed Terra repository for its Terra extensions')
if not any(entry.get('type') == 'gnome-extensions' for entry in gnome_entries):
    raise SystemExit('GNOME profile must own GNOME extension installation')
if 'configure-gnome-defaults.sh' not in str(gnome_entries):
    raise SystemExit('GNOME profile must configure its own defaults')
for profile in ('cosmic.yml', 'kinoite.yml'):
    rendered = (recipe_dir / 'modules' / profile).read_text(encoding='utf-8').lower()
    if 'gnome-extensions' in rendered or 'configure-gnome-defaults' in rendered or 'profiles/gnome' in rendered:
        raise SystemExit(f'{profile} must not compose GNOME extensions/defaults')

cosmic_entries = modules['cosmic.yml']['modules']
cosmic_systemd = next((entry for entry in cosmic_entries if entry.get('type') == 'systemd'), {})
if cosmic_systemd.get('user', {}).get('enabled') != ['doors-cosmic-dark-defaults.service']:
    raise SystemExit('COSMIC profile must enable only its dark-default user service')
kinoite_entries = modules['kinoite.yml']['modules']
kinoite_dnf = next((entry for entry in kinoite_entries if entry.get('type') == 'dnf'), {})
if kinoite_dnf.get('install', {}).get('packages') != ['breeze-gtk']:
    raise SystemExit('Kinoite profile must use the native Breeze GTK package')

if (root / 'files/common/etc/dconf').exists():
    raise SystemExit('common image payload must not contain GNOME dconf')
dconf = root / 'files/profiles/gnome/etc/dconf/db/local.d/00-doors'
if not dconf.is_file():
    raise SystemExit('GNOME profile dconf defaults are missing')
if any((root / 'files/profiles' / profile / 'etc/dconf').exists() for profile in ('cosmic', 'kinoite')):
    raise SystemExit('COSMIC/Kinoite profile must not ship GNOME dconf')
cosmic_seed = root / 'files/profiles/cosmic/usr/libexec/doors/seed-cosmic-dark-defaults.sh'
cosmic_unit = root / 'files/profiles/cosmic/usr/lib/systemd/user/doors-cosmic-dark-defaults.service'
if not cosmic_seed.is_file() or not cosmic_unit.is_file():
    raise SystemExit('COSMIC dark-default payload is incomplete')
seed = cosmic_seed.read_text(encoding='utf-8')
if '[[ -e "${target}" ]] && exit 0' not in seed or 'if ! ln "${temporary}" "${target}" 2>/dev/null; then' not in seed:
    raise SystemExit('COSMIC seeder must preserve an existing user preference atomically')
if 'ConditionPathExists=!%h/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark' not in cosmic_unit.read_text(encoding='utf-8'):
    raise SystemExit('COSMIC dark-default unit must skip an existing default-path preference')
kdeglobals = root / 'files/profiles/kinoite/etc/xdg/kdeglobals'
if not kdeglobals.is_file():
    raise SystemExit('Kinoite Plasma defaults are missing')
kde = kdeglobals.read_text(encoding='utf-8')
for line in ('LookAndFeelPackage=org.kde.breezedark.desktop', 'ColorScheme=BreezeDark', 'Theme=breeze-dark'):
    if line not in kde:
        raise SystemExit(f'Kinoite must retain native Breeze Dark default: {line}')
kinoite_payload = '\n'.join(p.read_text(encoding='utf-8', errors='ignore') for p in (root / 'files/profiles/kinoite').rglob('*') if p.is_file())
if re.search(r'(?i)(valve|steamdeck|gamescope-session|steam-big-picture|steam-bpm)', kinoite_payload):
    raise SystemExit('Kinoite profile must not ship Valve assets or a Game Mode/Big Picture autostart')
if (root / 'files/profiles/kinoite/etc/xdg/autostart').exists():
    raise SystemExit('Kinoite profile must not create desktop autostart entries')
PY

# Shared host/update/Flatpak contract.
need_file files/scripts/configure-uupd.sh
need_file files/scripts/enforce-flatpak-policy.sh
need_file files/common/usr/lib/systemd/system/doors-flatpak-bootstrap.service
need_file files/common/usr/lib/systemd/system/doors-update.service
need_file files/common/usr/lib/systemd/system/doors-update.timer
need_file files/common/usr/lib/systemd/user/doors-user-update.service
need_file files/common/usr/libexec/doors/bootstrap-flatpaks.sh
need_file files/common/usr/libexec/doors/update-system.sh
need_file files/common/usr/libexec/doors/update-user.sh
need_line files/common/usr/lib/systemd/system/doors-flatpak-bootstrap.service 'ExecStart=/usr/libexec/doors/bootstrap-flatpaks.sh'
need_line files/common/usr/lib/systemd/system/doors-flatpak-bootstrap.service 'WantedBy=multi-user.target'
need_line files/common/usr/lib/systemd/system/doors-update.service 'ExecStart=/usr/libexec/doors/update-system.sh'
need_line files/common/usr/lib/systemd/system/doors-update.timer 'Persistent=true'
need_line files/common/usr/lib/systemd/user/doors-user-update.service 'ExecStart=/usr/libexec/doors/update-user.sh'
need_line files/common/usr/libexec/doors/bootstrap-flatpaks.sh "  'io.github.kolunmi.Bazaar'"
need_line files/common/usr/libexec/doors/bootstrap-flatpaks.sh "  'com.ranfdev.DistroShelf'"
need_line files/common/usr/libexec/doors/bootstrap-flatpaks.sh "  'it.mijorus.gearlever'"
need_line files/common/usr/libexec/doors/bootstrap-flatpaks.sh '/usr/bin/flatpak --system install --noninteractive --or-update "${remote}" "${app_ids[@]}"'
for managed_update_fragment in \
  'regular_local_users() {' \
  'loginctl enable-linger "${user}"' \
  '/usr/bin/systemctl --user start --wait doors-user-update.service' \
  'unlabelled-container-not-auto-updated'; do
  grep -Fq -- "${managed_update_fragment}" files/common/usr/libexec/doors/update-system.sh \
    || fail "missing managed system-update behavior: ${managed_update_fragment}"
done
for managed_update_fragment in \
  'flatpak run it.mijorus.gearlever --update --all --yes' \
  'metadata-free-artifacts-are-never-executed' \
  'archive-no-update-metadata' \
  'unlabelled-container-not-auto-updated'; do
  grep -Fq -- "${managed_update_fragment}" files/common/usr/libexec/doors/update-user.sh \
    || fail "missing managed user-update behavior: ${managed_update_fragment}"
done
if grep -Eq '^[^#]*it\.mijorus\.gearlever.*--force' files/common/usr/libexec/doors/update-user.sh; then
  fail 'managed Gear Lever AppImage updates must not use --force'
fi
need_file files/common/etc/flatpak/remotes.d/flathub.flatpakrepo
need_line files/common/etc/flatpak/remotes.d/flathub.flatpakrepo '[Flatpak Repo]'
need_line files/common/etc/flatpak/remotes.d/flathub.flatpakrepo 'Url=https://dl.flathub.org/repo/'
need_line files/scripts/enforce-flatpak-policy.sh "readonly flathub_repo='/etc/flatpak/remotes.d/flathub.flatpakrepo'"
grep -Fq '"distrobox": {' files/scripts/configure-uupd.sh \
  || fail 'uupd must retain its Distrobox update module declaration'
grep -Fq '"flatpak": {' files/scripts/configure-uupd.sh \
  || fail 'uupd must retain its Flatpak update module declaration'
grep -Fq '"system": {' files/scripts/configure-uupd.sh \
  || fail 'uupd must retain its bootc/system update module'
python3 - <<'PY'
import json
from pathlib import Path

script = Path('files/scripts/configure-uupd.sh').read_text(encoding='utf-8')
payload = script.split("<<'JSON'\n", 1)[1].split('\nJSON\n', 1)[0]
config = json.loads(payload)
modules = config.get('modules', {})
if modules.get('system', {}).get('disable') is not False:
    raise SystemExit('uupd system module must remain enabled')
for module in ('brew', 'distrobox', 'flatpak'):
    if modules.get(module, {}).get('disable') is not True:
        raise SystemExit(f'uupd {module} module must be disabled under the Doors coordinator')
PY
[[ ! -e files/common/usr/lib/systemd/system/flatpak-preinstall.service ]] \
  || fail 'retired Flatpak preinstall service must not remain'
[[ ! -e files/common/usr/lib/systemd/system/doors-flatpak-bazaar.service ]] \
  || fail 'retired single-Flatpak bootstrap unit must not remain'
[[ ! -e files/scripts/synchronize-nvidia-mesa.sh ]] \
  || fail 'retired Bluefin/akmods Mesa synchronization script must not remain'
need_file files/systemd/user/wl-clip-persist.service
need_line files/systemd/user/wl-clip-persist.service 'ExecStart=/usr/local/bin/wl-clip-persist --clipboard regular'

# Arch Distrobox trust boundary. No Fedora/Terra/NVIDIA repository material may
# survive under the mounted immutable Distrobox payload.
distrobox_root='files/common/usr/share/doors/distrobox'
need_file "${distrobox_root}/doors-ai.ini"
need_file "${distrobox_root}/bootstrap-ai.sh"
need_file "${distrobox_root}/keys/bun-release-key.asc"
need_file "${distrobox_root}/herdr/.gitkeep"
need_file files/common/usr/bin/doors-ai
need_file files/common/usr/lib/systemd/user/doors-ai-distrobox.service
need_line "${distrobox_root}/doors-ai.ini" 'image=docker.io/library/archlinux:latest'
need_line "${distrobox_root}/doors-ai.ini" 'nvidia=true'
need_line "${distrobox_root}/doors-ai.ini" 'volume="/usr/share/doors/distrobox:/opt/doors:ro"'
need_line "${distrobox_root}/bootstrap-ai.sh" 'as_root pacman -Syu --noconfirm --needed \'
need_line "${distrobox_root}/bootstrap-ai.sh" '  archlinux-keyring \'
need_line "${distrobox_root}/bootstrap-ai.sh" '  base-devel git nodejs npm pnpm python python-pip deno mise opencode cuda'
need_line "${distrobox_root}/bootstrap-ai.sh" "readonly pi_package='@earendil-works/pi-coding-agent'"
need_line "${distrobox_root}/bootstrap-ai.sh" "readonly t3_package='t3'"
grep -Fq "npm_config_registry='https://registry.npmjs.org/'" "${distrobox_root}/bootstrap-ai.sh" \
  || fail 'Doors AI npm installs must use the canonical npm registry'
grep -Fq 'npm install --global --omit=dev --ignore-scripts' "${distrobox_root}/bootstrap-ai.sh" \
  || fail 'Doors AI npm installs must preserve lifecycle-script hardening'
grep -Fq '"${doors_dir}/herdr/herdr-linux-x86_64"' "${distrobox_root}/bootstrap-ai.sh" \
  || fail 'Doors AI bootstrap must require attestation-verified Herdr'
grep -Fq 'doors-ai recreate' files/common/usr/bin/doors-ai \
  || fail 'Doors AI launcher must offer explicit safe migration for old containers'
if grep -Ein '(dnf|yum|fedora-toolbox|cuda-fedora|terra44|/etc/yum\.repos\.d)' "${distrobox_root}/bootstrap-ai.sh" "${distrobox_root}/doors-ai.ini"; then
  fail 'Arch Distrobox payload retains Fedora/Terra/NVIDIA repository bootstrap logic'
fi
if grep -Eq '^[[:space:]]*nvidia-utils([[:space:]]|$)' "${distrobox_root}/bootstrap-ai.sh"; then
  fail 'Arch Distrobox must receive GPU access from Distrobox NVIDIA integration, not nvidia-utils'
fi
[[ ! -e "${distrobox_root}/repos" && ! -e "${distrobox_root}/profile.d" ]] \
  || fail 'obsolete Distrobox repository/profile assets remain'
[[ ! -e "${distrobox_root}/keys/RPM-GPG-KEY-NVIDIA-CUDA" && ! -e "${distrobox_root}/keys/RPM-GPG-KEY-terra44" ]] \
  || fail 'obsolete Distrobox RPM trust keys remain'
[[ "$(find "${distrobox_root}/keys" -type f -printf '%f\n' | sort)" == 'bun-release-key.asc' ]] \
  || fail 'Distrobox key directory must contain only the reviewed Bun release key'

# Fedora 44 pinning applies to all host RPM repository routes.
for repo_file in files/dnf/terra.repo files/dnf/faugus.repo files/dnf/helium.repo files/dnf/ublue-packages.repo; do
  if grep -Fq '$releasever' "${repo_file}"; then
    fail "repository must use an explicit Fedora 44 stream: ${repo_file}"
  fi
done
need_line files/dnf/terra.repo 'name=Terra 44'
need_line files/dnf/terra.repo 'metalink=https://tetsudou.fyralabs.com/metalink?repo=terra44&arch=$basearch'
need_line files/dnf/faugus.repo 'baseurl=https://download.copr.fedorainfracloud.org/results/faugus/faugus-launcher/fedora-44-$basearch/'
need_line files/dnf/helium.repo 'baseurl=https://download.copr.fedorainfracloud.org/results/imput/helium/fedora-44-$basearch/'
need_line files/dnf/ublue-packages.repo 'baseurl=https://download.copr.fedorainfracloud.org/results/ublue-os/packages/fedora-44-$basearch/'
for repo in files/dnf/terra.repo files/dnf/brave-origin.repo files/dnf/faugus.repo files/dnf/helium.repo files/dnf/ublue-packages.repo; do
  need_line "$repo" 'gpgcheck=1'
  need_line "$repo" 'skip_if_unavailable=False'
done
need_line files/dnf/terra.repo 'repo_gpgcheck=1'
need_line files/dnf/brave-origin.repo 'repo_gpgcheck=1'
need_line files/dnf/faugus.repo 'repo_gpgcheck=0'
need_line files/dnf/helium.repo 'repo_gpgcheck=0'
need_line files/dnf/ublue-packages.repo 'repo_gpgcheck=0'
need_line files/dnf/ublue-packages.repo 'includepkgs=uupd'
need_line files/dnf/terra.repo 'excludepkgs=faugus-launcher'
need_line files/dnf/faugus.repo 'includepkgs=faugus-launcher'
need_line files/dnf/faugus.repo 'priority=50'
need_line files/dnf/helium.repo 'includepkgs=helium-bin'
need_line files/dnf/brave-origin.repo 'includepkgs=brave-origin brave-keyring'
need_file files/scripts/harden-brave-keyring.sh
need_line files/scripts/harden-brave-keyring.sh 'rm -f /usr/libexec/brave-key-updater'

# Required GNOME profile default remains user-overridable and wallpaper-free.
dconf_defaults='files/profiles/gnome/etc/dconf/db/local.d/00-doors'
need_file "${dconf_defaults}"
for expected in \
  "color-scheme='prefer-dark'" "gtk-theme='Yaru-dark'" "font-name='Inter 11'" \
  "monospace-font-name='JetBrains Mono 11'" "dock-position='LEFT'" 'dock-fixed=true' \
  'autohide=false' 'enable-clipboard-monitoring=true' "binding='<Super><Shift>space'" \
  "custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae-toggle/']" \
  '[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae-toggle]'; do
  need_line "${dconf_defaults}" "${expected}"
done
if grep -Fq 'custom-keybinding:/' "${dconf_defaults}"; then
  fail 'dconf keyfiles must use path sections, not colon-qualified GSettings CLI syntax'
fi
for extension in \
  dash-to-dock@micxgx.gmail.com appindicatorsupport@rgcjonas.gmail.com \
  gsconnect@andyholmes.github.io clipboard-indicator@tudmotu.com \
  grand-theft-focus@zalckos.github.com just-perfection-desktop@just-perfection \
  AlphabeticalAppGrid@stuarthayhurst vicinae@dagimg-dot.netlify.app emoji-copy@felipeftn; do
  grep -Fq "${extension}" "${dconf_defaults}" \
    || fail "required GNOME extension default is absent: ${extension}"
done
if grep -Eq '(^|[[:space:]])(picture-uri|picture-uri-dark|primary-color|secondary-color)[[:space:]]*=' "${dconf_defaults}"; then
  fail 'the GNOME profile must not impose a wallpaper/background default'
fi

# CI composition and supply-chain semantics. Matrix outputs are deliberately
# avoided: each trusted build writes an immutable image identity artifact that
# a distinct fresh runner validates, scans, and attests.
python3 - <<'PY'
from pathlib import Path
import re
import yaml


def load(path):
    return yaml.safe_load(Path(path).read_text(encoding='utf-8'))


def includes(job):
    return job.get('strategy', {}).get('matrix', {}).get('include', [])


def named_steps(job, name):
    return [s for s in job.get('steps', []) if s.get('name') == name]

build_path = Path('.github/workflows/build.yml')
staging_path = Path('.github/workflows/staging.yml')
build_raw = build_path.read_text(encoding='utf-8')
staging_raw = staging_path.read_text(encoding='utf-8')
build = load(build_path)
staging = load(staging_path)
jobs = build.get('jobs', {})
required = {'contract', 'verification', 'image', 'image_publish', 'publish'}
if not required <= set(jobs):
    raise SystemExit(f'stable workflow lacks required jobs: {sorted(required - set(jobs))}')
if 'schedule:' in build_raw or 'doors-staging.yml' in build_raw:
    raise SystemExit('stable workflow must not publish staging or carry its schedule')
if 'doors-trusted-publication' not in str(build.get('concurrency', {}).get('group', '')):
    raise SystemExit('trusted stable publication must share the staging publication lock')
verification = jobs['verification']
verify_include = includes(verification)
expected_verify = {
    ('doors', 'doors.yml'), ('doors-cosmic', 'doors-cosmic.yml'), ('doors-kinoite', 'doors-kinoite.yml'),
}
if {(row.get('id'), row.get('recipe')) for row in verify_include} != expected_verify:
    raise SystemExit('verification matrix must build every stable public recipe exactly once')
verification_build_steps = [
    step for step in verification.get('steps', [])
    if str(step.get('uses', '')).startswith('blue-build/github-action@')
]
if len(verification_build_steps) != 2 or any(step.get('with', {}).get('push') is not False for step in verification_build_steps) or '${{ secrets.SIGNING_SECRET }}' in str(verification):
    raise SystemExit('untrusted verification must be non-publishing, secret-free, and retry at most once')
archive_dir = '${{ runner.temp }}/doors-candidate'
if any(step.get('env', {}).get('BB_BUILD_ARCHIVE') != archive_dir for step in verification_build_steps):
    raise SystemExit('every verification composition attempt must emit the reviewed OCI candidate archive')

boot_step_names = {
    'Prepare non-published candidate archive',
    'Fail closed if retry did not recover',
    'Materialize ${{ matrix.id }} candidate as a QCOW2 disk',
    'Boot ${{ matrix.id }} QCOW2 with direct os-autoinst',
    'Upload failed boot-validation evidence',
}
boot_steps = {step.get('name'): step for step in verification.get('steps', []) if step.get('name') in boot_step_names}
if set(boot_steps) != boot_step_names:
    raise SystemExit(f'verification boot gate lacks required steps: {sorted(boot_step_names - set(boot_steps))}')
archive_step = boot_steps['Prepare non-published candidate archive']
materialize_step = boot_steps['Materialize ${{ matrix.id }} candidate as a QCOW2 disk']
boot_step = boot_steps['Boot ${{ matrix.id }} QCOW2 with direct os-autoinst']
upload_step = boot_steps['Upload failed boot-validation evidence']
if 'mkdir -p "${RUNNER_TEMP}/doors-candidate"' not in archive_step.get('run', ''):
    raise SystemExit('verification must prepare the BlueBuild archive directory')
if materialize_step.get('env', {}).get('CANDIDATE_ARCHIVE') != '${{ runner.temp }}/doors-candidate/${{ matrix.id }}.tar.gz':
    raise SystemExit('verification must convert the exact per-matrix BlueBuild archive')
materialize_run = materialize_step.get('run', '')
for required_fragment in ('test -s "${CANDIDATE_ARCHIVE}"', 'sha256sum "${CANDIDATE_ARCHIVE}"', 'oci-archive:${CANDIDATE_ARCHIVE}', 'containers-storage:${CANDIDATE_IMAGE}', 'BOOTC_IMAGE_BUILDER', 'build', '--type qcow2', '--output /output', '--config /config.toml', '${CANDIDATE_IMAGE}'):
    if required_fragment not in materialize_run:
        raise SystemExit(f'verification boot conversion is missing: {required_fragment}')
if materialize_step.get('env', {}).get('BOOTC_IMAGE_BUILDER') != 'ghcr.io/osbuild/bootc-image-builder:v83.0.0@sha256:e7aadce6b3f5639cd47d83354791931ea219891a0d113c2fe74a0f0d352b165c':
    raise SystemExit('verification bootc-image-builder must remain the reviewed pinned image')
for required_fragment in ('[[customizations.filesystem]]', 'mountpoint = "/"', 'minsize = "40 GiB"', 'console=tty0 console=ttyS0,115200n8'):
    if required_fragment not in materialize_run:
        raise SystemExit(f'verification QCOW2 conversion is missing required test-disk configuration: {required_fragment}')
boot_run = boot_step.get('run', '')
for required_fragment in ('--exit-status-from-test-results', 'QEMU_NO_KVM=1', 'CASEDIR=/tests', 'HDD_1=qcow2/disk.qcow2', 'UEFI=1', 'QEMURAM=4096', 'SCHEDULE=tests/boot.pm'):
    if required_fragment not in boot_run:
        raise SystemExit(f'verification os-autoinst invocation is missing: {required_fragment}')
if '_EXIT_AFTER_SCHEDULE' in boot_run:
    raise SystemExit('verification must run the scheduled boot test, not exit after loading it')
if boot_step.get('env', {}).get('ISOTOVIDEO_IMAGE') != 'registry.opensuse.org/devel/openqa/containers/isotovideo:qemu-x86@sha256:273253ef539b8d78bdb0f235831222c1270da1b65d88c680e1a59b67be7dadcf':
    raise SystemExit('verification isotovideo runner must remain the reviewed pinned no-KVM image')
if 'boot-test:/tests:ro' not in boot_run or 'boot-test/artifacts:/work' not in boot_run:
    raise SystemExit('verification os-autoinst gate must use the repository-local test and artifact directory')
if upload_step.get('if') != 'failure()' or 'boot-test/artifacts' not in str(upload_step):
    raise SystemExit('verification must upload boot diagnostics only on failure')
if any('openqa-worker' in str(step).lower() or 'openqa-webui' in str(step).lower() for step in verification.get('steps', [])):
    raise SystemExit('verification must use direct os-autoinst, not deploy openQA infrastructure')
image = jobs['image']
if image.get('name') != 'image' or image.get('needs') != 'verification' or 'always()' not in str(image.get('if', '')):
    raise SystemExit('protected image aggregate must fail closed after the verification matrix')
publish_build = jobs['image_publish']
expected_publish = {
    ('doors', 'doors.yml', 'doors', 'latest'),
    ('doors-cosmic', 'doors-cosmic.yml', 'doors-cosmic', 'latest'),
    ('doors-kinoite', 'doors-kinoite.yml', 'doors-kinoite', 'latest'),
}
if {(row.get('id'), row.get('recipe'), row.get('package'), row.get('tag')) for row in includes(publish_build)} != expected_publish:
    raise SystemExit('stable publication matrix must cover exactly the three stable OCI packages')
if publish_build.get('environment') != 'ghcr-publish' or publish_build.get('permissions', {}).get('id-token') is not None:
    raise SystemExit('image publication must use protected signing environment without OIDC attestation token')
if 'github.repository == \'mheci/doors\'' not in str(publish_build.get('if', '')) or "github.ref == 'refs/heads/main'" not in str(publish_build.get('if', '')):
    raise SystemExit('stable publication must be restricted to trusted main')
publication_build_steps = [
    step for step in publish_build.get('steps', [])
    if str(step.get('uses', '')).startswith('blue-build/github-action@')
]
if len(publication_build_steps) != 2 or any(step.get('with', {}).get('push') is not True for step in publication_build_steps) or 'actions/upload-artifact@' not in str(publish_build):
    raise SystemExit('each stable publication must push and hand off an immutable identity artifact')
if publish_build.get('outputs'):
    raise SystemExit('matrix publication must not rely on unreliable matrix outputs')
publish = jobs['publish']
if publish.get('needs') != 'image_publish' or publish.get('permissions', {}).get('attestations') != 'write' or publish.get('permissions', {}).get('id-token') != 'write':
    raise SystemExit('fresh-runner stable release checks must wait for publication with OIDC attestation permissions')
if {(row.get('id'), row.get('package'), row.get('tag')) for row in includes(publish)} != {
    ('doors', 'doors', 'latest'), ('doors-cosmic', 'doors-cosmic', 'latest'), ('doors-kinoite', 'doors-kinoite', 'latest'),
}:
    raise SystemExit('fresh-runner stable release matrix must match published packages')
for step in ('Download immutable image identity', 'Validate immutable image identity', 'Install checksum-verified Trivy', 'Generate SPDX SBOM for immutable image digest', 'Attest build provenance with GitHub OIDC', 'Attest SPDX SBOM with GitHub OIDC'):
    if len(named_steps(publish, step)) != 1:
        raise SystemExit(f'fresh-runner stable release job lacks required step: {step}')
if 'needs.image_publish.outputs' in build_raw:
    raise SystemExit('fresh-runner release must consume artifact identity, not matrix outputs')
if '"${IMAGE}@${DIGEST}"' not in build_raw or 'subject-digest: ${{ env.DIGEST }}' not in build_raw:
    raise SystemExit('stable SBOM/provenance attestations must target the immutable digest')

staging_jobs = staging.get('jobs', {})
if set(staging_jobs) != {'contract', 'image_publish', 'publish'}:
    raise SystemExit('daily staging workflow must contain only contract, publication, and fresh-runner release jobs')
if re.search(r'^  (?:push|pull_request|merge_group):', staging_raw, re.MULTILINE):
    raise SystemExit('staging must be daily/manual only, never run on every stable event')
if "- cron: '20 3 * * *'" not in staging_raw:
    raise SystemExit('staging must have an explicit daily schedule')
if 'doors-trusted-publication' not in str(staging.get('concurrency', {}).get('group', '')):
    raise SystemExit('trusted staging publication must share the stable publication lock')
staging_publish = staging_jobs['image_publish']
if staging_publish.get('environment') != 'ghcr-publish' or staging_publish.get('permissions', {}).get('id-token') is not None:
    raise SystemExit('staging publication must use protected signing environment without OIDC attestation token')
staging_build_steps = [
    step for step in staging_publish.get('steps', [])
    if str(step.get('uses', '')).startswith('blue-build/github-action@')
]
if len(staging_build_steps) != 2 or any(step.get('with', {}).get('recipe') != 'doors-staging.yml' or step.get('with', {}).get('push') is not True for step in staging_build_steps) or 'IMAGE: ghcr.io/mheci/doors' not in staging_raw or 'TAG: staging' not in staging_raw:
    raise SystemExit('staging must publish ghcr.io/mheci/doors:staging from its dedicated recipe')
if 'ghcr.io/mheci/doors-staging' in staging_raw or re.search(r'(?m)^\s*package:\s*doors-staging\s*$', staging_raw):
    raise SystemExit('staging must not create a separate doors-staging OCI package')
record_steps = named_steps(staging_publish, 'Record stable latest digest before staging build')
resolve_steps = named_steps(staging_publish, 'Resolve immutable staging digest')
if len(record_steps) != 1 or len(resolve_steps) != 1:
    raise SystemExit('staging must record and then re-check the stable latest digest')
if '${IMAGE}:latest' not in record_steps[0].get('run', '') or 'STABLE_LATEST_DIGEST=' not in record_steps[0].get('run', ''):
    raise SystemExit('staging pre-build check must record doors:latest under the shared lock')
resolve_run = resolve_steps[0].get('run', '')
if 'latest_after=' not in resolve_run or 'latest_after}" == "${STABLE_LATEST_DIGEST}' not in resolve_run:
    raise SystemExit('staging post-build check must fail if doors:latest changes')
staging_release = staging_jobs['publish']
if staging_release.get('needs') != 'image_publish' or staging_release.get('permissions', {}).get('attestations') != 'write' or staging_release.get('permissions', {}).get('id-token') != 'write':
    raise SystemExit('staging fresh-runner release job must attest the published digest')
for step in ('Download immutable staging identity', 'Validate immutable staging identity', 'Install checksum-verified Trivy', 'Generate SPDX SBOM for immutable staging digest', 'Attest build provenance with GitHub OIDC', 'Attest SPDX SBOM with GitHub OIDC'):
    if len(named_steps(staging_release, step)) != 1:
        raise SystemExit(f'staging fresh-runner release job lacks required step: {step}')
if '"${IMAGE}@${DIGEST}"' not in staging_raw or 'subject-digest: ${{ env.DIGEST }}' not in staging_raw:
    raise SystemExit('staging SBOM/provenance attestations must target the immutable digest')

# Every action is commit-pinned, including identity handoff actions.
for workflow in Path('.github/workflows').glob('*.yml'):
    for line in workflow.read_text(encoding='utf-8').splitlines():
        match = re.match(r'\s*uses:\s*([^\s#]+)', line)
        if match and not re.search(r'@[0-9a-f]{40}$', match.group(1)):
            raise SystemExit(f'action is not commit-pinned: {workflow}: {match.group(1)}')
PY

# The direct os-autoinst distribution stays repository-local and deliberately
# read-only: it observes a serial boot rather than interacting with a guest.
need_file boot-test/main.pm
need_file boot-test/tests/boot.pm
need_line boot-test/main.pm "autotest::loadtest 'tests/boot.pm';"
for boot_gate_fragment in \
  'Linux[ ]version' \
  'systemd[[]1[]]:' \
  'Kernel[ ]panic' \
  'Entering[ ]emergency[ ]mode' \
  'expect_not_found => 1' \
  'wait_serial'; do
  grep -Fq -- "${boot_gate_fragment}" boot-test/tests/boot.pm \
    || fail "boot validation lacks required serial gate: ${boot_gate_fragment}"
done
need_line boot-test/tests/boot.pm "    die 'Doors boot gate observed a fatal serial signature after boot completion' if defined \$fatal_after_boot;"
if grep -Eqi '(type_string|send_key|script_run|assert_script_run|mouse_|ssh)' boot-test/tests/boot.pm; then
  fail 'boot validation must remain serial-observation-only until guest access is explicitly reviewed'
fi

# Dependency automation retains protected PR merge enforcement and action-pin
# ownership separation between Dependabot and Renovate.
need_file .github/dependabot.yml
need_file .github/workflows/dependabot-automerge.yml
need_file .github/workflows/dependabot-main-reconciliation.yml
need_file .github/workflows/dependency-review.yml
need_file .github/workflows/scorecard.yml
need_file .github/workflows/codeql.yml
need_file SECURITY.md
need_line .github/workflows/dependabot-automerge.yml '      - Build and publish stable Doors images'
need_line .github/dependabot.yml '  - package-ecosystem: github-actions'
need_line .github/dependabot.yml '      interval: daily'
need_line SECURITY.md 'Instead, submit a [private vulnerability report](https://github.com/mheci/doors/security/advisories/new) for `mheci/doors`. Include:'
need_line SECURITY.md 'We aim to acknowledge a vulnerability report within **7 days**, privately assess and begin mitigation within **30 days**, and coordinate disclosure with the reporter. A public disclosure target is normally no later than **90 days**, unless mitigation, active exploitation, or reporter coordination requires a different timeline. Never attach a Cosign private key, `SIGNING_SECRET`, registry token, generated Herdr artifact, or a live attestation download URL to an issue/PR.'
grep -Fq 'gh pr merge "${pr_number}"' .github/workflows/dependabot-automerge.yml \
  || fail 'Dependabot merge reconciliation must use a validated pull request number'
grep -Fq 'if [[ "${mergeable_state}" == '\''clean'\'' ]]' .github/workflows/dependabot-automerge.yml \
  || fail 'Dependabot must handle GitHub auto-merge rejection for an already-clean protected PR'
grep -Fq -- '--match-head-commit "${head_sha}"' .github/workflows/dependabot-automerge.yml \
  || fail 'Dependabot merge reconciliation must bind to its immutable head SHA'
python3 - <<'PY'
import json
from pathlib import Path
import re
import subprocess
import yaml


def load(path):
    data = yaml.safe_load(Path(path).read_text(encoding='utf-8'))
    if not isinstance(data, dict):
        raise SystemExit(f'{path} must contain one YAML mapping')
    return data


codeql_path = Path('.github/workflows/codeql.yml')
codeql_raw = codeql_path.read_text(encoding='utf-8')
codeql = load(codeql_path)
if 'pull_request_target:' in codeql_raw:
    raise SystemExit('CodeQL must not run in pull_request_target context')
codeql_jobs = codeql.get('jobs', {})
if set(codeql_jobs) != {'analyze-actions'}:
    raise SystemExit('CodeQL must contain exactly the GitHub Actions analysis job')
codeql_job = codeql_jobs['analyze-actions']
if codeql_job.get('name') != 'analyze (actions)' or codeql_job.get('permissions') != {
    'actions': 'read', 'contents': 'read', 'security-events': 'write',
}:
    raise SystemExit('CodeQL Actions analysis must retain minimal scan permissions')
codeql_steps = codeql_job.get('steps', [])
if not any(
    re.fullmatch(r'actions/checkout@[0-9a-f]{40}', str(step.get('uses', '')))
    and step.get('with', {}).get('persist-credentials') is False
    for step in codeql_steps
):
    raise SystemExit('CodeQL must check out with a commit pin and no persisted credentials')
init_steps = [
    step for step in codeql_steps
    if re.fullmatch(r'github/codeql-action/init@[0-9a-f]{40}', str(step.get('uses', '')))
]
analyze_steps = [
    step for step in codeql_steps
    if re.fullmatch(r'github/codeql-action/analyze@[0-9a-f]{40}', str(step.get('uses', '')))
]
if len(init_steps) != 1 or len(analyze_steps) != 1:
    raise SystemExit('CodeQL must initialize and analyze with reviewed commit-pinned actions')
if init_steps[0]['uses'].rsplit('@', 1)[1] != analyze_steps[0]['uses'].rsplit('@', 1)[1]:
    raise SystemExit('CodeQL initialization and analysis must use the same reviewed action revision')
if init_steps[0].get('with') != {
    'languages': 'actions', 'build-mode': 'none', 'queries': '+security-extended',
} or analyze_steps[0].get('with', {}).get('category') != '/language:actions':
    raise SystemExit('CodeQL must scan GitHub Actions with the security-extended suite')

reconcile_path = Path('.github/workflows/dependabot-main-reconciliation.yml')
reconcile_raw = reconcile_path.read_text(encoding='utf-8')
reconcile = load(reconcile_path)
if 'pull_request_target:' in reconcile_raw or 'actions/checkout@' in reconcile_raw:
    raise SystemExit('Dependabot main reconciliation must not execute checked-out PR code')
for required_fragment in (
    'Dependabot auto-merge',
    "- cron: '11,26,41,56 * * * *'",
    'actions: write',
    'commits/${main_sha}/pulls',
    '.user.login == "dependabot[bot]"',
    '.merged_at != null',
    '.merge_commit_sha == $sha',
    'gh workflow run "${workflow_name}"',
    'Build and publish stable Doors images',
    'Policy and static validation',
    'already failed for current main',
):
    if required_fragment not in reconcile_raw:
        raise SystemExit(f'Dependabot main reconciliation is missing: {required_fragment}')
reconcile_jobs = reconcile.get('jobs', {})
if set(reconcile_jobs) != {'reconcile'}:
    raise SystemExit('Dependabot main reconciliation must contain exactly one trusted job')
reconcile_job = reconcile_jobs['reconcile']
if reconcile_job.get('permissions') != {'actions': 'write', 'contents': 'read'}:
    raise SystemExit('Dependabot main reconciliation must retain only dispatch/read permissions')
reconcile_steps = reconcile_job.get('steps', [])
if len(reconcile_steps) != 1 or not isinstance(reconcile_steps[0].get('run'), str):
    raise SystemExit('Dependabot main reconciliation must retain one API-only shell step')
try:
    subprocess.run(
        ['bash', '-n'], input=reconcile_steps[0]['run'], text=True,
        check=True, capture_output=True,
    )
except subprocess.CalledProcessError as error:
    raise SystemExit(
        'Dependabot main reconciliation shell syntax is invalid: '
        + error.stderr.strip()
    ) from error

config = json.loads(Path('renovate.json').read_text(encoding='utf-8'))
if not (config.get('automerge') is True and config.get('platformAutomerge') is True):
    raise SystemExit('Renovate must request native protected auto-merge')
if config.get('automergeType') != 'pr':
    raise SystemExit('Renovate must merge via pull requests, never direct pushes')
rules = config.get('packageRules', [])
if not any(rule.get('matchManagers') == ['github-actions'] and rule.get('enabled') is False for rule in rules):
    raise SystemExit('Renovate must leave GitHub Actions dependency ownership to Dependabot')
custom = {rule.get('depNameTemplate') for rule in config.get('customManagers', [])}
if {'blue-build/cli', 'aquasecurity/trivy'} - custom:
    raise SystemExit('Renovate must retain BlueBuild CLI and Trivy custom managers')
PY

# Secret scanning remains narrowed only to the immutable reviewed Flathub public
# key line, whose bytes and OpenPGP identity are checked below.
need_file .gitleaks.toml
need_file .gitleaksignore
readonly expected_gitleaks_ignores=$'files/system/etc/flatpak/remotes.d/flathub.flatpakrepo:generic-api-key:8\nfiles/common/etc/flatpak/remotes.d/flathub.flatpakrepo:generic-api-key:8'
actual_gitleaks_ignores="$(grep -Ev '^[[:space:]]*(#|$)' .gitleaksignore || true)"
[[ "${actual_gitleaks_ignores}" == "${expected_gitleaks_ignores}" ]] \
  || fail 'Gitleaks ignore list must contain only legacy/current reviewed Flathub key fingerprints'
[[ ! -e files/system ]] || fail 'legacy files/system path must not be restored under its history-only Gitleaks suppression'
need_file .github/scripts/scan-gitleaks.sh
need_line .github/workflows/ci.yml '        run: ./.github/scripts/scan-gitleaks.sh'
need_line .github/workflows/ci.yml "          find files .github/scripts scripts -type f -name '*.sh' -print0 \\"
need_line .github/scripts/scan-gitleaks.sh "readonly version='8.30.1'"
need_line .github/scripts/scan-gitleaks.sh "readonly expected_sha256='551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb'"

# Shell syntax and executable-bit checks include all source payloads that will
# execute during compose or on a target image.
while IFS= read -r -d '' script; do
  bash -n "$script"
  [[ -x "$script" ]] || fail "script is not executable: $script"
done < <(find files .github/scripts scripts -type f -name '*.sh' -print0)

# Keys are vendored only after manual review. Require complete primary/subkey
# fingerprint sets so an appended key cannot silently widen trust.
key_fingerprints() {
  gpg --show-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10 }' | sort -u
}
expect_key_fingerprints() {
  local key_file="$1"
  shift
  local actual expected
  actual="$(key_fingerprints "${key_file}")"
  expected="$(printf '%s\n' "$@" | sort -u)"
  [[ "${actual}" == "${expected}" ]] \
    || fail "unexpected reviewed fingerprint set in ${key_file}"
}
expect_key_fingerprints files/dnf/terra44.gpg \
  AE09157A4DE88B497EA1D5D300CDAB43DE226D6F \
  DDD6F3C8F77F833483AEB42301DC082ACDE96E5A
expect_key_fingerprints files/dnf/faugus.gpg \
  53B018C402631F2762A4091967B25E7ACBB697C6
expect_key_fingerprints files/dnf/helium.gpg \
  07BCFCA30AC7E51BCFEDFFF74A3186EA47912C39
expect_key_fingerprints files/dnf/ublue-packages.gpg \
  AB4670779555943799BE7ED916BC8535A444A78A
expect_key_fingerprints files/common/usr/share/doors/distrobox/keys/bun-release-key.asc \
  F3DCC08A8572C0749B3E18888EAB4D40A7B22B59 \
  8CDF8ECABE81CE3F32AC047236FA8E877B80AB05
expect_key_fingerprints files/dnf/brave.gpg \
  DBF1A116C220B8C7164F98230686B78420038257 \
  47D32A74E9A9E013A4B4926C68D513D36A73CD96 \
  B2A3DCA350E67256740DF904DE4EC67BE4B0DCA0
cmp -s files/dnf/ublue-packages.gpg files/common/etc/pki/rpm-gpg/RPM-GPG-KEY-ublue-packages \
  || fail 'compose and retained UBlue package signing keys must be identical'
cmp -s files/dnf/brave.gpg files/common/etc/pki/rpm-gpg/RPM-GPG-KEY-brave \
  || fail 'compose and retained Brave signing keys must be identical'

flatpak_repo_key_fingerprints() {
  awk -F= '$1 == "GPGKey" { print $2; found = 1; exit } END { if (!found) exit 1 }' "$1" \
    | base64 -d \
    | gpg --show-keys --with-colons 2>/dev/null \
    | awk -F: '$1 == "fpr" { print $10 }' \
    | sort -u
}
expect_flatpak_repo_key_fingerprints() {
  local repo_file="$1"
  shift
  local actual expected
  actual="$(flatpak_repo_key_fingerprints "${repo_file}")"
  expected="$(printf '%s\n' "$@" | sort -u)"
  [[ "${actual}" == "${expected}" ]] \
    || fail "unexpected reviewed Flatpak signing key set in ${repo_file}"
}
flatpak_repo_gpgkey_line_sha256() {
  awk -F= '$1 == "GPGKey" { print $0; found = 1; exit } END { if (!found) exit 1 }' "$1" \
    | sha256sum | awk '{ print $1 }'
}
flatpak_repo='files/common/etc/flatpak/remotes.d/flathub.flatpakrepo'
[[ "$(grep -n '^GPGKey=' "${flatpak_repo}" | cut -d: -f1)" == '8' ]] \
  || fail 'reviewed Flathub GPGKey must remain on the Gitleaks-suppressed line 8'
[[ "$(flatpak_repo_gpgkey_line_sha256 "${flatpak_repo}")" == '817d8323bbc597fc4ecc478707f3b767abe6f7545d0d546fc09c07ce00bd1366' ]] \
  || fail 'reviewed Flathub GPGKey line unexpectedly changed'
expect_flatpak_repo_key_fingerprints "${flatpak_repo}" \
  54A6CDDD8919FB204200D8AC562702E9E3ED7EE8 \
  6E5C05D979C76DAF93C081354184DD4D907A7CAE

# Do not permit resolver/signature bypasses or retired platforms in buildable
# configuration. COSMIC and Kinoite are intentional, so they are not legacy.
if grep -RInE --exclude='validate-repository.sh' --exclude='*.md' \
  --exclude='*.json' --exclude='*.gpg' --exclude='*.asc' \
  '(--nogpgcheck|--nodeps|--noscripts|skip-unavailable|skip-broken|rpm --nodeps|kernel-cachyos|llama\.cpp|Hermes|Lemurs|Hyprland|kinoite-main|[Pp]laywright)' \
  recipes files .github scripts; then
  fail 'forbidden legacy/bypass term found in production configuration'
fi
if grep -RInE '(registry\.fedoraproject\.org/fedora-toolbox|cuda-fedora44|RPM-GPG-KEY-NVIDIA-CUDA|RPM-GPG-KEY-terra44)' \
  files/common/usr/share/doors/distrobox files/common/usr/bin/doors-ai; then
  fail 'retired Fedora Distrobox trust material remains'
fi

# Generated Herdr artifacts are CI-only and must never enter Git history.
if git ls-files --error-unmatch files/generated/herdr/herdr-linux-x86_64 >/dev/null 2>&1 \
  || git ls-files --error-unmatch files/generated/herdr/herdr.json >/dev/null 2>&1; then
  fail 'generated Herdr artifacts must not be version-controlled'
fi

git diff --check
printf '%s\n' 'Repository static validation passed.'
