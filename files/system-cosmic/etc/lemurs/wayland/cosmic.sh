#!/bin/sh
# Doors — COSMIC session via lemurs
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=COSMIC
export XDG_SESSION_DESKTOP=COSMIC
exec cosmic-session
