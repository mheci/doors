# Implementation notes

## Current implementation

- The recipes target BlueBuild Fedora NVIDIA Open `:44` bases and Fedora 44 disposable build stages.
- Fedora-specific repository files use literal Fedora 44 endpoints. Brave remains a constrained vendor-generic repository because it has no Fedora-versioned endpoint. Steam uses BlueBuild’s Fedora 44 Negativo17 multilib route, which matches the base codec stack; RPM Fusion is not mixed with it.
- `uupd` is installed through a restricted UBlue packages COPR file with a vendored RPM key; `configure-uupd.sh` enables only system staging and disables Homebrew/Flatpak modules.
- The systemd module enables `doors-update.timer` and `doors-flatpak-bootstrap.service`; it disables BlueBuild’s duplicate bootc and Flatpak timers.
- The owned Flatpak bootstrap uses the reviewed static Flathub descriptor and installs only Bazaar and Gear Lever.
- Native tooling is layered into every image: Fedora supplies Node/npm/pnpm, Python/pip and build tools; Terra supplies Bun, Deno, mise, OpenCode CLI, and Pi; the original native `t3` CLI is installed from a tracked integrity-locked npm input with lifecycle scripts disabled; NVIDIA's key-validated Fedora 44 route supplies `cuda-toolkit-13-4` while excluding driver replacements.
- The Herdr binary remains a CI-generated, immutable-release-attestation-verified input. `install-native-ai.sh` rechecks its manifest/digest and installs it as a host command only after all native RPM checks succeed.

## Local validation limitation

This sandbox has no Docker, Podman, Buildah, or bootc engine. A local BlueBuild compose cannot be executed here; the protected GitHub PR `image` job remains the required real compose gate. The static repository validator, shell syntax checks, YAML parse, actionlint, ShellCheck, offline Zizmor audit, and Gitleaks are run locally before proposing the PR.

## Outstanding physical gates

CI cannot validate MOK enrollment, NVIDIA/Wayland, suspend/resume, games, browser acceleration, `uupd` runtime behavior, native CUDA device compilation/execution, Flatpak first boot, or rollback. Follow `docs/TEST-PLAN.md` before declaring the image ready.
