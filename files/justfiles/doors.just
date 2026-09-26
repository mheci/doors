# Doors-native AI/development and Secure Boot convenience recipes.
# Under Universal Blue bases these are available through `ujust`.

# Open a shell with the native Doors development and AI tools on PATH.
doors-ai-shell:
    doors-ai shell

# Run one native command. Example: ujust doors-ai-run nvcc --version
doors-ai-run +ARGS:
    doors-ai run /usr/bin/bash -lc {{ quote(ARGS) }}

# Display the native toolchain paths and installed mise-managed agent CLIs.
doors-ai-status:
    doors-ai status

# Install every agent CLI declared in /etc/mise/config.toml for this account.
doors-ai-install:
    doors-ai install

# Upgrade OpenCode, Pi, Codex, and Herdr in place. No reboot or rebase.
doors-ai-upgrade:
    doors-ai upgrade

# Queue the tracked Doors MOK for owner-approved enrollment at the next reboot.
doors-secureboot-enroll:
    doors-secureboot enroll

# Show Secure Boot state and whether the tracked Doors MOK is enrolled.
doors-secureboot-status:
    doors-secureboot status

# Show the active Doors DNS policy and resolver/service state.
dns-status:
    doors-dns status

# Select a reviewed DNS policy. MODE is one of: resolved-quad9,
# resolved-cloudflare, unbound-quad9, unbound-cloudflare, or
# systemd-resolved-compat. Strict modes reject DHCP/VPN DNS bypasses.
dns-selector MODE:
    run0 doors-dns select {{ quote(MODE) }}

# Inspect the current immutable deployment before staging a desktop image switch.
doors-image-status:
    doors-image status

# Stage one fixed Doors desktop target (gnome or kinoite). This keeps a
# rollback deployment and does not reboot. The helper asks for confirmation.
doors-image-switch TARGET:
    run0 doors-image switch {{ quote(TARGET) }}

# Install or repair Hermes Agent (CLI + desktop app) for this account now.
doors-hermes-install:
    systemctl --user start doors-hermes-install.service && journalctl --user -u doors-hermes-install.service -n 20 --no-pager

# Show the image recipe working copy, open agent PRs, and recent builds.
doors-recipe-status:
    doors-recipe status

# Declare RPMs in the image recipe and open an auto-merging PR. Example:
# ujust doors-recipe-add-rpm htop tmux
doors-recipe-add-rpm +PKGS:
    doors-recipe add rpm {{ PKGS }} && doors-recipe ship

# Back up and reset only allowlisted desktop shell/theme settings for all
# regular local users. The helper asks for typed confirmation.
doors-desktop-cleanup:
    run0 doors-desktop-cleanup --all-users

# Inspect the exact current-root LUKS2 and crypttab enrollment state.
doors-luks-status:
    run0 doors-luks-enroll status

# Safely enroll the current-root LUKS2 volume with TPM2 PCR 7 plus PIN.
# A verified existing password slot is retained and no reboot is performed.
doors-luks-tpm2-pin:
    run0 doors-luks-enroll tpm2-pin

# Safely enroll the current-root LUKS2 volume with a FIDO2 key requiring a
# client PIN and user-presence touch. A password fallback remains intact.
doors-luks-fido2:
    run0 doors-luks-enroll fido2
