#!/usr/bin/env bash
# Install a pinned opencode build system-wide to /usr/local/bin.
# Version is Renovate-managed (renovate.json).
set -euo pipefail

VERSION="${OPENCODE_VERSION:-1.18.30}"

echo ">>> installing opencode ${VERSION}"
curl -fsSL "https://github.com/sst/opencode/releases/download/v${VERSION}/opencode-linux-x64.tar.gz" \
  -o /tmp/opencode.tar.gz
mkdir -p /tmp/opencode-x
tar -xzf /tmp/opencode.tar.gz -C /tmp/opencode-x
install -m 0755 /tmp/opencode-x/opencode /usr/local/bin/opencode
echo ">>> opencode installed to /usr/local/bin/opencode"
