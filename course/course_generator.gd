class_name CourseGenerator
extends RefCounted
## Builds the one-hole courses `/course-file generate <par> [flat|hilly] [water|dry]` writes
## (course/course_file.gd), used as test fixtures and smoke playtest courses. Every course it
## makes passes all five rules of course/validator.gd (tests/test_validator.gd checks).
##
## It never writes a CourseData: it lays the tiles out as course format version 1 data and
## constructs a new course from that with CourseData.from_dict, the loader course/save.gd
## uses, so CourseData keeps its two writers (CLAUDE.md Architecture).
##
## Layout, along +x on a D10 plot (rough at height 2): a 3x3 tee box round the tee, a fairway
## corridor 5 tiles wide from 40 yd out to the green's front, a round green round the cup,
## and with water a pond 3 tiles long across the corridor at 60% of the way, dug one step,
## with dry rough round both ends. `hilly` is not built in E2 (the skill's other variants
## are optional until E3).

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


## A new one-hole course, or null with a reason in `errors` for a par outside 3 to 5 or hilly.
static func generate(par: int, hilly: bool, water: bool, errors: Array[String] = []) -> CourseData:
	if not LENGTH_TILES.has(par):
		errors.append("par must be 3, 4 or 5, got %d" % par)
		return null
	if hilly:
		errors.append("hilly is not built yet; use flat")
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
	}
	return CourseData.from_dict(data, errors)
