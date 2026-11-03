class_name LandTuning
extends Resource
## Designer-tuned numbers for the natural land generator (course/land_generator.gd, E6-S2).
## Loaded from res://course/land_tuning.tres. The rates are the targets in docs/design.md
## Land, "Generated land"; tests/test_land_generator.gd holds them within their tolerances over
## seeds 1 to 20, so rerun it after any change here.

const PATH: String = "res://course/land_tuning.tres"

## Map size in tiles (D10's 128 x 128).
@export var map_size: Vector2i = Vector2i(128, 128)
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


static func load_default() -> LandTuning:
	return load(PATH) as LandTuning
