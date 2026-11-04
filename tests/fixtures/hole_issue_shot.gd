class_name HoleIssueShot
extends Node2D
## Screenshot fixture for E2-S3: a new sandbox with hole 1 placed through the tee and cup
## tools and failing three rules: a water wall across its line (rule 3), the cup on rough
## (rule 2) and par 4 on a 150 yd hole (rule 4). Each is highlighted on its tile, and the hole
## panel lists them with Open disabled. Run: scripts/screenshot.sh tests/fixtures/hole_issue_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _main: Main


func _ready() -> void:
	_main = MAIN_SCENE.instantiate() as Main
	# A small startup course: with no course_path main would generate 128 x 128 land first,
	# only for it to be replaced (E6-S22).
	_main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(_main)
	_main.new_sandbox()
	var tool: BuildTool = _main.build_tool
	tool.select_par(4)
	tool.select_tool(BuildTool.Tool.TEE)
	_click(Vector2i(40, 64))
	tool.select_tool(BuildTool.Tool.CUP)
	_click(Vector2i(70, 64))
	tool.select_surface(Surface.Type.WATER)
	tool.brush_size = 1
	tool.press_at(_at(Vector2i(55, 0)))
	tool.drag_to(_at(Vector2i(55, 127)))
	tool.release()
	tool.select_surface(Surface.Type.OOB)
	tool.brush_size = 3
	_click(Vector2i(48, 70))
	tool.select_tool(BuildTool.Tool.CUP)
	tool.hover_at(_at(Vector2i(62, 60)))
	_main.camera.set_zoom_index(1)
	_main.camera.position = Iso.tile_to_screen(Vector2(58, 64), 2)


func _click(cell: Vector2i) -> void:
	_main.build_tool.press_at(_at(cell))
	_main.build_tool.release()


func _at(cell: Vector2i) -> Vector2:
	return Iso.tile_to_screen(Vector2(cell), _main.course.get_height(cell.x, cell.y)) + Vector2(0.5, 0.5)
