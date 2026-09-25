#!/usr/bin/env bash
# Install the latest stable proton-cachyos release system-wide for native Steam.
#
# Steam scans /usr/share/steam/compatibilitytools.d, so the tool appears in
# every account's compatibility list with no per-user download. Because this
# runs during image composition, the shipped version advances with each
# weekly rebuild; users who want a different build can still add one through
# ProtonPlus in their own home directory.
#
# The release is resolved through GitHub's /releases/latest redirect, which
# never points at a pre-release, and the archive is verified against the
# .sha512sum the project publishes beside it. x86_64_v3 is a deliberate
# choice: Doors targets Turing-or-newer NVIDIA systems, all of which sit on
# CPUs with AVX2/BMI2.
set -euo pipefail

readonly repository='CachyOS/proton-cachyos'
readonly variant='x86_64_v3'
readonly destination='/usr/share/steam/compatibilitytools.d'
readonly version_file='/usr/share/doors/proton-cachyos.version'
readonly work_dir='/tmp/doors-proton-cachyos'

fail() {
  printf 'Doors proton-cachyos: %s\n' "$*" >&2
  exit 1
}

if [[ "$(uname -m)" != 'x86_64' ]]; then
  printf 'Doors proton-cachyos: skipped on %s (x86_64 only).\n' "$(uname -m)"
  exit 0
fi

command -v curl >/dev/null || fail 'curl is required'
command -v xz >/dev/null || fail 'xz is required'

rm -rf "${work_dir}"
mkdir -p "${work_dir}" "${destination}" "$(dirname "${version_file}")"
cd "${work_dir}"

# Resolve the latest stable tag without the rate-limited REST API.
latest_url="$(curl --fail --silent --show-error --location --head \
  --proto '=https' --tlsv1.2 --output /dev/null --write-out '%{url_effective}' \
  "https://github.com/${repository}/releases/latest")"
tag="${latest_url##*/}"
[[ "${tag}" =~ ^cachyos-[0-9]+\.[0-9]+-[0-9]{8}-slr$ ]] \
  || fail "unexpected release tag from ${latest_url}: ${tag}"

asset="proton-${tag}-${variant}.tar.xz"
base="https://github.com/${repository}/releases/download/${tag}"
for file in "${asset}" "${asset%.tar.xz}.sha512sum"; do
  curl --fail --silent --show-error --location --retry 3 --retry-delay 5 \
    --proto '=https' --tlsv1.2 --output "${file}" "${base}/${file}"
  [[ -s "${file}" ]] || fail "empty download: ${file}"
done

# The published checksum file names the archive; verify it as shipped and
# refuse any other shape rather than guessing which field is the digest.
grep -Eq "^[0-9a-f]{128}[[:space:]]+\*?${asset}$" "${asset%.tar.xz}.sha512sum" \
  || fail 'checksum file does not describe the downloaded archive'
sha512sum --check --status "${asset%.tar.xz}.sha512sum" \
  || fail 'archive digest does not match the published sha512sum'

# One top-level directory is expected; it becomes the tool's install name.
top_dir="$(tar --list --xz --file "${asset}" | head -n 1 | cut -d/ -f1)"
[[ -n "${top_dir}" && "${top_dir}" != '.' && "${top_dir}" != /* ]] \
  || fail "unexpected archive layout (top entry: '${top_dir}')"
[[ "$(tar --list --xz --file "${asset}" | cut -d/ -f1 | sort -u | wc -l)" -eq 1 ]] \
  || fail 'archive contains more than one top-level entry'

# Replace any prior proton-cachyos build so the image never carries two.
find "${destination}" -maxdepth 1 -mindepth 1 -type d -name 'proton-cachyos-*' -exec rm -rf {} +
tar --extract --xz --file "${asset}" --directory "${destination}" \
  --no-same-owner --no-same-permissions
install_dir="${destination}/${top_dir}"
for required in compatibilitytool.vdf toolmanifest.vdf proton; do
  [[ -e "${install_dir}/${required}" ]] || fail "installed tree is missing ${required}"
done
[[ -x "${install_dir}/proton" ]] || chmod 0755 "${install_dir}/proton"
chown -R root:root "${install_dir}"

printf '%s\n' "${tag#cachyos-}-${variant}" > "${version_file}"
cd /
rm -rf "${work_dir}"
printf 'Doors proton-cachyos: installed %s into %s\n' "${top_dir}" "${destination}"
