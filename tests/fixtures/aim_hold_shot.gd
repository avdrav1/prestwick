class_name AimHoldShot
extends Node2D
## Frame-sequence fixture for E10-S2: Play on hole 6 of courses/playtest_nine.json, with the
## hold box drawn as a thin outline. It steps Play by hand at 60 Hz (as tests/test_play_camera.gd
## does) and saves a frame at each stage: framed; after thirty 3 px mouse nudges (the camera
## has not moved); a quarter turn of the aim, 6 frames into the glide; and settled with the
## marker back in the box. First at the zoom the aim framing picks (0.5x), then one press of
## the zoom-in key nearer (1x). Needs a window:
##   godot --path . res://tests/fixtures/aim_hold_shot.tscn -- --out=docs/decisions/e10-s2
## writes <out>-0.5x-1-framed.png and so on, and quits.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DT: float = 1.0 / 60.0

var _main: Main
var _box: Control


func _ready() -> void:
	var out: String = "user://e10-s2"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	_main = MAIN_SCENE.instantiate() as Main
	_main.course_path = "res://courses/playtest_nine.json"
	add_child(_main)
	_main.frame_hole(6)
	_main.set_mode(Main.Mode.PLAY)
	_main.guest_sim.set_process(false)
	_main.set_process(false)
	_main.camera.set_process(false)
	_main.swing_control.set_process(false)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_box = Control.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.draw.connect(_draw_box)
	layer.add_child(_box)
	for zoom_ins: int in [0, 1]:
		for i: int in zoom_ins:
			_main.camera.step_zoom(1)
		_frames(300)
		var tag: String = "%s-%sx" % [out, str(_main.camera.zoom.x)]
		await _save(tag + "-1-framed.png")
		var start: Vector2 = _main.camera.screen_point(_main.camera.held_lead())
		for i: int in 15:
			_mouse_at(start + Vector2(0, 3 * i))
			_frames(1)
		for i: int in 15:
			_mouse_at(start + Vector2(0, 45 - 3 * i))
			_frames(1)
		await _save(tag + "-2-nudged.png")
		var sc: SwingControl = _main.swing_control
		sc.aim_at(sc.ball_at + Vector2.from_angle(deg_to_rad(sc.aim_deg + 90.0)) * 100.0)
		_frames(6)
		await _save(tag + "-3-gliding.png")
		_frames(300)
		await _save(tag + "-4-settled.png")
		sc.aim_at(sc.ball_at + Vector2.from_angle(deg_to_rad(sc.aim_deg - 90.0)) * 100.0)
	get_tree().quit()


func _frames(n: int) -> void:
	for i: int in n:
		_main.swing_control._process(DT)
		_main._process(DT)
		_main.camera._process(DT)


func _mouse_at(px: Vector2) -> void:
	var cam: CourseCamera = _main.camera
	var world: Vector2 = cam.position + (px - cam.view_size() * 0.5) / cam.zoom.x
	var local: Vector2 = _main.swing_control.to_local(cam.get_parent().to_global(world))
	_main.swing_control.aim_at(_main.swing_control._ground_under(local))


func _save(path: String) -> void:
	_box.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var err: int = get_viewport().get_texture().get_image().save_png(path)
	print("saved %s (%d)" % [path, err])


func _draw_box() -> void:
	_box.draw_rect(_main.camera.hold_box(), Color(1, 1, 1, 0.6), false, 1.0)
