# Art spec: golfer

## Purpose

The guests on the course (E3-S5; pillar 3: the course tells a story through its guests). One
golfer sprite set for every guest (design.md MVP: "one golfer sprite set"), dressed per group
in a shirt from a small set (E3-S28, "Shirts" below). It must read at 0.5x as a person
standing, walking or swinging, and which way they face, and which group it belongs to, so the
player can follow a group round a hole and see where a complaint came from.

## Look

SimGolf warmth, Mean 18 clarity: a small figure in a polo (drawn chalk, the shirt key; see
"Shirts") on an ink outline, slate_dark
trousers, skin head under a flag_red cap. The ink outline round the shirt and the
chalk or light trim in most shirts keep a guest readable on any surface (fairway, rough,
sand, green). The cap's brim
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

## Shirts (E3-S28)

Each group wears one shirt, and the groups of a day take the shirts in turn by arrival order
(`GolferArt.shirt_of_group`), so any six groups in a row differ. Groups never pass, so the
groups on one hole and the next (queued for a tee or playing it) are groups in a row, and they
all differ while no hole and its neighbour hold more than six. When play backs up they can
hold that many: on the nine-hole fixture (land seed 7) day seeds 1 to 10 put up to five groups
on one hole and six on two neighbouring holes (seeds 5 and 7), so four shirts met there (seed 5:
same-shirt groups on one hole for 21 simulated seconds, E3-S28 review) and the set is six
(`tests/test_guest_view.gd` plays seeds 5 and 7 and checks no two groups in one shirt share a
hole or stand on neighbouring holes). A day that backs up further repeats a shirt within reach. The sheets draw the shirt in one key colour, chalk, and
nowhere else (rows 9 to 16 of a frame, `shirt_rows`); `GuestView` puts a shader
(`art/sprites/golfer_shirt.gdshader`) on each figure that swaps every chalk pixel for the
group's shirt, so one sheet dresses every group. The set, in `art/sprites/golfer.tres`:

| # | Body | Trim | Pattern | Luma (body / trim) |
|---|------|------|---------|--------------------|
| 0 | chalk | - | plain | 236 |
| 1 | flag_red | chalk | hoops: trim on every odd sheet row | 105 / 236 |
| 2 | water_dark | chalk | yoke: trim on the rows above `yoke_row` 12 (the shoulders) | 74 / 236 |
| 3 | sun_yellow | - | plain | 196 |
| 4 | earth | - | plain | 101 |
| 5 | slate_light | water_dark | yoke | 169 / 74 |

Grayscale (colorblind rule: shape as well as colour): two shirts of one pattern differ by at
least `shirt_min_luma_step` 32 in Rec. 601 luma, and a patterned shirt's trim by as much from
its body, so plain light, striped, dark with light shoulders, plain mid-light, plain dark and
light with dark shoulders tell apart with no colour (`docs/decisions/e3-s28-shirts-gray.png`); the ink outline keeps every shirt
off the grass. Chalk and sun_yellow are the closest pair (40 apart). The cap stays flag_red
for everyone: the brim is the facing cue. Preview: `art/sprites/golfer_shirts_placeholder.png`
(`scripts/placeholder.py golfer`: the idle `s_0` frame in each shirt, in order; not loaded by
the game, checked against the .tres by `tests/test_guest_view.gd`).

Shader output (E3-S28 review): the GUT tests run headless and draw nothing, so they check the
rule, not the pixels. `scripts/shirt_render_check.gd` (`godot --path . -s
res://scripts/shirt_render_check.gd`, opens a window) renders the idle `s_0` frame in every
shirt through the shader and checks every pixel is the sheet's own (skin, cap, ink, club) or
the shirt's palette colour, within 1 of 255; run it after any change to the shader, the sheets
or the set. The shader multiplies the texture in once: in a `canvas_item` `fragment()` `COLOR`
already holds the texture sample, and multiplying by it again drew every pixel about texel
squared (skin #D37951 for #E8B090). The screenshots were sampled as well: skin, cap, ink and
every shirt body are exact palette values.

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
the swing so the top (frame 2) and the finish (frame 5) read at 0.5x. Draw the whole shirt in
flat chalk (240, 236, 224) and use chalk nowhere else in the frame: the shader recolours every
chalk pixel per group, so shading the shirt needs a second key colour and a shader change
(a story, not a repaint). Shirt colours and patterns are `shirt_body`, `shirt_trim` and
`shirt_pattern` in `art/sprites/golfer.tres`, palette colours only; keep
`scripts/placeholder.py`'s `GOLFER_SHIRTS` in step for the preview.
