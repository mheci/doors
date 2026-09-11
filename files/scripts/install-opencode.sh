#!/usr/bin/env bash
# Install a pinned opencode build. Version is Renovate-managed (renovate.json).
set -euo pipefail

VERSION="${OPENCODE_VERSION:-1.18.30}"

echo ">>> installing opencode ${VERSION}"
curl -fsSL "https://opencode.ai/install" | bash -s -- --version "${VERSION}" --no-modify-path
