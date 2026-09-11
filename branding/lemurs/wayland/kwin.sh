#!/bin/sh
# Doors — KDE Plasma (kwin_wayland) session via lemurs
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_DESKTOP=KDE
exec dbus-run-session startplasma-wayland
