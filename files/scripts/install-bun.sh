#!/usr/bin/env bash
# Install the latest stable Bun x86_64 release only after its release checksum
# has been verified against the reviewed, vendored Robobun OpenPGP key.
set -euo pipefail

readonly REPOSITORY='oven-sh/bun'
readonly API_URL="https://api.github.com/repos/${REPOSITORY}/releases/latest"
readonly KEY='/usr/share/doors/keys/bun-release-key.asc'
readonly ASSET='bun-linux-x64.zip'

[[ -s "${KEY}" ]] || { echo "Bun release key is missing" >&2; exit 1; }
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
export GNUPGHOME="${workdir}/gnupg"
mkdir -m 0700 "${GNUPGHOME}"
gpg --batch --import "${KEY}" >/dev/null

release_json="$(curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --silent --show-error "${API_URL}")"
tag="$(jq --raw-output '.tag_name // empty' <<<"${release_json}")"
if [[ ! "${tag}" =~ ^bun-v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Unexpected Bun stable release tag: ${tag:-<empty>}" >&2
  exit 1
fi
base_url="https://github.com/${REPOSITORY}/releases/download/${tag}"

curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --silent --show-error \
  "${base_url}/SHASUMS256.txt.asc" --output "${workdir}/SHASUMS256.txt.asc"
# --decrypt verifies the clear signature and writes only the signed checksum text.
gpg --batch --decrypt --output "${workdir}/SHASUMS256.txt" "${workdir}/SHASUMS256.txt.asc" >/dev/null
awk -v asset="${ASSET}" '$2 == asset { print }' "${workdir}/SHASUMS256.txt" > "${workdir}/${ASSET}.sha256"
if [[ "$(wc -l < "${workdir}/${ASSET}.sha256")" -ne 1 ]]; then
  echo "Expected exactly one signed checksum for ${ASSET}" >&2
  exit 1
fi

curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --silent --show-error \
  "${base_url}/${ASSET}" --output "${workdir}/${ASSET}"
(
  cd "${workdir}"
  sha256sum --check "${ASSET}.sha256"
)
unzip -q "${workdir}/${ASSET}" -d "${workdir}/unpacked"
install -D -m 0755 "${workdir}/unpacked/bun-linux-x64/bun" /usr/local/bin/bun

expected_version="${tag#bun-v}"
actual_version="$(/usr/local/bin/bun --version)"
if [[ "${actual_version}" != "${expected_version}" ]]; then
  echo "Bun binary version ${actual_version} does not match verified release ${expected_version}" >&2
  exit 1
fi
