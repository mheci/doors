#!/usr/bin/env bash
# Install the Terra NVIDIA userspace metapackages that dnf cannot install
# cleanly, because each one hard-requires `nvidia-kmod` (via nvidia-kmod-common)
# and dnf would satisfy that with akmod-nvidia / dkms-nvidia / kmod-nvidia —
# all of which run %post scripts that build kernel modules as root and abort
# the transaction. The real kernel modules are built against kernel-cachyos-lto
# in the `kmods` stage and copied in by install-kmods-nvidia.sh, so the kmod
# builders are never needed here.
#
# The four metapackages are downloaded with dnf5 and installed with
# `rpm -Uvh --nodeps --noscripts`:
#   - nvidia-kmod-common : GSP firmware + /usr/lib/modprobe.d/nvidia.conf + udev rules
#   - nvidia-driver      : suspend/resume systemd config + nvidia-ngx-updater
#   - nvidia-driver-cuda : nvidia-smi + CUDA MPS tools
#   - nvidia-settings    : nvidia-settings GUI
# Their libraries/deps (nvidia-driver-libs, -cuda-libs, nvidia-modprobe,
# nvidia-persistenced, nvidia-libXNVCtrl, nvidia-driver-common) are installed
# by the dnf module in gpu-nvidia.yml.
set -euo pipefail

echo ">>> downloading Terra NVIDIA metapackages"
cd "$(mktemp -d)"

# dnf5 download fetches every architecture the repos carry; we only install
# the x86_64/noarch rpms below.
dnf5 download -y --setopt=install_weak_deps=False \
  nvidia-kmod-common \
  nvidia-driver \
  nvidia-driver-cuda \
  nvidia-settings

echo ">>> installing metapackages (nodeps, noscripts)"
rpm -Uvh --nodeps --noscripts \
  nvidia-kmod-common-*.noarch.rpm \
  nvidia-driver-[0-9]*.x86_64.rpm \
  nvidia-driver-cuda-*.x86_64.rpm \
  nvidia-settings-*.x86_64.rpm

# The driver libraries were laid down by the dnf module; refresh the cache
# once so ldconfig-based lookups (nvidia-smi, nvtop) resolve immediately.
ldconfig || true

echo ">>> installed:"
rpm -q nvidia-kmod-common nvidia-driver nvidia-driver-cuda nvidia-settings
