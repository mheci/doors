# Doors

**Doors** is one public, signed [Bluefin](https://projectbluefin.io/) GNOME/GDM bootc image:

```text
ghcr.io/mheci/doors:latest
```

It is built from the generic `ghcr.io/ublue-os/bluefin:latest` base every **Monday at 00:00 UTC** and is designed for Turing-or-newer NVIDIA hardware. It has one AMD64 image, no ISO pipeline, no alternate desktop/session, and no variant matrix.

> [!WARNING]
> This image has not yet passed the mandatory physical NVIDIA/Wayland validation in [`docs/TEST-PLAN.md`](docs/TEST-PLAN.md). Do not treat a successful container build as proof of suspend, gaming, browser media, GPU, or clipboard correctness.

## Installation and verification

The release workflow signs the image with the repository Cosign public key and also publishes GitHub OIDC provenance and SBOM attestations.

```bash
# Verify the maintained key signature before rebasing.
cosign verify --key cosign.pub ghcr.io/mheci/doors:latest

# Inspect GitHub OIDC attestations (requires a recent GitHub CLI).
gh attestation verify oci://ghcr.io/mheci/doors:latest --owner mheci

# Switch an existing bootc system. This stages the image; reboot when ready.
sudo bootc switch ghcr.io/mheci/doors:latest
sudo systemctl reboot
```

For rpm-ostree systems, use the appropriate `rpm-ostree rebase` flow only after reviewing the target system’s migration guidance.

## What is included

- **Official NVIDIA path:** BlueBuild `akmods` (`base: main`, `nvidia-open`) with the stock Bluefin/Fedora kernel—no custom kernel, NVIDIA `.run`, custom kmods, or CUDA toolkit.
- **Gaming:** Steam, Heroic, Faugus, ProtonPlus, umu-launcher, Gamescope, and Vesktop.
- **Performance:** Falcond, Ananicy-cpp with CachyOS rules, and `scx_loader` set to `scx_lavd` / `LowLatency`. GameMode is deliberately excluded because it conflicts with Falcond.
- **Browsers:** Brave Origin stable, Zen, and Helium. Firefox and ordinary Brave are absent.
- **Development:** Deno, Bun, pnpm, mise, Herdr, Pi, t3code, OpenCode, Zed, Ghostty, Kitty, Neovim, and a practical CLI/Wayland tool set. CUDA, llama.cpp, Hermes, and Playwright are not included.
- **GNOME:** Yaru dark; Inter and JetBrains Mono defaults; a compact fixed left dock; the requested GNOME extensions; Vicinae at login on <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>Space</kbd>; uinput paste support; and regular-clipboard persistence.
- **Flatpak:** Flathub remains available. Only Bazaar is declared for automatic system provisioning, together with exactly its required runtime dependencies.

The complete, reviewed package/service/source list is [`audit/FINAL-PACKAGE-MANIFEST.md`](audit/FINAL-PACKAGE-MANIFEST.md) in this workspace audit record.

## Updates

Bluefin’s `uupd.timer` is enabled. It stages image updates in the background; it does **not** force a restart. Reboot manually when you want the staged deployment to become active:

```bash
bootc status
sudo systemctl reboot
```

User-local updater behavior is left available where upstream tools support it. Image-provided RPMs and declared external artifacts refresh only through a successful signed image rebuild.

## Build and release controls

- `main` is intended to be protected by PR + required checks, no force-push/deletion, and no direct production publication. Apply the one-time repository settings in [`docs/RELEASE-SECURITY.md`](docs/RELEASE-SECURITY.md).
- Only trusted `main`, scheduled, or manual-`main` runs can read `SIGNING_SECRET` and publish. Pull requests receive a no-push build with a throwaway signing key.
- Each production build verifies Herdr’s GitHub release attestation, verifies Bun’s signed checksum, uses signed RPM repositories, emits an SPDX SBOM, and attaches OIDC provenance/SBOM attestations to the immutable image digest.
- Renovate is deliberately conservative: it opens updates, but the current auto-merge allowlist is empty because every present dependency is a workflow, build-chain, key, or major-policy dependency requiring review.
- If current upstream Bluefin and official NVIDIA akmods artifacts are briefly ABI-misaligned, the scheduled build fails closed and retries next Monday without moving `latest` or requiring a manual workaround. See [`docs/UPSTREAM-COMPATIBILITY.md`](docs/UPSTREAM-COMPATIBILITY.md).

See [`docs/TRUST-MODEL.md`](docs/TRUST-MODEL.md) and [`docs/IMAGE-CONTRACT.md`](docs/IMAGE-CONTRACT.md) for the exact boundary and [`docs/TEST-PLAN.md`](docs/TEST-PLAN.md) for release gates.

## Local validation

```bash
./scripts/validate-repository.sh
# Requires BlueBuild plus the CI-generated Herdr input for a complete local build:
# GH_TOKEN=... ./.github/scripts/prepare-herdr.sh
# bluebuild build recipes/doors.yml
```

The generated Herdr input is intentionally ignored and must never be committed.

## License

[Apache-2.0](LICENSE). Individual packages, GNOME extensions, and upstream projects retain their own licenses.
