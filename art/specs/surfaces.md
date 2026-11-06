# Art spec: surfaces

## Purpose

The top face of every terrain tile. The player reads the course from these: where the
fairway ends, where the bunker is, which tiles are out. They must be readable at 0.5x zoom
and without color (colorblind rule).

## Look

SimGolf warmth (soft, sunlit greens, sand that looks warm) with Mean 18 clarity (each
surface is a flat, unmistakable field; no texture noise that competes with the ball).

## Sheet

- File: `art/tiles/surfaces_<state>.png`. Placeholder: `art/tiles/surfaces_placeholder.png`,
  and its label-free Play copy `art/tiles/surfaces_play_placeholder.png` (E3-S55): the same
  frames and patterns, the pattern running under where the label box was.
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
`oob` is surface 8 in the course format. D9 keeps it as a surface: from E2-S3 it is on the
Build palette as OB ground, and its frame is the palette button's icon.

Grayscale check (`art/tiles/tile_preview.tscn`, right half): rough, water and oob sit
close in luminance (about 108, 116, 100 of 255) and are told apart by pattern alone. Final
art should spread them further (E5-S2 requires a grayscale-distinguishable set).

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
lighter rough or a darker fairway or tee means retuning the ramp. The tee's fill (139 of 255
luminance) is the tight one: rough's fill (119) may rise at most to about 1.12.

## Anchor

Pixel (32, 16) of a frame, the diamond's center, sits on the screen point the isometric
projection returns for the tile's center at its height. Tile at grid (i, j), height h:
`x = (i - j) * 32`, `y = (i + j) * 16 - h * 16`.

## Code that reads it

- `art/tiles/surfaces.tres` (`TileArt`), field `surfaces` (`TileSheet`).
- The sheet's `play_texture` is the label-free copy; the course view draws it in Play
  (`CourseView.play_art`, E3-S55) and the labelled `texture` in Build. Unset, `texture` is
  drawn in both modes.
- `TileArt.load_default().surface_texture(&"green")` returns an `AtlasTexture`;
  `TileSheet.region(index)` returns the pixel rect for a TileSet atlas.
- The course renderer (E1-S4) and the builder's surface palette (E1-S5).
- `tests/test_tile_art.gd` checks layout, order, diamond shape, patterns and palette.

## For the artist replacing it

- Keep the file name pattern `surfaces_<state>.png`, 9 frames, 64x32, 1 px gutter, the order
  above. Point `surfaces.tres` at the new file; nothing else changes.
- Keep the anchor at (32, 16) and the diamond rasterization above, or tiles will gap.
- Keep one pattern per surface; it can be subtler, but it must survive a grayscale
  screenshot. Drop the corner labels: the labels are a placeholder aid for Build, and Play
  already hides them (E3-S55). With final art, leave `play_texture` unset in `surfaces.tres`
  (and delete the play placeholder), so the one sheet draws in both modes; the Build palette's
  icons come from the same sheet.
- Only colors from `art/palette.gpl`.
- Regenerate the placeholder with `python3 scripts/placeholder.py surfaces`.
