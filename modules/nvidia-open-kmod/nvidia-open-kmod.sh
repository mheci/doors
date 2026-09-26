#!/usr/bin/env bash
# Rebuild the open NVIDIA kernel module against kernel-cachyos.
#
# The BlueBuild NVIDIA Open base ships a prebuilt kmod for the Fedora kernel
# and then deletes akmods. CachyOS no longer publishes a matching prebuilt
# driver, and the official akmods module only supports Universal Blue kernels.
# This module is the build-time replacement: it uses Negativo17's open driver
# sources, keeps the CachyOS headers, and leaves signing to mok-sign.
set -euo pipefail

fail() {
  printf 'Doors NVIDIA open kmod: %s\n' "$*" >&2
  exit 1
}

[[ "$(uname -m)" == 'x86_64' ]] || fail 'NVIDIA open kmod rebuild is x86_64 only'

# shellcheck disable=SC1091
source /usr/lib/os-release
[[ "${VERSION_ID:-}" =~ ^[0-9]+$ ]] || fail "unexpected VERSION_ID: ${VERSION_ID:-unset}"

readonly release="${VERSION_ID}"
readonly key='/etc/pki/rpm-gpg/RPM-GPG-KEY-negativo17-nvidia'
readonly repo_file='/etc/yum.repos.d/fedora-nvidia.repo'
readonly akmodsbuild='/usr/sbin/akmodsbuild'
readonly akmodsbuild_backup='/usr/sbin/akmodsbuild.doors-backup'
readonly -a driver_packages=(
  nvidia-driver
  nvidia-driver-cuda
  nvidia-modprobe
  nvidia-persistenced
  nvidia-settings
  libnvidia-fbc
  libva-nvidia-driver
  nvidia-kmod-common
)
readonly -a excluded=(
  --exclude=kernel
  --exclude=kernel-core
  --exclude=kernel-modules
  --exclude=kernel-modules-core
  --exclude=kernel-modules-extra
  --exclude=kernel-devel
  --exclude=kernel-devel-matched
  --exclude=kernel-cachyos-nvidia-open
  --exclude=cuda-toolkit*
  --exclude=cuda-nvcc*
  --exclude=cuda-drivers*
)

[[ -s "${key}" ]] || fail "vendored Negativo17 key is missing: ${key}"
kver="$(rpm -q kernel-cachyos-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}')" \
  || fail 'kernel-cachyos-core is not installed'
[[ -d "/usr/src/kernels/${kver}" ]] || fail "CachyOS headers are missing for ${kver}"
[[ -x "/usr/src/kernels/${kver}/scripts/sign-file" || -f "/usr/src/kernels/${kver}/scripts/sign-file" ]] \
  || fail "CachyOS sign-file is missing for ${kver}"

install -d -m 0755 /etc/nvidia /etc/rpm /var/tmp
chmod 1777 /var/tmp
printf '%s\n' 'kernel-open' > /etc/nvidia/kernel.conf
printf '%s\n' '%_with_kmod_nvidia_open 1' > /etc/rpm/macros.nvidia-kmod

cat > "${repo_file}" <<EOF
[fedora-nvidia]
name=negativo17 - Nvidia (compose-time, open modules)
baseurl=https://negativo17.org/repos/nvidia/fedora-${release}/\$basearch/
enabled=1
skip_if_unavailable=False
gpgcheck=1
repo_gpgcheck=0
gpgkey=file://${key}
enabled_metadata=1
metadata_expire=6h
type=rpm-md
EOF

restore_akmodsbuild() {
  if [[ -f "${akmodsbuild_backup}" ]]; then
    mv -f -- "${akmodsbuild_backup}" "${akmodsbuild}"
  fi
}
cleanup() {
  restore_akmodsbuild
  rm -f -- "${repo_file}"
}
trap cleanup EXIT

# akmod-nvidia is a dependency of the driver stack, so it cannot be in the
# first transaction: its %post calls akmodsbuild while /var is writable and
# dnf5 aborts. Install only the toolchain, neutralize that check, then install
# akmod-nvidia without scriptlets. The explicit akmods invocation is the build.
dnf5 install -y --setopt=install_weak_deps=False \
  --disablerepo='*' --enablerepo=fedora --enablerepo=updates \
  --exclude=akmod-nvidia \
  akmods gcc-c++

[[ -f "${akmodsbuild}" ]] || fail "akmodsbuild is missing: ${akmodsbuild}"
cp -a -- "${akmodsbuild}" "${akmodsbuild_backup}"
sed -i '/if \[\[ -w \/var \]\] ; then/,/fi/d' "${akmodsbuild}"

dnf5 install -y --setopt=install_weak_deps=False --setopt=tsflags=noscripts \
  --disablerepo='*' --enablerepo=fedora --enablerepo=updates --enablerepo=fedora-nvidia \
  "${excluded[@]}" \
  akmod-nvidia

dnf5 install -y --setopt=install_weak_deps=False \
  --disablerepo='*' --enablerepo=fedora --enablerepo=updates --enablerepo=fedora-nvidia \
  "${excluded[@]}" \
  "${driver_packages[@]}"

if rpm -q kernel >/dev/null 2>&1; then
  fail 'the NVIDIA transaction reinstalled the Fedora kernel'
fi
[[ -d "/usr/src/kernels/${kver}" ]] || fail 'CachyOS headers were removed during the driver transaction'

akmods --force --kernels "${kver}" --kmod nvidia
restore_akmodsbuild

module_path=''
for candidate in \
  "/usr/lib/modules/${kver}/extra/nvidia/nvidia.ko.xz" \
  "/usr/lib/modules/${kver}/extra/nvidia/nvidia.ko.zst" \
  "/usr/lib/modules/${kver}/extra/nvidia/nvidia.ko.gz" \
  "/usr/lib/modules/${kver}/extra/nvidia/nvidia.ko"; do
  if [[ -s "${candidate}" ]]; then
    module_path="${candidate}"
    break
  fi
done
if [[ -z "${module_path}" ]]; then
  if compgen -G "/var/cache/akmods/nvidia/*.failed.log" >/dev/null; then
    cat /var/cache/akmods/nvidia/*.failed.log >&2 || true
  fi
  fail "open NVIDIA module was not built for ${kver}"
fi

license="$(modinfo -l "${module_path}")"
[[ "${license}" == 'Dual MIT/GPL' ]] \
  || fail "expected the open NVIDIA license, found: ${license:-empty}"

for suffix in '' -drm -modeset -peermem -uvm; do
  stem="${module_path%nvidia.ko*}"
  ext="${module_path##*nvidia.ko}"
  [[ -s "${stem}nvidia${suffix}.ko${ext}" ]] || fail "missing nvidia${suffix} module for ${kver}"
done

kmod_version="$(rpm -q akmod-nvidia --qf '%{VERSION}')"
userspace_version="$(rpm -q nvidia-modprobe --qf '%{VERSION}')"
[[ "${kmod_version}" == "${userspace_version}" ]] \
  || fail "akmod-nvidia ${kmod_version} does not match nvidia-modprobe ${userspace_version}"

# The built kmod RPM stays. The akmod toolchain must not remain, or a later
# boot could rebuild an unsigned module. The CachyOS headers stay installed.
dnf5 remove -y --no-autoremove --setopt=install_weak_deps=False akmods akmod-nvidia
rm -f -- /etc/systemd/system/multi-user.target.wants/akmods.service
[[ -s "${module_path}" ]] || fail 'removing akmods deleted the built NVIDIA module'
if rpm -q kernel >/dev/null 2>&1 || rpm -q kernel-devel >/dev/null 2>&1; then
  fail 'Fedora kernel or kernel-devel returned while removing the akmod toolchain'
fi
rpm -q kernel-cachyos-devel >/dev/null 2>&1 || fail 'CachyOS headers were removed'

rm -rf -- /var/cache/akmods /var/cache/dnf /var/cache/libdnf5
printf 'Doors NVIDIA open kmod: built %s for %s.\n' "${kmod_version}" "${kver}"
