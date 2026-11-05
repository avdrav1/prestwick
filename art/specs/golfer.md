# Art spec: golfer

## Purpose

The guests on the course (E3-S5; pillar 3: the course tells a story through its guests). One
golfer sprite set for every guest (design.md MVP: "one golfer sprite set"). It must read at
0.5x as a person standing, walking or swinging, and which way they face, so the player can
follow a group round a hole and see where a complaint came from.

## Look

SimGolf warmth, Mean 18 clarity: a small figure in a chalk polo on an ink outline, slate_dark
trousers, skin head under a flag_red cap. The chalk shirt is the brightest thing on any
surface (fairway, rough, sand, green), so a guest reads against all of them. The cap's brim
points where the golfer faces, and a guest facing away shows the back of the head
(earth_dark hair) and no eye, so the eight directions read in grayscale too (colorblind rule
for sprites: shape as well as colour). The club is slate_light. Colours from
`art/palette.gpl` only.

At 0.5x zoom the figure is drawn at twice its canvas size, so it stays 24 px on screen with
one texel a screen pixel (`figure_min_screen_scale` in `scenes/guest_view_tuning.tres`;
`docs/decisions/e3-s5-guests-0.5x.png`). A guest's ball is drawn at `ball_scale` 0.7 of the
player's ball, so the player's own ball is never mistaken for a guest's (shape, not colour).

No ground shadow in the sheet: `GuestView` draws a 2:1 ink ellipse under the feet in code,
as `ShotView` does for the ball, so the sheet keeps to fully opaque palette pixels.

## Sheets

Three PNGs, one per state, each one row: the 8 directions in the order below and, for each
direction, the state's frames in order. Every frame is 24 x 24 px (the golfer is 24 px tall,
art-spec constant), no padding, 1 px transparent gutter.

| State | File | Frames per direction | Sheet |
|-------|------|----------------------|-------|
| idle | `art/sprites/golfer_idle.png` | 2 (breathing: the head and shirt drop 1 px on frame 1) | 16 frames, 399 x 24 |
| walk | `art/sprites/golfer_walk.png` | 4 (stride: contact, pass, contact, pass) | 32 frames, 799 x 24 |
| swing | `art/sprites/golfer_swing.png` | 6 (address, takeaway, top, down, impact, finish) | 48 frames, 1199 x 24 |

Placeholders: `art/sprites/golfer_<state>_placeholder.png` (`scripts/placeholder.py golfer`),
each frame labelled with its direction in the top-left corner.

Directions are screen directions, clockwise from straight down the screen (toward the
camera): `s`, `sw`, `w`, `nw`, `n`, `ne`, `e`, `se`. Frame names are `<dir>_<n>`, `n` from 0:
`s_0`, `s_1`, `sw_0`, ... In grid terms (Iso: x = (i - j) × 32, y = (i + j) × 16) `se` is
along +i (x + 1), `sw` along +j (y + 1), `nw` along -i, `ne` along -j.

## Anchor

(12, 23): the middle of the feet, the frame's bottom row. It sits on the ground point
`HeightField.tile_top_screen` gives for where the guest stands (D17: on the top of the tile
under it, never at the bilinear height), and the sprite node sits at
`Iso.object_sort_key(tile, tile top)`, so it Y-sorts with the terrain like the ball and the
hole markers: over its own tile's top, under any tile, riser or object nearer the camera. A
hill in front hides a guest's feet or the whole guest.

## Timing (code, `scenes/guest_view_tuning.tres`)

- idle: `idle_fps` frames a real second, looping.
- walk: `walk_fps` frames a real second at 1x, times the sim speed, looping.
- swing: the 6 frames over the stroke's simulated second (`stroke_s`), so it plays at the
  sim's speed and freezes when paused.

## Which code reads it

`art/sprites/golfer.tres` (`GolferArt`, `art/sprites/golfer_art.gd`) holds the three sheets
as `TileSheet`s; `scenes/guest_view.gd` (`GuestView`) asks it for a frame by state,
direction and index (`GolferArt.frame`), never by pixel offset.

## For the artist

Replace the three placeholder PNGs with `golfer_idle.png`, `golfer_walk.png` and
`golfer_swing.png` at the same frame size (24 x 24), frame counts, order and anchor (12, 23),
then point the three `texture` entries in `art/sprites/golfer.tres` at them. Draw the club in
the swing so the top (frame 2) and the finish (frame 5) read at 0.5x. Variety between guests
(shirt colours) needs palette entries and is not in the MVP.
