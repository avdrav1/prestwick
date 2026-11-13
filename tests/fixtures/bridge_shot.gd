extends Node
## Screenshot fixture for E14-S1 (D69): main in Build over a pond with a footbridge across it,
## the cart path running up to it on both banks, at BRIDGE_ZOOM (default 1).
##
##   BRIDGE_ZOOM=1   scripts/screenshot.sh tests/fixtures/bridge_shot.tscn bridge-1x.png 20
##   BRIDGE_ZOOM=0.5 scripts/screenshot.sh tests/fixtures/bridge_shot.tscn bridge-0.5x.png 20
##
## E14-S2: BRIDGE_STEP=walk lays one bridge north to south across the pond's east side (x 24)
## instead, and stages guests (the main scene's own day, paused) along two walks GuestWalk.route
## finds: from the west bank to the east one along row 19 (round the pond's south end, the bridge
## out of its way) and from the north bank to the south-east one (over the bridge).
## Each walk's route is drawn as a chalk line, its guests at 20%, 45% and 70% of its time.
##   BRIDGE_STEP=walk scripts/screenshot.sh tests/fixtures/bridge_shot.tscn walk.png 30
##
## E14-S3: BRIDGE_STEP=island puts a green on an island in the pond and hole 1's tee on the south
## bank, no bridge: rule 7 closes it and its issue box says why.
##   BRIDGE_STEP=island scripts/screenshot.sh tests/fixtures/bridge_shot.tscn island.png 30

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SIZE: int = 40

var _main: Main


func _ready() -> void:
	var zoom: float = 1.0 if OS.get_environment("BRIDGE_ZOOM").is_empty() \
			else OS.get_environment("BRIDGE_ZOOM").to_float()
	_main = MAIN_SCENE.instantiate() as Main
	_main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(_main)
	var walk: bool = OS.get_environment("BRIDGE_STEP") == "walk"
	_main.show_course(pond_course())
	var b: CourseBuilder = _main.build_tool.builder
	if OS.get_environment("BRIDGE_STEP") == "island":
		for y: int in range(17, 22):
			for x: int in range(18, 23):
				b.level_water = false
				b.paint(Vector2i(x, y), Surface.Type.GREEN, 1)
		b.place_tee(1, Vector2i(20, 33), 3)
		b.place_cup(1, Vector2i(20, 19))
		b.move_clubhouse_beside(Vector2i(20, 33))
		_main.build_tool.select_hole(1)
	elif walk:
		b.begin_stroke()
		for y: int in range(12, 27):
			b.paint(Vector2i(24, y), Surface.Type.CART_PATH, 1)
		b.end_stroke()
		_stage_walks(b)
	else:
		lay_bridges(b)
	_main.camera.tracking = false
	_main.camera.set_zoom_index(_main.camera.tuning.zoom_levels.find(zoom))
	_main.camera.position = Iso.tile_to_screen(Vector2(20, 19), 2)
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(330, 40)
	label.text = "E14-S1 bridges at %sx: a footbridge across the pond, one corner bridge, path on the banks" % zoom
	if OS.get_environment("BRIDGE_STEP") == "island":
		label.text = "E14-S3 at %sx: an island green with no bridge, closed by rule 7" % zoom
	if walk:
		label.text = "E14-S2 at %sx: guests walk round the pond (west to east) and over the bridge (north to south-east)" % zoom
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)
	add_child(layer)


## A SIZE x SIZE map of rough at 3, every parcel owned, with an oval pond (at 2) in its middle.
static func pond_course() -> CourseData:
	var c := CourseData.create(SIZE, SIZE, Surface.Type.ROUGH, 3)
	for y: int in SIZE:
		for x: int in SIZE:
			if Vector2(x - 20, (y - 19) * 1.4).length() < 7.5:
				c.set_tile(x, y, 2, Surface.Type.WATER)
	return c


## A path from the west bank over the pond to the east bank along row 19 (a bridge where it
## crosses water), and a two-tile wide bridge up the pond along x = 17 to 18 from the south bank.
static func lay_bridges(b: CourseBuilder) -> void:
	b.begin_stroke()
	for x: int in range(9, 32):
		b.paint(Vector2i(x, 19), Surface.Type.CART_PATH, 1)
	b.end_stroke()
	b.begin_stroke()
	for y: int in range(20, 28):
		b.paint(Vector2i(17, y), Surface.Type.CART_PATH, 1)
	b.end_stroke()


## E14-S2: a par 3 south of the pond so guests come out, then six of them stood along two routes.
func _stage_walks(b: CourseBuilder) -> void:
	for y: int in range(31, 36):
		for x: int in range(28, 33):
			b.paint(Vector2i(x, y), Surface.Type.GREEN, 1)
	b.place_tee(1, Vector2i(6, 33), 3)
	b.place_cup(1, Vector2i(30, 33))
	b.move_clubhouse_beside(Vector2i(6, 33))
	var sim: GuestSim = _main.guest_sim
	while sim.brain == null or sim.brain.guests.size() < 6:
		sim.advance(1.0)
	sim.set_speed(0.0)
	var tuning := GuestTuning.load_default()
	var c: CourseData = b.course
	var walks: Array[GuestWalk] = [
		GuestWalk.route(c, Vector2(42.5, 97.5), Vector2(162.5, 97.5), tuning),
		GuestWalk.route(c, Vector2(97.5, 52.5), Vector2(147.5, 142.5), tuning),
	]
	for i: int in 6:
		var w: GuestWalk = walks[i / 3]
		var g: Guest = sim.brain.guests[i]
		g.position = w.point_at_time(w.duration * [0.2, 0.45, 0.7][i % 3])
		g.walk = null
		g.state = Guest.State.WAITING
		g.place = 0
	_main.guest_view.clear()
	_main.set_process(false)
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = Color8(240, 236, 224)
	for w: GuestWalk in walks:
		var l := line.duplicate() as Line2D
		for k: int in 81:
			var p: Vector2 = w.point_at_time(w.duration * k / 80.0) / 5.0 - Vector2(0.5, 0.5)
			l.add_point(Iso.tile_to_screen(p, TerrainMesh.ground_at(c, p)))
		l.z_index = 5
		_main.course_view.add_child(l)
