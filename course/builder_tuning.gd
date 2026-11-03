class_name BuilderTuning
extends Resource
## Designer-tuned numbers for the terrain builder. Loaded from res://course/builder_tuning.tres.

const PATH: String = "res://course/builder_tuning.tres"

## Brush widths in tiles, smallest first. Each is odd so the brush centers on the cursor tile.
@export var brush_sizes: PackedInt32Array = PackedInt32Array([1, 3, 5])
## Undo steps kept; the oldest falls off past this.
@export var undo_limit: int = 200
## The blank plot a New sandbox starts on (D10): its size in tiles, and the surface and whole
## height of every tile.
@export var plot_size: Vector2i = Vector2i(128, 128)
@export var plot_surface: Surface.Type = Surface.Type.ROUGH
@export_range(0, 7) var plot_ground: int = 2
## The par the tee and cup tools give a new hole until the player picks another (3, 4 or 5).
@export_range(3, 5) var default_par: int = 3
## How far past its resting height an issue text box may be pushed up to clear its
## neighbours, screen px at every zoom; past that it moves sideways instead (E2-S17).
@export var issue_box_max_stack: float = 96.0
## How far sideways off centre an issue text box may move, screen px at every zoom; a box
## that fits nowhere within both limits collapses to its badge, and the hole panel lists its
## reasons (E2-S17).
@export var issue_box_max_side: float = 160.0


static func load_default() -> BuilderTuning:
	return load(PATH) as BuilderTuning
