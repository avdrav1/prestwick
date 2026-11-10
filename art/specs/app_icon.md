# Art spec: app icon

> Status (E5-S1): spec only. `project.godot` sets no icon, so builds show Godot's.

## Purpose

The icon on the Linux and Windows builds (E5-S7) and the window: what a playtester clicks.

## Look

A pin and pennant (`flag_red`) on a green diamond tile (`green`, `green_dark` cross-hatch, the
game's own surface), `ink` outline: the game's two first readable things. Must read at 16 x 16.

## Sheet

- File: `art/ui/app_icon.png`, 256 x 256, one frame, plus hand-tuned `app_icon_32.png` and
  `app_icon_16.png` (small sizes are redrawn, not scaled). Placeholder:
  `art/ui/app_icon_placeholder.png`
  (`python3 scripts/placeholder.py app_icon --size 256x256 --frames 1 --folder ui --color fairway`).
- Palette colours only; transparent outside the tile.

## Code that reads it

`project.godot` `application/config/icon`, and the export presets' Windows icon (an .ico built
from the three sizes at `/ship-it`).
