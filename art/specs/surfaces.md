# Art spec: surfaces

## Purpose

The top face of every terrain tile. The player reads the course from these: where the
fairway ends, where the bunker is, which tiles are out. They must be readable at 0.5x zoom
and without color (colorblind rule).

## Look

SimGolf warmth (soft, sunlit greens, sand that looks warm) with Mean 18 clarity (each
surface is a flat, unmistakable field; no texture noise that competes with the ball).

## Sheet

Final art (E5-S2, D62): `art/tiles/surfaces_final.png`, written by `scripts/art_terrain.py`
(rerun it after any palette or rule change; it prints each surface's Rec. 709 mean and fill over
all its variants, the measures of `tests/test_course_view.gd`). The placeholders went with it.

- 64x32 frames, no padding, 1 px transparent gutter, one row. Each frame is the 2:1 diamond,
  pixel-center rasterized (rows widen by 4 px per row, 2 px wide at the top and bottom tips,
  62 px at the middle rows); corners are transparent.
- The pattern repeats every 4 x 4 tiles, not every tile (`TileSheet.macro` 4), so mowing
  stripes can be two tiles wide and rough and water do not look stamped (the E5-S1 sample's
  lesson: a pattern that repeats per tile cannot have a period over 64 px). The sheet holds 16
  variants of each surface, 144 frames (9359 x 32): frames 0 to 8 are variant (0, 0) of each
  surface in surface enum order, so frame index == surface value still names it (the Build
  palette's icons draw these), and variant (a, b) of surface s is frame s + 9 * (a + 4b). The
  course tile (x, y) draws variant (x mod 4, y mod 4) (`TileSheet.variant_of`).
- Every rule is a function of the pixel's place on the course (A = X + 2Y, B = 2Y - X of its
  course pixel, mod 256), so neighbouring tiles and variants join without seams on any slope.
- No seam line and no labels: the ground reads as one field, not a board (SimGolf); Build has
  its hover outline and the line of play for distances.

| # | Frame | Colours | Pattern (colorblind rule) |
| --- | --- | --- | --- |
| 0 | `fairway` | `fairway`, `tee_light` | mown stripes along the x axis, 2 tiles wide, the light one 44% of the pair, edges dithered in 2 x 2 cells through tile middles; a few blades |
| 1 | `rough` | `rough`, `rough_dark`, `fairway` | stippled: tufts of two dark blades with a lit tip, denser in slow patches |
| 2 | `green` | `green`, `green_dark`, `green_light` | cross-hatched: both 45 degree diagonals every 8 px, one `green_dark`, one dashed `green_light` |
| 3 | `tee` | `tee_light`, `tee_dark` | checkered: mown squares half a tile wide along the grid axes, the dark ones inset |
| 4 | `bunker` | `sand`, `sand_dark`, `sand_light` | dotted: 2 x 1 `sand_dark` dots every 8 px, rows offset, a light grain |
| 5 | `water` | `water_dark`, `water`, `water_light` | waves: deep water under scattered crests on rows 4 px apart (a swell with a light arc) |
| 6 | `trees` | `tree_dark`, `tree`, `rough` | canopy: round crowns on a staggered 8 px grid, lit on the upper left |
| 7 | `cart_path` | `path`, `path_dark` | lined: lines along the x axis about 7 px apart, grit between |
| 8 | `oob` | `oob`, `oob_dark` | bold diagonal stripes |

Values (Rec. 709 over all variants, mean / fill): fairway 157.7 / 153.4, rough 117.8 / 118.6,
green 192.4 / 194.9, tee 155.5 / 163.5, bunker 210.1 / 211.3, water 91.9 / 74.8, trees 77.2 /
62.5, cart path 166.3 / 176.5, oob 102.4 / 119.7.

Grayscale (`docs/decisions/e5-s2-*-gray.png`): water, the placeholder's near twin of rough
(116 against 108), is now deep water with light crests, about 26 below rough in mean and with a
light pattern where rough's is dark. Fairway and tee are close in value and told apart by
stripes against checks; green is the lightest grass and cross-hatched; bunker the lightest
surface, dotted.

## Height shade (E6-S18)

The sheet has one frame per surface, not per height. `CourseView` draws each top through an
alternative tile per height (`CourseView.top_alt(h, owned)`). The land surfaces (rough, water,
trees, oob; `BuilderTuning.height_shaded`) are modulated by a grey value,
`BuilderTuning.height_shade[h]` (0.80 at height 0 up to 1.10 at height 7, E6-S28, 1.0 at the D10 plot's
height 2), so low ground is darker and high ground lighter. Course surfaces (fairway, green,
tee, bunker, cart path) are not shaded, so their colour names the lie at every height. The
shade is a multiply, and above 1 it is capped per frame where the brightest coloured
(saturation 0.1 or more) pixel would reach 255, so no channel clips and the hue holds; water
(water_light 232) caps at about 1.10. Only the near-grey label chalk may clip toward white. It
holds in grayscale (`docs/decisions/e6-s18-land-0.5x-gray.png`), and on a rise that faces away
from the camera (no riser, only the edge cue's lip) the lighter side is the higher one. Final
art must keep rough's value band over heights 0 to 7 at least 5% clear of fairway, tee, green
and trees (`tests/test_course_view.gd`), and every shaded land surface at every height at
least 5% clear of fairway, tee and green at the plot's height, by its mean value and by its
fill (its most common colour, what is left at 0.5x once the speckle is gone; E6-S28); a
lighter rough or a darker fairway or tee means retuning the ramp. With the placeholder the
tee's fill (139 of 255 luminance) was the tight one; the final tee's fill is `tee_light` (163.5),
so rough at height 7 (fill 130.5) sits 17% under fairway's fill (153.4), and the tightest gap
is trees' band against rough's (trees at height 7, 84.9 mean, 11% under rough at height 0). The slope light was
checked against the final sheets (screenshots at three zooms) and kept as tuned in E3-S58:
the final values sit within 6 of the placeholder's.


Smooth ground (E3-S58, D50): the course view maps each frame's diamond (the tile's variant,
E5-S2) onto its tile's sloped ground (`course/terrain_mesh.gd`), pulled in by 1 px so the
transparent corners are never sampled, so a slope takes the flat frame with no new art. The height shade is read at the
ground's own height, blended between the whole steps, and the slope light multiplies it,
under the same headroom cap. Risers and the edge cue are no longer drawn.
## Anchor

Pixel (32, 16) of a frame, the diamond's center, sits on the screen point the isometric
projection returns for the tile's center at its height. Tile at grid (i, j), height h:
`x = (i - j) * 32`, `y = (i + j) * 16 - h * 16`.

## Code that reads it

- `art/tiles/surfaces.tres` (`TileArt`), field `surfaces` (`TileSheet`, `macro` 4).
- `play_texture` is unset: the final sheet has no labels and draws in both modes (E3-S55's
  label-free Play copy went with the placeholder).
- `TileArt.load_default().surface_texture(&"green")` returns an `AtlasTexture`;
  `TileSheet.region(index)` returns the pixel rect for a TileSet atlas.
- The course renderer (E1-S4) and the builder's surface palette (E1-S5).
- `tests/test_tile_art.gd` checks layout, order, diamond shape, patterns, stripes and palette;
  `tests/test_course_view.gd` the value bands.

## Changing it

- Change the rule in `scripts/art_terrain.py` and rerun it; never edit the PNG (D62).
- Keep 64x32 frames, 1 px gutter, the order above, the anchor (32, 16), the diamond
  rasterization and `macro` 4 (or change `art/tiles/surfaces.tres` with it), or tiles will gap.
- Keep one pattern per surface that survives a grayscale screenshot at 0.5x, and the value
  bands below `Height shade`.
- Only colors from `art/palette.gpl`.
