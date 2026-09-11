#!/usr/bin/env bash
# Build llama.cpp from source for the active backend.
#   universal images -> LLAMA_BACKEND=hip   (Fedora ROCm 7.1)
#   nvidia images    -> LLAMA_BACKEND=cuda  (Terra CUDA)
set -euo pipefail

BACKEND="${LLAMA_BACKEND:-cuda}"
# Bump via Renovate regexManagers (see renovate.json)
LLAMA_REF="${LLAMA_VERSION:-b10906}"
JOBS="$(nproc)"
OUT_DIR="/out/bin"

echo ">>> building llama.cpp [${BACKEND}] @ ${LLAMA_REF}"

dnf5 install -y git cmake gcc gcc-c++ ccache ninja-build

case "${BACKEND}" in
  cuda)
    # Terra CUDA toolchain (cuda-devel headers + cuda-nvcc compiler)
    dnf5 install -y --nogpgcheck --repofrompath \
      "terra,https://repos.fyralabs.com/terra$(rpm -E %fedora)" \
      terra-release terra-gpg-keys terra-release-nvidia
    dnf5 install -y cuda-devel cuda-nvcc
    GGML_CUDA=ON
    GGML_HIPBLAS=OFF
    ;;
  hip)
    # Fedora ROCm 7.1 (hipcc compiler + rocm-hip-devel headers + rocblas/hipblas devel)
    dnf5 install -y clang hipcc rocm-hip-devel rocblas rocblas-devel hipblas hipblas-devel rocm-core
    GGML_CUDA=OFF
    GGML_HIPBLAS=ON
    # Consumer AMD targets (ROCm 7.1): Vega, Vega20, Vega APU, Navi10, Navi21, Navi31, Phoenix
    export AMDGPU_TARGETS="${AMDGPU_TARGETS:-gfx900;gfx906;gfx90c;gfx1010;gfx1030;gfx1100;gfx1102}"
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
