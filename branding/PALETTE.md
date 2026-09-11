# Doors — branding kit

"Thresholds." Quiet surfaces, one warm accent, a single door glyph.

## Palette (source: user-provided coolors palette, derived into a dark gaming theme)

| Token     | Hex       | RGB           | Hyprland rgba | Role                              |
|-----------|-----------|---------------|---------------|-----------------------------------|
| base      | `#171216` | 23 18 22      | `0xff171216`  | window / terminal background      |
| surface   | `#1f171b` | 31 23 27      | `0xff1f171b`  | panels, cards                     |
| surface+  | `#2a2026` | 42 32 38      | `0xff2a2026`  | overlays, popups, hover surfaces  |
| border    | `#3a2d33` | 58 45 51      | `0xff3a2d33`  | hairlines, inactive borders       |
| text      | `#f2ecea` | 242 236 234   | `0xfff2ecea`  | primary text                      |
| muted     | `#b9a9ac` | 185 169 172   | `0xffb9a9ac`  | secondary text                    |
| rose      | `#f4acb7` | 244 172 183   | `0xfff4acb7`  | **accent** — focus, selection     |
| blush     | `#ffcad4` | 255 202 212   | `0xffffcad4`  | hover, subtle highlight           |
| peach     | `#ffe5d9` | 255 229 217   | `0xffffe5d9`  | warm secondary (warnings)         |
| sage      | `#d8e2dc` | 216 226 220   | `0xffd8e2dc`  | cool tertiary (success)           |

## Mark

A door glyph: rounded frame, panel ajar, rose light spilling through the gap and
pooling at the threshold. Same glyph on all six images. No text in the mark.

Files:
- `logo.svg` — 512px mark (transparent tile optional via the tile rect)
- `wallpaper.svg` — 3840x2160 default wallpaper (gradient + glyph)

## Type

- UI: Inter
- Mono: JetBrains Mono

## Identity strings

```
ID=doors
NAME=Doors
PRETTY_NAME=Doors (Kinoite | Hyprland | Cosmic)
polkit vendor = Doors
MOK cert CN (v2) = Doors Secure Boot
```

## Surfaces

| Desktop | Files |
|---|---|
| Hyprland | `hyprland/doors-colors.conf` |
| KDE Plasma | `kde/doors.colors`, `kde/plasmalogin-doors.conf` |
| COSMIC | `cosmic/README.md` (accent = rose `#f4acb7`) |
| GTK 3/4 | `gtk/doors-gtk.css`, `gtk/doors.gschema.override` |
| lemurs (login, all images) | `lemurs/config.toml`, `lemurs/wayland/*` |
