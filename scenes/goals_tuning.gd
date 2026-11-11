class_name GoalsTuning
extends Resource
## Designer-tuned numbers for the new course's goal checklist (E10-S1; scenes/goal_list.gd).
## Loaded from res://scenes/goals_tuning.tres.

const PATH: String = "res://scenes/goals_tuning.tres"

## The last goal: a dusk, with guests out that day, at this many stars or more
## (EconomyTuning.stars_of the day's rating).
@export var target_stars: float = 3.0
## The panel's text size, px; the next goal's "how" line is one px smaller.
@export var font_size: int = 13
## The gap the panel keeps above the bottom bar, px; with less room it shows its one line.
@export var bottom_gap: float = 8.0


static func load_default() -> GoalsTuning:
	return load(PATH) as GoalsTuning
