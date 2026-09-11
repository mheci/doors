#!/usr/bin/env bash
# Deterministic 32-bit mesa install from terra-mesa.
#
# terra-mesa is rebuilt frequently and its CDN can serve the i686 and x86_64
# trees from different build snapshots *under the same EVR*. The only files
# that collide are the uncolored /usr/share/drirc.d/*.conf (owned by
# mesa-vulkan-drivers in both arches); rpm shares an uncolored multilib file
# only when the payloads are byte-identical, and "retry the install" alone is
# not enough because a single transaction can still fetch a torn pair.
#
# So we: download BOTH arches of mesa-vulkan-drivers, extract their drirc trees,
# and only install once the two hashes agree. We then force the 64-bit package
# to that verified payload and dnf-install the verified 32-bit rpm by path so no
# re-download race can reintroduce the torn pair. Retried with a metadata
# refresh until the mirror is stable.
set -euo pipefail

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

extract_rpm() {  # $1 = rpmfile, $2 = dest dir; 0 on success
  local rpmfile dest
  rpmfile="$(readlink -f "$1")"; dest="$2"
  if command -v rpm2cpio >/dev/null 2>&1 && command -v cpio >/dev/null 2>&1; then
    ( cd "$dest" && rpm2cpio "$rpmfile" | cpio -idm --quiet 2>/dev/null )
  elif command -v rpm2archive >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    ( cd "$dest" && rpm2archive "$rpmfile" 2>/dev/null | tar -x 2>/dev/null )
  else
    return 1
  fi
}

drirc_hash() {
  local rpmfile d h
  rpmfile="$(readlink -f "$1")"
  d="$(mktemp -d)"
  if extract_rpm "$rpmfile" "$d" && [ -d "$d/usr/share/drirc.d" ]; then
    h="$( cd "$d/usr/share/drirc.d" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1 )"
  else
    h="none"
  fi
  rm -rf "$d"
  printf '%s' "$h"
}

for attempt in 1 2 3 4 5 6 7 8 9 10; do
  cd "$work"
  rm -f ./*.rpm
  dnf5 clean all || true
  dnf5 download -y mesa-vulkan-drivers mesa-vulkan-drivers.i686 || true
  x64="$(ls mesa-vulkan-drivers-*.x86_64.rpm 2>/dev/null | head -n1 || true)"
  i686="$(ls mesa-vulkan-drivers-*.i686.rpm 2>/dev/null | head -n1 || true)"

  if [ -n "$x64" ] && [ -n "$i686" ]; then
    hx="$(drirc_hash "$x64")"; hi="$(drirc_hash "$i686")"
    echo "attempt ${attempt}: drirc hash x86_64=${hx} i686=${hi}"
    if [ -n "$hx" ] && [ "$hx" != "none" ] && [ "$hx" = "$hi" ]; then
      echo "consistent pair; installing"
      # Force the 64-bit package to the verified payload so the on-disk tree
      # matches the 32-bit rpm we are about to install.
      rpm -Uvh --force --nodeps "$x64"
      # Install the verified 32-bit rpm by path (no re-download) + resolve its
      # dependencies and the rest of the 32-bit mesa stack from the repos.
      dnf5 install -y --setopt=install_weak_deps=0 \
        "./$i686" \
        mesa-dri-drivers.i686 mesa-libEGL.i686 mesa-libGL.i686
      echo "32-bit mesa installed on attempt ${attempt}"
      exit 0
    fi
  fi

  echo "inconsistent or incomplete pair; retrying" >&2
  sleep 20
done

echo "32-bit mesa install failed after 10 attempts" >&2
exit 1
