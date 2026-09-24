#!/usr/bin/env bash
# Finalize and verify the all-native development/AI toolchain after DNF has
# resolved it from the reviewed Fedora 44, Terra 44, and NVIDIA CUDA routes.
# The tracked T3 lock controls its native npm payload. Herdr is the sole
# generated input: CI verifies its immutable GitHub release asset before this
# script validates the manifest and digest again.
set -euo pipefail

readonly herdr_dir='/usr/share/doors/native-ai/herdr'
readonly herdr_artifact="${herdr_dir}/herdr-linux-x86_64"
readonly herdr_manifest="${herdr_dir}/herdr.json"
readonly cuda_root='/usr/local/cuda-13.4'
readonly t3_input_dir='/usr/share/doors/native-ai/t3'
readonly t3_prefix='/usr/local/lib/doors/native-ai/t3'
readonly npm_cache='/var/tmp/doors-native-ai-npm-cache'

fail() {
  printf 'Doors native AI setup: %s\n' "$*" >&2
  exit 1
}

for package in \
  nodejs nodejs-devel npm pnpm python3 python3-devel python3-pip \
  gcc gcc-c++ make cmake pkgconf-pkg-config \
  bun-bin deno mise opencode-cli pi cuda-toolkit-13-4; do
  rpm -q "${package}" >/dev/null 2>&1 || fail "missing native RPM: ${package}"
done

[[ -x "${cuda_root}/bin/nvcc" ]] \
  || fail "CUDA Toolkit 13.4 did not provide ${cuda_root}/bin/nvcc"
ln -sfn "${cuda_root}/bin/nvcc" /usr/local/bin/nvcc

for command in node npm pnpm python3 pip3 gcc g++ make cmake pkg-config \
  bun deno mise opencode pi nvcc; do
  command -v "${command}" >/dev/null 2>&1 \
    || fail "missing native command: ${command}"
done

# The native T3 CLI is its original npm package rather than Terra's separate
# t3code desktop GUI. The tracked lock pins its package tarballs and SRI
# digests; npm ci verifies those digests and never runs package lifecycle code.
[[ -s "${t3_input_dir}/package.json" && -s "${t3_input_dir}/package-lock.json" ]] \
  || fail 'pinned native T3 package-lock input is missing'
rm -rf "${t3_prefix}" "${npm_cache}"
install -d -m 0755 "${t3_prefix}" "${npm_cache}"
install -m 0644 "${t3_input_dir}/package.json" "${t3_prefix}/package.json"
install -m 0644 "${t3_input_dir}/package-lock.json" "${t3_prefix}/package-lock.json"
env npm_config_cache="${npm_cache}" npm_config_registry='https://registry.npmjs.org/' \
  /usr/bin/npm ci --prefix "${t3_prefix}" --omit=dev --ignore-scripts --no-audit --fund=false
cat > /usr/local/bin/t3 <<'T3_WRAPPER'
#!/usr/bin/env bash
# The image-owned T3 payload is updated only by a reviewed immutable rebase.
# Do not let its self-updater create an unmanaged replacement beside it.
set -euo pipefail

readonly t3_binary='/usr/local/lib/doors/native-ai/t3/node_modules/.bin/t3'
case "${1:-}" in
  update|uninstall)
    printf '%s\n' "t3 ${1} is disabled on Doors; update the immutable image instead." >&2
    exit 64
    ;;
esac
exec "${t3_binary}" "$@"
T3_WRAPPER
chmod 0755 /usr/local/bin/t3
rm -rf "${npm_cache}"
[[ -x /usr/local/bin/t3 ]] || fail 'pinned native T3 CLI installation failed'
t3 --help >/dev/null

[[ -s "${herdr_artifact}" && -s "${herdr_manifest}" ]] \
  || fail 'attestation-verified Herdr build input is missing'
repository="$(jq --raw-output '.repository // empty' "${herdr_manifest}")"
release_tag="$(jq --raw-output '.tag // empty' "${herdr_manifest}")"
asset="$(jq --raw-output '.asset // empty' "${herdr_manifest}")"
expected_sha256="$(jq --raw-output '.sha256 // empty' "${herdr_manifest}")"
[[ "${repository}" == 'herdrdev/herdr' && "${asset}" == 'herdr-linux-x86_64' ]] \
  && [[ "${release_tag}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  && [[ "${expected_sha256}" =~ ^[0-9a-f]{64}$ ]] \
  || fail 'Herdr verification manifest has an unexpected identity or shape'
actual_sha256="$(sha256sum "${herdr_artifact}" | awk '{print $1}')"
[[ "${actual_sha256}" == "${expected_sha256}" ]] \
  || fail 'Herdr artifact digest does not match CI-verified manifest'
install -m 0755 "${herdr_artifact}" /usr/local/bin/herdr

# Smoke checks require no network, user configuration, or GPU device.
nvcc --version >/dev/null
herdr --version >/dev/null
