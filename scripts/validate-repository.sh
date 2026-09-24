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
    'common.yml', 'gnome.yml', 'cosmic.yml', 'kinoite.yml', 'secureboot.yml',
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
    if stage.get('name') != 'doors-tools-build' or stage.get('from') != f"{spec['base']}:44":
        raise SystemExit(f'{filename} must pin its shared Doors tools stage to its Fedora 44 base')
    stage_modules = stage.get('modules', [])
    if stage_modules != [{'type': 'script', 'scripts': ['build-wl-clip-persist.sh', 'build-anechoic.sh']}]:
        raise SystemExit(f'{filename} has an unexpected disposable tools build-stage contract')
    expected_recipe_modules = [
        {'from-file': 'modules/common.yml'},
        {'from-file': f"modules/{spec['profile']}"},
        {'from-file': 'modules/secureboot.yml'},
        {'type': 'signing'},
        {'type': 'script', 'scripts': ['configure-doors-signature-policy.sh']},
    ]
    if recipe.get('modules') != expected_recipe_modules:
        raise SystemExit(f'{filename} must compose common, its isolated profile, secure-boot signing, then cross-Doors signature policy')
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
justfiles = [entry for entry in common if entry.get('type') == 'justfiles']
if justfiles != [{'type': 'justfiles', 'validate': True, 'include': ['doors.just']}]:
    raise SystemExit('common must install only the reviewed Doors ujust recipe set')
secureboot = modules['secureboot.yml'].get('modules')
if not isinstance(secureboot, list) or len(secureboot) != 2:
    raise SystemExit('late secure-boot module must contain exactly its tool and signing phases')
secureboot_dnf, secureboot_script = secureboot
if secureboot_dnf.get('type') != 'dnf' or secureboot_dnf.get('install', {}).get('install-weak-deps') is not False \
        or secureboot_dnf.get('install', {}).get('packages') != [
            'kmod', 'mokutil', 'openssl', 'sbsigntools',
        ]:
    raise SystemExit('secure-boot module must retain only target verification tooling')
expected_mok_secret = [{
    'type': 'env', 'name': 'DOORS_MOK_SIGNING_KEY',
    'mount': {'type': 'file', 'destination': '/run/secrets/doors-mok.key'},
}]
if secureboot_script.get('type') != 'script' or secureboot_script.get('no-cache') is not True \
        or secureboot_script.get('scripts') != ['sign-secureboot-payloads.sh'] \
        or secureboot_script.get('secrets') != expected_mok_secret:
    raise SystemExit('secure-boot signer must use the one no-cache BuildKit MOK file secret')
common_files = [entry for entry in common if entry.get('type') == 'files']
expected_common_files = [
    {'type': 'files', 'files': [{'source': 'common', 'destination': '/'}]},
    {'type': 'files', 'files': [{'source': 'cuda-runtime-repo', 'destination': '/'}]},
    {'type': 'files', 'files': [{'source': 'cuda-runtime-repo', 'destination': '/'}]},
    {'type': 'files', 'files': [{'source': 'generated/herdr', 'destination': '/usr/share/doors/native-ai/herdr'}]},
]
if common_files != expected_common_files:
    raise SystemExit('common must own only shared payload and the native Herdr build input')
if any(entry.get('type') == 'gnome-extensions' for entry in common):
    raise SystemExit('common module must not install GNOME Shell extensions')
expected_tools_copies = [
    {'type': 'copy', 'from': 'doors-tools-build', 'src': '/out/wl-clip-persist', 'dest': '/usr/bin/wl-clip-persist'},
    {'type': 'copy', 'from': 'doors-tools-build', 'src': '/out/wl-clip-persist.buildinfo', 'dest': '/usr/share/doors/third-party/wl-clip-persist.buildinfo'},
    {'type': 'copy', 'from': 'doors-tools-build', 'src': '/out/anechoic/libanechoic_ladspa.so', 'dest': '/usr/lib64/ladspa/libanechoic_ladspa.so'},
    {'type': 'copy', 'from': 'doors-tools-build', 'src': '/out/anechoic/LICENSE', 'dest': '/usr/share/licenses/anechoic/LICENSE'},
    {'type': 'copy', 'from': 'doors-tools-build', 'src': '/out/anechoic/anechoic-061038dd98d45abef5fc22ae9c27b289b50b180c.tar.gz', 'dest': '/usr/share/doors/anechoic/anechoic-061038dd98d45abef5fc22ae9c27b289b50b180c.tar.gz'},
    {'type': 'copy', 'from': 'doors-tools-build', 'src': '/out/anechoic/buildinfo', 'dest': '/usr/share/doors/anechoic/buildinfo'},
]
if [entry for entry in common if entry.get('type') == 'copy'] != expected_tools_copies:
    raise SystemExit('common must copy only the reviewed final artifacts from the disposable tools stage')
native_setup = [entry for entry in common if entry.get('type') == 'script' and entry.get('scripts') == ['install-native-ai.sh']]
if native_setup != [{'type': 'script', 'scripts': ['install-native-ai.sh']}]:
    raise SystemExit('common must finalize the native AI toolchain exactly once')
native_cuda = [entry for entry in common if entry.get('type') == 'containerfile']
if native_cuda != [{'type': 'containerfile', 'containerfiles': ['native-cuda']}]:
    raise SystemExit('common must relocate the NVIDIA toolkit through exactly one native CUDA containerfile')
common_dnf = next((entry for entry in common if entry.get('type') == 'dnf'), None)
if not isinstance(common_dnf, dict):
    raise SystemExit('common RPM module is missing')
https_indices = [
    index for index, entry in enumerate(common)
    if entry.get('type') == 'script' and entry.get('scripts') == ['enforce-rpm-https.sh']
]
dnf_index = common.index(common_dnf)
cuda_index = common.index(native_cuda[0])
if https_indices != [cuda_index - 1, cuda_index + 1, dnf_index + 2] or dnf_index != cuda_index + 2 \
        or common[cuda_index - 2] != {'type': 'files', 'files': [{'source': 'cuda-runtime-repo', 'destination': '/'}]} \
        or common[dnf_index + 1] != {'type': 'files', 'files': [{'source': 'cuda-runtime-repo', 'destination': '/'}]}:
    raise SystemExit('RPM HTTPS enforcement must bracket CUDA relocation and restored final repository composition')
repos = common_dnf.get('repos', {})
if repos.get('nonfree') != 'negativo17' or repos.get('cleanup') is not True:
    raise SystemExit('common RPM module must retain the reviewed Negativo17 repository policy')
if repos.get('files') != ['terra.repo', 'cuda-fedora44.repo', 'brave-origin.repo', 'faugus.repo', 'helium.repo', 'ublue-packages.repo']:
    raise SystemExit('common RPM module has an unexpected repository set')
if repos.get('keys') != ['terra44.gpg', 'cuda-fedora44.gpg', 'brave.gpg', 'faugus.gpg', 'helium.gpg', 'ublue-packages.gpg']:
    raise SystemExit('common RPM module has an unexpected signing-key set')
remove = common_dnf.get('remove', {})
if remove.get('auto-remove') is not False or remove.get('packages') != [
    'firefox', 'firefox-langpacks', 'brave-browser', 'gamemode', 'gamemode-libs',
]:
    raise SystemExit('common RPM removal policy changed unexpectedly')
common_packages = common_dnf.get('install', {}).get('packages', [])
required_common = {
    'gamescope', 'steam', 'uupd', 'greenboot', 'vicinae', 'ghostty',
    'zed', 'breeze-icon-theme', 'brave-origin', 'helium-bin', 'faugus-launcher',
    'pipewire-utils', 'ladspa', 'lsp-plugins-ladspa',
    # Native development/AI tooling shared by every image.
    'nodejs24', 'nodejs24-devel', 'nodejs24-npm', 'nodejs24-bin',
    'nodejs24-npm-bin', 'pnpm', 'python3', 'python3-devel', 'python3-pip',
    'gcc', 'gcc-c++', 'make', 'cmake', 'pkgconf-pkg-config',
    'bun-bin', 'deno', 'mise', 'opencode-cli',
    # Shared NTS/DNS, all-desktop cleanup, polkit/run0, and safe LUKS enrollment.
    'chrony', 'unbound', 'unbound-anchor', 'polkit', 'cryptsetup', 'dracut',
    'tpm2-tss', 'tpm2-tools', 'libfido2', 'dconf', 'dbus-daemon',
}
if not required_common <= set(common_packages):
    raise SystemExit('common RPM baseline is missing a required host package')
if {'distrobox', 'podman'} & set(common_packages):
    raise SystemExit('container tooling must not be explicitly layered for Doors native development')
if {'opencode', 'cuda-toolkit', 'cuda', 't3code', 'pi'} & set(common_packages):
    raise SystemExit('common must retain the reviewed native OpenCode/CUDA identities and locked npm Pi payload')
if {'nodejs', 'nodejs-devel', 'npm'} & set(common_packages):
    raise SystemExit('Pi requires the explicit Fedora 44 Node 24 package set, not an unversioned Node alternative')
if {'cuda-toolkit-13-4', 'cuda-nvcc-13-4'} & set(common_packages):
    raise SystemExit('CUDA RPMs must be relocated from mutable /usr/local in the dedicated native CUDA layer')
cuda_containerfile = root / 'containerfiles' / 'native-cuda' / 'Containerfile'
if not cuda_containerfile.is_file():
    raise SystemExit('native CUDA relocation Containerfile is missing')
cuda_rendered = cuda_containerfile.read_text(encoding='utf-8')
for fragment in (
    "cuda_source='/usr/local/cuda-13.4'",
    "cuda_destination='/usr/lib/doors/cuda-13.4'",
    "nsight_source='/opt/nvidia'",
    'test -s /etc/yum.repos.d/cuda-fedora44.repo;',
    "dnf5 install -y --setopt=install_weak_deps=False",
    "--disablerepo='*' --enablerepo=fedora --enablerepo=updates",
    '--enablerepo=cuda-fedora44-x86_64',
    'cuda-toolkit-13-4;',
    'test -x "${cuda_source}/bin/nvcc";',
    'cp -a "${cuda_source}/." "${cuda_destination}/";',
    'test -d "${nsight_source}/nsight-compute";',
    'test -d "${nsight_source}/nsight-systems";',
    'cp -a "${nsight_compute_dir}" "${cuda_destination}/nsight-compute-$(basename "${nsight_compute_dir}")";',
    'cp -a "${nsight_systems_dir}" "${cuda_destination}/nsight-systems-$(basename "${nsight_systems_dir}")";',
    "-name 'nsight-compute-*'",
    "-name 'nsight-systems-*'",
    'test -x "${cuda_destination}/bin/nvcc";',
    'test -x "${cuda_destination}/bin/ncu";',
    'test -x "${cuda_destination}/bin/nsys";',
    'test -d "${cuda_destination}/targets/x86_64-linux/lib";',
    ' > /etc/ld.so.conf.d/987_cuda-13.conf;',
    ' > /etc/ld.so.conf.d/000_cuda.conf;',
    ' > /etc/ld.so.conf.d/gds-13-4.conf;',
    'rm -rf -- "${cuda_source}" /usr/local/cuda-13 /usr/local/cuda \\',
    '"${nsight_source}/nsight-compute" "${nsight_source}/nsight-systems";',
    'for mutable_cuda_path in "${cuda_source}" /usr/local/cuda-13 /usr/local/cuda \\',
    '"${nsight_source}/nsight-compute" "${nsight_source}/nsight-systems"; do',
    'ldconfig;',
):
    if fragment not in cuda_rendered:
        raise SystemExit(f'native CUDA relocation is missing: {fragment}')
if '--nogpgcheck' in cuda_rendered or 'http://' in cuda_rendered:
    raise SystemExit('native CUDA relocation must preserve repository signature and HTTPS policy')
if any('gnome-shell-extension-' in str(package) for package in common_packages):
    raise SystemExit('GNOME Shell extension RPMs must stay in the GNOME profile')
if 'greenboot-default-health-checks' in common_packages:
    raise SystemExit('Doors must use its bounded deployment-local Greenboot check, not upstream generic defaults')
common_systemd = next((entry for entry in common if entry.get('type') == 'systemd'), None)
if not isinstance(common_systemd, dict):
    raise SystemExit('common systemd policy is missing')
expected_system_enabled = {
    'falcond.service', 'ananicy-cpp.service', 'scx_loader.service', 'doors-update.timer',
    'doors-flatpak-bootstrap.service', 'greenboot-healthcheck.service',
    'greenboot-set-rollback-trigger.service',
    'chronyd.service', 'systemd-resolved.service', 'unbound-anchor.timer',
}
if set(common_systemd.get('system', {}).get('enabled', [])) != expected_system_enabled:
    raise SystemExit('common systemd enabled units changed unexpectedly')
if set(common_systemd.get('system', {}).get('disabled', [])) != {
    'uupd.timer', 'bootc-fetch-apply-updates.timer', 'flatpak-system-updates.timer',
    'podman-auto-update.timer',
}:
    raise SystemExit('common systemd disabled timer policy changed unexpectedly')
if set(common_systemd.get('user', {}).get('enabled', [])) != {
    'vicinae.service', 'wl-clip-persist.service',
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
if 'dconf' in gnome_dnf.get('install', {}).get('packages', []):
    raise SystemExit('dconf must remain shared for cross-desktop all-account cleanup')
if not {'dconf', 'dbus-daemon'} <= set(common_packages):
    raise SystemExit('shared desktop cleanup dependencies are missing from common composition')
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
for line in ('LookAndFeelPackage=org.kde.breezedark.desktop', 'ColorScheme=BreezeDark', 'Theme=breeze-dark', '[KDE Action Restrictions][$i]', 'ghns=false'):
    if line not in kde:
        raise SystemExit(f'Kinoite must retain native Breeze Dark/GHNS policy: {line}')
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
need_file files/common/etc/greenboot/check/required.d/10-doors-deployment.sh
need_file files/common/etc/systemd/system/greenboot-healthcheck.service.d/10-doors-grub-only.conf
need_file files/common/etc/systemd/system/greenboot-set-rollback-trigger.service.d/10-doors-grub-only.conf
need_line files/common/usr/lib/systemd/system/doors-flatpak-bootstrap.service 'ExecStart=/usr/libexec/doors/bootstrap-flatpaks.sh'
need_line files/common/usr/lib/systemd/system/doors-flatpak-bootstrap.service 'WantedBy=multi-user.target'
need_line files/common/usr/lib/systemd/system/doors-update.service 'ExecStart=/usr/libexec/doors/update-system.sh'
need_line files/common/usr/lib/systemd/system/doors-update.timer 'Persistent=true'
need_line files/common/usr/lib/systemd/user/doors-user-update.service 'ExecStart=/usr/libexec/doors/update-user.sh'
need_line files/common/etc/greenboot/check/required.d/10-doors-deployment.sh 'readonly status_timeout_seconds=60'
need_line files/common/etc/greenboot/check/required.d/10-doors-deployment.sh '  "${rpm_ostree_binary}" status --json)"'
need_line files/common/etc/greenboot/check/required.d/10-doors-deployment.sh '  and ([.deployments[]? | select(.booted == true)] | length == 1)'
need_line files/common/etc/systemd/system/greenboot-healthcheck.service.d/10-doors-grub-only.conf 'ConditionPathExists=/boot/grub2/grubenv'
need_line files/common/etc/systemd/system/greenboot-set-rollback-trigger.service.d/10-doors-grub-only.conf 'ConditionPathExists=/boot/grub2/grubenv'
if grep -Eq '(curl|wget|getent|ping|bootc[[:space:]]+status)' files/common/etc/greenboot/check/required.d/10-doors-deployment.sh; then
  fail 'Doors required Greenboot check must remain bounded and offline'
fi
need_line files/common/usr/libexec/doors/bootstrap-flatpaks.sh "  'io.github.kolunmi.Bazaar'"
if grep -Fq 'DistroShelf' files/common/usr/libexec/doors/bootstrap-flatpaks.sh; then
  fail 'Doors bootstrap must not retain a Distrobox manager'
fi
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
grep -Fq '/usr/bin/flatpak --system remote-delete --force' files/scripts/enforce-flatpak-policy.sh \
  || fail 'Flatpak policy must remove inherited non-Flathub system remotes'
grep -Fq '/usr/share/flatpak/remotes.d' files/scripts/enforce-flatpak-policy.sh \
  || fail 'Flatpak policy must remove inherited static remote metadata'
grep -Fq '/usr/bin/flatpak --system remote-add --if-not-exists flathub "${flathub_repo}"' files/scripts/enforce-flatpak-policy.sh \
  || fail 'Flatpak policy must register the reviewed descriptor as the active system remote'
grep -Fq 'active_flathub_url="$(/usr/bin/flatpak --system remote-url flathub)' files/scripts/enforce-flatpak-policy.sh \
  || fail 'Flatpak policy must verify the active reviewed remote endpoint'
grep -Fq 'flatpak_remote_url="$(/usr/bin/flatpak --system remote-url flathub' files/scripts/verify-common.sh \
  || fail 'Flatpak verifier must inspect the installed system remote endpoint'
grep -Fq '"${flatpak_remote_url%/}/" == '\''https://dl.flathub.org/repo/'\''' files/scripts/verify-common.sh \
  || fail 'Flatpak verifier must normalize Flatpak trailing-slash output'
if grep -Fq '"distrobox": {' files/scripts/configure-uupd.sh; then
  fail 'uupd must not retain a Distrobox update module declaration'
fi
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
if 'distrobox' in modules:
    raise SystemExit('uupd configuration must not retain a Distrobox module')
for module in ('brew', 'flatpak'):
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
need_line files/systemd/user/wl-clip-persist.service 'ExecStart=/usr/bin/wl-clip-persist --clipboard regular'
# Compose must not depend on GitHub's mutable/rate-limited releases API for
# wl-clip-persist. Its pinned source archive and Cargo lockfile are the build
# contract, and the target verifier checks the matching installed provenance.
need_file files/scripts/build-wl-clip-persist.sh
need_line files/scripts/build-wl-clip-persist.sh "readonly tag='v0.5.0'"
need_line files/scripts/build-wl-clip-persist.sh "readonly commit='e26fde01c13922e3a65049dafb7d5adfbc52626e'"
need_line files/scripts/build-wl-clip-persist.sh "readonly source_sha256='4f57033dae159b887168210bcc69de84ba5f43e7e39444e483297e6ccb4b747c'"
need_line files/scripts/build-wl-clip-persist.sh 'cargo install --locked --path "${source_dir}" --root "${workdir}/install-root"'
if grep -Fq 'api.github.com/repos/Linus789/wl-clip-persist/releases/latest' files/scripts/build-wl-clip-persist.sh \
  || grep -Fq 'git ls-remote' files/scripts/build-wl-clip-persist.sh; then
  fail 'wl-clip-persist must use a hash-verified pinned source archive, not mutable GitHub release discovery'
fi

# Shared PipeWire/WirePlumber policy must be additive and desktop neutral. The
# only bundled third-party audio binary is the narrow, hash-verified Anechoic
# LADSPA target; its matching GPL source and license accompany it in the image.
need_file files/scripts/build-anechoic.sh
need_file files/common/etc/pipewire/pipewire.conf.d/20-doors-audio.conf
need_file files/common/etc/pipewire/pipewire-pulse.conf.d/20-doors-proton-wine.conf
need_file files/common/etc/pipewire/pipewire.conf.d/99-doors-anechoic.conf
need_file files/common/etc/wireplumber/wireplumber.conf.d/20-doors-alsa-no-suspend.conf
need_file files/common/etc/modprobe.d/doors-audio.conf
need_file files/common/usr/share/doc/doors/AUDIO.md
need_line files/scripts/build-anechoic.sh "readonly commit='061038dd98d45abef5fc22ae9c27b289b50b180c'"
need_line files/scripts/build-anechoic.sh "readonly source_sha256='40bc93f8fa4b99205ecc5a948f4edceb52f9d54098ed5cd62a4ad42372ff9ad4'"
for anechoic_build_flag in \
  '-DBUILD_TESTS=OFF' \
  '-DBUILD_OFFLINE_TOOL=OFF' \
  '-DBUILD_LADSPA_PLUGIN=ON' \
  '-DBUILD_VST_PLUGIN=OFF' \
  '-DBUILD_VST3_PLUGIN=OFF' \
  '-DBUILD_LV2_PLUGIN=OFF' \
  '-DBUILD_AU_PLUGIN=OFF' \
  '-DBUILD_AUV3_PLUGIN=OFF'; do
  grep -Fq -- "${anechoic_build_flag}" files/scripts/build-anechoic.sh \
    || fail "Anechoic build has an unexpected target policy: ${anechoic_build_flag}"
done
need_line files/common/etc/pipewire/pipewire.conf.d/20-doors-audio.conf '    module.x11.bell = false'
for audio_line in \
  '    default.clock.rate = 48000' \
  '    default.clock.quantum = 256' \
  '    default.clock.min-quantum = 64' \
  '    default.clock.max-quantum = 1024' \
  '    resample.quality = 10'; do
  need_line files/common/etc/pipewire/pipewire.conf.d/20-doors-audio.conf "${audio_line}"
done
need_line files/common/etc/pipewire/pipewire-pulse.conf.d/20-doors-proton-wine.conf '    pulse.default.req = 256/48000'
need_line files/common/etc/pipewire/pipewire.conf.d/99-doors-anechoic.conf '                        plugin = ladspa/libanechoic_ladspa'
need_line files/common/etc/pipewire/pipewire.conf.d/99-doors-anechoic.conf '                        label = noise_suppressor_mono'
need_line files/common/etc/wireplumber/wireplumber.conf.d/20-doors-alsa-no-suspend.conf '                session.suspend-timeout-seconds = 0'
need_line files/common/etc/modprobe.d/doors-audio.conf 'options snd_hda_intel power_save=0 power_save_controller=N'
if grep -RInE '(override\.monitor\.alsa\.rules|node\.always-process|BUILD_(VST|VST3|LV2|AU|AUV3)_PLUGIN=ON)' \
  files/scripts/build-anechoic.sh files/common/etc/pipewire files/common/etc/wireplumber; then
  fail 'audio payload contains an unsupported legacy WirePlumber match or non-LADSPA Anechoic target'
fi

# Shared host-integration contract: strict NTS/DNS defaults, retained run0
# authorization, all-account desktop transitions, no coredump/debug retention,
# and fail-closed LUKS enrollment helpers.
for host_policy_file in \
  files/common/etc/chrony.conf \
  files/common/etc/systemd/resolved.conf.d/90-doors-dns.conf \
  files/common/etc/NetworkManager/conf.d/90-doors-dns.conf \
  files/common/etc/unbound/conf.d/90-doors.conf \
  files/common/etc/polkit-1/rules.d/49-doors-wheel-admin.rules \
  files/common/etc/systemd/coredump.conf.d/90-doors.conf \
  files/common/etc/systemd/system.conf.d/90-doors-coredump.conf \
  files/common/etc/systemd/user.conf.d/90-doors-coredump.conf \
  files/common/etc/systemd/journald.conf.d/90-doors-retention.conf \
  files/common/etc/environment.d/90-doors-log-noise.conf \
  files/common/etc/sysctl.d/90-doors-gaming.conf \
  files/common/etc/modprobe.d/nvidia-rebar.conf \
  files/common/usr/lib/bootc/kargs.d/90-doors-nvme.toml \
  files/common/usr/bin/doors-dns \
  files/common/usr/bin/doors-desktop-cleanup \
  files/common/usr/bin/doors-image \
  files/common/usr/bin/doors-luks-enroll \
  files/scripts/configure-doors-signature-policy.sh; do
  need_file "${host_policy_file}"
done
for host_helper in \
  files/common/usr/bin/doors-dns \
  files/common/usr/bin/doors-desktop-cleanup \
  files/common/usr/bin/doors-image \
  files/common/usr/bin/doors-luks-enroll; do
  [[ -x "${host_helper}" ]] || fail "Doors host helper is not executable: ${host_helper}"
  bash -n "${host_helper}" || fail "Doors host helper has invalid shell syntax: ${host_helper}"
done
grep -Fq -- '--enforce-container-sigpolicy' files/common/usr/bin/doors-image \
  || fail 'Doors image switcher must enforce the installed container signature policy'
[[ -x files/scripts/configure-doors-signature-policy.sh ]] \
  || fail 'cross-Doors signature-policy script is not executable'
bash -n files/scripts/configure-doors-signature-policy.sh \
  || fail 'cross-Doors signature-policy script has invalid shell syntax'
for repository in ghcr.io/mheci/doors ghcr.io/mheci/doors-cosmic ghcr.io/mheci/doors-kinoite; do
  grep -Fq "${repository}" files/scripts/configure-doors-signature-policy.sh \
    || fail "cross-Doors signature policy omits ${repository}"
done
grep -Fq '"type": "sigstoreSigned"' files/scripts/configure-doors-signature-policy.sh \
  || fail 'cross-Doors signature policy must require Cosign signatures'
grep -Fq 'use-sigstore-attachments: true' files/scripts/configure-doors-signature-policy.sh \
  || fail 'cross-Doors signature policy must configure signature attachment discovery'
grep -Fq '"signedIdentity": {"type": "matchRepository"}' files/scripts/configure-doors-signature-policy.sh \
  || fail 'cross-Doors signature policy must match only the signed repository identity'
grep -Fq 'doors-shared.pub' files/scripts/configure-doors-signature-policy.sh \
  || fail 'cross-Doors signature policy must pin the shared Doors public key path'

# Exercise the post-signing policy extension against the exact policy shape
# supplied by BlueBuild: reject by default plus Docker's permissive fallback.
# This proves the script replaces every permitted Doors scope with the shared
# key rule without widening the fallback or adding an unrelated repository.
signature_policy_test_root="$(mktemp -d)"
cleanup_signature_policy_test() {
  rm -rf -- "${signature_policy_test_root}"
}
trap cleanup_signature_policy_test EXIT
mkdir -p "${signature_policy_test_root}/etc/containers/registries.d" \
  "${signature_policy_test_root}/etc/pki/containers"
cat > "${signature_policy_test_root}/etc/containers/policy.json" <<'EOF'
{
  "default": [{"type": "reject"}],
  "transports": {
    "docker": {
      "": [{"type": "insecureAcceptAnything"}],
      "ghcr.io/mheci/doors": [{
        "type": "sigstoreSigned",
        "keyPath": "/etc/pki/containers/doors.pub",
        "signedIdentity": {"type": "matchRepository"}
      }]
    }
  }
}
EOF
cp cosign.pub "${signature_policy_test_root}/etc/pki/containers/doors.pub"
python3 - "${signature_policy_test_root}" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
source = Path('files/scripts/configure-doors-signature-policy.sh').read_text(encoding='utf-8')
source = source.replace(
    "readonly containers_dir='/etc/containers'",
    f"readonly containers_dir='{root}/etc/containers'",
)
source = source.replace(
    "readonly keys_dir='/etc/pki/containers'",
    f"readonly keys_dir='{root}/etc/pki/containers'",
)
if "readonly containers_dir='/etc/containers'" in source or "readonly keys_dir='/etc/pki/containers'" in source:
    raise SystemExit('could not relocate cross-Doors signature-policy fixture')
script = root / 'configure-doors-signature-policy.sh'
script.write_text(source, encoding='utf-8')
script.chmod(0o755)
PY
IMAGE_NAME=doors "${signature_policy_test_root}/configure-doors-signature-policy.sh" \
  || fail 'cross-Doors signature-policy fixture failed'
python3 - "${signature_policy_test_root}" <<'PY'
import json
from pathlib import Path
import sys
import yaml

root = Path(sys.argv[1])
trusted = {
    'ghcr.io/mheci/doors',
    'ghcr.io/mheci/doors-cosmic',
    'ghcr.io/mheci/doors-kinoite',
}
policy = json.loads((root / 'etc/containers/policy.json').read_text(encoding='utf-8'))
if policy.get('default') != [{'type': 'reject'}]:
    raise SystemExit('cross-Doors fixture weakened the reject default policy')
docker = policy.get('transports', {}).get('docker', {})
if set(docker) != {''} | trusted:
    raise SystemExit(f'cross-Doors fixture has unexpected Docker policy scopes: {sorted(docker)}')
if docker.get('') != [{'type': 'insecureAcceptAnything'}]:
    raise SystemExit('cross-Doors fixture unexpectedly altered BlueBuild Docker fallback')
expected_rule = [{
    'type': 'sigstoreSigned',
    'keyPath': str(root / 'etc/pki/containers/doors-shared.pub'),
    'signedIdentity': {'type': 'matchRepository'},
}]
for repository in trusted:
    if docker.get(repository) != expected_rule:
        raise SystemExit(f'cross-Doors fixture has invalid policy rule for {repository}')
if (root / 'etc/pki/containers/doors-shared.pub').read_bytes() != Path('cosign.pub').read_bytes():
    raise SystemExit('cross-Doors fixture did not copy the production public key')
registry = yaml.safe_load((root / 'etc/containers/registries.d/doors-signatures.yaml').read_text(encoding='utf-8'))
expected_registry = {'docker': {repository: {'use-sigstore-attachments': True} for repository in trusted}}
if registry != expected_registry:
    raise SystemExit('cross-Doors fixture has unexpected signature attachment configuration')
PY
cleanup_signature_policy_test
trap - EXIT
for chrony_line in \
  'server time.cloudflare.com iburst nts' \
  'server nts.netnod.se iburst nts' \
  'minsources 2' \
  'authselectmode require' \
  'cmdport 0'; do
  need_line files/common/etc/chrony.conf "${chrony_line}"
done
need_line files/common/etc/systemd/resolved.conf.d/90-doors-dns.conf 'DNSOverTLS=yes'
need_line files/common/etc/systemd/resolved.conf.d/90-doors-dns.conf 'DNSSEC=yes'
need_line files/common/etc/NetworkManager/conf.d/90-doors-dns.conf 'dns=none'
need_line files/common/etc/NetworkManager/conf.d/90-doors-dns.conf 'systemd-resolved=false'
for dns_template in \
  resolved-quad9.conf resolved-cloudflare.conf resolved-unbound.conf resolved-compat.conf \
  networkmanager-strict.conf networkmanager-compat.conf unbound-quad9.conf unbound-cloudflare.conf; do
  need_file "files/common/usr/share/doors/dns/${dns_template}"
done
need_line files/common/etc/unbound/conf.d/90-doors.conf '    port: 5335'
need_line files/common/etc/unbound/conf.d/90-doors.conf '    auto-trust-anchor-file: "/var/lib/unbound/root.key"'
need_line files/common/etc/unbound/conf.d/90-doors.conf '    forward-tls-upstream: yes'
grep -Fq 'unbound-anchor -a "${unbound_anchor}"' files/common/usr/bin/doors-dns \
  || fail 'Doors DNS selector must refresh/validate the Unbound trust anchor'
grep -Fq 'unbound-checkconf' files/common/usr/bin/doors-dns \
  || fail 'Doors DNS selector must validate Unbound configuration'
grep -Fq '127\.0\.0\.1:5335' files/common/usr/bin/doors-dns \
  || fail 'Doors DNS selector must verify the local Unbound listener'
grep -Fq 'systemd-resolved-compat' files/common/usr/bin/doors-dns \
  || fail 'Doors DNS selector must retain its explicit compatibility mode'
if grep -Eq '(^|[^[:alnum:]_])(--wipe-slot|luksErase|erase[[:space:]]+)' files/common/usr/bin/doors-luks-enroll; then
  fail 'Doors LUKS enrollment helper must never remove/wipe a recovery slot'
fi
for luks_fragment in \
  '--tpm2-pcrs=7' \
  '--tpm2-with-pin=yes' \
  'mokutil --sb-state' \
  '--fido2-with-client-pin=yes' \
  '--fido2-with-user-presence=yes' \
  'cryptsetup open --test-passphrase --disable-external-tokens' \
  'rpm-ostree initramfs --enable' \
  'lsinitrd'; do
  grep -Fq -- "${luks_fragment}" files/common/usr/bin/doors-luks-enroll \
    || fail "Doors LUKS helper lacks required safety/integration behavior: ${luks_fragment}"
done
if grep -Fq -- '--hostonly' files/common/usr/bin/doors-luks-enroll; then
  fail 'Doors LUKS helper must not use host-only initramfs generation'
fi
need_line files/common/etc/systemd/coredump.conf.d/90-doors.conf 'Storage=none'
need_line files/common/etc/systemd/coredump.conf.d/90-doors.conf 'ProcessSizeMax=0'
need_line files/common/etc/systemd/system.conf.d/90-doors-coredump.conf 'DefaultLimitCORE=0'
need_line files/common/etc/systemd/user.conf.d/90-doors-coredump.conf 'DefaultLimitCORE=0'
need_line files/common/etc/systemd/journald.conf.d/90-doors-retention.conf 'MaxLevelStore=warning'
need_line files/common/etc/environment.d/90-doors-log-noise.conf 'QT_LOGGING_RULES=*.debug=false'
for performance_line in \
  'vm.max_map_count = 1048576' \
  'vm.page_lock_unfairness = 1' \
  'kernel.split_lock_mitigate = 0'; do
  need_line files/common/etc/sysctl.d/90-doors-gaming.conf "${performance_line}"
done
need_line files/common/etc/modprobe.d/nvidia-rebar.conf 'options nvidia NVreg_EnableResizableBar=1'
need_line files/common/usr/lib/bootc/kargs.d/90-doors-nvme.toml 'kargs = ["nvme_core.default_ps_max_latency_us=0"]'
grep -Fq 'org.freedesktop.systemd1.manage-units' files/common/etc/polkit-1/rules.d/49-doors-wheel-admin.rules \
  || fail 'run0 retained systemd authorization is missing'
grep -Fq 'polkit.Result.AUTH_ADMIN_KEEP' files/common/etc/polkit-1/rules.d/49-doors-wheel-admin.rules \
  || fail 'run0 authorization must be retained after authentication'
grep -Fq 'org.freedesktop.udisks2.' files/common/etc/polkit-1/rules.d/49-doors-wheel-admin.rules \
  || fail 'wheel UDisks action authorization is missing'
grep -Fq 'polkit.Result.YES' files/common/etc/polkit-1/rules.d/49-doors-wheel-admin.rules \
  || fail 'wheel UDisks authorization must be no-prompt'
for just_recipe in dns-selector doors-image-switch doors-desktop-cleanup doors-luks-tpm2-pin doors-luks-fido2; do
  grep -Eq "^${just_recipe}([[:space:]]|:)" files/justfiles/doors.just \
    || fail "Doors ujust recipe is missing: ${just_recipe}"
done

# Native development/AI trust boundary. All shipped tooling is native image
# content. The tracked T3 and Pi locks supply their pinned npm inputs; the only
# generated input is CI-attestation-verified Herdr, checked again before it
# becomes a host command.
need_file files/common/usr/bin/doors-ai
need_line files/common/usr/bin/doors-ai 'readonly -a native_tools=(bun deno herdr mise ncu node npm nsys pnpm nvcc opencode pi t3)'
need_file files/common/etc/profile.d/doors-cuda.sh
need_file files/dnf/cuda-fedora44.repo
need_file files/cuda-runtime-repo/etc/yum.repos.d/cuda-fedora44.repo
need_file files/dnf/cuda-fedora44.gpg
need_file files/common/etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-cuda
need_file containerfiles/native-cuda/Containerfile
need_file files/scripts/install-native-ai.sh
need_file files/common/usr/share/doors/native-ai/t3/package.json
need_file files/common/usr/share/doors/native-ai/t3/package-lock.json
need_file files/common/usr/share/doors/native-ai/pi/package.json
need_file files/common/usr/share/doors/native-ai/pi/package-lock.json
need_line .gitignore '/files/generated/herdr/herdr-linux-x86_64'
need_line .gitignore '/files/generated/herdr/herdr.json'
for executable in \
  files/common/usr/bin/doors-ai \
  files/scripts/install-native-ai.sh; do
  [[ -x "${executable}" ]] || fail "native AI helper is not executable: ${executable}"
done
for obsolete_path in \
  files/common/usr/bin/doors-distrobox \
  files/common/usr/lib/systemd/user/doors-distrobox.service \
  files/common/usr/share/doors/distrobox; do
  [[ ! -e "${obsolete_path}" ]] || fail "retired Distrobox payload remains: ${obsolete_path}"
done
need_file files/scripts/verify-common.sh
need_line files/scripts/verify-common.sh '  for unit in vicinae.service wl-clip-persist.service; do'
need_line files/scripts/verify-common.sh '  for provider in nodejs24 nodejs24-devel nodejs24-npm nodejs24-bin nodejs24-npm-bin; do'
need_line files/scripts/verify-common.sh "  cuda_root='/usr/lib/doors/cuda-13.4'"
grep -Fq '/opt/nvidia/nsight-compute' files/scripts/verify-common.sh \
  || fail 'runtime verifier must reject mutable Nsight Compute payloads'
grep -Fq '/opt/nvidia/nsight-systems' files/scripts/verify-common.sh \
  || fail 'runtime verifier must reject mutable Nsight Systems payloads'
for native_cuda_command in nvcc ncu nsys; do
  grep -Fq "\${cuda_root}/bin/${native_cuda_command}" files/scripts/verify-common.sh \
    || fail "runtime verifier must validate native CUDA command: ${native_cuda_command}"
done
grep -Fq '/usr/lib/doors/cuda-13.4/targets/x86_64-linux/lib' files/scripts/verify-common.sh \
  || fail 'runtime verifier must validate the immutable CUDA loader path'
grep -Fq '/etc/ld.so.conf.d/gds-13-4.conf' files/scripts/verify-common.sh \
  || fail 'runtime verifier must validate the relocated GPUDirect loader path'
need_line files/scripts/verify-common.sh '    nodejs24 nodejs24-devel nodejs24-npm nodejs24-bin nodejs24-npm-bin pnpm \'
need_line files/scripts/verify-common.sh '    cuda-nsight-compute-13-4 cuda-nsight-systems-13-4 \'
need_line files/scripts/install-native-ai.sh "readonly herdr_dir='/usr/share/doors/native-ai/herdr'"
need_line files/scripts/install-native-ai.sh "readonly cuda_root='/usr/lib/doors/cuda-13.4'"
need_line files/scripts/install-native-ai.sh "readonly t3_input_dir='/usr/share/doors/native-ai/t3'"
need_line files/scripts/install-native-ai.sh "readonly t3_prefix='/usr/lib/doors/native-ai/t3'"
need_line files/scripts/install-native-ai.sh "readonly pi_input_dir='/usr/share/doors/native-ai/pi'"
need_line files/scripts/install-native-ai.sh "readonly pi_prefix='/usr/lib/doors/native-ai/pi'"
need_line files/scripts/install-native-ai.sh '  nodejs24 nodejs24-devel nodejs24-npm nodejs24-bin nodejs24-npm-bin pnpm \'
need_line files/scripts/install-native-ai.sh '  bun-bin deno mise opencode-cli cuda-toolkit-13-4 cuda-nvcc-13-4 \'
need_line files/scripts/install-native-ai.sh '  cuda-nsight-compute-13-4 cuda-nsight-systems-13-4; do'
grep -Fq "npm_config_registry='https://registry.npmjs.org/'" files/scripts/install-native-ai.sh \
  || fail 'native npm payload installation must use the canonical HTTPS registry'
need_line files/scripts/install-native-ai.sh '    /usr/bin/npm ci --prefix "${prefix}" --omit=dev --ignore-scripts --no-audit --fund=false'
need_line files/scripts/install-native-ai.sh "install_locked_npm_payload 'T3' \"\${t3_input_dir}\" \"\${t3_prefix}\""
need_line files/scripts/install-native-ai.sh "install_locked_npm_payload 'Pi' \"\${pi_input_dir}\" \"\${pi_prefix}\""
need_line files/scripts/install-native-ai.sh "readonly t3_binary='/usr/lib/doors/native-ai/t3/node_modules/.bin/t3'"
need_line files/scripts/install-native-ai.sh "readonly pi_binary='/usr/lib/doors/native-ai/pi/node_modules/.bin/pi'"
grep -Fq '  update|uninstall)' files/scripts/install-native-ai.sh \
  || fail 'native T3 wrapper must reject its self-update commands'
grep -Fq 'update the immutable image instead.' files/scripts/install-native-ai.sh \
  || fail 'native T3 wrapper must direct updates to the immutable image'
need_line files/scripts/install-native-ai.sh 'for cuda_command in nvcc ncu ncu-ui nsys nsys-ui; do'
need_line files/scripts/install-native-ai.sh '  ln -sfn "${cuda_root}/bin/${cuda_command}" "/usr/bin/${cuda_command}"'
need_line files/scripts/install-native-ai.sh 'ncu --version >/dev/null'
need_line files/scripts/install-native-ai.sh 'nsys --version >/dev/null'
need_line files/scripts/install-native-ai.sh 'chmod 0755 /usr/bin/t3'
need_line files/scripts/install-native-ai.sh 'chmod 0755 /usr/bin/pi'
need_line files/scripts/install-native-ai.sh 'install -m 0755 "${herdr_artifact}" /usr/bin/herdr'
python3 - <<'PY'
import json
from pathlib import Path

native_root = Path('files/common/usr/share/doors/native-ai')
t3_package = json.loads((native_root / 't3/package.json').read_text(encoding='utf-8'))
t3_lock = json.loads((native_root / 't3/package-lock.json').read_text(encoding='utf-8'))
if t3_package != {
    'name': 'doors-native-t3',
    'version': '1.0.0',
    'private': True,
    'description': 'Pinned native T3 Code CLI installation input for Doors.',
    'dependencies': {'t3': '0.0.42'},
}:
    raise SystemExit('native T3 package input changed unexpectedly')
if t3_lock.get('lockfileVersion') != 3 or t3_lock.get('packages', {}).get('', {}).get('dependencies') != {'t3': '0.0.42'}:
    raise SystemExit('native T3 lockfile shape changed unexpectedly')
expected_t3 = {
    'node_modules/t3': {
        'version': '0.0.42',
        'resolved': 'https://registry.npmjs.org/t3/-/t3-0.0.42.tgz',
        'integrity': 'sha512-B/BiAR9qwG+smhUj7b+R8V6rAsmYMyj0Sz50/KbBMmAy2DhFJdj4PpcAVNWabFHyyEksVtAxYuWjxEa01zg/sw==',
    },
    'node_modules/@t3code/t3-linux-x64': {
        'version': '0.0.42',
        'resolved': 'https://registry.npmjs.org/@t3code/t3-linux-x64/-/t3-linux-x64-0.0.42.tgz',
        'integrity': 'sha512-iRdhsW7qoQnTW+cChqMmuZwfakz90z5tpi3wA/Jg4AwljXF07o64Rhkf26TyMy0V3BWu5AAHTNFhK3znTMm1uA==',
    },
}
for lock_path, fields in expected_t3.items():
    if {field: t3_lock['packages'].get(lock_path, {}).get(field) for field in fields} != fields:
        raise SystemExit(f'native T3 lockfile identity changed unexpectedly: {lock_path}')

pi_package = json.loads((native_root / 'pi/package.json').read_text(encoding='utf-8'))
pi_lock = json.loads((native_root / 'pi/package-lock.json').read_text(encoding='utf-8'))
if pi_package != {
    'name': 'doors-native-pi',
    'version': '1.0.0',
    'private': True,
    'description': 'Pinned native Pi coding agent installation input for Doors.',
    'dependencies': {'@earendil-works/pi-coding-agent': '0.85.1'},
}:
    raise SystemExit('native Pi package input changed unexpectedly')
if pi_lock.get('lockfileVersion') != 3 or pi_lock.get('packages', {}).get('', {}).get('dependencies') != {
    '@earendil-works/pi-coding-agent': '0.85.1',
}:
    raise SystemExit('native Pi lockfile shape changed unexpectedly')
expected_pi = {
    'version': '0.85.1',
    'resolved': 'https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-0.85.1.tgz',
    'integrity': (
        'sha512-FGRN+OHbWaefBPGaTggAdLjrIHW+s2PzLyglz/5d'
        'fLzb9of7uuXMXYC0fJIeZTw+shS32o2cuQ9jF7YSDuL/oQ=='
    ),
}
pi_entry = pi_lock['packages'].get('node_modules/@earendil-works/pi-coding-agent', {})
if {field: pi_entry.get(field) for field in expected_pi} != expected_pi:
    raise SystemExit('native Pi lockfile identity changed unexpectedly')
PY
need_line files/common/etc/profile.d/doors-cuda.sh 'if [[ -d /usr/lib/doors/cuda-13.4 ]]; then'
need_line files/common/etc/profile.d/doors-cuda.sh '  export CUDA_HOME=/usr/lib/doors/cuda-13.4'
need_line files/common/usr/bin/doors-ai '  doors-ai status'
need_line files/common/usr/bin/doors-ai '  doors-ai run <command> [args...]'
if grep -Ein 'distrobox|podman|export-app|export-tool|recreate|bootstrap' \
  files/common/usr/bin/doors-ai; then
  fail 'native Doors AI helper retains container/export behavior'
fi
need_file files/justfiles/doors.just
need_line files/justfiles/doors.just '    doors-ai run /usr/bin/bash -lc {{ quote(ARGS) }}'
for recipe in \
  'doors-ai-shell:' \
  'doors-ai-run +ARGS:' \
  'doors-ai-status:' \
  'doors-secureboot-enroll:'; do
  grep -Fq -- "${recipe}" files/justfiles/doors.just \
    || fail "Doors ujust recipe is missing: ${recipe}"
done
if grep -Ein 'distrobox|export-app|export-tool|recreate|bootstrap' \
  files/justfiles/doors.just; then
  fail 'Doors ujust recipes retain container/export behavior'
fi

# Secure Boot trust material is deliberately public and immutable in Git; only
# the matching private key is mounted ephemerally from the protected workflow.
secureboot_root='files/common/usr/share/doors/secureboot'
need_file "${secureboot_root}/doors-mok.der"
need_file "${secureboot_root}/doors-mok.fingerprint"
need_file files/common/usr/bin/doors-secureboot
need_file files/scripts/sign-secureboot-payloads.sh
need_file docs/SECURE-BOOT-OPERATIONS.md
[[ -x files/common/usr/bin/doors-secureboot ]] || fail 'Doors Secure Boot target helper is not executable'
grep -Fq 'DOORS_MOK_SIGNING_KEY' docs/SECURE-BOOT-OPERATIONS.md   || fail 'Secure Boot operations runbook must name the protected MOK secret'
grep -Fq 'MokManager' docs/SECURE-BOOT-OPERATIONS.md   || fail 'Secure Boot operations runbook must preserve the physical-owner enrollment boundary'
[[ "$(find "${secureboot_root}" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)" == $'doors-mok.der\ndoors-mok.fingerprint' ]] \
  || fail 'Secure Boot directory must contain only the public certificate and its fingerprint'
certificate_subject="$(openssl x509 -inform DER -in "${secureboot_root}/doors-mok.der" \
  -noout -subject -nameopt RFC2253 | sed 's/^subject=//')"
[[ "${certificate_subject}" == 'CN=Doors Secure Boot MOK' ]] \
  || fail 'Doors MOK certificate has an unexpected subject'
certificate_fingerprint="$(openssl x509 -inform DER -in "${secureboot_root}/doors-mok.der" \
  -noout -fingerprint -sha256 | cut -d= -f2 | tr 'A-F' 'a-f')"
[[ "$(cat "${secureboot_root}/doors-mok.fingerprint")" == "sha256:${certificate_fingerprint}" ]] \
  || fail 'tracked Doors MOK fingerprint does not match the DER certificate'
certificate_text="$(openssl x509 -inform DER -in "${secureboot_root}/doors-mok.der" -noout -text)"
grep -Fq 'CA:FALSE' <<<"${certificate_text}" \
  || fail 'Doors MOK must be an end-entity certificate'
grep -Fq 'Digital Signature' <<<"${certificate_text}" \
  || fail 'Doors MOK must permit code signing'
grep -Fq 'Code Signing' <<<"${certificate_text}" \
  || fail 'Doors MOK must retain the general code-signing EKU for kernel and module payloads'
private_mok_files="$(find "${secureboot_root}" -type f \( -name '*.key' -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' \) -print)"
[[ -z "${private_mok_files}" ]] \
  || fail 'MOK private material must never be tracked in the image source tree'
tracked_private_keys="$(git ls-files | grep -Ei '\.(key|pem|p12|pfx)$' || true)"
[[ -z "${tracked_private_keys}" ]] \
  || fail 'private-key container formats must never be tracked anywhere in the repository'
need_line files/common/usr/bin/doors-secureboot "readonly certificate='/usr/share/doors/secureboot/doors-mok.der'"
need_line files/common/usr/bin/doors-secureboot "readonly fingerprint_file='/usr/share/doors/secureboot/doors-mok.fingerprint'"
for required_fragment in \
  'DOORS_MOK_KEY_PATH' \
  'DOORS_MOK_FINGERPRINT_FILE' \
  'the tracked MOK fingerprint does not match the public certificate' \
  "-name 'vmlinuz*' -o -name '*.efi' -o -name '*.efi.signed'" \
  'sbsign --key "${mok_key}"' \
  '"${sign_file}" sha256 "${mok_key}"' \
  'sbverify --cert "${certificate_pem}"' \
  'modinfo -F signer' \
  'depmod -a "${kernel_version}"' \
  'dnf5 install -y --setopt=install_weak_deps=False kernel-devel' \
  'dnf5 remove -y kernel-devel' \
  'remove_transient_kernel_devel'; do
  grep -Fq -- "${required_fragment}" files/scripts/sign-secureboot-payloads.sh \
    || fail "Secure Boot signer lacks required behavior: ${required_fragment}"
done
if grep -Eq '(cp|install|cat)[^[:cntrl:]]*(mok_key|doors-mok\.key)' files/scripts/sign-secureboot-payloads.sh; then
  fail 'Secure Boot signer must not copy or print the MOK private key'
fi
need_line files/common/usr/bin/doors-secureboot '    sudo mokutil --import "${certificate}"'
need_line files/common/usr/bin/doors-secureboot '  sudo mokutil --trust-mok'
grep -Fq 'MokManager' files/common/usr/bin/doors-secureboot \
  || fail 'MOK helper must state the required physical MokManager approval boundary'

# Fedora 44 pinning applies to all host RPM repository routes.
for repo_file in files/dnf/terra.repo files/dnf/cuda-fedora44.repo files/dnf/faugus.repo files/dnf/helium.repo files/dnf/ublue-packages.repo; do
  if grep -Fq '$releasever' "${repo_file}"; then
    fail "repository must use an explicit Fedora 44 stream: ${repo_file}"
  fi
done
need_line files/dnf/terra.repo 'name=Terra 44'
need_line files/dnf/terra.repo 'baseurl=https://repos.fyralabs.com/terra44'
need_line files/dnf/faugus.repo 'baseurl=https://download.copr.fedorainfracloud.org/results/faugus/faugus-launcher/fedora-44-$basearch/'
need_line files/dnf/helium.repo 'baseurl=https://download.copr.fedorainfracloud.org/results/imput/helium/fedora-44-$basearch/'
need_line files/dnf/ublue-packages.repo 'baseurl=https://download.copr.fedorainfracloud.org/results/ublue-os/packages/fedora-44-$basearch/'
need_line files/dnf/cuda-fedora44.repo 'baseurl=https://developer.download.nvidia.com/compute/cuda/repos/fedora44/x86_64'
for repo in files/dnf/terra.repo files/dnf/cuda-fedora44.repo files/dnf/brave-origin.repo files/dnf/faugus.repo files/dnf/helium.repo files/dnf/ublue-packages.repo; do
  need_line "$repo" 'gpgcheck=1'
  need_line "$repo" 'skip_if_unavailable=False'
  if grep -Eq '^[[:space:]]*(baseurl|mirrorlist|metalink)[[:space:]]*=[[:space:]]*http://' "$repo"; then
    fail "tracked RPM repository permits HTTP transport: ${repo}"
  fi
done
need_file files/scripts/enforce-rpm-https.sh
need_line files/scripts/enforce-rpm-https.sh "readonly dnf_config_dir='/etc/dnf/libdnf5.conf.d'"
need_line files/scripts/enforce-rpm-https.sh 'sslverify=True'
grep -Fq 'protocol=https' files/scripts/enforce-rpm-https.sh \
  || fail 'RPM HTTPS policy must force Fedora metalinks to request HTTPS mirrors'
need_line files/dnf/terra.repo 'baseurl=https://repos.fyralabs.com/terra44'
need_line files/dnf/terra.repo 'repo_gpgcheck=1'
need_line files/dnf/brave-origin.repo 'repo_gpgcheck=1'
need_line files/dnf/faugus.repo 'repo_gpgcheck=0'
need_line files/dnf/helium.repo 'repo_gpgcheck=0'
need_line files/dnf/ublue-packages.repo 'repo_gpgcheck=0'
need_line files/dnf/cuda-fedora44.repo 'repo_gpgcheck=1'
need_line files/dnf/cuda-fedora44.repo 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-cuda'
need_line files/dnf/cuda-fedora44.repo 'excludepkgs=cuda-drivers* nvidia-driver* nvidia-modprobe* nvidia-persistenced* nvidia-settings* nvidia-libXNVCtrl* nvidia-xconfig*'
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
import subprocess
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
if len(verification_build_steps) != 2 or any(step.get('with', {}).get('push') is not False for step in verification_build_steps) or '${{ secrets.SIGNING_SECRET }}' in str(verification) or '${{ secrets.DOORS_MOK_SIGNING_KEY }}' in str(verification):
    raise SystemExit('untrusted verification must be non-publishing, production-secret-free, and retry at most once')
ephemeral_cosign_steps = [
    step for step in verification.get('steps', [])
    if step.get('name') == 'Generate ephemeral non-publishing signing key'
]
if len(ephemeral_cosign_steps) != 1:
    raise SystemExit('verification must generate exactly one candidate-only Cosign key')
ephemeral_cosign_run = ephemeral_cosign_steps[0].get('run', '')
for required_fragment in (
    "COSIGN_PASSWORD='' cosign generate-key-pair",
    'while IFS= read -r pem_line',
    '::add-mask::',
    'DOORS_TEST_COSIGN_PRIVATE_KEY<<DOORS_TEST_COSIGN_EOF',
    '>> "$GITHUB_ENV"',
):
    if required_fragment not in ephemeral_cosign_run:
        raise SystemExit(f'verification ephemeral Cosign log protection is missing: {required_fragment}')
if 'GITHUB_OUTPUT' in ephemeral_cosign_run or '${{ steps.ephemeral_cosign.outputs.private_key }}' in str(verification):
    raise SystemExit('candidate Cosign private material must not travel through an unmasked step output')
if any(step.get('with', {}).get('cosign_private_key') != '${{ env.DOORS_TEST_COSIGN_PRIVATE_KEY }}' for step in verification_build_steps):
    raise SystemExit('candidate Cosign key must be inherited from masked GITHUB_ENV by each compose attempt')
ephemeral_mok_steps = [step for step in verification.get('steps', []) if step.get('id') == 'ephemeral_mok']
if len(ephemeral_mok_steps) != 1:
    raise SystemExit('verification must generate exactly one candidate-only MOK pair')
ephemeral_mok_run = ephemeral_mok_steps[0].get('run', '')
for required_fragment in (
    'openssl req -x509 -newkey rsa:4096',
    "-subj '/CN=Doors Secure Boot MOK/'",
    'basicConstraints=critical,CA:FALSE',
    'keyUsage=critical,digitalSignature',
    'extendedKeyUsage=codeSigning',
    'files/common/usr/share/doors/secureboot/doors-mok.der',
    'files/common/usr/share/doors/secureboot/doors-mok.fingerprint',
):
    if required_fragment not in ephemeral_mok_run:
        raise SystemExit(f'verification ephemeral MOK generation is missing: {required_fragment}')
for required_fragment in (
    'while IFS= read -r pem_line',
    '::add-mask::',
    'DOORS_MOK_SIGNING_KEY<<DOORS_MOK_EOF',
    '>> "$GITHUB_ENV"',
):
    if required_fragment not in ephemeral_mok_run:
        raise SystemExit(f'verification ephemeral MOK log protection is missing: {required_fragment}')
if 'GITHUB_OUTPUT' in ephemeral_mok_run or '${{ steps.ephemeral_mok.outputs.private_key }}' in str(verification):
    raise SystemExit('candidate MOK private material must not travel through an unmasked step output')
if any('DOORS_MOK_SIGNING_KEY' in step.get('env', {}) for step in verification_build_steps):
    raise SystemExit('candidate MOK must be inherited from masked GITHUB_ENV, not logged as an action env input')
archive_dir = '${{ runner.temp }}/doors-candidate'
if any(step.get('env', {}).get('BB_BUILD_ARCHIVE') != archive_dir for step in verification_build_steps):
    raise SystemExit('every verification composition attempt must emit the reviewed OCI candidate archive')

boot_step_names = {
    'Prepare non-published candidate archive',
    'Fail closed if retry did not recover',
    'Reclaim compose cache before QCOW2 materialization',
    'Materialize ${{ matrix.id }} candidate as a QCOW2 disk',
    'Boot ${{ matrix.id }} QCOW2 with direct os-autoinst',
    'Upload failed boot-validation evidence',
}
boot_steps = {step.get('name'): step for step in verification.get('steps', []) if step.get('name') in boot_step_names}
if set(boot_steps) != boot_step_names:
    raise SystemExit(f'verification boot gate lacks required steps: {sorted(boot_step_names - set(boot_steps))}')
archive_step = boot_steps['Prepare non-published candidate archive']
reclaim_step = boot_steps['Reclaim compose cache before QCOW2 materialization']
materialize_step = boot_steps['Materialize ${{ matrix.id }} candidate as a QCOW2 disk']
boot_step = boot_steps['Boot ${{ matrix.id }} QCOW2 with direct os-autoinst']
upload_step = boot_steps['Upload failed boot-validation evidence']
key_cleanup_steps = [
    step for step in verification.get('steps', [])
    if step.get('name') == 'Remove ephemeral candidate MOK private key'
]
if len(key_cleanup_steps) != 1 or key_cleanup_steps[0].get('if') != 'always()':
    raise SystemExit('verification must remove and clear its ephemeral candidate keys after all compose attempts')
for required_fragment in ('"${RUNNER_TEMP}/doors-test-mok.key"', '"${RUNNER_TEMP}/doors-test-cosign.key"', "printf 'DOORS_MOK_SIGNING_KEY=\\n'", "printf 'DOORS_TEST_COSIGN_PRIVATE_KEY=\\n'", '>> "$GITHUB_ENV"'):
    if required_fragment not in key_cleanup_steps[0].get('run', ''):
        raise SystemExit(f'verification ephemeral MOK cleanup is missing: {required_fragment}')
reclaim_run = reclaim_step.get('run', '')
for required_fragment in ('docker buildx ls', 'docker buildx inspect bluebuild', 'docker buildx prune --builder bluebuild --all --force', 'docker buildx prune --all --force', 'docker system prune --all --force --volumes', 'sudo podman system prune --all --force --volumes', 'df -h /'):
    if required_fragment not in reclaim_run:
        raise SystemExit(f'verification QCOW2 cache reclamation is missing: {required_fragment}')
if 'mkdir -p "${RUNNER_TEMP}/doors-candidate"' not in archive_step.get('run', ''):
    raise SystemExit('verification must prepare the BlueBuild archive directory')
if materialize_step.get('env', {}).get('CANDIDATE_ARCHIVE') != '${{ runner.temp }}/doors-candidate/${{ matrix.id }}.tar.gz':
    raise SystemExit('verification must convert the exact per-matrix BlueBuild archive')
materialize_run = materialize_step.get('run', '')
for required_fragment in ('test -s "${CANDIDATE_ARCHIVE}"', 'sha256sum "${CANDIDATE_ARCHIVE}"', 'oci-archive:${CANDIDATE_ARCHIVE}', 'containers-storage:${CANDIDATE_IMAGE}', 'rm -f -- "${CANDIDATE_ARCHIVE}"', 'Disk usage before QCOW2 materialization:', 'BOOTC_IMAGE_BUILDER', 'build', '--type qcow2', '--output /output', '--config /config.toml', '${CANDIDATE_IMAGE}'):
    if required_fragment not in materialize_run:
        raise SystemExit(f'verification boot conversion is missing: {required_fragment}')
if materialize_step.get('env', {}).get('BOOTC_IMAGE_BUILDER') != 'ghcr.io/osbuild/bootc-image-builder:v83.0.0@sha256:e7aadce6b3f5639cd47d83354791931ea219891a0d113c2fe74a0f0d352b165c':
    raise SystemExit('verification bootc-image-builder must remain the reviewed pinned image')
for required_fragment in ('[[customizations.filesystem]]', 'mountpoint = "/"', 'minsize = "40 GiB"', 'console=tty0 console=ttyS0,115200n8'):
    if required_fragment not in materialize_run:
        raise SystemExit(f'verification QCOW2 conversion is missing required test-disk configuration: {required_fragment}')
boot_run = boot_step.get('run', '')
for required_fragment in ('--env CI=1', '--exit-status-from-test-results', 'QEMU_NO_KVM=1', 'CASEDIR=/tests', 'NEEDLES_DIR=needles', 'HDD_1=qcow2/disk.qcow2', 'UEFI=1', 'QEMURAM=4096', 'SCHEDULE=tests/boot.pm'):
    if required_fragment not in boot_run:
        raise SystemExit(f'verification os-autoinst invocation is missing: {required_fragment}')
if '_EXIT_AFTER_SCHEDULE' in boot_run:
    raise SystemExit('verification must run the scheduled boot test, not exit after loading it')
try:
    subprocess.run(['bash', '-n'], input=boot_run, text=True, check=True, capture_output=True)
except subprocess.CalledProcessError as error:
    raise SystemExit('verification os-autoinst shell syntax is invalid: ' + error.stderr.strip()) from error
if boot_step.get('env', {}).get('ISOTOVIDEO_IMAGE') != 'registry.opensuse.org/devel/openqa/containers/isotovideo:qemu-x86@sha256:273253ef539b8d78bdb0f235831222c1270da1b65d88c680e1a59b67be7dadcf':
    raise SystemExit('verification isotovideo runner must remain the reviewed pinned no-KVM image')
if 'boot-test:/tests:ro' not in boot_run or 'boot-test/artifacts:/work' not in boot_run:
    raise SystemExit('verification os-autoinst gate must use the repository-local test and artifact directory')
upload_path = upload_step.get('with', {}).get('path', '')
if upload_step.get('if') != 'failure()' or 'boot-test/artifacts' not in str(upload_path):
    raise SystemExit('verification must upload boot diagnostics only on failure')
if '!boot-test/artifacts/qcow2/disk.qcow2' not in str(upload_path):
    raise SystemExit('verification failure evidence must exclude the oversized generated QCOW2 disk')
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
if any(step.get('env', {}).get('DOORS_MOK_SIGNING_KEY') != '${{ secrets.DOORS_MOK_SIGNING_KEY }}' for step in publication_build_steps):
    raise SystemExit('protected production MOK key may be supplied only to trusted stable BlueBuild publication actions')
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
if any(step.get('env', {}).get('DOORS_MOK_SIGNING_KEY') != '${{ secrets.DOORS_MOK_SIGNING_KEY }}' for step in staging_build_steps):
    raise SystemExit('protected production MOK key may be supplied only to trusted staging BlueBuild publication actions')
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

# The production MOK secret must never appear outside the four protected
# BlueBuild publication action environments (stable primary/retry and staging
# primary/retry). Candidate jobs use only their generated disposable key.
if build_raw.count('${{ secrets.DOORS_MOK_SIGNING_KEY }}') != 2 or staging_raw.count('${{ secrets.DOORS_MOK_SIGNING_KEY }}') != 2:
    raise SystemExit('production MOK secret references must remain limited to trusted primary/retry publication actions')

# Every action is commit-pinned, including identity handoff actions. Artifact
# uploads additionally share one revision: a partial action bump must not leave
# the failure-evidence path on an obsolete implementation.
upload_artifact_pins = set()
for workflow in Path('.github/workflows').glob('*.yml'):
    for line in workflow.read_text(encoding='utf-8').splitlines():
        match = re.match(r'\s*uses:\s*([^\s#]+)', line)
        if match and not re.search(r'@[0-9a-f]{40}$', match.group(1)):
            raise SystemExit(f'action is not commit-pinned: {workflow}: {match.group(1)}')
        if match and match.group(1).startswith('actions/upload-artifact@'):
            upload_artifact_pins.add(match.group(1))
if len(upload_artifact_pins) != 1:
    raise SystemExit('all artifact handoff and boot-evidence uploads must use one reviewed pinned release')
PY

# The direct os-autoinst distribution stays repository-local and deliberately
# read-only: it observes a serial boot rather than interacting with a guest.
need_file boot-test/main.pm
need_file boot-test/tests/boot.pm
need_file boot-test/needles/.gitkeep
need_line boot-test/main.pm "autotest::loadtest 'tests/boot.pm';"
for boot_gate_fragment in \
  'Linux[ ]version' \
  'systemd[[]1[]]:' \
  'Kernel[ ]panic' \
  'Entering[ ]emergency[ ]mode' \
  'expect_not_found => 1' \
  'Greenboot[ ]Health[ ]Checks[ ]Runner' \
  'wait_serial'; do
  grep -Fq -- "${boot_gate_fragment}" boot-test/tests/boot.pm \
    || fail "boot validation lacks required serial gate: ${boot_gate_fragment}"
done
need_line boot-test/tests/boot.pm '    my $ansi_sgr = qr/\e\[[0-9;]*m/;'
need_line boot-test/tests/boot.pm '    my $qemu_no_gpu_service = qr/'
need_line boot-test/tests/boot.pm '        nvidia-cdi-refresh'
need_line boot-test/tests/boot.pm '        (?=[[:space:]]|$ansi_sgr|[^\x00-\x7f]|$)'
need_line boot-test/tests/boot.pm '        Failed[ ]to[ ]start[ ](?!$qemu_no_gpu_service)'
need_line boot-test/tests/boot.pm '    my $greenboot_complete = qr/Finished[ ].{0,160}Greenboot[ ]Health[ ]Checks[ ]Runner/imx;'
need_line boot-test/tests/boot.pm "    die 'Doors boot gate did not observe a successful Greenboot health check' unless defined \$greenboot;"
need_line boot-test/tests/boot.pm "    die 'Doors boot gate observed a fatal serial signature after boot completion' unless defined \$fatal_after_boot;"
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

# Secret-scanning exceptions are limited to reviewed public material: the two
# legacy/current Flathub key lines and one exact NVIDIA CUDA public-key digest.
need_file .gitleaks.toml
python3 - <<'PY'
import tomllib
from pathlib import Path


config = tomllib.loads(Path('.gitleaks.toml').read_text(encoding='utf-8'))
def expected_cuda_checksum():
    return '9221458f62030a18d5a28eecf44496016ff9c11548492ac2ce428f75c7513cab'


expected = {
    'title': 'Doors secret-scanning policy',
    'extend': {'useDefault': True},
    'allowlists': [
        {
            'description': 'Allow public commit identifiers preserved in raw Trivy evidence',
            'targetRules': ['sourcegraph-access-token'],
            'condition': 'AND',
            'paths': [r'^audit/raw/trivy-current-doors-(?:secrets|vuln-misconfig)\.json$'],
            'regexTarget': 'line',
            'regexes': [
                r'https?://github\.com/[^/[:space:]]+/[^/[:space:]]+/commit/[0-9a-f]{40}',
                r'^[[:space:]]*"Version":[[:space:]]*"[0-9a-f]{40}",[[:space:]]*$',
            ],
        },
        {
            'description': 'Allow the reviewed NVIDIA CUDA public-key checksum in its verifier',
            'targetRules': ['generic-api-key'],
            'condition': 'AND',
            'paths': [r'^files/scripts/verify-common\.sh$'],
            'regexTarget': 'line',
            'regexes': [
                r"^[[:space:]]*cuda_key_sha256='" + expected_cuda_checksum() + r"'$",
            ],
        },
    ],
}
if config != expected:
    raise SystemExit('Gitleaks policy must retain only its reviewed narrow exceptions')
PY
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
expect_key_fingerprints files/dnf/cuda-fedora44.gpg \
  129994480EC63D2789BC98E490DFED2F73CD9B30
[[ "$(sha256sum files/dnf/cuda-fedora44.gpg | awk '{print $1}')" == '9221458f62030a18d5a28eecf44496016ff9c11548492ac2ce428f75c7513cab' ]] \
  || fail 'NVIDIA CUDA signing key digest changed unexpectedly'
expect_key_fingerprints files/dnf/brave.gpg \
  DBF1A116C220B8C7164F98230686B78420038257 \
  47D32A74E9A9E013A4B4926C68D513D36A73CD96 \
  B2A3DCA350E67256740DF904DE4EC67BE4B0DCA0
cmp -s files/dnf/ublue-packages.gpg files/common/etc/pki/rpm-gpg/RPM-GPG-KEY-ublue-packages \
  || fail 'compose and retained UBlue package signing keys must be identical'
cmp -s files/dnf/brave.gpg files/common/etc/pki/rpm-gpg/RPM-GPG-KEY-brave \
  || fail 'compose and retained Brave signing keys must be identical'
cmp -s files/dnf/cuda-fedora44.gpg files/common/etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-cuda \
  || fail 'compose and retained NVIDIA CUDA signing keys must be identical'
cmp -s files/dnf/cuda-fedora44.repo files/cuda-runtime-repo/etc/yum.repos.d/cuda-fedora44.repo \
  || fail 'compose and retained NVIDIA CUDA repository definitions must be identical'

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
if grep -RInE 'docker\.io/library/archlinux|distrobox-export|distrobox assemble|distrobox-upgrade' \
  files/common/usr files/scripts files/justfiles; then
  fail 'retired Distrobox integration remains in native image payload'
fi
if grep -RInF 'com.ranfdev.DistroShelf' files recipes docs README.md audit \
  --exclude-dir=raw; then
  fail 'retired Distrobox manager remains in active policy/documentation'
fi

# Generated Herdr artifacts are CI-only and must never enter Git history.
if git ls-files --error-unmatch files/generated/herdr/herdr-linux-x86_64 >/dev/null 2>&1 \
  || git ls-files --error-unmatch files/generated/herdr/herdr.json >/dev/null 2>&1; then
  fail 'generated Herdr artifacts must not be version-controlled'
fi

git diff --check
printf '%s\n' 'Repository static validation passed.'
