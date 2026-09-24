#!/usr/bin/env bash
# brave-origin needs Brave's keyring RPM at compose time. That RPM also carries
# unrelated beta/nightly trust material and a background key updater. Doors uses
# only the reviewed Origin keys, has no runtime Brave repository, and updates
# through rebuilt images, so remove the unused material after the strict DNF
# transaction.
set -euo pipefail

readonly key_dir='/etc/pki/rpm-gpg'
readonly origin_key="${key_dir}/RPM-GPG-KEY-brave"
readonly -a expected_origin_fingerprints=(
  'DBF1A116C220B8C7164F98230686B78420038257'
  '47D32A74E9A9E013A4B4926C68D513D36A73CD96'
  'B2A3DCA350E67256740DF904DE4EC67BE4B0DCA0'
)
gpg_home="$(mktemp -d)"
readonly gpg_home
trap 'rm -rf "${gpg_home}"' EXIT
chmod 0700 "${gpg_home}"
export GNUPGHOME="${gpg_home}"

[[ -s "${origin_key}" ]] || { echo 'Brave Origin signing key is missing' >&2; exit 1; }

# The vendor RPM starts a short post-install import helper in the background.
# Wait for the helper's exact argv element rather than using a broad process
# regex, which could accidentally match a build wrapper's command text.
updater_running() {
  local proc cmdline
  for proc in /proc/[0-9]*; do
    [[ -r "${proc}/cmdline" ]] || continue
    cmdline="$(tr '\0' '\n' < "${proc}/cmdline" 2>/dev/null || true)"
    if [[ $'\n'"${cmdline}"$'\n' == *$'\n/usr/libexec/brave-key-updater\n'* ]]; then
      return 0
    fi
  done
  return 1
}
for _ in {1..40}; do
  updater_running || break
  sleep 0.25
done
updater_running && { echo 'Brave key updater did not finish during compose' >&2; exit 1; }

actual_origin_fingerprints="$(gpg --show-keys --with-colons "${origin_key}" 2>/dev/null \
  | awk -F: '$1 == "fpr" { print $10 }' | sort -u)"
expected_fingerprints="$(printf '%s\n' "${expected_origin_fingerprints[@]}" | sort)"
[[ "${actual_origin_fingerprints}" == "${expected_fingerprints}" ]] || {
  echo 'Brave keyring changed the reviewed Origin signing-key set' >&2
  exit 1
}

# Capture short IDs before removing every non-Origin Brave key file. The keyring
# post-install script can import those into the RPM database; remove precisely
# those imported records without touching Fedora, Negativo17, or Origin keys.
shopt -s nullglob
unapproved_key_files=("${key_dir}"/RPM-GPG-KEY-brave-*)
unapproved_key_ids=()
for key_file in "${unapproved_key_files[@]}"; do
  while IFS= read -r fingerprint; do
    [[ "${fingerprint}" =~ ^[0-9A-F]{40}$ ]] || {
      echo "Unexpected Brave auxiliary key fingerprint in ${key_file}" >&2
      exit 1
    }
    key_id="${fingerprint: -8}"
    unapproved_key_ids+=("${key_id,,}")
  done < <(gpg --show-keys --with-colons "${key_file}" 2>/dev/null | awk -F: '$1 == "fpr" { print $10 }')
done
rm -f "${unapproved_key_files[@]}"

for key_id in "${unapproved_key_ids[@]}"; do
  while IFS= read -r rpm_key; do
    [[ -n "${rpm_key}" ]] || continue
    rpm -e "${rpm_key}"
  done < <(rpm -qa "gpg-pubkey-${key_id}-*")
done

# The package's updater re-imports every RPM-GPG-KEY-brave* file. Remove it so
# no future image layer can recreate unrelated key trust.
rm -f /usr/libexec/brave-key-updater
rm -f /etc/cron.daily/brave-key-updater

printf 'Doors Brave keyring hardened: only reviewed Origin keys remain.\n'
