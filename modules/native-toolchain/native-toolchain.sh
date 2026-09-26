#!/usr/bin/env bash
# Finalize and verify the native development toolchain after DNF has resolved
# its RPM portion from the reviewed Fedora 44, Terra 44, and NVIDIA CUDA routes.
#
# Compilers, runtimes (Node, Bun, Deno, Python), CUDA 13.4, and mise itself are
# image-owned. Fast-moving agent CLIs (OpenCode, Pi, Codex, Herdr) are NOT
# baked in: /etc/mise/config.toml declares them and each account installs and
# upgrades them at runtime, so a tool release never requires an image rebuild
# or a reboot. This module only proves that policy file is well-formed.
set -euo pipefail

readonly cuda_root='/usr/lib/doors/cuda-13.4'
readonly mise_policy='/etc/mise/config.toml'
readonly scratch_home='/var/tmp/doors-mise-check'

fail() {
  printf 'Doors native toolchain: %s\n' "$*" >&2
  exit 1
}

for package in \
  nodejs24 nodejs24-devel nodejs24-npm nodejs24-bin nodejs24-npm-bin pnpm \
  python3 python3-devel python3-pip \
  gcc gcc-c++ make cmake pkgconf-pkg-config \
  bun-bin deno mise python3-ruamel-yaml cuda-toolkit-13-4 cuda-nvcc-13-4 \
  cuda-nsight-compute-13-4 cuda-nsight-systems-13-4; do
  rpm -q "${package}" >/dev/null 2>&1 || fail "missing native RPM: ${package}"
done

for cuda_command in nvcc ncu ncu-ui nsys nsys-ui; do
  [[ -x "${cuda_root}/bin/${cuda_command}" ]] \
    || fail "CUDA Toolkit 13.4 did not provide ${cuda_root}/bin/${cuda_command}"
  ln -sfn "${cuda_root}/bin/${cuda_command}" "/usr/bin/${cuda_command}"
done

for command in node npm pnpm python3 pip3 gcc g++ make cmake pkg-config \
  bun deno mise nvcc ncu nsys; do
  command -v "${command}" >/dev/null 2>&1 || fail "missing native command: ${command}"
done

# The system-wide mise policy must parse and declare the reviewed tool set.
# Nothing is installed here: tool payloads belong to the account that runs
# them, never to the image.
[[ -s "${mise_policy}" ]] || fail "system mise policy is missing: ${mise_policy}"
mkdir -p "${scratch_home}"
policy_tools="$(env HOME="${scratch_home}" MISE_SYSTEM_CONFIG_FILE="${mise_policy}" \
  mise config ls --json 2>/dev/null \
  | jq --raw-output --arg policy "${mise_policy}" \
      '[.[] | select(.path == $policy) | .tools[]] | join(" ")')" \
  || fail 'system mise policy did not parse'
rm -rf "${scratch_home}"
[[ -n "${policy_tools}" ]] || fail 'system mise policy declares no tools'
for tool in opencode pi codex herdr; do
  [[ " ${policy_tools} " == *" ${tool} "* ]] || fail "system mise policy does not declare ${tool}"
done

# doors-recipe (runtime recipe manipulation) needs ruamel.yaml and must parse.
python3 -c 'import ruamel.yaml, tomllib' || fail 'python3 ruamel.yaml/tomllib unavailable'
python3 -m py_compile /usr/bin/doors-recipe || fail 'doors-recipe does not compile'
[[ -x /usr/bin/doors-recipe ]] || fail 'doors-recipe is not executable'

# Smoke checks require no network, user configuration, or GPU device.
nvcc --version >/dev/null
ncu --version >/dev/null
nsys --version >/dev/null
mise --version >/dev/null

printf 'Doors native toolchain verified: CUDA 13.4, Node, Bun, Deno, mise policy (%s).\n' "${policy_tools}"
