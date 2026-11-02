# Art spec: surfaces

## Purpose

The top face of every terrain tile. The player reads the course from these: where the
fairway ends, where the bunker is, which tiles are out. They must be readable at 0.5x zoom
and without color (colorblind rule).

## Look

SimGolf warmth (soft, sunlit greens, sand that looks warm) with Mean 18 clarity (each
surface is a flat, unmistakable field; no texture noise that competes with the ball).

## Sheet

- File: `art/tiles/surfaces_<state>.png`. Placeholder: `art/tiles/surfaces_placeholder.png`.
- One row of 9 frames, each 64x32, no padding, 1 px transparent gutter. Sheet is 584x32.
- Frame order is the surface enum from `/course-file`, so frame index == surface value.
- Frame shape: the 2:1 diamond, pixel-center rasterized. Rows widen by 4 px per row,
  2 px wide at the top and bottom tips, 62 px at the middle rows. Corners are transparent.
- Each frame draws a 1 px darker line along its two bottom edges only, so two neighbors
  share one seam.
- Patterns repeat every 8 px (or a divisor of 32x16), so neighboring tiles join without seams.

| # | Frame | Base color | Pattern (colorblind rule) | Label |
| --- | --- | --- | --- | --- |
| 0 | `fairway` | `fairway` | plain | FW |
| 1 | `rough` | `rough` | stippled: irregular dark flecks (`rough_dark`) and a lighter one | RO |
| 2 | `green` | `green` | cross-hatched: both 45 degree diagonals in `green_dark` | GR |
| 3 | `tee` | `tee_light` / `tee_dark` | checkered: 4 px mown squares | TE |
| 4 | `bunker` | `sand` | dotted: regular dot grid in `sand_dark`, rows offset | BU |
| 5 | `water` | `water` | waves: small `water_light` crests, rows offset | WA |
| 6 | `trees` | `tree_dark` | canopy: round crowns in `tree` on a staggered grid | TR |
| 7 | `cart_path` | `path` | lined: lines along one isometric axis in `path_dark` | CP |
| 8 | `oob` | `oob` / `oob_dark` | bold diagonal stripes | OB |

Tee, trees and oob patterns are not named by the art-spec skill; they are chosen here.
`oob` is surface 8 in the course format; whether OB is a surface or stakes is still open
(E2-S1). If E2-S1 drops it, delete frame 8 and its name in `surfaces.tres`.

Grayscale check (`art/tiles/tile_preview.tscn`, right half): rough, water and oob sit
close in luminance (about 108, 116, 100 of 255) and are told apart by pattern alone. Final
art should spread them further (E5-S2 requires a grayscale-distinguishable set).

## Anchor

Pixel (32, 16) of a frame, the diamond's center, sits on the screen point the isometric
projection returns for the tile's center at its height. Tile at grid (i, j), height h:
`x = (i - j) * 32`, `y = (i + j) * 16 - h * 16`.

## Code that reads it

- `art/tiles/surfaces.tres` (`TileArt`), field `surfaces` (`TileSheet`).
- `TileArt.load_default().surface_texture(&"green")` returns an `AtlasTexture`;
  `TileSheet.region(index)` returns the pixel rect for a TileSet atlas.
- The course renderer (E1-S4) and the builder's surface palette (E1-S5).
- `tests/test_tile_art.gd` checks layout, order, diamond shape, patterns and palette.

## For the artist replacing it

- Keep the file name pattern `surfaces_<state>.png`, 9 frames, 64x32, 1 px gutter, the order
  above. Point `surfaces.tres` at the new file; nothing else changes.
- Keep the anchor at (32, 16) and the diamond rasterization above, or tiles will gap.
- Keep one pattern per surface; it can be subtler, but it must survive a grayscale
  screenshot. Drop the corner labels.
- Only colors from `art/palette.gpl`.
- Regenerate the placeholder with `python3 scripts/placeholder.py surfaces`.
