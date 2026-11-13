extends Node
## Screenshot fixture for E14-S1 (D69): main in Build over a pond with a footbridge across it,
## the cart path running up to it on both banks, at BRIDGE_ZOOM (default 1).
##
##   BRIDGE_ZOOM=1   scripts/screenshot.sh tests/fixtures/bridge_shot.tscn bridge-1x.png 20
##   BRIDGE_ZOOM=0.5 scripts/screenshot.sh tests/fixtures/bridge_shot.tscn bridge-0.5x.png 20

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SIZE: int = 40

var _main: Main


func _ready() -> void:
	var zoom: float = 1.0 if OS.get_environment("BRIDGE_ZOOM").is_empty() \
			else OS.get_environment("BRIDGE_ZOOM").to_float()
	_main = MAIN_SCENE.instantiate() as Main
	_main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(_main)
	_main.show_course(pond_course())
	var b: CourseBuilder = _main.build_tool.builder
	lay_bridges(b)
	_main.camera.tracking = false
	_main.camera.set_zoom_index(_main.camera.tuning.zoom_levels.find(zoom))
	_main.camera.position = Iso.tile_to_screen(Vector2(20, 19), 2)
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(330, 40)
	label.text = "E14-S1 bridges at %sx: a footbridge across the pond, one corner bridge, path on the banks" % zoom
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
