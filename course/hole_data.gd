class_name HoleData
extends Resource
## One hole of a course: tee and cup tiles, par, number, and whether it is open.
## Owned by CourseData. Readers treat these as read-only; course/builder.gd replaces
## holes through CourseData.set_holes.

## A tee or cup not placed yet (E2-S3 places them one at a time). Any off-map tile counts as
## not placed (course/validator.gd rule 1). CourseData.from_dict rejects an off-map tee or cup,
## so CourseSave.save_file drops a half-placed hole from the file and reports its number
## (E2-S12, docs/design.md Holes in Build).
const UNPLACED: Vector2i = Vector2i(-1, -1)

var number: int = 1
var par: int = 3
var tee: Vector2i = Vector2i.ZERO
var cup: Vector2i = Vector2i.ZERO
var open: bool = true


func _init(p_number: int = 1, p_par: int = 3, p_tee: Vector2i = Vector2i.ZERO,
		p_cup: Vector2i = Vector2i.ZERO, p_open: bool = true) -> void:
	number = p_number
	par = p_par
	tee = p_tee
	cup = p_cup
	open = p_open


## Course format version 1 hole object.
func to_dict() -> Dictionary:
	return {
		"number": number,
		"par": par,
		"tee": [tee.x, tee.y],
		"cup": [cup.x, cup.y],
		"open": open,
	}


func copy() -> HoleData:
	return HoleData.new(number, par, tee, cup, open)


## Parses a format v1 hole object. Returns null and appends to `errors` when malformed.
## Bounds are checked by CourseData.from_dict, which knows the map size.
static func from_dict(data: Dictionary, errors: Array[String]) -> HoleData:
	var start := errors.size()
	var n := CourseData.read_int(data, "number", errors, "hole")
	var p := CourseData.read_int(data, "par", errors, "hole")
	var t := _read_tile(data, "tee", errors)
	var c := _read_tile(data, "cup", errors)
	var o: Variant = data.get("open", true)
	if typeof(o) != TYPE_BOOL:
		errors.append("hole: open must be true or false")
	if errors.size() > start:
		return null
	return HoleData.new(n, p, t, c, o)


static func _read_tile(data: Dictionary, key: String, errors: Array[String]) -> Vector2i:
	var v: Variant = data.get(key)
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 2:
		errors.append("hole: %s must be [x, y]" % key)
		return Vector2i.ZERO
	var pair := {"x": v[0], "y": v[1]}
	var x := CourseData.read_int(pair, "x", errors, "hole %s" % key)
	var y := CourseData.read_int(pair, "y", errors, "hole %s" % key)
	return Vector2i(x, y)
