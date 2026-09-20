#!/usr/bin/env bash
# Pi's official distribution channel is npm. The package has an npm shrinkwrap;
# npm verifies registry-provided Subresource Integrity data while downloading.
set -euo pipefail

readonly PACKAGE='@earendil-works/pi-coding-agent'
# Pin the delivery endpoint to the official npm registry rather than inheriting
# an arbitrary global npm configuration from a base layer.
export npm_config_registry='https://registry.npmjs.org/'
export npm_config_prefix='/usr/local'
export npm_config_cache='/tmp/npm-cache'
# The audited package needs no lifecycle installation hook. Refuse future hooks
# rather than executing new build-time code without an explicit review.
npm install --global --omit=dev --ignore-scripts "${PACKAGE}@latest"
/usr/local/bin/pi --version >/dev/null
npm cache clean --force >/dev/null 2>&1
rm -rf "${npm_config_cache}"
