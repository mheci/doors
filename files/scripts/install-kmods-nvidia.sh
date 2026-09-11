#!/usr/bin/env bash
# Install the kmods staged by build-kmods-nvidia.sh and rebuild initramfs
# so the NVIDIA module is available at first boot.
# Runs in the FINAL image, after kernel.yml has installed kernel-cachyos-lto.
set -euo pipefail

SRC="/tmp/kmods"
[ -d "${SRC}" ] || { echo "no kmods staged at ${SRC}" >&2; exit 0; }

# The staged kmods carry the kernel version they were built for. It MUST match
# the kernel now present in the final image (same COPR, same build run).
STAGE_KVER="$(find "${SRC}/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -n1)"
FINAL_KVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-cachyos-lto | head -n1)"

if [ -z "${STAGE_KVER}" ] || [ ! -d "/usr/lib/modules/${STAGE_KVER}" ]; then
  echo "ERROR: kmods were built for kernel '${STAGE_KVER}' but that kernel is not" >&2
  echo "       present in the final image (have '${FINAL_KVER}')." >&2
  echo "       The kmods stage and the final image pulled different kernel-cachyos-lto" >&2
  echo "       builds — re-run the build so both stages share one kernel version." >&2
  exit 1
fi

echo ">>> installing NVIDIA kmods (built for ${STAGE_KVER})"
cp -a "${SRC}/lib/modules/." /usr/lib/modules/

echo ">>> refreshing module deps + initramfs"
depmod -a "${STAGE_KVER}" 2>/dev/null || true
dracut --force --regenerate-all 2>/dev/null || true
echo ">>> NVIDIA kmods installed"
