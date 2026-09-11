#!/usr/bin/env bash
# Build llama.cpp from source for the active backend.
#   universal images -> LLAMA_BACKEND=hip   (Terra ROCm / Fedora ROCm devel)
#   nvidia images    -> LLAMA_BACKEND=cuda  (Terra cuda-nvcc)
set -euo pipefail

BACKEND="${LLAMA_BACKEND:-cuda}"
# Bump via Renovate regexManagers (see renovate.json)
LLAMA_REF="${LLAMA_VERSION:-b10906}"
JOBS="$(nproc)"
OUT_DIR="${STAGE_OUT_DIR:-/out}/bin"

echo ">>> building llama.cpp [${BACKEND}] @ ${LLAMA_REF}"

dnf5 install -y git cmake gcc gcc-c++ ccache ninja-build

case "${BACKEND}" in
  cuda)
    dnf5 install -y cuda-nvcc
    GGML_CUDA=ON
    GGML_HIPBLAS=OFF
    ;;
  hip)
    dnf5 install -y rocm-hip-devel rocm-hip-libs hipblas-devel rocblas-devel
    GGML_CUDA=OFF
    GGML_HIPBLAS=ON
    # llama.cpp needs the ROCm LLVM clang + amdhip64; detect at build time
    export AMDGPU_TARGETS="$(rocminfo 2>/dev/null | awk -F': *' '/Name:/{print $2}' | grep -E '^gfx[0-9]+' | sort -u | paste -sd, - || echo gfx1100)"
    # shellcheck disable=SC2155
    export PATH="/opt/rocm/bin:/opt/rocm/llvm/bin:${PATH}"
    ;;
  *)
    echo "unknown LLAMA_BACKEND=${BACKEND}" >&2
    exit 1
    ;;
esac

curl -fsSL "https://github.com/ggml-org/llama.cpp/archive/${LLAMA_REF}.tar.gz" -o /tmp/llama.tar.gz
mkdir -p /tmp/llama-src
tar -xzf /tmp/llama.tar.gz --strip-components=1 -C /tmp/llama-src

cmake -B /tmp/llama-build -S /tmp/llama-src \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DGGML_CUDA="${GGML_CUDA}" \
  -DGGML_HIPBLAS="${GGML_HIPBLAS}" \
  -DGGML_NATIVE=OFF \
  -DGGML_OPENMP=ON \
  -DLLAMA_CURL=ON \
  -DLLAMA_BUILD_TOOLS=ON

cmake --build /tmp/llama-build -j "${JOBS}" --target llama-cli llama-server llama-bench llama-quantize

mkdir -p "${OUT_DIR}"
install -m 0755 \
  /tmp/llama-build/bin/llama-cli \
  /tmp/llama-build/bin/llama-server \
  /tmp/llama-build/bin/llama-bench \
  /tmp/llama-build/bin/llama-quantize \
  "${OUT_DIR}/"

echo ">>> llama.cpp installed to ${OUT_DIR}"
