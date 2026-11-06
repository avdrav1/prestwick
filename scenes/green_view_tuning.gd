class_name GreenViewTuning
extends Resource
## Designer-tuned numbers for the overhead green view (E3-S52, D48; scenes/green_view.gd).
## Loaded from res://scenes/green_view_tuning.tres.

const PATH: String = "res://scenes/green_view_tuning.tres"

## Tiles of ground drawn round the green's bounding box on every side.
@export var fringe_tiles: int = 2
## A tile's side in the panel, screen px: the largest that fits the window in the free view
## (less `margin_px` each side), held between these two.
@export var min_tile_px: float = 24.0
@export var max_tile_px: float = 40.0
## Gap kept between the panel and the edge of the free view, screen px.
@export var margin_px: float = 16.0
## The panel's frame round the tiles, and the height of its title strip, screen px.
@export var inset_px: float = 6.0
@export var header_px: float = 22.0
## Height as a shade: each step below the window's highest tile multiplies its colours by
## (1 - height_shade_step), never below height_shade_min, so low ground draws darker, by value.
@export var height_shade_step: float = 0.08
@export var height_shade_min: float = 0.68
## Slope arrows: a tile whose centred fall (steps per tile, the height field's slope at its
## centre) is at least `arrow_min_fall` gets one, pointing downhill. Its length is
## `arrow_length` of a tile at a fall of 0.5 and `arrow_length_steep` at a fall of 1 step or
## more; a fall of 2 or more per tile (a bank, felt as steep) draws a double head.
@export var arrow_min_fall: float = 0.2
@export var arrow_length: float = 0.45
@export var arrow_length_steep: float = 0.7
## Ink widths, screen px: the arrow's line and a contour (step) line on a tile edge.
@export var arrow_width: float = 2.0
@export var contour_width: float = 2.0
## Drawn sizes, screen px: the ball, the cup (at least; never smaller than the real cup at
## the panel's scale), the putter's marker ring and the putt line's dots.
@export var ball_radius_px: float = 4.0
@export var cup_radius_px: float = 5.0
@export var marker_radius_px: float = 8.0
@export var dot_radius_px: float = 2.0


static func load_default() -> GreenViewTuning:
	return load(PATH) as GreenViewTuning
