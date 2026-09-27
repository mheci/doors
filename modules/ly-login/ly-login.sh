#!/usr/bin/env bash
# ly is the display manager for the tiling images. The packaged session file
# starts an unconfigured compositor, so replace it after the package install.
set -euo pipefail

fail() {
  printf 'Doors ly-login: %s\n' "$*" >&2
  exit 1
}

# BlueBuild passes the recipe entry as a JSON string, not a file path.
[[ -n "${1:-}" ]] || fail 'module config was not passed'
command -v jq >/dev/null 2>&1 || fail 'jq is required'

compositor="$(printf '%s' "$1" | jq -r 'try .["compositor"] // empty')"
case "${compositor}" in
  hyprland|sway) ;;
  *) fail "compositor must be hyprland or sway, got '${compositor}'" ;;
esac

[[ -f /usr/lib/systemd/system/ly.service ]] || fail 'ly.service is not installed'
systemctl enable ly.service
systemctl set-default graphical.target

for unit in gdm.service sddm.service lightdm.service; do
  if [[ -e "/usr/lib/systemd/system/${unit}" ]]; then
    systemctl disable "${unit}" || true
    systemctl mask "${unit}"
  fi
done

session_src="/usr/share/doors/${compositor}/session.desktop"
[[ -f "${session_src}" ]] || fail "missing ${session_src}"
install -D -m 0644 "${session_src}" "/usr/share/wayland-sessions/${compositor}.desktop"

if [[ "${compositor}" == hyprland ]]; then
  find /usr/share/wayland-sessions -name 'hyprland*.desktop' ! -name 'hyprland.desktop' -delete
  [[ -x /usr/bin/Hyprland || -x /usr/bin/hyprland ]] || fail 'Hyprland binary is missing'
  command -v qs >/dev/null 2>&1 || fail 'quickshell (qs) is missing'
  [[ -f /usr/share/doors/hyprland/hypr/hyprland.lua ]] || fail 'hyprland.lua is missing'
  [[ -f /usr/share/doors/hyprland/quickshell/shell.qml ]] || fail 'quickshell config is missing'
  rpm -q hyprland >/dev/null 2>&1 || fail 'hyprland package is missing'
else
  find /usr/share/wayland-sessions -name 'sway*.desktop' ! -name 'sway.desktop' -delete
  [[ -x /usr/bin/sway ]] || fail 'sway binary is missing'
  command -v waybar >/dev/null 2>&1 || fail 'waybar is missing'
  [[ -f /usr/share/doors/sway/config ]] || fail 'sway config is missing'
  rpm -q sway >/dev/null 2>&1 || fail 'sway package is missing'
fi

[[ -x "/usr/libexec/doors/doors-${compositor}-session" ]] || fail "session wrapper is not executable"
printf 'Doors ly-login: %s session installed and ly enabled.\n' "${compositor}"
