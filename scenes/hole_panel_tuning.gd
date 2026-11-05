class_name HolePanelTuning
extends Resource
## Designer-tuned hole panel numbers (E3-S10). Loaded from res://scenes/hole_panel_tuning.tres.

const PATH: String = "res://scenes/hole_panel_tuning.tres"

## The tallest the Build hole panel may be with its list collapsed, screen px at 1280 x 720:
## the picked hole's row, New hole, the details and its issue text, which is cut to fit and
## scrolls (HolePanel._fit_issues). tests/test_hole_list.gd holds it with every rule failing.
@export var max_height: float = 280.0


static func load_default() -> HolePanelTuning:
	return load(PATH) as HolePanelTuning
