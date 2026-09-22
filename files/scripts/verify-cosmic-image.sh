#!/usr/bin/env bash
# COSMIC-only Doors image invariants.
set -euo pipefail
# shellcheck source=verify-common.sh
source "$(dirname "$0")/verify-common.sh"

verify_common

[[ ! -e /etc/dconf/db/local.d/00-doors ]] \
  || fail 'GNOME dconf defaults must not ship in the COSMIC image'
[[ -x /usr/libexec/doors/seed-cosmic-dark-defaults.sh ]] \
  || fail 'COSMIC dark-default seeder is missing'
grep -Fqx "printf '%s\\n' true > \"\${temporary}\"" \
  /usr/libexec/doors/seed-cosmic-dark-defaults.sh \
  || fail 'COSMIC dark-default seeder does not write the expected value'
require_global_user_enabled doors-cosmic-dark-defaults.service
