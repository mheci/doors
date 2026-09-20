#!/usr/bin/env bash
# Resolve the current upstream Herdr release, verify its GitHub release
# attestation, and materialize exactly the verified artifact for BlueBuild.
set -euo pipefail

readonly repository='herdrdev/herdr'
readonly asset='herdr-linux-x86_64'
readonly generated_dir='files/generated/herdr'
# GHSA-8xvp-7hj6-mcj9 fixed token forwarding during release-attestation
# verification in 2.93.0. Fail before handling GH_TOKEN on an older runner.
readonly minimum_gh_version='2.93.0'

: "${GH_TOKEN:?GH_TOKEN is required for GitHub attestation verification}"
command -v gh >/dev/null
gh_version="$(gh --version | awk 'NR == 1 { sub(/^v/, "", $3); print $3; exit }')"
if [[ ! "${gh_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || [[ "$(printf '%s\n%s\n' "${minimum_gh_version}" "${gh_version}" | sort -V | head -n 1)" != "${minimum_gh_version}" ]]; then
  echo "GitHub CLI >= ${minimum_gh_version} is required for safe release-asset verification; found ${gh_version:-<unknown>}" >&2
  exit 1
fi
# Immutable-release verification is intentionally a hard requirement rather
# than silently falling back to an unauthenticated digest-only download.
gh release verify-asset --help >/dev/null 2>&1 || {
  echo 'Installed GitHub CLI lacks immutable-release asset verification' >&2
  exit 1
}
command -v jq >/dev/null
command -v sha256sum >/dev/null

release_json="$(gh api "repos/${repository}/releases/latest")"
tag="$(jq --raw-output '.tag_name // empty' <<<"${release_json}")"
if [[ ! "${tag}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Unexpected Herdr release tag: ${tag:-<empty>}" >&2
  exit 1
fi

asset_json="$(jq --compact-output --arg asset "${asset}" '.assets[] | select(.name == $asset)' <<<"${release_json}")"
[[ -n "${asset_json}" ]] || { echo "Release ${tag} has no ${asset} asset" >&2; exit 1; }
url="$(jq --raw-output '.browser_download_url // empty' <<<"${asset_json}")"
digest="$(jq --raw-output '.digest // empty' <<<"${asset_json}")"
if [[ ! "${url}" =~ ^https://github\.com/herdrdev/herdr/releases/download/ ]] \
  || [[ ! "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo 'Herdr release metadata has an unexpected URL or SHA-256 digest' >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
artifact="${workdir}/${asset}"
curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --silent --show-error \
  "${url}" --output "${artifact}"
actual_sha256="$(sha256sum "${artifact}" | awk '{print $1}')"
[[ "sha256:${actual_sha256}" == "${digest}" ]] || {
  echo 'Herdr release asset does not match the GitHub release SHA-256 digest' >&2
  exit 1
}

# GitHub's immutable-release attestation binds this exact local artifact to
# the named upstream release. Unlike a build-provenance attestation, release
# attestations are verified with the release command. This fails closed when
# the release is not immutable or the asset is not in its signed inventory.
env -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN \
  gh release verify-asset "${tag}" "${artifact}" --repo "${repository}"

rm -rf "${generated_dir}"
mkdir -p "${generated_dir}"
install -m 0755 "${artifact}" "${generated_dir}/${asset}"
cat > "${generated_dir}/herdr.json" <<JSON
{
  "repository": "${repository}",
  "tag": "${tag}",
  "asset": "${asset}",
  "sha256": "${actual_sha256}",
  "source_url": "${url}",
  "verified_by": "gh release verify-asset ${tag} herdr-linux-x86_64 --repo ${repository}"
}
JSON
