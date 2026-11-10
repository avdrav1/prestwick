# Art spec: hole markers (tee markers, pin and cup)

> Status (E5-S1): drawn in code, `course/hole_marker.gd` (`HoleMarker`, E2-S2): the tee marker is
> two square blocks either side of the tile centre with the hole number beside one (chalk on
> ink, E3-S66), the pin a dark cup with a 30 px pole and a `flag_red` pennant. That drawing is
> the placeholder.

## Purpose

Say where each hole starts and ends at every zoom (pillar 1: a hole is playable once placed,
so its ends must show), and which tee is which with nine holes.

## Look

Mean 18 clarity: the pin is the tallest thin thing on a green and the only `flag_red` upright on
the course; tee markers are a pair of round blocks (SimGolf's coloured tee balls) in
`sun_yellow` on `ink`. Shape as well as colour: a pair of blocks versus a pole and pennant.

## Sheet

- File: `art/sprites/hole_markers_<state>.png`. No PNG placeholder: the code drawing stands in.
- One row of 5 frames, 1 px gutter:

| # | Frame | Size | Contents |
| --- | --- | --- | --- |
| 0 | `tee_block` | 8 x 8 | one tee block; the code draws two, either side of the tile centre |
| 1 | `cup` | 12 x 6 | the cup hole on the green, 2:1 |
| 2 | `pin_0` | 16 x 36 | pole and pennant, the pennant still |
| 3 | `pin_1` | 16 x 36 | pennant mid wave |
| 4 | `pin_2` | 16 x 36 | pennant full wave |

The hole number stays text drawn in code (it must stay sharp at every zoom).

## Anchor

`tee_block` (4, 6), `cup` (6, 3), `pin_*` (2, 34): the pole's foot in the cup centre on the
drawn ground. The reaction tags sit above the pole's top (`scenes/reaction_tags.gd`), so the
pole stays 30 px tall at 1x.

## Code that reads it

`course/hole_marker.gd` (`_draw`), `scenes/green_view.gd` (the overhead green inset draws its
own pin and cup; it keeps code drawing unless E5-S3 says otherwise).

## For the artist replacing it

- Keep the frame order, sizes and anchors. Palette colours only. The pin's pennant must not be
  confused with the decor `flag` (square, `sun_yellow`).
