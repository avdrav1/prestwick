extends Node
## Screenshot fixture for E6-S5: main in Build on generated land (seed LAND_SEED, default 1)
## owning only the starting block with $5,000, so owned, buyable and out-of-reach parcels show.
##
##   LAND_SHOT=<case> scripts/screenshot.sh tests/fixtures/land_buy_shot.tscn out.png
##   buyable  the Buy land tool hovering the parcel west of the block (the default)
##   far      the Buy land tool hovering a parcel out of reach
##   confirm  after a click on the buyable parcel, the cursor moved on: the confirm, the
##            parcel still outlined in yellow; since E6-S17 the confirm floats by the
##            clicked tile and names the parcel "NW parcel, 130 yd out"; at LAND_ZOOM=1
##            the tile is under the land panel, so the confirm drops below it, clear of the HUD
##   bought   after confirming it: the line has moved and the budget dropped; since E6-S17
##            the hovered parcel, now owned, is outlined in pale ink, not red
##   refused  Raise clicked on unowned land: the hint and the "not your land" message
##   LAND_ZOOM=0.5|1|2 picks a camera zoom step (default 0.5).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const BLOCK: Rect2i = Rect2i(3, 3, 2, 2)
const BUYABLE := Vector2i(2, 3)
const FAR := Vector2i(1, 2)

var _main: Main


func _ready() -> void:
	var land_seed: int = 1
	if not OS.get_environment("LAND_SEED").is_empty():
		land_seed = OS.get_environment("LAND_SEED").to_int()
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	var c := LandGenerator.generate(land_seed)
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), BLOCK.has_point(Vector2i(p, q)))
	c.set_land_budget(LandPrices.load_default().land_budget)
	_main.show_course(c)
	var zoom := OS.get_environment("LAND_ZOOM")
	var index: int = _main.camera.tuning.zoom_levels.find(0.5 if zoom.is_empty() else zoom.to_float())
	if index >= 0:
		_main.camera.set_zoom_index(index)
	var focus := Vector2i(48, 56)
	_main.camera.position = Iso.tile_to_screen(Vector2(focus), c.get_height(focus.x, focus.y))
	_main.camera.tracking = false
	var tool: BuildTool = _main.build_tool
	var shot := OS.get_environment("LAND_SHOT")
	match shot:
		"far":
			tool.select_tool(BuildTool.Tool.BUY)
			tool.hover_at(_at(FAR * 16 + Vector2i(8, 8)))
		"confirm", "bought":
			tool.select_tool(BuildTool.Tool.BUY)
			tool.press_at(_at(BUYABLE * 16 + Vector2i(8, 8)))
			tool.release()
			if shot == "bought":
				_main.land_panel.confirm_buy()
				tool.hover_at(_at(BUYABLE * 16 + Vector2i(8, 8)))
			else:
				# The cursor has moved on toward the confirm: the pending parcel stays pinned.
				tool.hover_at(_at(FAR * 16 + Vector2i(8, 8)))
		"refused":
			tool.select_tool(BuildTool.Tool.RAISE)
			tool.brush_size = 3
			tool.press_at(_at(Vector2i(42, 56)))
			tool.release()
		_:
			tool.select_tool(BuildTool.Tool.BUY)
			tool.hover_at(_at(BUYABLE * 16 + Vector2i(8, 8)))
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(220, 12)
	label.text = "E6-S5 land, seed %d: %s" % [land_seed, "buyable" if shot.is_empty() else shot]
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)
	add_child(layer)


func _at(cell: Vector2i) -> Vector2:
	return Iso.tile_to_screen(Vector2(cell), _main.course.get_height(cell.x, cell.y))
