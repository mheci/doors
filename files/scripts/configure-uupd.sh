#!/usr/bin/env bash
# Make uupd the single automatic updater. It stages bootc deployments and
# updates Flatpaks/Distroboxes; BlueBuild's parallel update timers are disabled.
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
      "disable": false
    },
    "flatpak": {
      "disable": false
    },
    "system": {
      "disable": false
    }
  }
}
JSON
