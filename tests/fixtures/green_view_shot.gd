class_name GreenViewShot
extends Node2D
## Screenshot fixture for E3-S52 (D48): the main scene in Play with the player's ball at rest on
## a green, the putter aimed at the cup and its solve settled, so the overhead green view is
## open. `kind` picks the green: "flat", "contoured" (a tilt falling toward the front right, in
## whole steps) or "tiered" (a back tier two steps over a middle tier, one step over the front).
## The greens are built through CourseBuilder on a 40 x 32 plot of rough at height 2;
## tests/test_green_view.gd uses the same courses.
##
## Run: scripts/screenshot.sh tests/fixtures/green_view_shot_flat.tscn (and _contoured, _tiered)

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH: String = "res://tests/fixtures/flat_20x20.json"
## The green's tiles, before its corners are cut.
const GREEN := Rect2i(18, 10, 9, 10)

@export var kind: String = "flat"
## Grayscale: the whole screen drawn in luminance only (the colorblind check).
@export var gray: bool = false


func _ready() -> void:
	var made := course(kind)
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = FLAT_PATH
	add_child(main)
	main.show_course(made.course)
	main.set_mode(Main.Mode.PLAY)
	var sc := main.swing_control
	sc.set_process(false)
	sc.place_ball(made.ball)
	sc.aim_at(sc.field.tile_center(made.cup))
	sc._refresh_aim()
	sc.settle_aim()
	main.swing_panel.refresh()
	if gray:
		var layer := CanvasLayer.new()
		layer.layer = 10
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform sampler2D screen: hint_screen_texture;\nvoid fragment() {\n\tvec3 c = texture(screen, SCREEN_UV).rgb;\n\tfloat l = dot(c, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(l, l, l, 1.0);\n}\n"
		mat.shader = sh
		rect.material = mat
		layer.add_child(rect)
		add_child(layer)
	print("green view %s: power %.2f, miss %.2f yd" % [kind, sc.aim_power, sc.aim_putt.miss_yd])


## The fixture course of `kind` with hole 1 on it: {course, ball (yards), cup (tile)}.
static func course(p_kind: String) -> Dictionary:
	var c := CourseData.create(40, 32, Surface.Type.ROUGH, 2)
	var b := CourseBuilder.new(c)
	var heights := {}
	for y: int in range(GREEN.position.y - 3, GREEN.end.y + 3):
		for x: int in range(GREEN.position.x - 3, GREEN.end.x + 3):
			heights[Vector2i(x, y)] = _height(p_kind, Vector2i(x, y))
	for level: int in range(3, 8):
		b.begin_stroke()
		for cell: Vector2i in heights:
			if heights[cell] >= level:
				b.raise(cell, 1)
		b.end_stroke()
	b.begin_stroke()
	for y: int in range(12, 20):
		for x: int in range(6, 18):
			b.paint(Vector2i(x, y), Surface.Type.FAIRWAY, 1)
	for y: int in range(GREEN.position.y, GREEN.end.y):
		for x: int in range(GREEN.position.x, GREEN.end.x):
			var corner_x := x == GREEN.position.x or x == GREEN.end.x - 1
			var corner_y := y == GREEN.position.y or y == GREEN.end.y - 1
			if not (corner_x and corner_y):
				b.paint(Vector2i(x, y), Surface.Type.GREEN, 1)
	for cell: Vector2i in [Vector2i(27, 13), Vector2i(28, 13), Vector2i(27, 14), Vector2i(28, 14),
			Vector2i(27, 15), Vector2i(21, 20), Vector2i(22, 20), Vector2i(23, 20), Vector2i(22, 21)]:
		b.paint(cell, Surface.Type.BUNKER, 1)
	for cell: Vector2i in [Vector2i(17, 8), Vector2i(18, 8), Vector2i(19, 7), Vector2i(20, 7)]:
		b.paint(cell, Surface.Type.TREES, 1)
	b.end_stroke()
	var ball := Vector2i(21, 16)
	var cup := Vector2i(24, 12)
	match p_kind:
		"contoured":
			ball = Vector2i(20, 16)
			cup = Vector2i(24, 13)
		"tiered":
			ball = Vector2i(22, 17)
			cup = Vector2i(23, 12)
	b.place_tee(1, Vector2i(5, 15), 4)
	b.place_cup(1, cup, 4)
	var at := (Vector2(ball) + Vector2(0.5, 0.5)) * 5.0
	return {"course": c, "ball": at, "cup": cup}


static func _height(p_kind: String, cell: Vector2i) -> int:
	match p_kind:
		"contoured":
			# Falls toward the front right (+x, +y): one step about every three tiles across
			# the diagonal, with a crown at the back left.
			var h := 2 + clampi(((GREEN.end.x - cell.x) + (GREEN.end.y - cell.y)) / 4, 0, 4)
			if Vector2(cell).distance_to(Vector2(20, 12)) < 1.6:
				h += 1
			return mini(h, 7)
		"tiered":
			if cell.y < 14:
				return 5
			if cell.y < 17:
				return 3
			return 2
	return 2
