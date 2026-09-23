# Implementation notes

## Current implementation

- The recipe targets BlueBuild Fedora Silverblue NVIDIA Open `:44` and a Fedora 44 disposable build stage.
- Fedora-specific repository files use literal Fedora 44 endpoints. Brave remains a constrained vendor-generic repository because it has no Fedora-versioned endpoint. Steam uses BlueBuild’s Fedora 44 Negativo17 multilib route, which matches the base codec stack; RPM Fusion is not mixed with it.
- `uupd` is installed through a restricted UBlue packages COPR file with a vendored RPM key; `configure-uupd.sh` enables system/Flatpak/Distrobox modules and disables Homebrew.
- The systemd module enables `uupd.timer`, `doors-flatpak-bootstrap.service`, and the generic user `doors-distrobox.service`; it disables BlueBuild’s duplicate bootc and Flatpak timers.
- The owned Flatpak bootstrap uses the reviewed static Flathub descriptor and installs only Bazaar and DistroShelf.
- AI tooling was removed from host layering. `doors-ai.ini` declares a rootless Arch Linux Distrobox with NVIDIA integration, init/systemd support, and start-now behavior. Its read-only bootstrap refreshes signed official Arch repositories, installs the CUDA toolkit without driver packages, verifies Bun/Pi/Herdr delivery, and creates a success marker only at completion.
- The Herdr binary remains a CI-generated, immutable-release-attestation-verified input but is copied only into the Distrobox bootstrap payload; it is not installed as a host command.

## Local validation limitation

This sandbox has no Docker, Podman, Buildah, or bootc engine. A local BlueBuild compose cannot be executed here; the protected GitHub PR `image` job remains the required real compose gate. The static repository validator, shell syntax checks, YAML parse, actionlint, ShellCheck, offline Zizmor audit, and Gitleaks are run locally before proposing the PR.

## Outstanding physical gates

CI cannot validate MOK enrollment, NVIDIA/Wayland, suspend/resume, games, browser acceleration, uupd runtime behavior, Distrobox GPU passthrough, CUDA compilation, Flatpak first boot, or rollback. Follow `docs/TEST-PLAN.md` before declaring the image ready.
