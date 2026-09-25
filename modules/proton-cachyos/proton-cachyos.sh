#!/usr/bin/env bash
# Install the latest Proton-CachyOS release into Steam's system-wide
# compatibility tool directory. Native Steam lists every tool found under
# /usr/share/steam/compatibilitytools.d next to Valve's own Proton builds.
#
# The x86_64_v3 build is deliberate: Doors targets Turing-or-newer NVIDIA
# gaming systems, all of which pair with v3-capable CPUs (Haswell/Zen or
# newer). It gains AVX2 code paths over the generic build.
#
# "Latest" is resolved through GitHub's release redirect rather than the API,
# so the build never hits unauthenticated API rate limits from shared runner
# addresses. The tarball is verified against the sha512sum the project
# publishes with the release. Run this module with `no-cache: true` so a
# weekly rebuild refetches rather than replaying a cached layer.
set -euo pipefail

readonly repository='CachyOS/proton-cachyos'
readonly variant='x86_64_v3'
readonly install_root='/usr/share/steam/compatibilitytools.d'
readonly version_file='/usr/share/doors/proton-cachyos.version'
readonly work_dir='/var/tmp/doors-proton-cachyos'

fail() {
  printf 'Doors Proton-CachyOS: %s\n' "$*" >&2
  exit 1
}

fetch() {
  curl --fail --location --proto '=https' --tlsv1.2 --retry 5 --retry-delay 10 \
    --silent --show-error "$@"
}

if [[ "$(uname -m)" != 'x86_64' ]]; then
  printf 'Doors Proton-CachyOS: skipped on %s (x86_64 only)\n' "$(uname -m)"
  exit 0
fi
command -v xz > /dev/null || fail 'xz is required to unpack the release'

rm -rf "${work_dir}"
mkdir -p "${work_dir}" "${install_root}" "$(dirname "${version_file}")"

# Resolve the latest non-prerelease tag from the redirect target.
location="$(curl --silent --show-error --head --proto '=https' --tlsv1.2 --retry 5 \
  "https://github.com/${repository}/releases/latest" \
  | tr -d '\r' | awk 'tolower($1) == "location:" { print $2 }' | tail -1)"
tag="${location##*/tag/}"
[[ -n "${tag}" && "${tag}" != "${location}" ]] || fail "could not resolve the latest release tag from ${location:-no redirect}"
[[ "${tag}" =~ ^cachyos-[0-9]+\.[0-9]+-[0-9]{8}(-[a-z0-9]+)?$ ]] || fail "unexpected release tag shape: ${tag}"

base="proton-${tag}-${variant}"
download="https://github.com/${repository}/releases/download/${tag}"

fetch --output "${work_dir}/${base}.sha512sum" "${download}/${base}.sha512sum"
fetch --output "${work_dir}/${base}.tar.xz" "${download}/${base}.tar.xz"
# The published checksum file must describe exactly this archive; refuse any
# other shape rather than guessing which field is the digest.
grep -Eq "^[0-9a-f]{128}[[:space:]]+\*?${base}\.tar\.xz\$" "${work_dir}/${base}.sha512sum" \
  || fail 'checksum file does not describe the downloaded archive'
(cd "${work_dir}" && sha512sum --check --status "${base}.sha512sum") \
  || fail "sha512 mismatch for ${base}.tar.xz"

# The archive must contain exactly one top-level directory carrying a Steam
# compatibility tool manifest; anything else is refused rather than guessed.
top_level="$(tar --list --xz --file "${work_dir}/${base}.tar.xz" | cut -d/ -f1 | sort -u)"
[[ "$(printf '%s\n' "${top_level}" | wc -l)" -eq 1 && "${top_level}" == "${base}" ]] \
  || fail "archive layout is not a single ${base}/ directory"

# Replace any previously composed Proton-CachyOS so the image carries only the
# current release; user-installed copies under ~/.steam are unaffected.
find "${install_root}" -mindepth 1 -maxdepth 1 -name 'proton-cachyos-*' -exec rm -rf {} +
tar --extract --xz --file "${work_dir}/${base}.tar.xz" --directory "${install_root}" \
  --no-same-owner --no-same-permissions
for required in compatibilitytool.vdf toolmanifest.vdf proton; do
  [[ -e "${install_root}/${base}/${required}" ]] || fail "extracted tree is missing ${required}"
done
chown -R root:root "${install_root}/${base}"
chmod -R u+rwX,go+rX,go-w "${install_root}/${base}"
chmod 0755 "${install_root}/${base}/proton"
printf '%s\n' "${tag#cachyos-}-${variant}" > "${version_file}"

rm -rf "${work_dir}"
printf 'Doors Proton-CachyOS: installed %s from release %s into %s\n' "${base}" "${tag}" "${install_root}"
