#!/usr/bin/env bash
# Finalize and verify the all-native development/AI toolchain after DNF has
# resolved its RPM portion from the reviewed Fedora 44, Terra 44, and NVIDIA
# CUDA routes. The tracked T3 and Pi locks control their native npm payloads.
# Herdr is the sole generated input: CI verifies its immutable GitHub release
# asset before this script validates the manifest and digest again.
set -euo pipefail

readonly herdr_dir='/usr/share/doors/native-ai/herdr'
readonly herdr_artifact="${herdr_dir}/herdr-linux-x86_64"
readonly herdr_manifest="${herdr_dir}/herdr.json"
readonly cuda_root='/usr/lib/doors/cuda-13.4'
readonly t3_input_dir='/usr/share/doors/native-ai/t3'
readonly t3_prefix='/usr/lib/doors/native-ai/t3'
readonly pi_input_dir='/usr/share/doors/native-ai/pi'
readonly pi_prefix='/usr/lib/doors/native-ai/pi'
readonly npm_cache='/var/tmp/doors-native-ai-npm-cache'

fail() {
  printf 'Doors native AI setup: %s\n' "$*" >&2
  exit 1
}

install_locked_npm_payload() {
  local label="$1"
  local input_dir="$2"
  local prefix="$3"

  [[ -s "${input_dir}/package.json" && -s "${input_dir}/package-lock.json" ]] \
    || fail "pinned native ${label} package-lock input is missing"
  rm -rf "${prefix}"
  install -d -m 0755 "${prefix}" "${npm_cache}"
  install -m 0644 "${input_dir}/package.json" "${prefix}/package.json"
  install -m 0644 "${input_dir}/package-lock.json" "${prefix}/package-lock.json"
  env npm_config_cache="${npm_cache}" npm_config_registry='https://registry.npmjs.org/' \
    /usr/bin/npm ci --prefix "${prefix}" --omit=dev --ignore-scripts --no-audit --fund=false
}

for package in \
  nodejs24 nodejs24-devel nodejs24-npm nodejs24-bin nodejs24-npm-bin pnpm \
  python3 python3-devel python3-pip \
  gcc gcc-c++ make cmake pkgconf-pkg-config \
  bun-bin deno mise opencode-cli cuda-toolkit-13-4 cuda-nvcc-13-4 \
  cuda-nsight-compute-13-4 cuda-nsight-systems-13-4; do
  rpm -q "${package}" >/dev/null 2>&1 || fail "missing native RPM: ${package}"
done

for cuda_command in nvcc ncu ncu-ui nsys nsys-ui; do
  [[ -x "${cuda_root}/bin/${cuda_command}" ]] \
    || fail "CUDA Toolkit 13.4 did not provide ${cuda_root}/bin/${cuda_command}"
  ln -sfn "${cuda_root}/bin/${cuda_command}" "/usr/bin/${cuda_command}"
done

for command in node npm pnpm python3 pip3 gcc g++ make cmake pkg-config \
  bun deno mise opencode nvcc ncu nsys; do
  command -v "${command}" >/dev/null 2>&1 \
    || fail "missing native command: ${command}"
done

# Pi 0.85.1 uses Node's globSync API, first available in the supported Node
# range at 22.19.0. Fail during composition rather than ship a CLI that cannot
# start if a Fedora stream ever regresses its nodejs runtime.
node - <<'NODE' || fail 'Pi 0.85.1 requires Node.js 22.19.0 or newer'
const [major, minor, patch] = process.versions.node.split('.').map(Number);
if (major < 22 || (major === 22 && (minor < 19 || (minor === 19 && patch < 0)))) {
  process.exit(1);
}
NODE

# The native T3 CLI is its original npm package rather than Terra's separate
# t3code desktop GUI. The tracked lock pins its package tarballs and SRI
# digests; npm ci verifies those digests and never runs package lifecycle code.
install_locked_npm_payload 'T3' "${t3_input_dir}" "${t3_prefix}"
cat > /usr/bin/t3 <<'T3_WRAPPER'
#!/usr/bin/env bash
# The image-owned T3 payload is updated only by a reviewed immutable rebase.
# Do not let its self-updater create an unmanaged replacement beside it.
set -euo pipefail

readonly t3_binary='/usr/lib/doors/native-ai/t3/node_modules/.bin/t3'
case "${1:-}" in
  update|uninstall)
    printf '%s\n' "t3 ${1} is disabled on Doors; update the immutable image instead." >&2
    exit 64
    ;;
esac
exec "${t3_binary}" "$@"
T3_WRAPPER
chmod 0755 /usr/bin/t3

# The old Doors AI container installed this exact Pi coding-agent release using
# npm. Keep it native and immutable: a tracked lock replaces the mutable global
# installation, while the image-owned wrapper retains the ordinary `pi` command.
install_locked_npm_payload 'Pi' "${pi_input_dir}" "${pi_prefix}"
cat > /usr/bin/pi <<'PI_WRAPPER'
#!/usr/bin/env bash
# Pi itself is image-owned; per-user settings and extensions remain under $HOME.
set -euo pipefail

readonly pi_binary='/usr/lib/doors/native-ai/pi/node_modules/.bin/pi'
exec "${pi_binary}" "$@"
PI_WRAPPER
chmod 0755 /usr/bin/pi
rm -rf "${npm_cache}"
[[ -x /usr/bin/t3 ]] || fail 'pinned native T3 CLI installation failed'
[[ -x /usr/bin/pi ]] || fail 'pinned native Pi CLI installation failed'
t3 --help >/dev/null
pi --version >/dev/null

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
install -m 0755 "${herdr_artifact}" /usr/bin/herdr

# Smoke checks require no network, user configuration, or GPU device.
nvcc --version >/dev/null
ncu --version >/dev/null
nsys --version >/dev/null
herdr --version >/dev/null
