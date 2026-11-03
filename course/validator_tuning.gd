class_name ValidatorTuning
extends Resource
## Designer-tuned numbers for the hole rules (docs/design.md Hole validation rules, D11).
## Loaded from res://course/validator_tuning.tres. Change the landing distance with the driver
## target (Balance targets), not alone.

const PATH: String = "res://course/validator_tuning.tres"

## Rule 4: the shortest par 4 and the shortest par 5, in whole yards on the rounded yardage.
## Anything shorter than par4_min_yd is a par 3.
@export var par4_min_yd: int = 250
@export var par5_min_yd: int = 471
## Rule 5: a par 4 or par 5's landing zone is a disc centred
## min(landing_distance_yd, yardage - cup_clearance_yd) from the tee along the tee-to-cup line.
@export var landing_distance_yd: float = 240.0
@export var cup_clearance_yd: float = 60.0
## Rule 5: a tee whose tile centre is this close to the zone centre, or closer, is inside.
@export var zone_radius_yd: float = 30.0
## Footprint (CourseValidator.in_footprint, read by course/builder.gd): tiles whose centre is within this distance of the tee-to-cup segment.
@export var footprint_half_width_yd: float = 30.0


static func load_default() -> ValidatorTuning:
	return load(PATH) as ValidatorTuning
