# Doors — gaming
alias g := gamescope

# Launch Steam through gamescope (HDR-ready)
gamescope:
    gamescope --hdr-enabled --fullscreen -- steam

# Run Heroic (Epic/GOG/Amazon)
heroic:
    heroic

# Flatpak management helpers
flatsetup:
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Show GPU info (varies by backend)
gpu:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi
    elif command -v rocminfo >/dev/null 2>&1; then rocminfo | head -n 40
    else lspci | grep -Ei 'vga|3d|display'; fi
