# Doors — ujust recipes
# `just` / `ujust` with no args lists this file.
alias u := update

# Weekly check for image updates (manual apply by design — decision U1)
update:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v bootc >/dev/null 2>&1 || { echo "bootc not found"; exit 1; }
    echo "Checking for updates (nothing is applied automatically)..."
    bootc status
    bootc upgrade --check

# Apply a checked update manually
upgrade:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo bootc upgrade

# Display Doors branding / about
about:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Doors — a gaming-tuned Fedora Atomic desktop"
    echo "  kernel : $(uname -r)"
    echo "  shell  : $SHELL"
    echo "  desktop: ${DESKTOP_SESSION:-unknown}"
    if command -v scxctl >/dev/null 2>&1; then echo "  sched  : $(scxctl status 2>/dev/null | head -n1 || true)"; fi

# Rebuild initramfs (rarely needed)
initramfs:
    sudo dracut --force --regenerate-all

# Pin the current deployment (bootc)
pin:
    sudo bootc rollback --help >/dev/null 2>&1 || true
    echo "Use: sudo bootc status to inspect the current deployment"
