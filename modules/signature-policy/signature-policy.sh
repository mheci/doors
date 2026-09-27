#!/usr/bin/env bash
# Extend BlueBuild's per-image signing module policy to every fixed Doors image
# transition target. The shared production Cosign public key is reused only for
# the trusted-main Doors repositories.
set -Eeuo pipefail

readonly containers_dir='/etc/containers'
readonly policy_file="${containers_dir}/policy.json"
readonly keys_dir='/etc/pki/containers'
readonly shared_key="${keys_dir}/doors-shared.pub"
readonly registry_file="${containers_dir}/registries.d/doors-signatures.yaml"
readonly -a doors_repositories=(
  'ghcr.io/mheci/doors'
  'ghcr.io/mheci/doors-kinoite'
  'ghcr.io/mheci/doors-hyprland'
  'ghcr.io/mheci/doors-sway'
)

fail() {
  printf 'Doors signature policy: %s\n' "$*" >&2
  exit 1
}

[[ -n "${IMAGE_NAME:-}" ]] || fail 'BlueBuild IMAGE_NAME is unavailable'
readonly image_key="${keys_dir}/${IMAGE_NAME//\//_}.pub"
[[ -s "${image_key}" ]] \
  || fail "BlueBuild signing module did not install the expected public key: ${image_key}"
[[ -s "${policy_file}" ]] || fail "BlueBuild signing module did not install ${policy_file}"
command -v jq >/dev/null 2>&1 || fail 'jq is required to extend the signature policy'

# The BlueBuild signing module establishes a reject-by-default policy first.
# Do not silently weaken it while adding sibling Doors repositories.
jq -e '.default[0].type == "reject" and (.transports.docker | type == "object")' \
  "${policy_file}" >/dev/null \
  || fail 'expected reject-by-default Docker signature policy is missing'

install -d -m 0755 "${keys_dir}" "${containers_dir}/registries.d"
install -m 0644 "${image_key}" "${shared_key}"

policy_temp="$(mktemp "${containers_dir}/.doors-policy.XXXXXX")"
trap 'rm -f -- "${policy_temp}"' EXIT
# Rebuild the filter from the repository list so a new image is one array entry.
jq_filter='def doors_rule: [{"type":"sigstoreSigned","keyPath":$key_path,"signedIdentity":{"type":"matchRepository"}}]; .'
repo_index=0
jq_args=(--arg key_path "${shared_key}")
for repository in "${doors_repositories[@]}"; do
  jq_args+=(--arg "repo${repo_index}" "${repository}")
  jq_filter+=" | .transports.docker[\$repo${repo_index}] = doors_rule"
  repo_index=$((repo_index + 1))
done
jq "${jq_args[@]}" "${jq_filter}" "${policy_file}" > "${policy_temp}"
install -m 0644 "${policy_temp}" "${policy_file}"

# Cosign signatures are stored as legacy sigstore attachments by the pinned
# BlueBuild/Cosign publication flow. Tell containers-image/bootc where to find
# those attachments for every accepted switch target.
{
  printf 'docker:\n'
  for repository in "${doors_repositories[@]}"; do
    printf '  %s:\n    use-sigstore-attachments: true\n' "${repository}"
  done
} > "${registry_file}"
chmod 0644 "${registry_file}"

for repository in "${doors_repositories[@]}"; do
  jq -e --arg repository "${repository}" --arg key_path "${shared_key}" '
    .transports.docker[$repository] == [{
      "type": "sigstoreSigned",
      "keyPath": $key_path,
      "signedIdentity": {"type": "matchRepository"}
    }]
  ' "${policy_file}" >/dev/null || fail "signature policy is incomplete for ${repository}"
done

printf 'Doors signature policy extended to %s transition targets.\n' "${#doors_repositories[@]}"
