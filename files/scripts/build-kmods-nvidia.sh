#!/usr/bin/env bash
# Build NVIDIA kernel modules (nvidia-open) against kernel-cachyos-lto.
# Runs in the `kmods` stage on base-main:44, which shares the kernel
# (from kernel.yml) with the target image. Final artifacts land in
# ${STAGE_OUT_DIR:-/out}/kmods and are copied in via gpu-nvidia.yml.
set -euo pipefail

echo ">>> installing NVIDIA build deps"
dnf5 install -y --nogpgcheck --repofrompath \
  "terra,https://repos.fyralabs.com/terra$(rpm -E %fedora)" \
  terra-release terra-gpg-keys terra-release-nvidia
dnf5 install -y akmod-nvidia kernel-cachyos-lto kernel-cachyos-lto-devel-matched \
  kernel-headers gcc gcc-c++ make elfutils-libelf-devel

echo ">>> building NVIDIA kmods with akmods"
akmods --force --kernels "$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-cachyos-lto | head -n1)"

KVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-cachyos-lto | head -n1)"
KVER_FULL="$(ls /usr/lib/modules/ | grep '^'"${KVER}"'$' | head -n1)"
OUT_DIR="${STAGE_OUT_DIR:-/out}/kmods"

mkdir -p "${OUT_DIR}/lib/modules/${KVER_FULL}/extra"
cp -a "/usr/lib/modules/${KVER_FULL}/extra/." "${OUT_DIR}/lib/modules/${KVER_FULL}/extra/" || true

if ! ls "${OUT_DIR}/lib/modules/${KVER_FULL}/extra/"*.ko.zst >/dev/null 2>&1; then
  echo ">>> no .ko.zst produced; fallback to any built nvidia modules"
  find /usr/lib/modules/"${KVER_FULL}" -name 'nvidia*.ko*' -exec cp -a {} "${OUT_DIR}/lib/modules/${KVER_FULL}/extra/" \;
fi

echo ">>> NVIDIA kmods staged at ${OUT_DIR}:"
find "${OUT_DIR}" -name 'nvidia*.ko*' | head -n 40
