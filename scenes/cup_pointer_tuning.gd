class_name CupPointerTuning
extends Resource
## Designer-tuned numbers for the off-screen cup's edge marker (E3-S64; scenes/cup_pointer.gd).
## Loaded from res://scenes/cup_pointer_tuning.tres.

const PATH: String = "res://scenes/cup_pointer_tuning.tres"

## The marker's centre stands this far inside the free view's edge, screen px.
@export var edge_inset: float = 28.0
## The arrow's length from the marker's centre to its tip, screen px.
@export var arrow_length: float = 26.0
## The arrow's half-width at its base, screen px.
@export var arrow_half_width: float = 9.0
## The hole number's text size, px, and the padding round it in its box.
@export var font_size: int = 14
@export var padding: float = 4.0


static func load_default() -> CupPointerTuning:
	return load(PATH) as CupPointerTuning
