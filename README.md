# Doors

Doors is a signed, bootable Fedora Silverblue 44 image for `linux/amd64` systems with a Turing-or-newer NVIDIA GPU. It is based on BlueBuild's Fedora Silverblue NVIDIA Open image and is published at [`ghcr.io/mheci/doors`](https://github.com/mheci/doors/pkgs/container/doors).

## Image profile

- GNOME and GDM with the upstream NVIDIA Open driver stack.
- Steam, Gamescope, Heroic, ProtonPlus, umu-launcher, Vesktop, Falcond, scx, and GNOME integration.
- Brave Origin, Zen, and Helium. Firefox and ordinary Brave are not included.
- Bazaar and DistroShelf as system Flatpaks.
- `doors-ai`: a GPU-aware Fedora 44 Distrobox containing CUDA and AI/development tooling. Those tools are not layered onto the immutable host.
- `uupd.timer` coordinates bootc, Flatpak, and Distrobox updates.

## Rebase

When Secure Boot is enabled, complete BlueBuild's [MOK enrollment procedure](https://github.com/blue-build/base-images#migration-from-ublue-base-images) before switching deployments.

Run the verification commands from a checkout of this repository:

```bash
cosign verify --key cosign.pub ghcr.io/mheci/doors:latest
gh attestation verify oci://ghcr.io/mheci/doors:latest --owner mheci
sudo bootc switch ghcr.io/mheci/doors:latest
sudo systemctl reboot
```

After rebooting, confirm the active deployment:

```bash
bootc status
```

## First login

A networked boot provisions Bazaar and DistroShelf. The rootless AI Distrobox initializes with the user session. Check the system provisioning service or enter the container manually:

```bash
systemctl status doors-flatpak-bootstrap.service
doors-ai shell
doors-ai run nvcc --version
doors-ai run pi --version
```

## Updates and recovery

`uupd.timer` is enabled by default. Inspect deployments and roll back the previous booted deployment if needed:

```bash
bootc status
sudo bootc rollback
sudo systemctl reboot
```

See [the image contract](docs/IMAGE-CONTRACT.md) for the full composition and [the test plan](docs/TEST-PLAN.md) for hardware validation.
