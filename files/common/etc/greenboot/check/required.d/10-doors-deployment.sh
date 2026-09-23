#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Greenboot invokes required checks before declaring a staged immutable
# deployment successful. Keep this check local and bounded: boot-time health
# must not depend on DNS, a registry, or an arbitrary user artifact.
set -euo pipefail

readonly status_timeout_seconds=60
readonly timeout_binary='/usr/bin/timeout'
readonly rpm_ostree_binary='/usr/bin/rpm-ostree'
readonly jq_binary='/usr/bin/jq'

for required_binary in "${timeout_binary}" "${rpm_ostree_binary}" "${jq_binary}"; do
  [[ -x "${required_binary}" ]] || {
    printf 'Doors Greenboot health check requires %s\n' "${required_binary}" >&2
    exit 1
  }
done

[[ -e /run/ostree-booted ]] || {
  printf '%s\n' 'Doors Greenboot health check requires an OSTree/bootc deployment.' >&2
  exit 1
}

status_json="$("${timeout_binary}" --foreground "${status_timeout_seconds}" \
  "${rpm_ostree_binary}" status --json)"
"${jq_binary}" --exit-status '
  (.deployments | type == "array")
  and ([.deployments[]? | select(.booted == true)] | length == 1)
' <<<"${status_json}" >/dev/null

printf '%s\n' 'Doors booted rpm-ostree deployment is healthy.'
