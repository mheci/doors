#!/usr/bin/env bash
# Runs inside the rootless Arch Linux Doors AI Distrobox. The immutable host
# never receives AI harnesses or the CUDA toolkit; pacman uses only Arch's
# signed official repositories, with no AUR helper or external package repo.
set -euo pipefail

readonly doors_dir='/opt/doors'
readonly completion_marker='/var/lib/doors-ai/provisioned'
readonly bun_repository='oven-sh/bun'
readonly bun_asset='bun-linux-x64.zip'
readonly pi_package='@earendil-works/pi-coding-agent'
readonly t3_package='t3'

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo -- "$@"
  fi
}

[[ -e "${completion_marker}" ]] && exit 0
for required in \
  "${doors_dir}/keys/bun-release-key.asc" \
  "${doors_dir}/herdr/herdr-linux-x86_64" \
  "${doors_dir}/herdr/herdr.json"; do
  [[ -s "${required}" ]] || { echo "Doors AI input is missing: ${required}" >&2; exit 1; }
done

# Keep the pacman trust root current while upgrading and installing the entire
# supported toolchain in one signed official-repository transaction. `cuda`
# supplies /opt/cuda and nvcc; host GPU driver access comes from Distrobox's
# NVIDIA integration, so this container intentionally does not install
# nvidia-utils or any driver package.
as_root pacman -Syu --noconfirm --needed \
  archlinux-keyring \
  base-devel git nodejs npm pnpm python python-pip deno mise opencode cuda
[[ -x /opt/cuda/bin/nvcc ]] || { echo 'Arch cuda package did not provide nvcc' >&2; exit 1; }
as_root ln -sfn /opt/cuda/bin/nvcc /usr/local/bin/nvcc
/usr/local/bin/nvcc --version >/dev/null

# Bun is accepted only after a clear-signed release checksum verifies against
# the reviewed vendored release key, then its binary reports the signed tag.
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
export GNUPGHOME="${workdir}/gnupg"
mkdir -m 0700 "${GNUPGHOME}"
gpg --batch --import "${doors_dir}/keys/bun-release-key.asc" >/dev/null
release_json="$(curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --silent --show-error \
  "https://api.github.com/repos/${bun_repository}/releases/latest")"
tag="$(jq --raw-output '.tag_name // empty' <<<"${release_json}")"
[[ "${tag}" =~ ^bun-v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { echo "Unexpected Bun stable release tag: ${tag:-<empty>}" >&2; exit 1; }
base_url="https://github.com/${bun_repository}/releases/download/${tag}"
curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --silent --show-error \
  "${base_url}/SHASUMS256.txt.asc" --output "${workdir}/SHASUMS256.txt.asc"
gpg --batch --decrypt --output "${workdir}/SHASUMS256.txt" "${workdir}/SHASUMS256.txt.asc" >/dev/null
awk -v asset="${bun_asset}" '$2 == asset { print }' "${workdir}/SHASUMS256.txt" > "${workdir}/${bun_asset}.sha256"
[[ "$(wc -l < "${workdir}/${bun_asset}.sha256")" -eq 1 ]] \
  || { echo "Expected exactly one signed checksum for ${bun_asset}" >&2; exit 1; }
curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --silent --show-error \
  "${base_url}/${bun_asset}" --output "${workdir}/${bun_asset}"
(
  cd "${workdir}"
  sha256sum --check "${bun_asset}.sha256"
)
unzip -q "${workdir}/${bun_asset}" -d "${workdir}/bun"
as_root install -m 0755 "${workdir}/bun/bun-linux-x64/bun" /usr/local/bin/bun
[[ "$(/usr/local/bin/bun --version)" == "${tag#bun-v}" ]] \
  || { echo 'Verified Bun binary version differs from signed release tag' >&2; exit 1; }

# Pi and T3 Code are published through npm. Use the canonical registry, honor
# npm integrity metadata, and forbid package lifecycle hooks during install.
as_root env \
  npm_config_registry='https://registry.npmjs.org/' \
  npm_config_prefix='/usr/local' \
  npm_config_cache='/var/tmp/doors-ai-npm-cache' \
  npm install --global --omit=dev --ignore-scripts \
  "${pi_package}@latest" "${t3_package}@latest"
/usr/local/bin/pi --version >/dev/null
/usr/local/bin/t3 --help >/dev/null
as_root rm -rf /var/tmp/doors-ai-npm-cache

# Herdr enters only as the CI-prepared immutable release artifact. The mounted
# manifest is generated after GitHub release-attestation verification in CI.
artifact="${doors_dir}/herdr/herdr-linux-x86_64"
manifest="${doors_dir}/herdr/herdr.json"
repository="$(jq --raw-output '.repository // empty' "${manifest}")"
release_tag="$(jq --raw-output '.tag // empty' "${manifest}")"
expected_sha256="$(jq --raw-output '.sha256 // empty' "${manifest}")"
asset="$(jq --raw-output '.asset // empty' "${manifest}")"
[[ "${repository}" == 'herdrdev/herdr' && "${asset}" == 'herdr-linux-x86_64' ]] \
  && [[ "${release_tag}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  && [[ "${expected_sha256}" =~ ^[0-9a-f]{64}$ ]] \
  || { echo 'Herdr verification manifest has an unexpected identity or shape' >&2; exit 1; }
actual_sha256="$(sha256sum "${artifact}" | awk '{print $1}')"
[[ "${actual_sha256}" == "${expected_sha256}" ]] \
  || { echo 'Herdr artifact digest does not match verified manifest' >&2; exit 1; }
as_root install -m 0755 "${artifact}" /usr/local/bin/herdr
/usr/local/bin/herdr --version >/dev/null

# Record success only after every installer and verification succeeds.
as_root install -d -m 0755 "$(dirname "${completion_marker}")"
as_root touch "${completion_marker}"
