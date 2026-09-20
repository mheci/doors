#!/usr/bin/env bash
# Bluefin can be published between paired x86_64/i686 Mesa updates. The
# official akmods nvidia-open installer subsequently adds these i686 packages;
# synchronizing their x86_64 counterparts first prevents RPM file conflicts
# while retaining signed, enabled Bluefin/Fedora repository policy.
set -euo pipefail

command -v dnf5 >/dev/null

dnf5 -y --refresh --setopt=install_weak_deps=False upgrade \
  mesa-dri-drivers \
  mesa-filesystem \
  mesa-libEGL \
  mesa-libGL \
  mesa-libgbm \
  mesa-vulkan-drivers
