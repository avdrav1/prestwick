# Art spec: trees

> Status (E5-S1): spec only. Today the trees surface (6) is a flat canopy pattern on the ground
> (`art/specs/surfaces.md`) with nothing standing on it, so the 10 yd block it puts on a shot
> cannot be seen (E2 review, E6-S2 note). E5-S3 draws these sprites over it.

## Purpose

Stand a tree on every trees tile so the player sees the obstacle at the height it blocks a
flight (pillar 2): the trees row's `block_height`, 10 yd, 5 height steps, 80 px at 1x. A tree
must read as taller than a guest (24 px) and say which tiles are blocked at 0.175x.

## Look

SimGolf warmth, Mean 18 clarity: a round broadleaf crown in `tree_dark`, `tree` and a lit
`rough` edge on the upper left (the ground's light comes from there, `terrain_tuning.tres`
`light_dir`), an `earth_dark` trunk, an `ink` outline on the crown's lower right only. Shape
does the work in grayscale: a crown on a trunk, not a green blob. No ground shadow in the sheet
(drawn in code like the golfer's, so the sheet stays opaque palette pixels).

## Sheet

- File: `art/sprites/trees_<state>.png`. Placeholder: `art/sprites/trees_placeholder.png`
  (`python3 scripts/placeholder.py trees --size 64x96 --frames 3 --folder sprites --color tree`).
- One row of 3 frames, 64 x 96 px each, 1 px gutter (194 x 96): `a`, `b`, `c`, three crowns of
  one species so a stand does not look stamped. The variant is picked per tile by a hash of its
  cell, so a course looks the same on every load.
- The tree is 80 px from foot to crown top at 1x; the frame leaves 16 px under the anchor for
  the trunk foot's half of the diamond.

## Anchor

(32, 88): the tile centre on the drawn ground (`HeightField.height_at`, D50), as the golfer and
clubhouse stand. Sorted at `Iso.object_sort_key` of its tile, with guests, markers and the
clubhouse.

## Code that reads it

None yet. E5-S3 adds a TileSheet in a `trees.tres` and a Y-sorted view under CourseView
(like `course/clubhouse_view.gd`). Below 0.5x the crowns may be culled to the ground pattern
if frame time needs it (`scripts/nine_holes_perf.gd`).

## For the artist replacing it

- Keep `trees_<state>.png`, 3 frames of 64 x 96, 1 px gutter, anchor (32, 88), crown top at
  y 8 (80 px above the anchor).
- Only colours from `art/palette.gpl`. Must read as a tree in a grayscale screenshot at 0.5x.
- The ground pattern under it (surfaces frame 6) stays: it is what 0.175x shows.
