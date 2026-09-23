# Doors-managed Distrobox and Secure Boot convenience recipes.
# Under Universal Blue bases these are available through `ujust`.

# Create all missing Doors-declared Distroboxes without replacing existing ones.
doors-distrobox-bootstrap:
    doors-distrobox bootstrap

# Open the managed Arch AI tooling Distrobox.
doors-ai-shell:
    doors-ai shell

# Run one container-shell command safely. Example: ujust doors-ai-run nvcc --version
doors-ai-run +ARGS:
    doors-ai run /usr/bin/bash -lc {{ quote(ARGS) }}

# Export one container desktop application into the host launcher.
doors-ai-export-app APP:
    doors-ai export-app {{ quote(APP) }}

# Remove a previously exported container desktop application.
doors-ai-unexport-app APP:
    doors-ai unexport-app {{ quote(APP) }}

# Export one Doors AI command-line tool into ~/.local/bin on the host.
doors-ai-export-tool TOOL:
    doors-ai export-tool {{ quote(TOOL) }}

# Remove a previously exported Doors AI command-line tool.
doors-ai-unexport-tool TOOL:
    doors-ai unexport-tool {{ quote(TOOL) }}

# Export the standard Doors AI CLI set: Bun, Deno, Herdr, mise, nvcc, OpenCode, Pi, and T3 Code.
doors-ai-export-all:
    doors-ai export-all

# List app and binary wrappers currently exported from doors-ai.
doors-ai-list-exports:
    doors-ai list-exports

# Queue the tracked Doors MOK for owner-approved enrollment at the next reboot.
doors-secureboot-enroll:
    doors-secureboot enroll

# Show Secure Boot state and whether the tracked Doors MOK is enrolled.
doors-secureboot-status:
    doors-secureboot status
