class_name LandPrices
extends RefCounted
## Parcel prices and the New course land budget (D28, D57, docs/design.md Land), every number
## read from res://data/land.json. Reads a course; never writes one.
##
##   price = price_scale * (base_price + relief_step_price * relief + tree_tile_price * trees
##           + water_tile_price * water),
##   clamped to price_scale * min_price..price_scale * max_price and rounded to the nearest
##   price_round,
##
## where relief is the parcel's highest tile height minus its lowest, and trees and water are
## its tile counts of those surfaces. The terms are D28's dollars before the money scale (D56);
## price_scale is that scale, so land moves with the build costs (D57).

const PATH: String = "res://data/land.json"

## Dollars a New course starts with to buy parcels (E6-S6 hands it out).
var land_budget: int = 0
var base_price: int = 0
var relief_step_price: int = 0
var tree_tile_price: int = 0
var water_tile_price: int = 0
var min_price: int = 0
var max_price: int = 0
var price_round: int = 1
## The money scale on every term above (D56, D57): 0.61.
var price_scale: float = 1.0


## The prices in data/land.json. Fails an assert, and keeps the zero defaults, when the file
## is missing or a number is not a whole number.
static func load_default() -> LandPrices:
	var lp := LandPrices.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert(typeof(parsed) == TYPE_DICTIONARY, "%s must be a JSON object" % PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		return lp
	var data: Dictionary = parsed
	var errors: Array[String] = []
	lp.land_budget = CourseData.read_int(data, "land_budget", errors)
	lp.base_price = CourseData.read_int(data, "base_price", errors)
	lp.relief_step_price = CourseData.read_int(data, "relief_step_price", errors)
	lp.tree_tile_price = CourseData.read_int(data, "tree_tile_price", errors)
	lp.water_tile_price = CourseData.read_int(data, "water_tile_price", errors)
	lp.min_price = CourseData.read_int(data, "min_price", errors)
	lp.max_price = CourseData.read_int(data, "max_price", errors)
	lp.price_round = maxi(CourseData.read_int(data, "price_round", errors), 1)
	var scale: Variant = data.get("price_scale")
	if typeof(scale) in [TYPE_INT, TYPE_FLOAT] and float(scale) > 0.0:
		lp.price_scale = float(scale)
	else:
		errors.append("price_scale must be a number above 0, got %s" % scale)
	assert(errors.is_empty(), "%s: %s" % [PATH, errors])
	return lp


## What parcel `p` of `course` costs, in dollars. 0 for a parcel off the map.
func price(course: CourseData, p: Vector2i) -> int:
	var r: Rect2i = course.parcel_rect(p)
	if r.size == Vector2i.ZERO:
		return 0
	var lo: int = CourseData.MAX_HEIGHT
	var hi: int = 0
	var trees: int = 0
	var water: int = 0
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var h: int = course.get_height(x, y)
			lo = mini(lo, h)
			hi = maxi(hi, h)
			match course.get_surface(x, y):
				Surface.Type.TREES:
					trees += 1
				Surface.Type.WATER:
					water += 1
	return scaled(base_price + relief_step_price * (hi - lo) + tree_tile_price * trees \
			+ water_tile_price * water)


## A raw price (D28's formula before the scale) scaled, clamped and rounded, in dollars.
func scaled(raw: int) -> int:
	var clamped: float = clampf(raw * price_scale, min_price * price_scale, max_price * price_scale)
	return roundi(clamped / float(price_round)) * price_round


## `dollars` as the HUD and refusals write it: "$1,150".
static func money(dollars: int) -> String:
	var digits := str(absi(dollars))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-$" if dollars < 0 else "$") + digits + out
