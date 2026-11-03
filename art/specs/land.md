# Art spec: unowned land

## Purpose

Land the player has not bought cannot be built on (E6-S4) and is out of bounds in play (D29),
so it must read at a glance as "not yours", and the parcel grid must show where the next
purchase would go (D26, D27; pillar 2). Built in E6-S5.

## Look

Two things, so the colorblind rule holds (a pattern as well as a shade):

- A shade: `CourseView` draws every top, riser and edge cue of an unowned tile through an
  alternative tile modulated by `BuilderTuning.unowned_tint`, so the ground underneath keeps
  its own surface pattern, only darker.
- A pattern, this sheet: a screen-diagonal hatch over the top, 2 px of `ink` every 8 px, plus
  a 2 px dashed line just inside each edge of the top that lies on a parcel edge: `chalk`
  then `ink`, 8 px of screen x each (a survey-stake line). Where an unowned parcel meets
  owned land the line is the boundary; between two unowned parcels the lines of both sides
  meet into one parcel edge. The line reads as a fence in grayscale.
- The line is dashed, not solid, because a solid bright line just inside a back edge is the
  edge cue's lip (`art/specs/edge_cue.md`), one step of rise. The edge cue never alternates
  chalk and ink along an edge, so a boundary is not taken for a step, or a step for a
  boundary (pillar 2; the boundary is also the OB line, D29). The dash period (16 px) divides
  32, so the dashes of neighbouring tiles along a parcel edge join, and a dash is still 4 px
  at 0.5x.

The hatch period (8 px) divides 32 and 16, so the lines of neighbouring tiles, and of tiles
one or more steps higher, join into one pattern without seams.

## Sheet

- File: `art/tiles/land_<state>.png`. Placeholder: `art/tiles/land_placeholder.png`.
- One row of 16 frames, each 64x32, no padding, 1 px transparent gutter. Sheet is 1039x32.
- Frame index is a mask of the edges that carry a parcel line: bit 0 `w` the back-left edge
  (screen upper-left, toward x - 1), bit 1 `n` the back-right (upper-right, toward y - 1),
  bit 2 `e` the front-right (toward x + 1), bit 3 `s` the front-left (toward y + 1). Names
  are `hatch` then `_` and the letters in that order: `hatch`, `hatch_w`, `hatch_n`,
  `hatch_wn`, `hatch_e`, ... `hatch_wnes`.
- Everything outside the top diamond is transparent; between the hatch lines too.

## Anchor

(32, 16), as a surface top. `CourseView` puts the frame on a `Land<h>` layer per height at
the top's sort key (`Iso.top_sort_key`), added after the edge cue layers, so it draws over
its own top and cue and under any object on the tile, and a hill in front hides it.

## When it shows

`CourseView.land_frame(course, x, y)`: -1 on an owned tile, else the mask of the tile's
edges whose neighbour is in another parcel (the map border too). Main redraws a parcel's
tiles when the builder buys it or undoes the purchase (`CourseView.refresh_parcel`).

## Code that reads it

- `art/tiles/surfaces.tres` (`TileArt`), field `land` (`TileSheet`).
- `course/course_view.gd`: `LAND_SOURCE`, `land_layer(h)`, `land_frame`, `refresh_parcel`.
- `tests/test_tile_art.gd` checks the layout, the palette, the edge lines per frame, and that
  the parcel line's band is dashed where the edge cue's is solid;
  `tests/test_course_view.gd` checks when the overlay shows.

## For the artist replacing it

- Keep `land_<state>.png`, 16 frames in mask order, 64x32, 1 px gutter, anchor (32, 16).
- Keep a pattern that tiles on a period dividing 32 x 16 and an edge line that joins along a
  parcel edge; a fence, rope or survey-stake line is fine if it reads at 0.5x in grayscale.
  It must never be a solid bright line just inside the edge: that is the edge cue.
- Only colors from `art/palette.gpl`. Regenerate with `python3 scripts/placeholder.py land`.
