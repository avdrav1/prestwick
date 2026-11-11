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
## E8-S1 (D64): the player closed it with Close. The builder opens a closed hole that passes
## every rule by itself, except one closed by hand: that stays closed until Open is pressed.
## A rule closing the hole leaves it false. In a file it is the hole object's optional
## "closed_by_hand": true, absent when false, so a hole without it writes as before.
var closed_by_hand: bool = false
## E8-S5: the player picked this par with the par buttons. Placing a tee or cup with the Build
## tools sets par to the one the yardage makes (rule 4) unless this is set; the hole panel says
## when a hand-picked par and the yardage disagree. In a file it is the hole object's optional
## "par_by_hand": true, absent when false, as closed_by_hand.
var par_by_hand: bool = false


func _init(p_number: int = 1, p_par: int = 3, p_tee: Vector2i = Vector2i.ZERO,
		p_cup: Vector2i = Vector2i.ZERO, p_open: bool = true, p_closed_by_hand: bool = false,
		p_par_by_hand: bool = false) -> void:
	number = p_number
	par = p_par
	tee = p_tee
	cup = p_cup
	open = p_open
	closed_by_hand = p_closed_by_hand
	par_by_hand = p_par_by_hand


## Course format version 1 hole object, with "closed_by_hand" only when set (E8-S1, D64: an
## optional field of the same format version, as E5-S3's decor), and "par_by_hand" likewise
## (E8-S5).
func to_dict() -> Dictionary:
	var out := {
		"number": number,
		"par": par,
		"tee": [tee.x, tee.y],
		"cup": [cup.x, cup.y],
		"open": open,
	}
	if closed_by_hand:
		out["closed_by_hand"] = true
	if par_by_hand:
		out["par_by_hand"] = true
	return out


func copy() -> HoleData:
	return HoleData.new(number, par, tee, cup, open, closed_by_hand, par_by_hand)


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
	var by_hand: Variant = data.get("closed_by_hand", false)
	if typeof(by_hand) != TYPE_BOOL:
		errors.append("hole: closed_by_hand must be true or false")
	var par_hand: Variant = data.get("par_by_hand", false)
	if typeof(par_hand) != TYPE_BOOL:
		errors.append("hole: par_by_hand must be true or false")
	if errors.size() > start:
		return null
	return HoleData.new(n, p, t, c, o, by_hand, par_hand)


static func _read_tile(data: Dictionary, key: String, errors: Array[String]) -> Vector2i:
	var v: Variant = data.get(key)
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 2:
		errors.append("hole: %s must be [x, y]" % key)
		return Vector2i.ZERO
	var pair := {"x": v[0], "y": v[1]}
	var x := CourseData.read_int(pair, "x", errors, "hole %s" % key)
	var y := CourseData.read_int(pair, "y", errors, "hole %s" % key)
	return Vector2i(x, y)
