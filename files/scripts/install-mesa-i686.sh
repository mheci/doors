#!/usr/bin/env bash
# Install Terra 32-bit mesa in its own transaction.
#
# Why a dedicated script (not a dnf module): terra-mesa ships
# /usr/share/drirc.d/*.conf as *uncolored* files in BOTH the i686 and x86_64
# mesa-vulkan-drivers packages. rpm permits same-name multilib pairs to share an
# uncolored file only when the two payloads are byte-identical, and Terra's CDN
# occasionally serves the two arches from different build snapshots (the i686
# and x86_64 trees are pushed independently). When that window is open, the
# transaction fails with "file .../00-radv-defaults.conf ... conflicts with
# file from package mesa-vulkan-drivers ...". Retrying after a metadata refresh
# re-fetches a consistent pair, after which the files are identical and rpm
# merges them. Doing this up front means the later `dnf install steam` no
# longer has to upgrade 32-bit mesa mid-transaction.
set -euo pipefail

pkgs=(
  mesa-dri-drivers.i686
  mesa-libEGL.i686
  mesa-libGL.i686
  mesa-vulkan-drivers.i686
)

for attempt in 1 2 3 4 5; do
  if dnf5 install -y --setopt=install_weak_deps=0 "${pkgs[@]}"; then
    echo "32-bit mesa installed on attempt ${attempt}"
    exit 0
  fi
  echo "32-bit mesa attempt ${attempt} failed; refreshing metadata and retrying" >&2
  dnf5 clean all || true
  sleep 10
done

echo "32-bit mesa install failed after 5 attempts" >&2
exit 1
