extends Node
## Screenshot fixture for E1-S9 (D4, D5): main in Play on one of the GridHeightEvidence
## courses, with several predicted ball paths drawn over the map and the live ball frozen at
## a chosen point of one shot. The overlay is drawn on top of everything (not depth sorted);
## the ball and its shadow are the real ShotView.
##
##   EVIDENCE_CASE=green scripts/screenshot.sh tests/fixtures/grid_height_shot.tscn out.png
##   EVIDENCE_CASE=hill  ...       EVIDENCE_CASE=riser ...   (2x close-up of a hillside landing)
##   EVIDENCE_ZOOM=0.5|1|2 picks a camera zoom step for any case (E1-S10 edge cues).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const COLORS: Array[Color] = [
	Color8(216, 58, 58), Color8(64, 112, 216), Color8(240, 200, 64), Color8(200, 96, 216),
	Color8(64, 200, 216),
]

var _main: Main
var _overlay: _Overlay


func _ready() -> void:
	var case_name := OS.get_environment("EVIDENCE_CASE")
	if case_name.is_empty():
		case_name = "green"
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	_main.set_mode(Main.Mode.PLAY)
	_overlay = _Overlay.new()
	_overlay.z_index = 100
	match case_name:
		"green":
			_green(false)
		"green_mirrored":
			_green(true)
		"hill":
			_hill(false, 1)
		"hill_mirrored":
			_hill(true, 1)
		"riser":
			_hill(true, 2)
		"steps":
			_steps()
		_:
			push_error("grid_height_shot: unknown EVIDENCE_CASE %s" % case_name)
	_main.course_view.add_child(_overlay)
	_apply_zoom(OS.get_environment("EVIDENCE_ZOOM"))
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(200, 12)
	label.text = _overlay.caption
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)
	add_child(layer)


func _yd(tile: Vector2) -> Vector3:
	var p := (tile + Vector2(0.5, 0.5)) * 5.0
	return Vector3(p.x, p.y, 0.0)


func _green(mirrored: bool) -> void:
	var c := GridHeightEvidence.green_contour(mirrored)
	_main.show_course(c)
	var dir := -1.0 if mirrored else 1.0
	var putts: Array = [
		["uphill 9 yd/s: rolls back", Vector2(4.5, 5.5) if not mirrored else Vector2(10.5, 5.5), Vector2(9 * dir, 0)],
		["uphill 11 yd/s: climbs one tier", Vector2(4.5, 6.5) if not mirrored else Vector2(10.5, 6.5), Vector2(11 * dir, 0)],
		["downhill 5 yd/s: drops a tier", Vector2(10.5, 4.5) if not mirrored else Vector2(4.5, 4.5), Vector2(-5 * dir, 0)],
		["sidehill 3 yd/s: falls off the band", Vector2(5.5, 2.5) if not mirrored else Vector2(9.5, 2.5), Vector2(0, 3)],
	]
	var lines: PackedStringArray = ["Green, 3-step contour (tiers 2 tiles deep, rising %s). Putt paths:" % [
		"towards the camera" if mirrored else "away from the camera"]]
	for i: int in putts.size():
		var ball := Ball.new(c, 1)
		ball.record_path = true
		var from: Vector3 = _yd(putts[i][1])
		ball.start_roll(Vector2(from.x, from.y), putts[i][2])
		ball.run_to_rest()
		_overlay.add_path(ball.field, ball.path, COLORS[i])
		lines.append("  %s" % putts[i][0])
	# Live ball: a chip from the fairway onto the front tiers, frozen at rest.
	var field := HeightField.new(c, BallParams.load_default())
	var start := _yd(Vector2(1, 8))
	start.z = field.height_at(start.x, start.y)
	_fire(c, start, Ball.launch_velocity(14.0, 40.0, -15.0), 2.0)
	lines.append("  ball + red X: a chip from the fairway (14 yd/s, 40 deg), at rest")
	_overlay.caption = "\n".join(lines)


## The hillside, or its mirror along x (rising towards the camera, risers in view). Shots are
## mirrored with it. The live ball is frozen at its first touchdown.
func _hill(mirrored: bool, zoom_index: int) -> void:
	var c := GridHeightEvidence.hillside(mirrored)
	_main.show_course(c)
	var field := HeightField.new(c, BallParams.load_default())
	var shots: Array = [
		["up, 1 step / 2 tiles", Vector2(1, 3), 0.0],
		["down, 1 step / 2 tiles", Vector2(25, 2), 180.0],
		["down, 1 step / tile", Vector2(25, 9), 180.0],
	]
	var lines: PackedStringArray = ["Hillside 0 to 7, rising %s. Shot paths (25 yd/s, 30 deg):" % [
		"towards the camera" if mirrored else "away from the camera"]]
	for i: int in shots.size():
		var start := _yd(_mirror(shots[i][1], mirrored))
		start.z = field.height_at(start.x, start.y)
		var heading: float = 180.0 - shots[i][2] if mirrored else shots[i][2]
		var p := ShotPrediction.run(c, 1, start, Ball.launch_velocity(25.0, 30.0, heading))
		_overlay.add_path(field, p.path, COLORS[i])
		lines.append("  %s: lands %s, rests %s" % [shots[i][0], p.landing_tile, p.rest_tile])
	var start := _yd(_mirror(Vector2(4, 8), mirrored))
	start.z = field.height_at(start.x, start.y)
	var shot := _fire(c, start, Ball.launch_velocity(25.0, 30.0, 180.0 if mirrored else 0.0), 1.0)
	lines.append("  ball: up, 1 step / tile, frozen at its first touchdown %s (z %.1f steps)" % [
		shot.landing_tile, shot.landing.z / 2.0])
	_overlay.caption = "\n".join(lines)
	if zoom_index != _main.camera.zoom_index:
		_main.camera.set_zoom_index(zoom_index)
		_main.camera.position = Iso.point_to_screen(field.iso_point(shot.landing))


## E1-S10: rises of 1, 2, 3 and 1 steps facing away from the camera, on green, fairway,
## bunker and rough, so a 1-step cue (one lip line) sits next to 2+-step cues (two lines).
func _steps() -> void:
	var c := CourseData.create(12, 12, Surface.Type.ROUGH, 0)
	var strips: Array = [[1, Surface.Type.GREEN], [2, Surface.Type.FAIRWAY], [3, Surface.Type.BUNKER],
			[1, Surface.Type.ROUGH]]
	for i: int in strips.size():
		for y: int in range(1 + i * 3, 3 + i * 3):
			for x: int in range(4, 10):
				c.set_tile(x, y, strips[i][0], strips[i][1])
	_main.show_course(c)
	_overlay.caption = "Edge cues, back to front: rises of 1 (green), 2 (fairway), 3 (bunker), 1 (rough) step"


## Sets the camera to the zoom step `zoom` (such as "0.5") and keeps its centre.
func _apply_zoom(zoom: String) -> void:
	if zoom.is_empty():
		return
	var levels: PackedFloat32Array = _main.camera.tuning.zoom_levels
	var index: int = levels.find(zoom.to_float())
	if index < 0:
		push_error("grid_height_shot: EVIDENCE_ZOOM %s is not one of %s" % [zoom, levels])
		return
	_main.camera.set_zoom_index(index)
	_overlay.caption += "\nzoom %sx" % zoom


func _mirror(tile: Vector2, mirrored: bool) -> Vector2:
	return Vector2(GridHeightEvidence.HILL_W - 1 - tile.x, tile.y) if mirrored else tile


## Fires the live ball and freezes it `share` of the way to its landing (1.0 = at touchdown);
## a share above 1 plays it to rest.
func _fire(c: CourseData, start: Vector3, v: Vector3, share: float) -> ShotPrediction:
	var view := _main.shot_view
	view.fire(c, start, v, 1)
	view.set_process(false)
	var ticks := view.prediction.ticks
	if share <= 1.0:
		var to_landing := 0
		for p: Vector3 in view.prediction.path:
			to_landing += 1
			if p == view.prediction.landing:
				break
		ticks = roundi(to_landing * share)
	view.advance(ticks / float(Ball.TICK_HZ))
	print("grid height shot: tick %d of %d, ball %s, landing %s tile %s, rest tile %s" % [
		view.ball.steps, view.prediction.ticks, view.ball.position, view.prediction.landing,
		view.prediction.landing_tile, view.prediction.rest_tile])
	return view.prediction


## Ball paths drawn over the map: the ball line in colour, its ground track in dark dots.
class _Overlay extends Node2D:
	var caption: String = ""
	var _paths: Array = []

	func add_path(field: HeightField, path: PackedVector3Array, color: Color) -> void:
		var air := PackedVector2Array()
		var ground := PackedVector2Array()
		for p: Vector3 in path:
			air.append(Iso.point_to_screen(field.iso_point(p)))
			ground.append(Iso.point_to_screen(field.iso_point(
					Vector3(p.x, p.y, field.height_at(p.x, p.y)))))
		_paths.append([air, ground, color])
		queue_redraw()

	func _draw() -> void:
		for entry: Array in _paths:
			var ground: PackedVector2Array = entry[1]
			for i: int in range(0, ground.size(), 4):
				draw_circle(ground[i], 1.2, Color(0.1, 0.1, 0.13, 0.8))
			draw_polyline(entry[0], Color.BLACK, 4.0)
			draw_polyline(entry[0], entry[2], 2.0)
			draw_circle(entry[0][entry[0].size() - 1], 4.0, entry[2])
