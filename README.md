# Doors

```bash
cosign verify --key cosign.pub ghcr.io/mheci/doors:latest
sudo bootc switch ghcr.io/mheci/doors:latest
sudo systemctl reboot
```

```bash
cosign verify --key cosign.pub ghcr.io/mheci/doors-kinoite:latest
sudo bootc switch ghcr.io/mheci/doors-kinoite:latest
sudo systemctl reboot
```

```bash
bootc status
sudo bootc rollback
sudo systemctl reboot
```

```bash
sudo doors-secureboot enroll
doors-secureboot status
doors-secureboot verify
```
