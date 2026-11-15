class_name ShapeShot
extends Node2D
## Screenshot fixture for E20-S1 (D74): a shaped drive's curved aim on a Dogleg Hollow corner
## hole in Play. SHAPE_HOLE (default 2, Willow Pond, right round the pond) is played from its
## tee with the driver, aimed SHAPE_AIM degrees (default 11) right of the tee-to-turn line, at
## the trees past the corner, with the shot shape SHAPE_ID (default fade; "straight" for the
## same aim flown straight). SHAPE_ZOOM (0.5 or 1) centres between tee and landing at that zoom; unset, Play frames it. SHAPE_SWING=1 freezes a swing at 90%
## after click 2 so the live landing marker shows over the faded 100% one.
##   SHAPE_ID=straight scripts/screenshot.sh tests/fixtures/shape_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = DoglegHollow.PATH
	add_child(main)
	var n := _env_int("SHAPE_HOLE", 2)
	var k := _env_float("SHAPE_AIM", 11.0)
	var id := OS.get_environment("SHAPE_ID")
	if id == "":
		id = "fade"
	main.play_hole(n)
	var sc := main.swing_control
	sc.set_process(false)
	sc.select_club(sc.model.clubs.club("driver"))
	sc.select_shape(sc.model.shapes.shape(id))
	var turn: Variant = GuestHole.turn_of(main.course, sc.hole)
	var to: Vector2 = (turn as Vector2) - sc.ball_at
	sc.aim_deg = fposmod(rad_to_deg(to.angle()) + k, 360.0)
	sc._refresh_aim()
	if OS.get_environment("SHAPE_SWING") == "1":
		sc.press()
		sc.advance(0.9 / sc.swing.rate())
		sc.press()
	main.swing_panel.refresh()
	main.swing_panel.hint_panel.visible = false  # the first-swing hint is E10-S3's, not this shot's
	var p := sc.aim_prediction
	print("shape shot: hole %d %s aim %+.0f: landing %s rest %s (%s), scattered %s" % [n, id, k,
			p.landing, p.rest, Surface.Type.keys()[sc.field.surface_at(p.rest.x, p.rest.y)],
			p.scattered])
	var zs := OS.get_environment("SHAPE_ZOOM")
	if zs == "":
		return  # Play's own framing of the tee and the marker
	main.camera.set_zoom_level(zs.to_float())
	var land := main.tile_world(sc.field.tile_at(p.landing.x, p.landing.y))
	var at: Vector2 = main.tile_world(sc.hole.tee).lerp(land, _env_float("SHAPE_AT", 0.5))
	# The free view above the swing panel: its middle sits SHAPE_LIFT px (default 70) above the
	# window's. The camera stops tracking the aim so it stays put.
	var lift := _env_float("SHAPE_LIFT", 70.0)
	main.camera.tracking = false
	main.camera.position = at + Vector2(0.0, lift) / main.camera.zoom.x


static func _env_int(name: String, fallback: int) -> int:
	var s := OS.get_environment(name)
	return s.to_int() if s != "" else fallback


static func _env_float(name: String, fallback: float) -> float:
	var s := OS.get_environment(name)
	return s.to_float() if s != "" else fallback
