#!/usr/bin/env bash
# Build NVIDIA kernel modules (nvidia-open) against kernel-cachyos-lto.
# Runs in the `kmods` stage on base-main:44. Artifacts land in /out/kmods and
# are copied into the final image via gpu-nvidia.yml.
#
# NOTE: akmod-nvidia is installed with --no-deps on purpose. Installing it with
# its full dependency tree drags the userspace driver into this scratch stage,
# and Terra's weak deps pull BOTH the 610 and legacy 580xx driver branches,
# which conflict on /usr/lib64/libnvidia-ml.so.1. We only need the akmod
# source here; the userspace driver is layered in the final image (gpu-nvidia.yml).
set -euo pipefail

echo ">>> enabling CachyOS COPR + Terra nvidia"
dnf5 copr enable -y bieszczaders/kernel-cachyos-lto
dnf5 install -y --nogpgcheck --repofrompath \
  "terra,https://repos.fyralabs.com/terra$(rpm -E %fedora)" \
  terra-release terra-gpg-keys terra-release-nvidia

echo ">>> installing build toolchain (weak deps off)"
dnf5 install -y --setopt=install_weak_deps=False \
  akmods kmodtool \
  kernel-cachyos-lto kernel-cachyos-lto-devel-matched kernel-headers \
  gcc gcc-c++ make elfutils-libelf-devel

echo ">>> installing akmod-nvidia source only"
# dnf5 has no --no-deps; fetch the rpm and install it with rpm --nodeps.
# akmod-nvidia only ships the SRPM source into /usr/src/akmods/, and the
# build toolchain above provides everything akmods needs to compile it.
if dnf5 download -y --setopt=install_weak_deps=False akmod-nvidia; then
  rpm -Uvh --nodeps akmod-nvidia-*.rpm
else
  # Fallback: full deps, weak deps off (still avoids the 580xx conflict)
  dnf5 install -y --setopt=install_weak_deps=False akmod-nvidia
fi

echo ">>> building NVIDIA kmods with akmods"
KVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-cachyos-lto | head -n1)"
akmods --force --kernels "${KVER}"

OUT_DIR="/out/kmods"
mkdir -p "${OUT_DIR}/lib/modules/${KVER}/extra"

# akmods installs built modules under /usr/lib/modules/<kver>/extra
if [ -d "/usr/lib/modules/${KVER}/extra" ]; then
  cp -a "/usr/lib/modules/${KVER}/extra/." "${OUT_DIR}/lib/modules/${KVER}/extra/"
fi
if ! ls "${OUT_DIR}/lib/modules/${KVER}/extra/"nvidia*.ko* >/dev/null 2>&1; then
  echo ">>> no nvidia modules in extra/; searching all of /usr/lib/modules"
  find /usr/lib/modules/"${KVER}" -name 'nvidia*.ko*' -exec cp -a {} "${OUT_DIR}/lib/modules/${KVER}/extra/" \;
fi

echo ">>> NVIDIA kmods staged at ${OUT_DIR}:"
find "${OUT_DIR}" -name 'nvidia*.ko*' | head -n 40
