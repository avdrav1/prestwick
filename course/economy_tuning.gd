class_name EconomyTuning
extends RefCounted
## The economy's numbers (E4-S1; D56 build costs, D58 income and rating; docs/design.md
## Economy and time), every one read from res://data/economy.json. A reader only: nothing here
## charges, pays or rates. E4-S2 charges the build costs, E4-S4 the upkeep, E4-S5 the rating
## and arrivals, E4-S6 the fee. The starting balance is LandPrices.land_budget (D57) and the
## rating window GuestTuning's rating_window.

const PATH: String = "res://data/economy.json"
## The reaction kinds rating_points names, in GuestReaction.Kind's reading order.
const POINT_KINDS: PackedStringArray = ["praise", "neutral", "complaint"]

## Dollars to paint one tile, by Surface.Type (index = the enum value).
var tile_price: PackedInt32Array = PackedInt32Array()
## Dollars for one step of height raised or lowered on one tile.
var height_step_price: int = 0
var tee_marker_price: int = 0
var cup_price: int = 0
var upkeep_per_open_hole: int = 0
## The fee ceiling per round is this times the stars.
var fee_ceiling_per_star: int = 0
var arrivals_base: int = 0
var arrivals_per_star: int = 0
var arrivals_max: int = 0
## Arrivals are full up to this share of the ceiling...
var fee_full_arrivals_share: float = 0.0
## ...then fall in a straight line to this share of them at the ceiling.
var ceiling_arrivals_share: float = 0.0
## Rating points for praise, neutral and complaint, in POINT_KINDS order.
var rating_points: PackedFloat32Array = PackedFloat32Array()
## What load reported wrong, one line each; empty when the file is good.
var errors: Array[String] = []


## The numbers in data/economy.json. Fails an assert, and lists why in `errors`, when the file
## is missing a number or one is out of range.
static func load_default() -> EconomyTuning:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var t := from_dict(parsed if typeof(parsed) == TYPE_DICTIONARY else {})
	assert(t.errors.is_empty(), "%s: %s" % [PATH, t.errors])
	return t


## Reads `data` (data/economy.json's shape); range errors go to `errors`.
static func from_dict(data: Dictionary) -> EconomyTuning:
	var t := EconomyTuning.new()
	var e: Array[String] = []
	var tiles: Variant = data.get("tile_price")
	t.tile_price.resize(Surface.COUNT)
	if typeof(tiles) != TYPE_DICTIONARY:
		e.append("tile_price must be an object of surface prices")
	else:
		for i in Surface.COUNT:
			t.tile_price[i] = CourseData.read_int(tiles, Surface.NAMES[i], e, "tile_price")
	t.height_step_price = CourseData.read_int(data, "height_step_price", e)
	t.tee_marker_price = CourseData.read_int(data, "tee_marker_price", e)
	t.cup_price = CourseData.read_int(data, "cup_price", e)
	t.upkeep_per_open_hole = CourseData.read_int(data, "upkeep_per_open_hole", e)
	t.fee_ceiling_per_star = CourseData.read_int(data, "fee_ceiling_per_star", e)
	t.arrivals_base = CourseData.read_int(data, "arrivals_base", e)
	t.arrivals_per_star = CourseData.read_int(data, "arrivals_per_star", e)
	t.arrivals_max = CourseData.read_int(data, "arrivals_max", e)
	t.fee_full_arrivals_share = _read_share(data, "fee_full_arrivals_share", e)
	t.ceiling_arrivals_share = _read_share(data, "ceiling_arrivals_share", e)
	var pts: Variant = data.get("rating_points")
	t.rating_points.resize(POINT_KINDS.size())
	if typeof(pts) != TYPE_DICTIONARY:
		e.append("rating_points must be an object of praise, neutral and complaint points")
	else:
		for i in POINT_KINDS.size():
			t.rating_points[i] = CourseData.read_int(pts, POINT_KINDS[i], e, "rating_points")
	for i in Surface.COUNT:
		if t.tile_price[i] < 0:
			e.append("tile_price: %s must be 0 or more" % Surface.NAMES[i])
	for key: String in ["height_step_price", "tee_marker_price", "cup_price", "upkeep_per_open_hole",
			"fee_ceiling_per_star", "arrivals_base", "arrivals_per_star"]:
		if int(t.get(key)) < 0:
			e.append("%s must be 0 or more" % key)
	if t.arrivals_max < 1:
		e.append("arrivals_max must be 1 or more")
	if t.fee_full_arrivals_share >= 1.0:
		e.append("fee_full_arrivals_share must be below 1")
	if not (t.rating_points[2] <= t.rating_points[1] and t.rating_points[1] <= t.rating_points[0]):
		e.append("rating_points must run complaint <= neutral <= praise")
	t.errors = e
	return t


static func _read_share(data: Dictionary, key: String, e: Array[String]) -> float:
	var v: Variant = data.get(key)
	if typeof(v) not in [TYPE_INT, TYPE_FLOAT] or float(v) < 0.0 or float(v) > 1.0:
		e.append("%s must be a share from 0 to 1, got %s" % [key, v])
		return 0.0
	return float(v)


## Dollars to paint one tile with `surface` (a Surface.Type).
func price_of(surface: int) -> int:
	return tile_price[surface]


## The fee ceiling per round at `stars`.
func fee_ceiling(stars: float) -> float:
	return fee_ceiling_per_star * stars


## The share of a day's arrivals that comes at a fee of `fee_share` of the ceiling (0 free, 1 the
## ceiling): 1 up to fee_full_arrivals_share, then a straight line to ceiling_arrivals_share.
func fee_arrivals_share(fee_share: float) -> float:
	var x := clampf(fee_share, 0.0, 1.0)
	if x <= fee_full_arrivals_share:
		return 1.0
	return 1.0 - (1.0 - ceiling_arrivals_share) * (x - fee_full_arrivals_share) \
			/ (1.0 - fee_full_arrivals_share)


## Guests arriving in a day at `stars` and a fee of `fee_share` of the ceiling:
## (arrivals_base + arrivals_per_star x stars) x fee_arrivals_share, rounded, at most
## arrivals_max (the cap is a day's capacity, so it holds whatever the fee).
func arrivals(stars: float, fee_share: float) -> int:
	return mini(roundi((arrivals_base + arrivals_per_star * stars) * fee_arrivals_share(fee_share)),
			arrivals_max)
