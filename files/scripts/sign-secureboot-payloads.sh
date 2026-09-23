#!/usr/bin/env bash
# Sign every shipped kernel PE/COFF payload and loadable module during compose.
#
# The MOK private key is a BuildKit secret mounted only for this module RUN. It
# must never be copied, logged, emitted as an image environment variable, or
# retained in a layer. The public DER certificate is deliberate image content:
# target owners need it to enroll the matching MOK locally.
set -euo pipefail

readonly expected_subject='CN=Doors Secure Boot MOK'
readonly expected_signer='Doors Secure Boot MOK'
readonly module_root="${DOORS_SECUREBOOT_MODULE_ROOT:-/usr/lib/modules}"
readonly certificate="${DOORS_MOK_CERTIFICATE:-/usr/share/doors/secureboot/doors-mok.der}"
readonly fingerprint_file="${DOORS_MOK_FINGERPRINT_FILE:-/usr/share/doors/secureboot/doors-mok.fingerprint}"
readonly mok_key="${DOORS_MOK_KEY_PATH:-/run/secrets/doors-mok.key}"
readonly scratch_parent="${DOORS_SECUREBOOT_SCRATCH_PARENT:-/var/tmp}"
readonly kernel_source_root="${DOORS_SECUREBOOT_KERNEL_SOURCE_ROOT:-/usr/src/kernels}"
# Set only when this no-cache RUN installed headers solely to obtain sign-file.
# It must be removed before the layer commits.
transient_kernel_devel=0

die() {
  printf 'Doors Secure Boot signing failed: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

require_readable_file() {
  [[ -r "$1" && -f "$1" ]] || die "required file is missing or unreadable: $1"
}

for command in awk cut depmod find modinfo openssl sbverify sbsign sed sha256sum sort tr xz; do
  require_command "${command}"
done
require_readable_file "${certificate}"
require_readable_file "${fingerprint_file}"
require_readable_file "${mok_key}"
[[ -d "${module_root}" ]] || die "kernel module root is missing: ${module_root}"

scratch="$(mktemp -d "${scratch_parent%/}/doors-secureboot.XXXXXX")"
trap 'rm -rf -- "${scratch}"' EXIT
readonly scratch
readonly certificate_pem="${scratch}/doors-mok.pem"

# A mismatched CI secret/certificate must fail before touching a kernel payload.
certificate_subject="$(openssl x509 -inform DER -in "${certificate}" -noout -subject -nameopt RFC2253 \
  | sed 's/^subject=//')"
[[ "${certificate_subject}" == "${expected_subject}" ]] \
  || die "the tracked MOK certificate has an unexpected subject"
certificate_fingerprint="$(openssl x509 -inform DER -in "${certificate}" -noout -fingerprint -sha256 \
  | cut -d= -f2 | tr 'A-F' 'a-f')"
[[ "$(<"${fingerprint_file}")" == "sha256:${certificate_fingerprint}" ]] \
  || die 'the tracked MOK fingerprint does not match the public certificate'

key_public_sha256="$(openssl pkey -in "${mok_key}" -pubout -outform DER 2>/dev/null \
  | sha256sum | awk '{print $1}')"
certificate_public_sha256="$(openssl x509 -inform DER -in "${certificate}" -pubkey -noout \
  | openssl pkey -pubin -outform DER 2>/dev/null \
  | sha256sum | awk '{print $1}')"
[[ "${key_public_sha256}" == "${certificate_public_sha256}" ]] \
  || die 'the protected MOK private key does not match the tracked public certificate'

openssl x509 -inform DER -in "${certificate}" -out "${certificate_pem}"

replace_preserving_metadata() {
  local original="$1"
  local replacement="$2"

  [[ -s "${replacement}" ]] || die "signing did not produce a replacement for ${original}"
  chmod --reference="${original}" "${replacement}"
  chown --reference="${original}" "${replacement}"
  touch --reference="${original}" "${replacement}"
  mv -f -- "${replacement}" "${original}"
}

sign_pe_payload() {
  local payload="$1"
  local replacement

  replacement="$(mktemp "${scratch}/signed-payload.XXXXXX")"
  rm -f -- "${replacement}"
  sbsign --key "${mok_key}" --cert "${certificate_pem}" \
    --output "${replacement}" "${payload}"
  sbverify --cert "${certificate_pem}" "${replacement}" >/dev/null \
    || die "MOK verification failed for generated kernel payload ${payload}"
  replace_preserving_metadata "${payload}" "${replacement}"
  sbverify --cert "${certificate_pem}" "${payload}" >/dev/null \
    || die "MOK verification failed after replacing kernel payload ${payload}"
}

sign_module() {
  local sign_file="$1"
  local module="$2"
  local expanded replacement signer

  case "${module}" in
    *.ko)
      "${sign_file}" sha256 "${mok_key}" "${certificate}" "${module}"
      ;;
    *.ko.xz)
      expanded="$(mktemp "${scratch}/module.XXXXXX")"
      replacement="$(mktemp "${scratch}/module.XXXXXX")"
      xz --decompress --stdout -- "${module}" > "${expanded}"
      "${sign_file}" sha256 "${mok_key}" "${certificate}" "${expanded}"
      # Match Fedora's kernel package module-compression contract.
      xz --compress --check=crc32 --lzma2=dict=1MiB --stdout -- "${expanded}" > "${replacement}"
      replace_preserving_metadata "${module}" "${replacement}"
      ;;
    *.ko.zst)
      require_command zstd
      expanded="$(mktemp "${scratch}/module.XXXXXX")"
      replacement="$(mktemp "${scratch}/module.XXXXXX")"
      zstd --quiet --decompress --stdout -- "${module}" > "${expanded}"
      "${sign_file}" sha256 "${mok_key}" "${certificate}" "${expanded}"
      zstd --quiet --compress --stdout -- "${expanded}" > "${replacement}"
      replace_preserving_metadata "${module}" "${replacement}"
      ;;
    *.ko.gz)
      require_command gzip
      expanded="$(mktemp "${scratch}/module.XXXXXX")"
      replacement="$(mktemp "${scratch}/module.XXXXXX")"
      gzip --decompress --stdout -- "${module}" > "${expanded}"
      "${sign_file}" sha256 "${mok_key}" "${certificate}" "${expanded}"
      gzip --no-name --stdout -- "${expanded}" > "${replacement}"
      replace_preserving_metadata "${module}" "${replacement}"
      ;;
    *)
      die "unsupported module compression format: ${module}"
      ;;
  esac

  signer="$(modinfo -F signer "${module}" 2>/dev/null || true)"
  [[ "${signer}" == "${expected_signer}" ]] \
    || die "MOK module verification failed for ${module}"
}

payload_count=0
while IFS= read -r -d '' payload; do
  sign_pe_payload "${payload}"
  ((payload_count += 1))
done < <(
  # Fedora ships the ordinary vmlinuz plus optional UKI, DTB-loader, and
  # addon PE/COFF artifacts below module-version trees. Sign all EFI payloads
  # there rather than relying on a package-name-specific subset.
  find "${module_root}" -type f \( \
    -name 'vmlinuz*' -o -name '*.efi' -o -name '*.efi.signed' \
  \) -print0 | LC_ALL=C sort -z
)
((payload_count > 0)) || die "no kernel PE/COFF payloads found beneath ${module_root}"

install_transient_kernel_devel() {
  # kernel-devel intentionally does not require a matching kernel. That is
  # essential for BlueBuild's NVIDIA bases, whose shipped kernel can lead the
  # Fedora metadata used at compose time.
  if rpm -q kernel-devel >/dev/null 2>&1; then
    return 0
  fi
  require_command dnf5
  dnf5 install -y --setopt=install_weak_deps=False kernel-devel
  transient_kernel_devel=1
}

remove_transient_kernel_devel() {
  ((transient_kernel_devel == 1)) || return 0
  dnf5 remove -y kernel-devel
  if rpm -q kernel-devel >/dev/null 2>&1; then
    die 'transient kernel-devel remains installed after Secure Boot signing'
  fi
  transient_kernel_devel=0
}

resolve_sign_file() {
  local kernel_dir="$1"
  local kernel_version="$2"
  local candidate fallback=''

  # Prefer a precisely matched tool if the base carries it. BlueBuild bases can
  # intentionally lead Fedora metadata, though: kernel-devel-matched would try
  # to replace the already-installed NVIDIA kernel. Fedora's sign-file utility
  # has a version-independent module-signature format, so a standalone
  # kernel-devel copy is a safe fail-closed fallback when the exact headers are
  # unavailable.
  for candidate in \
    "${kernel_dir}/build/scripts/sign-file" \
    "${kernel_source_root}/${kernel_version}/scripts/sign-file"; do
    if [[ -x "${candidate}" ]]; then
      sign_file="${candidate}"
      return 0
    fi
  done

  if [[ -d "${kernel_source_root}" ]]; then
    while IFS= read -r candidate; do
      fallback="${candidate}"
    done < <(
      find "${kernel_source_root}" -type f -path '*/scripts/sign-file' -perm /111 -print \
        | LC_ALL=C sort
    )
  fi

  # Do not retain the large header package in a separate layer. Install it only
  # after the exact/base-provided paths have been exhausted, then locate the
  # standalone sign-file it supplies and remove the package before success.
  if [[ -z "${fallback}" ]]; then
    install_transient_kernel_devel
    while IFS= read -r candidate; do
      fallback="${candidate}"
    done < <(
      find "${kernel_source_root}" -type f -path '*/scripts/sign-file' -perm /111 -print \
        | LC_ALL=C sort
    )
  fi
  [[ -n "${fallback}" ]] \
    || die "kernel-devel sign-file is unavailable for kernel ${kernel_version}"
  sign_file="${fallback}"
}

module_count=0
while IFS= read -r -d '' kernel_dir; do
  kernel_version="${kernel_dir##*/}"
  sign_file=''
  resolve_sign_file "${kernel_dir}" "${kernel_version}"

  while IFS= read -r -d '' module; do
    sign_module "${sign_file}" "${module}"
    ((module_count += 1))
  done < <(
    find "${kernel_dir}" -type f \( \
      -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' -o -name '*.ko.gz' \
    \) -print0 | LC_ALL=C sort -z
  )

  # The image uses the normal merged-/usr path. Refresh dependency metadata only
  # for actual kernel module trees; a global uki.extra.d directory has no modules.
  first_module="$(find "${kernel_dir}" -type f \( \
    -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' -o -name '*.ko.gz' \
  \) -print -quit)"
  if [[ -n "${first_module}" ]]; then
    depmod -a "${kernel_version}"
  fi
done < <(find "${module_root}" -mindepth 1 -maxdepth 1 -type d -print0 | LC_ALL=C sort -z)
((module_count > 0)) || die "no loadable kernel modules found beneath ${module_root}"
remove_transient_kernel_devel

printf 'Doors Secure Boot: signed and verified %d kernel payload(s) and %d module(s).\n' \
  "${payload_count}" "${module_count}"
