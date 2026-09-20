#!/usr/bin/env bash
# The CI preflight downloads, hashes, and GitHub-attestation-verifies Herdr.
# This image-build step accepts only that generated manifest/binary pair.
set -euo pipefail

readonly generated='/usr/local/lib/doors/generated/herdr'
readonly artifact="${generated}/herdr-linux-x86_64"
readonly manifest="${generated}/herdr.json"
readonly final_manifest='/usr/share/doors/third-party/herdr.json'

[[ -x "${artifact}" ]] || { echo "Attestation-verified Herdr artifact is missing" >&2; exit 1; }
[[ -s "${manifest}" ]] || { echo "Herdr verification manifest is missing" >&2; exit 1; }

repository="$(jq --raw-output '.repository // empty' "${manifest}")"
tag="$(jq --raw-output '.tag // empty' "${manifest}")"
expected_sha256="$(jq --raw-output '.sha256 // empty' "${manifest}")"
asset="$(jq --raw-output '.asset // empty' "${manifest}")"
if [[ "${repository}" != 'herdrdev/herdr' || "${asset}" != 'herdr-linux-x86_64' ]] \
  || [[ ! "${tag}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || [[ ! "${expected_sha256}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Herdr verification manifest has an unexpected identity or shape" >&2
  exit 1
fi
actual_sha256="$(sha256sum "${artifact}" | awk '{print $1}')"
if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
  echo "Herdr binary digest does not match its attestation-verified manifest" >&2
  exit 1
fi

install -D -m 0755 "${artifact}" /usr/local/bin/herdr
install -D -m 0644 "${manifest}" "${final_manifest}"
/usr/local/bin/herdr --version >/dev/null
rm -rf "${generated}"
