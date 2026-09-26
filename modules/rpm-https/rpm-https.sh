#!/usr/bin/env bash
# Force TLS for every active RPM repository before any Doors DNF transaction.
# Fedora MirrorManager honours `protocol=https`; repositories without a
# protocol-filterable metalink must use an explicit HTTPS baseurl instead.
set -Eeuo pipefail

readonly repo_dir='/etc/yum.repos.d'
readonly dnf_config_dir='/etc/dnf/libdnf5.conf.d'

fail() {
  printf 'Doors RPM HTTPS policy: %s\n' "$*" >&2
  exit 1
}

[[ -d "${repo_dir}" ]] || fail "repository directory is missing: ${repo_dir}"

# Do not rely on the transport used to fetch a metalink: without this query,
# Fedora's response may include HTTP mirror URLs. Keep the rewrite idempotent
# so a later fedora-repos update cannot silently restore HTTP mirror candidates.
while IFS= read -r -d '' repo_file; do
  sed -E -i \
    -e '/^[[:space:]]*(baseurl|mirrorlist|metalink)[[:space:]]*=[[:space:]]*http:\/\// s/http:\/\//https:\/\//' \
    -e '/^[[:space:]]*metalink[[:space:]]*=[[:space:]]*https:\/\/mirrors\.fedoraproject\.org\/metalink\?/ { /(^|[?&])protocol=https([&#]|$)/! s/$/\&protocol=https/ }' \
    "${repo_file}"
done < <(find "${repo_dir}" -type f -name '*.repo' -print0)

# libdnf performs normal certificate validation as an explicit global policy.
install -d -m 0755 "${dnf_config_dir}"
cat > "${dnf_config_dir}/90-doors-https.conf" <<'EOF'
[main]
sslverify=True
EOF

# Fail closed if an active repository URL is neither TLS nor local file media.
while IFS= read -r -d '' repo_file; do
  awk -v repo_file="${repo_file}" '
    /^[[:space:]]*(baseurl|mirrorlist|metalink)[[:space:]]*=/ {
      line = $0
      sub(/^[[:space:]]*(baseurl|mirrorlist|metalink)[[:space:]]*=[[:space:]]*/, "", line)
      if (line !~ /^(https|file):\/\//) {
        printf "%s: non-HTTPS repository URL: %s\n", repo_file, line > "/dev/stderr"
        exit 1
      }
    }
  ' "${repo_file}" || fail "refusing non-HTTPS RPM repository configuration in ${repo_file}"
done < <(find "${repo_dir}" -type f -name '*.repo' -print0)

# Verify the rewrite instead of trusting it: Fedora metalinks must retain a
# selector that returns only TLS mirror URLs.
while IFS= read -r -d '' repo_file; do
  if grep -Eq '^[[:space:]]*metalink[[:space:]]*=[[:space:]]*https://mirrors\.fedoraproject\.org/metalink\?' "${repo_file}"; then
    grep -Eq '^[[:space:]]*metalink[[:space:]]*=.*([?&])protocol=https([&#]|$)' "${repo_file}" \
      || fail "Fedora metalink lacks protocol=https in ${repo_file}"
  fi
done < <(find "${repo_dir}" -type f -name '*.repo' -print0)

printf 'Doors RPM HTTPS policy: every active repository route is TLS.\n'
