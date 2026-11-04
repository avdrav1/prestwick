class_name CourseGenerator
extends RefCounted
## Builds the one-hole courses `/course-file generate <par> [flat|hilly] [water|dry]` writes
## (course/course_file.gd), used as test fixtures and smoke playtest courses. Every course it
## makes passes all six rules of course/validator.gd (tests/test_validator.gd checks).
##
## It never writes a CourseData: it lays the tiles out as course format data (every parcel
## owned, an unlimited land budget) and
## constructs a new course from that with CourseData.from_dict, the loader course/save.gd
## uses, so CourseData keeps its two writers (CLAUDE.md Architecture).
##
## Layout, along +x on a D10 plot (rough at height 2): a 3x3 tee box round the tee, a fairway
## corridor 5 tiles wide from 40 yd out to the green's front, a round green round the cup,
## and with water a pond 3 tiles long across the corridor at 60% of the way, dug one step,
## with dry rough round both ends. `hilly` adds a gentle ridge (ridge_rise, below).

## Hole lengths in tiles at 5 yd per tile: 160, 380 and 520 yd. Fixture shapes, not tunables.
const LENGTH_TILES: Dictionary = {3: 32, 4: 76, 5: 104}
const MAP_ROWS: int = 25
const END_MARGIN: int = 6
const PLOT_HEIGHT: int = 2
const FAIRWAY_HALF_WIDTH: int = 2
const FAIRWAY_START: int = 8
const GREEN_RADIUS: float = 3.2
const POND_AT: float = 0.6
const POND_LENGTH: int = 3
const POND_HALF_WIDTH: int = 4
## The hilly ridge: a band one step above the plot, RIDGE_WIDTH tiles along the hole, its
## first tile at RIDGE_AT of the way from tee to cup, across every row of the map.
const RIDGE_AT: float = 0.35
const RIDGE_WIDTH: int = 4


## A new one-hole course, or null with a reason in `errors` for a par outside 3 to 5.
static func generate(par: int, hilly: bool, water: bool, errors: Array[String] = []) -> CourseData:
	if not LENGTH_TILES.has(par):
		errors.append("par must be 3, 4 or 5, got %d" % par)
		return null
	var length: int = LENGTH_TILES[par]
	var w: int = length + 2 * END_MARGIN
	var h: int = MAP_ROWS
	var mid: int = h / 2
	var tee := Vector2i(END_MARGIN, mid)
	var cup := Vector2i(END_MARGIN + length, mid)
	var pond_x: int = tee.x + roundi(length * POND_AT)

	var tiles := PackedByteArray()
	tiles.resize(w * h)
	for y: int in h:
		for x: int in w:
			var s: Surface.Type = Surface.Type.ROUGH
			var height: int = PLOT_HEIGHT
			if hilly:
				height += ridge_rise(x, tee.x, length)
			var on_corridor: bool = absi(y - mid) <= FAIRWAY_HALF_WIDTH
			if on_corridor and x >= tee.x + FAIRWAY_START and x < cup.x:
				s = Surface.Type.FAIRWAY
			if water and x >= pond_x and x < pond_x + POND_LENGTH and absi(y - mid) <= POND_HALF_WIDTH:
				s = Surface.Type.WATER
				height = PLOT_HEIGHT - 1
			if Vector2(x - cup.x, y - cup.y).length() <= GREEN_RADIUS:
				s = Surface.Type.GREEN
			if absi(x - tee.x) <= 1 and absi(y - tee.y) <= 1:
				s = Surface.Type.TEE
			tiles[y * w + x] = (height << 4) | s

	var data := {
		"version": CourseData.FORMAT_VERSION,
		"name": "Par %d, %s, %s" % [par, "hilly" if hilly else "flat", "water" if water else "dry"],
		"author": "course-file generate",
		"width": w,
		"height": h,
		"tiles": Marshalls.raw_to_base64(tiles),
		"holes": [HoleData.new(1, par, tee, cup, true).to_dict()],
		"thumbnail": "",
		# A fixture plays on land it owns, with no budget, as New sandbox does (D26).
		"owned": CourseData.all_owned_rows(w, h),
		"land_budget": null,
	}
	return CourseData.from_dict(data, errors)


## Steps above the plot at column `x` on a hilly hole from `tee_x`, `length` tiles long: 1 on
## the ridge, 0 elsewhere. A one-step terrace with one-step risers, the gentlest hill the
## height model has (D5), clear of the tee box, the green and the pond, so the surfaces and
## the six rules are those of the flat hole. Kept on its own on purpose: E6-S2's land
## generator replaces it (D19).
static func ridge_rise(x: int, tee_x: int, length: int) -> int:
	var start: int = tee_x + roundi(length * RIDGE_AT)
	return 1 if x >= start and x < start + RIDGE_WIDTH else 0
