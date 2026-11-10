# Art spec: HUD theme and icons

> Status (E5-S1): the HUD is Godot's default theme and font with panels coloured in code;
> the stars (`scenes/stars_view.gd`), reaction tags (`scenes/reaction_tags.gd`) and the
> off-screen cup pointer (`scenes/cup_pointer.gd`) are drawn in code; the Build palette's
> surface buttons use the surfaces sheet as icons. That is the placeholder.

## Purpose

One look for every panel and button in Build and Play (the toolbar must fit 1280 px, E5-S13),
icons for the Build tools that have only words today, and a font that stays legible at the
reaction tags' size.

## Look

SimGolf warmth: warm `chalk` text on `slate_dark` panels with an `ink` outline, rounded 2 px
corners, `sun_yellow` focus ring (keyboard focus must be visible, E5-S6). Colours from
`art/palette.gpl` only.

## Sheets

- `art/ui/theme.tres`: a Godot Theme whose StyleBoxTextures read `art/ui/panel.png`
  (9-slice 24 x 24, 6 px margins), `art/ui/button_<normal|hover|pressed|focus>.png` (9-slice
  24 x 24 each, 6 px margins).
- `art/ui/tool_icons.png`: one row of 16 x 16 icons, 1 px gutter, for the Build tools with no
  surface frame: `raise`, `lower`, `tee`, `cup`, `clubhouse`, `buy_land`, `undo`, `play`,
  `build` (9 frames, 152 x 16). Anchor: top-left (icons sit in buttons).
- `art/ui/stars.png`: 3 frames 14 x 14 (`empty`, `half`, `full`), replacing the drawn star.
- Font: a licensed pixel or humanist font at the sizes the HUD uses, its license in
  `art/ui/LICENSES.md`.

The reaction tags and the cup pointer stay drawn in code (their text and size change), using
the theme's font.

## Code that reads it

`scenes/main.tscn` (the theme on the HUD root), `scenes/build_palette.gd` (icons),
`scenes/stars_view.gd`.

## For the artist replacing it

- No placeholder PNGs: the default theme is the placeholder. Keep 9-slice margins as stated so
  buttons keep their 3 px side margins (`BuildPalette.BUTTON_SIDE_MARGIN`).
