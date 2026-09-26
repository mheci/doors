#!/usr/bin/env bash
# Download a reviewed, checksum-pinned Gitleaks CLI and scan every reachable
# commit. Keep this independent of gitleaks-action: its embedded v8.24.3 CLI
# cannot enforce this repository's rule-scoped allowlist.
set -euo pipefail

readonly version='8.30.1'
readonly archive="gitleaks_${version}_linux_x64.tar.gz"
readonly expected_sha256='551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb'
readonly release_url="https://github.com/gitleaks/gitleaks/releases/download/v${version}/${archive}"

for command in curl sha256sum tar timeout; do
  command -v "${command}" >/dev/null
done

workdir="$(mktemp -d)"
readonly workdir
trap 'rm -rf "${workdir}"' EXIT
archive_path="${workdir}/${archive}"

curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --silent --show-error \
  "${release_url}" --output "${archive_path}"
printf '%s  %s\n' "${expected_sha256}" "${archive_path}" | sha256sum --check --status
tar -xzf "${archive_path}" -C "${workdir}" gitleaks

# Bound the scan so a platform/tool regression fails visibly rather than
# consuming an entire CI job. The checkout uses fetch-depth: 0.
timeout --signal=TERM 4m "${workdir}/gitleaks" git \
  --redact --log-opts='--all' --config .gitleaks.toml
