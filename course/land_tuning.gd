class_name LandTuning
extends Resource
## Designer-tuned numbers for the natural land generator (course/land_generator.gd, E6-S2).
## Loaded from res://course/land_tuning.tres. The rates are the targets in docs/design.md
## Land, "Generated land"; tests/test_land_generator.gd holds them within their tolerances over
## seeds 1 to 20, so rerun it after any change here.

const PATH: String = "res://course/land_tuning.tres"

## Map size in tiles: a New course's (D71: 192 x 192; D10's 128 x 128 before, D10_MAP_SIZE).
## The size is per course file, so a course made on 128 x 128 stays that size.
@export var map_size: Vector2i = Vector2i(192, 192)
## D71: the map the hill, stand and pond count bounds below are given for (D10's 128 x 128).
## The generator scales each bound by map_size's area over this one's, rounded (count), so a
## bigger map gets more hills, stands and ponds at the same shares and sizes: 192 x 192 has
## hills 9 to 18, stands 34 to 79 and ponds 9 to 23. On a map this size they are as written.
@export var count_map_size: Vector2i = Vector2i(128, 128)
## The lowland every hill rises from (D10's plot height).
@export_range(0, 7) var base_height: int = 2

@export_group("Hills")
## Hills per map, both included.
@export var hill_count_min: int = 4
@export var hill_count_max: int = 8
## A hill's peak, in whole steps above the base height, both included. base + max <= 7.
@export var hill_peak_min: int = 2
@export var hill_peak_max: int = 5
## A hill's radius in tiles is its peak times a value drawn from this range, so a taller hill is
## wider and its slope stays about as gentle. Below about 3.2 the slope clamp flattens peaks.
@export var hill_radius_per_step_min: float = 5.0
@export var hill_radius_per_step_max: float = 8.0
## Extra lobes on a hill (0 to this many), which make it irregular: each sits this share of the
## hill's radius from its centre, with this share of its peak (and radius).
@export var hill_lobes_max: int = 2
@export var hill_lobe_offset_min: float = 0.45
@export var hill_lobe_offset_max: float = 0.85
@export var hill_lobe_scale_min: float = 0.45
@export var hill_lobe_scale_max: float = 0.8
## High ground: every radius is scaled by one factor, between these two, so that this share of
## the map is at high_ground_level or more (docs/design.md: 15%, 8% to 25%). A small map or few
## hills can miss it; the factor's range keeps hill shapes sane.
@export var high_ground_share: float = 0.15
@export_range(0, 7) var high_ground_level: int = 4
@export var hill_scale_min: float = 0.6
@export var hill_scale_max: float = 1.6

@export_group("Trees")
## Share of the map's tiles that are trees, in stands of whole tiles.
@export var tree_share: float = 0.12
@export var tree_stands_min: int = 15
@export var tree_stands_max: int = 35
@export var tree_stand_min_tiles: int = 20
@export var tree_stand_max_tiles: int = 200

@export_group("Ponds")
## Share of the map's tiles that are water, in flat ponds dug one step into flat ground.
@export var water_share: float = 0.04
@export var ponds_min: int = 4
@export var ponds_max: int = 10
@export var pond_min_tiles: int = 15
@export var pond_max_tiles: int = 120

@export_group("Floors")
## Every parcel keeps at least this share of its tiles rough (so never all water).
@export var parcel_min_rough: float = 0.6
## The starting block (D26) keeps at least this share rough, and has no water.
@export var start_block_min_rough: float = 0.85

@export_group("Starting block")
## The starting block's side in parcels (D26: 2; D67: 4), at the centre of the map: the land a
## New course owns for free (CourseBuilder.new_course, LandGenerator.start_block) and the land
## the generator keeps dry and start_block_min_rough rough. Fixtures laid on the land before
## D67 generate with D26_BLOCK_PARCELS (load_d26) so their land stays as it was.
@export_range(1, 8) var start_block_parcels: int = 4


static func load_default() -> LandTuning:
	return load(PATH) as LandTuning


## D71: count bound `n` (hill_count_min and so on, given for count_map_size) scaled to
## map_size by area, rounded half away from zero.
func count(n: int) -> int:
	var base: float = maxf(count_map_size.x * count_map_size.y, 1.0)
	return roundi(n * (map_size.x * map_size.y) / base)


## D71: the map before D71 (D10), 128 x 128, which every fixture laid on generated land keeps.
const D10_MAP_SIZE: Vector2i = Vector2i(128, 128)


## The default tuning on D10's 128 x 128 map (a copy): the land every seed generated after D67
## and before D71, with its starting block (4 x 4 parcels) and its counts. Fixtures, scripts and
## tests that were measured on that land (the balance tables, the economy sim) pin it, so
## nothing measured moves with D71's bigger map.
static func load_d67() -> LandTuning:
	var t := load_default().duplicate() as LandTuning
	t.map_size = D10_MAP_SIZE
	return t


## D67: the starting block before D67 (D26), 2 x 2 parcels.
const D26_BLOCK_PARCELS: int = 2


## The default tuning with D26's 2 x 2 starting block on D10's 128 x 128 map (a copy,
## load_d67 with the old block): the land every seed generated before D67, which the fixtures
## laid on it (PlaytestNine, NineHoles, ReactionHoles, CourseGenerator's hilly land) keep, so
## their holes and every balance table stay as they are.
static func load_d26() -> LandTuning:
	var t := load_d67()
	t.start_block_parcels = D26_BLOCK_PARCELS
	return t
