#!/usr/bin/env bash
# Install lemurs (TTY display manager) from the pinned upstream release:
# binary -> /usr/bin/lemurs, systemd unit, and PAM service.
# Version is Renovate-managed (renovate.json).
set -euo pipefail

VERSION="${LEMURS_VERSION:-0.4.0}"

echo ">>> installing lemurs ${VERSION}"
curl -fsSL "https://github.com/coastalwhite/lemurs/releases/download/v${VERSION}/lemurs-x86_64-unknown-linux-gnu.tar.xz" \
  -o /tmp/lemurs.tar.xz
mkdir -p /tmp/lemurs-x
tar -xJf /tmp/lemurs.tar.xz -C /tmp/lemurs-x --strip-components=1

install -m 0755 /tmp/lemurs-x/lemurs /usr/bin/lemurs
install -m 0644 /tmp/lemurs-x/extra/lemurs.service /usr/lib/systemd/system/lemurs.service
install -m 0644 /tmp/lemurs-x/extra/lemurs.pam /etc/pam.d/lemurs

echo ">>> lemurs installed"
