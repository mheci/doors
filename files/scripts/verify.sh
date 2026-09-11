#!/usr/bin/env bash
# prove-it-works: fail the build if Doors is not ready to ship.
set -euo pipefail

fail() { echo "VERIFY FAIL: $*" >&2; exit 1; }

echo ">>> Doors verify"

# 1. display manager is lemurs
[ -x /usr/bin/lemurs ] || fail "lemurs binary missing"
[ -f /etc/lemurs/config.toml ] || fail "lemurs config missing"

# 2. scheduler tooling present and loader wired
[ -x /usr/bin/scx_loader ] || fail "scx_loader missing"
[ -x /usr/bin/scxctl ] || fail "scxctl missing"
[ -f /etc/scx_loader/config.toml ] || fail "scx_loader config missing"

# 3. falcond present
[ -x /usr/bin/falcond ] || fail "falcond missing"
[ -f /etc/falcond/config.conf ] || fail "falcond config missing"

# 4. llama.cpp present and built for the right backend
[ -x /usr/bin/llama-server ] || fail "llama-server missing"
[ -x /usr/bin/llama-cli ] || fail "llama-cli missing"

# 5. AI agents present
[ -x /usr/local/bin/pi ] || fail "pi missing"
[ -x /usr/local/bin/opencode ] || fail "opencode missing"

# 6. gaming essentials
# steam is intentionally universal-only: Terra's nvidia-driver-libs carries an
# '(x86-32 = 610 if steam)' conditional while Terra's 32-bit tree is at 615,
# so steam cannot resolve on -nvidia until Terra finishes the 610→615 push.
if rpm -q nvidia-driver-libs >/dev/null 2>&1; then
  echo "nvidia image: steam intentionally excluded; checking NVIDIA stack instead"
  [ -x /usr/bin/nvidia-smi ] || fail "nvidia-smi missing"
  [ -e /usr/lib64/libcuda.so.1 ] || fail "libcuda missing (llama.cpp CUDA backend)"
else
  command -v steam >/dev/null || fail "steam missing"
fi
command -v gamescope >/dev/null || fail "gamescope missing"
command -v protonplus >/dev/null || fail "protonplus missing"
command -v umu-run >/dev/null || fail "umu-launcher missing"

# 7. brand + fonts shipped
[ -d /usr/share/wallpapers/doors ] || fail "doors wallpaper missing"
[ -d /usr/share/icons/doors ] || fail "doors icon missing"

echo ">>> Doors verify OK"
