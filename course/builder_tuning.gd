class_name BuilderTuning
extends Resource
## Designer-tuned numbers for the terrain builder. Loaded from res://course/builder_tuning.tres.

const PATH: String = "res://course/builder_tuning.tres"

## Brush widths in tiles, smallest first. Each is odd so the brush centers on the cursor tile.
@export var brush_sizes: PackedInt32Array = PackedInt32Array([1, 3, 5])
## Undo steps kept; the oldest falls off past this.
@export var undo_limit: int = 200


static func load_default() -> BuilderTuning:
	return load(PATH) as BuilderTuning
