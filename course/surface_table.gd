class_name SurfaceTable
extends Resource
## The per-surface numbers the ball reads, one SurfaceRow per Surface.Type in enum order.
## Lives at course/surfaces.tres, where /balance expects it. Read-only for gameplay code.

const DEFAULT_PATH := "res://course/surfaces.tres"

@export var rows: Array[SurfaceRow] = []


static func load_default() -> SurfaceTable:
	return load(DEFAULT_PATH) as SurfaceTable


func row(surface: Surface.Type) -> SurfaceRow:
	return rows[surface]


## Problems with the table, empty when every surface has a row in enum order.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if rows.size() != Surface.COUNT:
		errors.append("expected %d rows, got %d" % [Surface.COUNT, rows.size()])
	for i in mini(rows.size(), Surface.COUNT):
		var r := rows[i]
		if r == null:
			errors.append("row %d is empty" % i)
		elif r.name != Surface.name_of(i):
			errors.append("row %d is %s, expected %s" % [i, r.name, Surface.name_of(i)])
		elif r.roll < 0.0:
			errors.append("%s: roll below 0" % r.name)
	return errors
