class_name ShotViewTuning
extends Resource
## Designer-tuned numbers for the drawn shot (scenes/shot_view.gd). Loaded from
## res://scenes/shot_view_tuning.tres.

const PATH: String = "res://scenes/shot_view_tuning.tres"

## E2-S13: a ball that stops in water or OB stays drawn where it went in for this many
## seconds before it appears at its drop point and the shot counts as at rest.
@export var hazard_show_time: float = 0.8


static func load_default() -> ShotViewTuning:
	return load(PATH) as ShotViewTuning
