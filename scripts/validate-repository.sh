#!/usr/bin/env bash
# Fast, dependency-light invariants for local use and required CI.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "${root}"
fail() { echo "VALIDATION FAIL: $*" >&2; exit 1; }
need_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
need_line() { grep -Fqx -- "$2" "$1" || fail "missing expected line in $1: $2"; }

[[ "$(find recipes -maxdepth 1 -type f -name '*.yml' | wc -l)" -eq 1 ]] \
  || fail 'there must be exactly one recipe'
need_file recipes/doors.yml
need_line recipes/doors.yml 'base-image: ghcr.io/ublue-os/bazzite-gnome-nvidia-open'
need_line recipes/doors.yml 'image-version: latest'
need_line recipes/doors.yml 'blue-build-tag: none'
need_line recipes/doors.yml '  - latest'
if grep -Eq '(^|[[:space:]])type:[[:space:]]+akmods|synchronize-nvidia-mesa\.sh' recipes/doors.yml; then
  fail 'the Bazzite NVIDIA Open base must not layer a second akmods or Mesa synchronization path'
fi
if grep -Eq '^[[:space:]]*-[[:space:]]+gamescope[[:space:]]*$' recipes/doors.yml; then
  fail 'the Bazzite base already supplies terra-gamescope; do not layer Fedora gamescope'
fi
grep -Fq 'vesktop terra-gamescope falcond' files/scripts/verify-image.sh \
  || fail "image verification must require Bazzite's preinstalled terra-gamescope component"
grep -Fq 'vicinae gamescope scx_loader' files/scripts/verify-image.sh \
  || fail 'image verification must require the Gamescope executable'
[[ ! -e files/scripts/synchronize-nvidia-mesa.sh ]] \
  || fail 'the retired Bluefin/akmods Mesa synchronization script must not remain'
need_line recipes/doors.yml '      - enforce-flatpak-policy.sh'
need_file files/scripts/enforce-flatpak-policy.sh
need_line files/scripts/install-pi.sh "readonly PACKAGE='@earendil-works/pi-coding-agent'"
need_line files/scripts/install-pi.sh "export npm_config_registry='https://registry.npmjs.org/'"
need_line files/scripts/enforce-flatpak-policy.sh '[Flatpak Preinstall io.github.kolunmi.Bazaar]'
need_line files/scripts/enforce-flatpak-policy.sh "rm -f /usr/share/ublue-os/privileged-setup.hooks.d/99-flatpaks.sh"
grep -Fqx '  - linux/amd64' recipes/doors.yml || fail 'the NVIDIA-targeted image must stay amd64-only'
need_line .github/workflows/build.yml "    - cron: '0 0 * * 1'"
need_line .github/workflows/build.yml "      github.repository == 'mheci/doors' &&"
need_line .github/workflows/build.yml '          IMAGE: ghcr.io/mheci/doors'
need_line .github/workflows/build.yml '          registry_namespace: mheci'
need_line .github/workflows/build.yml '      packages: read # Authenticates the GHCR pull for the public Bazzite base image.'
[[ "$(grep -Fc '          registry_token: ${{ github.token }}' .github/workflows/build.yml)" -eq 4 ]] \
  || fail 'both build attempts in verification and publication must authenticate their GHCR pulls'
need_line .github/workflows/build.yml '        id: verification_build_retry'
need_line .github/workflows/build.yml '        id: publish_build_retry'
[[ "$(grep -Fc '          sleep 300' .github/workflows/build.yml)" -eq 2 ]] \
  || fail 'each build path must retain exactly one bounded upstream-convergence retry'
need_file .gitleaks.toml
need_file .github/scripts/scan-gitleaks.sh
need_line .github/workflows/ci.yml '        run: ./.github/scripts/scan-gitleaks.sh'
need_line .github/scripts/scan-gitleaks.sh "readonly version='8.30.1'"
need_line .github/scripts/scan-gitleaks.sh "readonly expected_sha256='551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb'"
grep -Fq -- "--redact --log-opts='--all' --config .gitleaks.toml" .github/scripts/scan-gitleaks.sh \
  || fail 'credential scan must use the repository Gitleaks configuration'
if grep -Fq 'gitleaks/gitleaks-action@' .github/workflows/ci.yml; then
  fail 'the legacy Gitleaks action cannot enforce the repository allowlist'
fi

# Autonomous maintenance deliberately divides GitHub Actions pins (Dependabot)
# from every other Renovate-supported dependency source; do not let both bots
# create competing PRs for the same action reference.
need_file .github/dependabot.yml
need_line .github/dependabot.yml '  - package-ecosystem: github-actions'
need_line .github/dependabot.yml '      interval: daily'
need_file .github/workflows/dependabot-automerge.yml
need_line .github/workflows/dependabot-automerge.yml '  workflow_run: # zizmor: ignore[dangerous-triggers] -- no checkout or PR-code execution; API validates Dependabot ownership'
grep -Fq 'gh pr merge "${pr_number}"' .github/workflows/dependabot-automerge.yml \
  || fail 'Dependabot auto-merge must use a validated PR number rather than check out PR code'
grep -Fq '"${author}" != '\''dependabot[bot]'\''' .github/workflows/dependabot-automerge.yml \
  || fail 'Dependabot auto-merge must validate the API-reported Dependabot author'
need_file .github/workflows/dependency-review.yml
need_file .github/workflows/scorecard.yml
need_line .github/workflows/scorecard.yml "    - cron: '27 3 * * 1'"

# Parse every YAML document for syntax without downloading a parser. Prefer
# PyYAML (present on Fedora/GitHub runners); retain Ruby as a local fallback.
if python3 -c 'import yaml' >/dev/null 2>&1; then
  while IFS= read -r -d '' yaml_file; do
    python3 - "$yaml_file" <<'PY'
import pathlib
import sys
import yaml
list(yaml.safe_load_all(pathlib.Path(sys.argv[1]).read_text()))
PY
  done < <(find recipes .github -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)
elif command -v ruby >/dev/null 2>&1; then
  while IFS= read -r -d '' yaml_file; do
    ruby -e 'require "yaml"; YAML.load_stream(File.read(ARGV.fetch(0)))' "$yaml_file" >/dev/null
  done < <(find recipes .github -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)
else
  fail 'neither PyYAML nor Ruby is available to parse YAML'
fi

while IFS= read -r -d '' script; do
  bash -n "$script"
  [[ -x "$script" ]] || fail "script is not executable: $script"
done < <(find files/scripts .github/scripts scripts -type f -name '*.sh' -print0)
python3 -m json.tool renovate.json >/dev/null
python3 - <<'PY'
import json
from pathlib import Path

config = json.loads(Path('renovate.json').read_text(encoding='utf-8'))
if not (config.get('automerge') is True and config.get('platformAutomerge') is True):
    raise SystemExit('Renovate must request protected GitHub native auto-merge')
if config.get('automergeType') != 'pr':
    raise SystemExit('Renovate must merge through pull requests, never direct pushes')
rules = config.get('packageRules', [])
if not any(rule.get('matchManagers') == ['github-actions'] and rule.get('enabled') is False for rule in rules):
    raise SystemExit('Renovate must disable github-actions because Dependabot owns Action pins')
custom_dependencies = {rule.get('depNameTemplate') for rule in config.get('customManagers', [])}
if {'blue-build/cli', 'anchore/syft'} - custom_dependencies:
    raise SystemExit('Renovate must retain the custom BlueBuild CLI and Syft managers')
PY

# Keys are vendored only after manual review. Require the complete fingerprint
# set -- including expected signing subkeys -- not merely a trusted primary, so an
# injected additional key cannot silently widen a repository's trust root.
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
expect_key_fingerprints files/system/usr/share/doors/keys/bun-release-key.asc \
  F3DCC08A8572C0749B3E18888EAB4D40A7B22B59 \
  8CDF8ECABE81CE3F32AC047236FA8E877B80AB05
expect_key_fingerprints files/dnf/brave.gpg \
  DBF1A116C220B8C7164F98230686B78420038257 \
  47D32A74E9A9E013A4B4926C68D513D36A73CD96 \
  B2A3DCA350E67256740DF904DE4EC67BE4B0DCA0

# Required repo-signature policy. COPR metadata signing is unavailable by
# design; its reviewed exception is explicit rather than silently weakened.
for repo in files/dnf/terra.repo files/dnf/brave-origin.repo files/dnf/faugus.repo files/dnf/helium.repo; do
  need_line "$repo" 'gpgcheck=1'
  need_line "$repo" 'skip_if_unavailable=False'
done
need_line files/dnf/terra.repo 'repo_gpgcheck=1'
need_line files/dnf/brave-origin.repo 'repo_gpgcheck=1'
need_line files/dnf/faugus.repo 'repo_gpgcheck=0'
need_line files/dnf/helium.repo 'repo_gpgcheck=0'
# The Faugus COPR must remain the source for its launcher while dependencies
# resolve normally from signed Fedora/Terra repositories.
need_line files/dnf/terra.repo 'excludepkgs=faugus-launcher'
need_line files/dnf/faugus.repo 'includepkgs=faugus-launcher'
need_line files/dnf/faugus.repo 'priority=50'
need_line files/dnf/helium.repo 'includepkgs=helium-bin'
need_line files/dnf/brave-origin.repo 'includepkgs=brave-origin brave-keyring'
need_file files/scripts/harden-brave-keyring.sh
need_line recipes/doors.yml '      - harden-brave-keyring.sh'
need_line files/scripts/harden-brave-keyring.sh 'rm -f /usr/libexec/brave-key-updater'
cmp -s files/dnf/brave.gpg files/system/etc/pki/rpm-gpg/RPM-GPG-KEY-brave \
  || fail 'the compose and retained Brave signing keys must be identical'

# BlueBuild's per-package repo selector also restricts dependency resolution to
# that one repo. The package set intentionally uses the reviewed enabled repo
# set instead, so Fedora dependencies of Terra/COPR packages can resolve.
if grep -Eq '^[[:space:]]*-[[:space:]]+repo:' recipes/doors.yml; then
  fail 'per-package repo selectors would hide required signed dependencies'
fi
if grep -Fq 'type: default-flatpaks' recipes/doors.yml; then
  fail 'BlueBuild default-flatpaks would duplicate Bazzite native preinstallation'
fi

# Desktop defaults are part of the image contract, not optional branding.
# Keep all requested extensions and a safe, user-overridable GNOME-only default
# profile; explicitly forbid an image-selected wallpaper.
dconf_defaults='files/system/etc/dconf/db/local.d/00-doors'
need_file "${dconf_defaults}"
need_line "${dconf_defaults}" "color-scheme='prefer-dark'"
need_line "${dconf_defaults}" "gtk-theme='Yaru-dark'"
need_line "${dconf_defaults}" "font-name='Inter 11'"
need_line "${dconf_defaults}" "monospace-font-name='JetBrains Mono 11'"
need_line "${dconf_defaults}" "dock-position='LEFT'"
need_line "${dconf_defaults}" 'dock-fixed=true'
need_line "${dconf_defaults}" 'autohide=false'
need_line "${dconf_defaults}" "enable-clipboard-monitoring=true"
need_line "${dconf_defaults}" "binding='<Super><Shift>space'"
need_line "${dconf_defaults}" "custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae-toggle/']"
need_line "${dconf_defaults}" '[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae-toggle]'
if grep -Fq 'custom-keybinding:/' "${dconf_defaults}"; then
  fail 'dconf keyfiles must use path sections, not colon-qualified GSettings CLI syntax'
fi
for required_extension in \
  dash-to-dock@micxgx.gmail.com \
  appindicatorsupport@rgcjonas.gmail.com \
  gsconnect@andyholmes.github.io \
  clipboard-indicator@tudmotu.com \
  grand-theft-focus@zalckos.github.com \
  just-perfection-desktop@just-perfection \
  AlphabeticalAppGrid@stuarthayhurst \
  vicinae@dagimg-dot.netlify.app \
  emoji-copy@felipeftn; do
  grep -Fq "${required_extension}" "${dconf_defaults}" \
    || fail "required GNOME extension default is absent: ${required_extension}"
done
if grep -Eq '(^|[[:space:]])(picture-uri|picture-uri-dark|primary-color|secondary-color)[[:space:]]*=' "${dconf_defaults}"; then
  fail 'the image must not impose a wallpaper/background default'
fi
need_line recipes/doors.yml '        - vicinae.service'

# The official systemd module copies this user-unit source and enables it
# globally. Preserve precisely the requested unfiltered regular clipboard scope.
need_file files/systemd/user/wl-clip-persist.service
need_line files/systemd/user/wl-clip-persist.service 'ExecStart=/usr/local/bin/wl-clip-persist --clipboard regular'
need_line recipes/doors.yml '        - wl-clip-persist.service'
need_line .github/scripts/prepare-herdr.sh "readonly minimum_gh_version='2.93.0'"
grep -Fq 'gh release verify-asset "${tag}" "${artifact}" --repo "${repository}"' .github/scripts/prepare-herdr.sh \
  || fail 'Herdr must use immutable-release asset verification'

# Do not permit old bypasses or retired designs in buildable configuration.
if grep -RInE --exclude='validate-repository.sh' --exclude='*.md' \
  --exclude='*.json' --exclude='*.gpg' --exclude='*.asc' \
  '(--nogpgcheck|--nodeps|--noscripts|skip-unavailable|skip-broken|rpm --nodeps|kernel-cachyos|llama\.cpp|Hermes|Lemurs|Hyprland|COSMIC|kinoite-main|[Pp]laywright)' \
  recipes files .github scripts; then
  fail 'forbidden legacy/bypass term found in production configuration'
fi

# Herdr artifacts are CI-generated and must never be committed accidentally.
if git ls-files --error-unmatch files/generated/herdr/herdr-linux-x86_64 >/dev/null 2>&1 \
  || git ls-files --error-unmatch files/generated/herdr/herdr.json >/dev/null 2>&1; then
  fail 'generated Herdr artifacts must not be version-controlled'
fi

git diff --check
printf '%s\n' 'Repository static validation passed.'
