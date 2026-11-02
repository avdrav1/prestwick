# Art spec: edge cue

## Purpose

Rises that face away from the camera (toward x - 1 or y - 1) have no visible riser, so
without a cue their tops look level and the slope is invisible (D5, finding 3). The edge cue
is a lip line along the higher tile's back edge, so every step on the course can be counted
from the fixed camera (pillar 2). Built in E1-S10.

## Look

A "lip": a dark shadow line just outside the higher top, on the lower tile's side of the
edge, then a bright highlight line just inside it. One lip means a rise of one step. Two
lips, the second 2 px further in, mean a rise of two or more steps.

Colorblind rule: the step class is told by the number of lines, not by color. On dark
ground (rough, fairway, tee) it reads as one or two bright lines; on light ground (green,
sand) as one or two dark lines. It holds in a grayscale screenshot
(`docs/decisions/e1-s10-steps-1x-gray.png`).

## Sheet

- File: `art/tiles/edges_<state>.png`. Placeholder: `art/tiles/edges_placeholder.png`.
- One row of 8 frames, each 64x32, no padding, 1 px transparent gutter. Sheet is 519x32.
- Frame names: `l` is the back-left edge (screen upper-left, toward x - 1), `r` the
  back-right edge (screen upper-right, toward y - 1). The digit is the rise: 1, or 2 for two
  steps or more.

| # | Frame | Back-left | Back-right |
| --- | --- | --- | --- |
| 0 | `l1` | one lip | none |
| 1 | `l2` | two lips | none |
| 2 | `r1` | none | one lip |
| 3 | `r2` | none | two lips |
| 4 | `l1r1` | one lip | one lip |
| 5 | `l1r2` | one lip | two lips |
| 6 | `l2r1` | two lips | one lip |
| 7 | `l2r2` | two lips | two lips |

- Bands, measured straight down from the edge line (2 px each, so they survive nearest
  sampling at 0.5x): `ink` at -2 to 0 (outside the top), `chalk` at 0 to 2; for two lips
  also `ink` at 2 to 4 and `chalk` at 4 to 6. Bands follow the edge's whole line, so the
  lines of neighbouring tiles along one edge join without a gap.
- The front half of the frame stays transparent.

## Anchor

(32, 18), not (32, 16): the top diamond sits 2 px lower in the frame than in a surface
frame, so the shadow has room above the top corner. `CourseView` shifts the cue layers up
by `anchor.y - 16` and moves their sort origin down as much, so the sort key is unchanged.
A cue at height h sorts with that tile's top (`Iso.top_sort_key`) and wins the tie by tree
order, so it draws over its own top and under any object on the tile.

## When it shows

`CourseView.edge_cue_frame(course, x, y)`: a tile higher than its back neighbour draws a cue
on that edge. Level or higher neighbours draw none (a higher back neighbour's riser already
shows the step), and neither does the map border.

## Code that reads it

- `art/tiles/surfaces.tres` (`TileArt`), field `edges` (`TileSheet`).
- `course/course_view.gd`: `EDGE_SOURCE`, `edge_layer(h)`, `edge_cue_frame`.
- `tests/test_tile_art.gd` counts the lips per frame by luminance; `tests/test_course_view.gd`
  checks when the cue shows and that `refresh_cell` updates it.

## For the artist replacing it

- Keep `edges_<state>.png`, 8 frames, 64x32, 1 px gutter, anchor (32, 18), the order above.
- Keep the count rule: one mark for one step, two for more, readable in grayscale.
  A grass lip, a softer shadow or dashes are fine if the count still reads at 0.5x.
- Only colors from `art/palette.gpl`. Regenerate with `python3 scripts/placeholder.py edges`.
