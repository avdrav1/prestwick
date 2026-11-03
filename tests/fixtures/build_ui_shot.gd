class_name BuildUiShot
extends Node2D
## Screenshot fixture for E1-S5: the main scene in Build mode after a few builder edits
## (a raised green mound, a dragged cart path, a bunker), with the 3x3 brush hovering on the
## pyramid. Run: scripts/screenshot.sh tests/fixtures/build_ui_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _main: Main


func _ready() -> void:
	_main = MAIN_SCENE.instantiate() as Main
	_main.course_path = "res://courses/heights_20x20.json"
	add_child(_main)
	var tool: BuildTool = _main.build_tool
	tool.brush_size = 3
	tool.select_tool(BuildTool.Tool.RAISE)
	for n: int in 3:
		tool.press_at(_at(Vector2i(14, 14)))
		tool.release()
	tool.select_surface(Surface.Type.GREEN)
	tool.press_at(_at(Vector2i(14, 14)))
	tool.release()
	tool.brush_size = 1
	tool.select_surface(Surface.Type.CART_PATH)
	tool.press_at(_at(Vector2i(8, 10)))
	for x: int in range(9, 14):
		tool.drag_to(_at(Vector2i(x, 10)))
	tool.release()
	tool.select_surface(Surface.Type.BUNKER)
	tool.brush_size = 3
	tool.press_at(_at(Vector2i(11, 17)))
	tool.release()
	tool.hover_at(_at(Vector2i(3, 3)))


func _at(cell: Vector2i) -> Vector2:
	return Iso.tile_to_screen(Vector2(cell), _main.course.get_height(cell.x, cell.y))
