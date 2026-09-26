#!/usr/bin/env bash
# Replace the Fedora kernel and its module-build headers with the official
# CachyOS COPR kernel. The COPR no longer publishes a matching NVIDIA kmod;
# nvidia-open-kmod rebuilds that driver afterwards.
#
# Fedora's userspace kernel-headers package stays installed. glibc-devel, GCC,
# and CUDA require it, and this COPR does not replace it. kernel-cachyos-devel
# is the kernel header tree used to build modules.
set -euo pipefail

fail() {
  printf 'Doors CachyOS kernel: %s\n' "$*" >&2
  exit 1
}

[[ "$(uname -m)" == 'x86_64' ]] || fail 'kernel-cachyos is published for x86_64 only'

# shellcheck disable=SC1091
source /usr/lib/os-release
[[ "${VERSION_ID:-}" =~ ^[0-9]+$ ]] || fail "unexpected VERSION_ID: ${VERSION_ID:-unset}"

readonly release="${VERSION_ID}"
readonly key='/etc/pki/rpm-gpg/RPM-GPG-KEY-cachyos-kernel'
readonly repo_file='/etc/yum.repos.d/cachyos-kernel.repo'
readonly version_file='/usr/share/doors/kernel-cachyos.version'
readonly -a stock_names=(
  kernel
  kernel-core
  kernel-modules
  kernel-modules-core
  kernel-modules-extra
  kernel-devel
  kernel-devel-matched
)
readonly -a required_names=(
  kernel-cachyos
  kernel-cachyos-core
  kernel-cachyos-modules
  kernel-cachyos-devel
  kernel-cachyos-devel-matched
)

[[ -s "${key}" ]] || fail "vendored CachyOS signing key is missing: ${key}"
gpg --show-keys --with-colons "${key}" | grep -q '^pub:' \
  || fail 'vendored CachyOS key is not a public key'

install -d -m 0755 /boot /etc/yum.repos.d /usr/share/doors /var/tmp
chmod 1777 /var/tmp

# Package signatures stay mandatory. Repository metadata is unsigned on COPR,
# so the allowlist is the control that keeps this source limited to the
# desktop kernel and its matching headers. The stale prebuilt NVIDIA kmods
# in this COPR do not match the current kernel and are not allowlisted.
cat > "${repo_file}" <<EOF
[cachyos-kernel]
name=CachyOS kernel COPR (allowlisted)
baseurl=https://download.copr.fedorainfracloud.org/results/bieszczaders/kernel-cachyos/fedora-${release}-\$basearch/
type=rpm-md
enabled=1
priority=10
gpgcheck=1
repo_gpgcheck=0
gpgkey=file://${key}
skip_if_unavailable=False
metadata_expire=6h
includepkgs=kernel-cachyos kernel-cachyos-core kernel-cachyos-modules kernel-cachyos-devel kernel-cachyos-devel-matched
EOF

cleanup_repo() {
  rm -f -- "${repo_file}"
}
trap cleanup_repo EXIT

present=()
for name in "${stock_names[@]}"; do
  if rpm -q "${name}" >/dev/null 2>&1; then
    present+=("${name}")
  fi
done

mapfile -t stale_kmods < <(rpm -qa --qf '%{NAME}\n' 'kmod-nvidia*' 'akmod-nvidia*' | sort -u)
if ((${#stale_kmods[@]})); then
  dnf5 remove -y --no-autoremove --setopt=install_weak_deps=False "${stale_kmods[@]}"
fi
if ((${#present[@]})); then
  dnf5 remove -y --no-autoremove --setopt=install_weak_deps=False "${present[@]}"
fi

dnf5 install -y --setopt=install_weak_deps=False \
  --disablerepo='*' --enablerepo=fedora --enablerepo=updates --enablerepo=cachyos-kernel \
  kernel-cachyos kernel-cachyos-devel-matched

for name in "${required_names[@]}"; do
  rpm -q "${name}" >/dev/null 2>&1 || fail "required package was not installed: ${name}"
done
for name in "${stock_names[@]}"; do
  if rpm -q "${name}" >/dev/null 2>&1; then
    fail "Fedora kernel package remains installed: ${name}"
  fi
done
if rpm -qa | grep -Eq '^kernel-cachyos-(lts|rt|server|nvidia-open)-'; then
  fail 'a non-desktop or prebuilt NVIDIA CachyOS package was installed'
fi

kver="$(rpm -q kernel-cachyos-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}')"
[[ -n "${kver}" && -d "/usr/lib/modules/${kver}" && -d "/usr/src/kernels/${kver}" ]] \
  || fail "CachyOS kernel or headers are missing for ${kver}"

# Package removal does not always delete a previous kernel tree. A leftover
# Fedora tree makes the initramfs module regenerate the wrong image.
shopt -s nullglob
for leftover in /usr/lib/modules/* /usr/src/kernels/*; do
  [[ -d "${leftover}" ]] || continue
  [[ "${leftover##*/}" == "${kver}" ]] && continue
  rm -rf -- "${leftover}"
done
for leftover in /boot/vmlinuz-* /boot/initramfs-*; do
  [[ -e "${leftover}" ]] || continue
  case "${leftover}" in
    *cachyos*) continue ;;
  esac
  rm -f -- "${leftover}"
done
shopt -u nullglob
if [[ ! -e "/usr/lib/modules/${kver}/vmlinuz" && ! -e "/lib/modules/${kver}/vmlinuz" \
  && ! -e "/boot/vmlinuz-${kver}" ]]; then
  fail "CachyOS vmlinuz is missing for ${kver}"
fi
find "/usr/src/kernels/${kver}" -type f -path '*/scripts/sign-file' -perm /111 -print -quit \
  | grep -q . || fail "CachyOS sign-file is missing for ${kver}"

command -v setsebool >/dev/null 2>&1 || fail 'setsebool is required to allow CachyOS module loads'
setsebool -P domain_kernel_load_modules on
getsebool domain_kernel_load_modules | grep -q ' on$' \
  || fail 'SELinux boolean domain_kernel_load_modules did not persist'

printf '%s\n' "${kver}" > "${version_file}"
printf 'Doors CachyOS kernel: installed %s with matching headers.\n' "${kver}"
