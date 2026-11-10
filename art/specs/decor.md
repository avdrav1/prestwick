# Art spec: decor

> Status (E5-S3): final art, `python3 scripts/art_sprites.py decor` (D62). Placed with the Build
> bar's Decor tool, stored in the course (`CourseData.set_decor`, the optional `decor` field),
> drawn by `course/decor_view.gd`; `tests/test_decor.gd` shows it does nothing to the ball or the
> validator.

## Purpose

Things the player places to make the course a place (pillar 3) that do nothing to the ball,
the validator or guests' paths (E5-S3: `tests/test_decor.gd`). They must never be mistaken for
a hazard, a tee marker or a pin (pillar 2), so none is red and upright like the pin, and none is
a pair of blocks like a tee marker.

## Look

SimGolf warmth: small, friendly props at golfer scale (a bench is about half a golfer's
height). `earth`/`earth_light` wood, `slate` metal, `chalk` lettering, `ink` outline. Colours
from `art/palette.gpl` only.

## Sheet

- File: `art/sprites/decor.png`, loaded from `art/sprites/decor.tres`.
- One row of 4 frames, 48 x 48 px each, 1 px gutter (195 x 48):

| # | Frame | Contents |
| --- | --- | --- |
| 0 | `bench_x` | a wooden bench along the x axis |
| 1 | `bench_y` | the same along the y axis |
| 2 | `flag` | a course flag on a tall pole: `sun_yellow` cloth (never `flag_red`), square, not a pennant |
| 3 | `sign` | a hole sign board on two posts, `chalk` face with an `ink` frame |

## Anchor

(24, 40): the tile centre on the drawn ground, sorted at `Iso.object_sort_key` of its tile.

## Code that reads it

`course/decor_view.gd` (DecorView), `scenes/build_tool.gd` (Tool.DECOR: a click places the tool's
kind or steps the kind of the decor clicked; a right-click or R takes it away), `course/builder.gd`
(`set_decor`, `decor_refusal`: not on water, unowned land or the clubhouse; free; one undo step).

## Changing it

- Keep `decor_<state>.png`, 4 frames of 48 x 48, order above, anchor (24, 40). Append new
  frames; never reorder (course files will store the index).
