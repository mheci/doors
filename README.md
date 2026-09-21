# Doors

## Rebase

Complete the BlueBuild Secure Boot MOK enrollment first when Secure Boot is enabled: <https://github.com/blue-build/base-images#migration-from-ublue-base-images>.

```bash
cosign verify --key cosign.pub ghcr.io/mheci/doors:latest
gh attestation verify oci://ghcr.io/mheci/doors:latest --owner mheci
sudo bootc switch ghcr.io/mheci/doors:latest
sudo systemctl reboot
```

Doors is pinned to the BlueBuild Fedora Silverblue NVIDIA Open **44** base. Firefox and ordinary Brave are removed; Brave Origin, Zen, and Helium remain.

## After the first login

Bazaar and DistroShelf are provisioned as system Flatpaks when the network is available. The GPU-aware Fedora 44 AI Distrobox initializes automatically; use it directly when needed:

```bash
doors-ai shell
doors-ai run nvcc --version
doors-ai run pi --version
```

`uupd.timer` coordinates bootc, Flatpak, and Distrobox updates. Check deployments or recover manually:

```bash
bootc status
sudo bootc rollback
sudo systemctl reboot
```
