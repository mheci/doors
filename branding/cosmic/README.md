# Doors — COSMIC theming

COSMIC reads its accent from `com.system76.CosmicSettings` and its dark-mode
preference from the settings daemon. The Doors defaults are applied with a
gschema override + a first-boot settings file:

```ini
# /etc/cosmic/settings.ron (or via cosmic-settings on first boot)
accent = "#f4acb7"
dark_mode = true
```

Doors tokens for any COSMIC theme components:

| Token | Hex |
|---|---|
| base | `#171216` |
| surface | `#1f171b` |
| surface+ | `#2a2026` |
| border | `#3a2d33` |
| text | `#f2ecea` |
| muted | `#b9a9ac` |
| accent (rose) | `#f4acb7` |
| success (sage) | `#d8e2dc` |
| warning (peach) | `#ffe5d9` |

The door glyph (`../logo.svg`) is used as the COSMIC greeter logo and default
wallpaper motif, same as the other desktops.
