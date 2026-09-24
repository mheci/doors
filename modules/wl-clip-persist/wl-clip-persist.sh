#!/usr/bin/env bash
# Build a reviewed wl-clip-persist release in the disposable stage. The source
# archive is pinned by immutable commit and SHA-256 so compose never queries
# GitHub's rate-limited mutable releases API.
set -euo pipefail

readonly repository='Linus789/wl-clip-persist'
readonly tag='v0.5.0'
readonly commit='e26fde01c13922e3a65049dafb7d5adfbc52626e'
readonly source_sha256='4f57033dae159b887168210bcc69de84ba5f43e7e39444e483297e6ccb4b747c'
readonly source_url="https://github.com/${repository}/archive/${commit}.tar.gz"
readonly out_dir='/out'

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
source_archive="${workdir}/wl-clip-persist.tar.gz"
source_dir="${workdir}/wl-clip-persist-${commit}"

mkdir -p "${out_dir}"
dnf5 install -y --setopt=install_weak_deps=False cargo gcc make

curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --silent --show-error \
  "${source_url}" --output "${source_archive}"
printf '%s  %s\n' "${source_sha256}" "${source_archive}" | sha256sum --check --status

tar --extract --gzip --file "${source_archive}" --directory "${workdir}" --no-same-owner
[[ -d "${source_dir}" && -f "${source_dir}/Cargo.toml" && -f "${source_dir}/Cargo.lock" ]] \
  || { echo 'Pinned wl-clip-persist archive has an unexpected layout' >&2; exit 1; }

export CARGO_HOME="${workdir}/cargo-home"
export CARGO_TARGET_DIR="${workdir}/cargo-target"
cargo install --locked --path "${source_dir}" --root "${workdir}/install-root"
install -D -m 0755 "${workdir}/install-root/bin/wl-clip-persist" "${out_dir}/wl-clip-persist"
"${out_dir}/wl-clip-persist" --help >/dev/null

cat > "${out_dir}/wl-clip-persist.buildinfo" <<INFO
repository=${repository}
tag=${tag}
commit=${commit}
source_url=${source_url}
source_sha256=${source_sha256}
INFO

printf 'wl-clip-persist %s built from %s.\n' "${tag}" "${commit}"
