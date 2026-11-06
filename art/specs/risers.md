# Art spec: risers

> Status (E3-S58, D50): not drawn. The course view draws the ground as a smooth mesh over the
> bilinear surface the ball rolls on (`course/terrain_mesh.gd`), so a rise is a slope and no
> risers are drawn; the map's two front edges and water banks are plain side faces in
> `side_color` (`course/terrain_tuning.tres`), lit by their facing. The riser sheets
> (`risers_placeholder.png`, `risers_play_placeholder.png`) are unused by the game and kept
> only for `art/tiles/tile_preview.tscn`; final art (E5) needs no riser frames. The rest of this
> spec is the terrace design D5 chose and D50 replaced.

## Purpose

The side walls that show height. One frame is one height step (16 px). A tile at height h
stands on h stacked riser steps, so hills read as terraces and the player can count steps
at a glance, which shot physics depends on (pillar 2).

## Look

Warm earth, left face in shade and right face in light, with faint strata so steps can be
counted. Clear and blocky, like Mean 18's terrain edges; no grass overhang yet.

## Sheet

- File: `art/tiles/risers_<state>.png`. Placeholder: `art/tiles/risers_placeholder.png`,
  and its label-free Play copy `art/tiles/risers_play_placeholder.png` (E3-S55, the same
  frames without the labels; `play_texture` in `surfaces.tres`).
- One row of 3 frames, each 64x32, no padding, 1 px transparent gutter. Sheet is 194x32.

| # | Frame | Contents | Label |
| --- | --- | --- | --- |
| 0 | `both` | left and right face, light front corner | RB |
| 1 | `left` | left (south-west) face only | RL |
| 2 | `right` | right (south-east) face only | RR |

- Shape: the V-shaped band between the bottom edges of a diamond and the same edges 16 px
  higher. It is exactly what a diamond sweeps rising one step, minus the raised diamond, so
  it fills the gap between two tops with no overlap and no hole. Each face owns its corner
  column (column 0 for the left face, 63 for the right, rows 0 to 15) even though no top
  diamond does: walls repeat every 32 px, so without it a 1 px seam shows between them.
- Left face `earth_dark` with `ink` strata, right face `earth` with `earth_dark` strata,
  strata every 6 px parallel to the top edge, `ink` foot line, `earth_light` front corner.

## Anchor

A riser frame for step k (the wall between height k and k + 1) uses the same 64x32 box and
the same anchor, (32, 16), as a surface tile at height k. Draw order for one tile: risers for
k = 0 .. h - 1, bottom up, then the surface at h; tiles back to front by i + j.
`left` and `right` let the renderer skip a face hidden by a neighbor at equal or greater
height; `both` is the common case.

## Code that reads it

- `art/tiles/surfaces.tres` (`TileArt`), field `risers` (`TileSheet`), and `riser_px` (16).
- `TileArt.load_default().riser_texture(&"left")`.
- The course renderer (E1-S4). `art/tiles/tile_preview.tscn` draws a stepped hill with them.
- `tests/test_tile_art.gd` checks the band shape and the left/right split.

## For the artist replacing it

- Keep `risers_<state>.png`, 3 frames, 64x32, 1 px gutter, order `both`, `left`, `right`.
- Keep the band shape exactly; anything outside it is hidden by or overlaps the tile above.
- Optional later frames (append, do not reorder): a grass lip under the top step, a water
  edge for tiles next to water. Rises that face away from the camera have no riser; their
  lip line is its own sheet, `art/specs/edge_cue.md` (E1-S10). There are no ramp frames:
  D5 dropped ramp tiles.
- Only colors from `art/palette.gpl`. Drop the labels, and leave `play_texture` unset for the
  risers in `surfaces.tres` (delete the play placeholder): Play draws the one sheet then.
- Regenerate the placeholder with `python3 scripts/placeholder.py risers`.
