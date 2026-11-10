# Art spec: trees

> Status (E5-S3): final art, `python3 scripts/art_sprites.py trees` (D62), drawn on every trees
> tile by `course/tree_view.gd`.

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

- File: `art/sprites/trees.png`, loaded from `art/sprites/trees.tres`.
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

`course/tree_view.gd` (TreeView, a Y-sorted child of CourseView): the trees of one depth row
and ground height share a node at `Iso.object_sort_key`, so a guest behind a tree is hidden by
its crown and one in front draws over it (`tests/test_sprites.gd`). Trees on unowned land take
`unowned_tint`. All trees draw at every zoom (none culled; the 0.175x course shot reads). Below 0.5x the crowns may be culled to the ground pattern
if frame time needs it (`scripts/nine_holes_perf.gd`).

## Changing it

- Keep `trees_<state>.png`, 3 frames of 64 x 96, 1 px gutter, anchor (32, 88), crown top at
  y 8 (80 px above the anchor).
- Only colours from `art/palette.gpl`. Must read as a tree in a grayscale screenshot at 0.5x.
- The ground pattern under it (surfaces frame 6) stays: it is what 0.175x shows.
