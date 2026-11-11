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
## The shade follows the height field (HeightField.height_at), sampled `shade_subdiv` times a
## tile side and blended between, so it runs smooth across a slope (E3-S56).
@export var height_shade_step: float = 0.08
@export var height_shade_min: float = 0.68
@export var shade_subdiv: int = 4
## Contours (E3-S56, ContourTracer): a line every `contour_interval` steps, `contour_width` px,
## and a heavier index line, `index_width` px, every `index_interval` steps, both counted from
## `contour_offset`. At 0.5 the index lines sit at half steps, half way up each one-step rise
## (smooth curves), and the thin whole-step lines run along each terrace's falling edge through
## its edge tiles' centres (ContourTracer). The tracer cuts each tile-centre cell into
## `contour_subdiv` a side, so the curves run smooth.
@export var contour_interval: float = 0.5
@export var index_interval: float = 1.0
@export var contour_offset: float = 0.5
@export var contour_width: float = 1.25
@export var index_width: float = 2.5
@export var contour_subdiv: int = 4
## Downhill ticks on the low side of each line: one every `tick_spacing_px` along it,
## `tick_length_px` long.
@export var tick_spacing_px: float = 22.0
@export var tick_length_px: float = 4.0
## Steep-fall arrows: only a tile whose steepest fall (steps per tile, the height field's
## slope a quarter tile from its centre toward each side, GreenView.steep_fall_at) reaches
## `arrow_steep_fall` gets one, pointing downhill, `arrow_length` of a tile long,
## `arrow_width` px, on a chalk halo. A ball does not stop on such a bank.
@export var arrow_steep_fall: float = 2.0
@export var arrow_length: float = 0.6
@export var arrow_width: float = 2.0
## E7-S2: the sprites (cup, pin, ball) drawn at this whole-number times their sheet size, so
## the pixel art stays crisp. A tile is 24 to 40 px here against 36 px along a tile's edge at
## the course's 1x, so 1 matches the course art's 1x.
@export var sprite_scale: float = 1.0
## Drawn sizes, screen px (at least, for the sprites): the ball's radius to its outline's
## outer edge, the cup's hole (never smaller than the real cup at the panel's scale), the
## putter's marker ring and the putt line's dots.
@export var ball_radius_px: float = 4.0
@export var cup_radius_px: float = 5.0
@export var marker_radius_px: float = 8.0
@export var dot_radius_px: float = 2.0


static func load_default() -> GreenViewTuning:
	return load(PATH) as GreenViewTuning
