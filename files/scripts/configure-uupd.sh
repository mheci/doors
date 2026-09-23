#!/usr/bin/env bash
# Keep uupd as the reviewed immutable-host update engine. Doors' own timer
# serializes every host and per-user adapter, so uupd must not independently
# update Flatpaks, Distroboxes, or Homebrew for only active logind users.
set -euo pipefail

install -d -m 0755 /etc/uupd
cat > /etc/uupd/config.json <<'JSON'
{
  "checks": {
    "hardware": {
      "enable": true,
      "bat-min-percent": 20,
      "cpu-max-percent": 50,
      "mem-max-percent": 90,
      "net-max-bytes": 700000
    }
  },
  "modules": {
    "brew": {
      "disable": true
    },
    "distrobox": {
      "disable": true
    },
    "flatpak": {
      "disable": true
    },
    "system": {
      "disable": false
    }
  }
}
JSON
