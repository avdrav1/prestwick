extends Node
## Screenshot fixture for E6-S2: main in Build on generated land (course/land_generator.gd).
##
##   LAND_SEED=7 scripts/screenshot.sh tests/fixtures/land_shot.tscn out.png
##   LAND_ZOOM=0.5|1|2 picks a camera zoom step (default 0.5, the whole map in view);
##   LAND_FOCUS=block centres the camera on the starting block's centre tile, LAND_FOCUS=x,y on
##   tile (x, y).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _main: Main


func _ready() -> void:
	var land_seed: int = 1
	if not OS.get_environment("LAND_SEED").is_empty():
		land_seed = OS.get_environment("LAND_SEED").to_int()
	_main = MAIN_SCENE.instantiate() as Main
	# A small startup course: with no course_path main would generate 128 x 128 land first,
	# only for it to be replaced (E6-S22).
	_main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(_main)
	var c := LandGenerator.generate(land_seed)
	_main.show_course(c)
	var zoom := OS.get_environment("LAND_ZOOM")
	var levels: PackedFloat32Array = _main.camera.tuning.zoom_levels
	var index: int = levels.find(0.5 if zoom.is_empty() else zoom.to_float())
	if index >= 0:
		_main.camera.set_zoom_index(index)
	var focus := OS.get_environment("LAND_FOCUS")
	if not focus.is_empty():
		var mid: Vector2i = LandGenerator.start_block(c.width, c.height).get_center()
		if focus != "block":
			var parts := focus.split(",")
			mid = Vector2i(parts[0].to_int(), parts[1].to_int())
		_main.camera.position = Iso.tile_to_screen(Vector2(mid), c.get_height(mid.x, mid.y))
		_main.camera.tracking = false
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(200, 12)
	label.text = "Generated land, seed %d (%dx%d)" % [land_seed, c.width, c.height]
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)
	add_child(layer)
