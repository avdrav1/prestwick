class_name ValidatorTuning
extends Resource
## Designer-tuned numbers for the hole rules (docs/design.md Hole validation rules, D11).
## Loaded from res://course/validator_tuning.tres. Change the landing distance with the driver
## target (Balance targets), not alone.

const PATH: String = "res://course/validator_tuning.tres"

## Rule 4: the shortest par 4 and the shortest par 5, in whole yards on the rounded yardage.
## Anything shorter than par4_min_yd is a par 3. 320 since D33 (E6-S19): a perfect drive
## rolls 297 yd on flat fairway, so it stops short of a 30 yd green round a 320 yd cup.
## Change it with the driver's carry and roll (golf/clubs.tres), not alone, and keep it at or
## above zone_from_yd (order_issue), or par 4s between them lose their landing zones.
@export var par4_min_yd: int = 320
@export var par5_min_yd: int = 471
## Rule 5: every hole of zone_from_yd or more (rounded yardage), whatever its par, has a
## landing zone; shorter holes have none (D35, E6-S37). 300 yd: a par 3 of about 298 to 319
## yd cannot be reached in one on level ground, so its tee shots land short of the green.
## Change it with par4_min_yd: it must stay at or below it (order_issue, E6-S39).
@export var zone_from_yd: int = 300
## Rule 5: the landing zone is a disc centred
## min(landing_distance_yd, yardage - cup_clearance_yd) from the tee along the tee-to-cup line.
## Rule 4 (D47) reads the same disc on every hole of landing_distance_yd or more (not only
## from zone_from_yd, E3-S25 review): a hole whose disc holds no fairway is a dogleg, turning
## at its own fairway that far from the tee (CourseValidator.turn_point).
@export var landing_distance_yd: float = 240.0
@export var cup_clearance_yd: float = 60.0
## Rule 5: a tee whose tile centre is this close to the zone centre, or closer, is inside.
@export var zone_radius_yd: float = 30.0
## Rule 4 (D47, E3-S25 review): a dogleg turns only at fairway that runs on, 8 neighbours
## through fairway, to a tile centre this close to its cup, so another hole's fairway never
## bends it. 40 yd: a 5 x 5 green and an apron or a fringe bunker round it.
@export var turn_cup_reach_yd: float = 40.0
## Footprint (CourseValidator.in_footprint, read by course/builder.gd): tiles whose centre is within this distance of the tee-to-cup segment.
@export var footprint_half_width_yd: float = 30.0


static func load_default() -> ValidatorTuning:
	return load(PATH) as ValidatorTuning


## "" when the tunables keep their order, else what is wrong: every par 4 must have a landing
## zone, so zone_from_yd may not be above par4_min_yd (E6-S39).
func order_issue() -> String:
	if zone_from_yd > par4_min_yd:
		return "zone_from_yd (%d yd) is above par4_min_yd (%d yd): par 4s from %d to %d yd would have no landing zone" % [
				zone_from_yd, par4_min_yd, par4_min_yd, zone_from_yd - 1]
	return ""
