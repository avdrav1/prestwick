class_name HazardShot
extends Node2D
## Screenshot fixture for E2-S13: a par 3 to an island green in the main scene, the tee shot
## carried short into the water. `dropped` false captures the ball still drawn where it went
## in (ShotView.showing_hazard); true captures it at its drop, after the show time.
## Run: scripts/screenshot.sh tests/fixtures/hazard_shot_splash.tscn, or
## tests/fixtures/hazard_shot_drop.tscn.
##
## `out_of_bounds` (E6-S13): a par 3 over owned land with the parcel behind the green not
## owned (D29), the 6-iron flown long onto it (E6-S16: 2 tiles past the line; the 3-iron went
## 8), captured in the hold, so the OB cue (a flag_red circle struck through) shows where the
## ball came to rest on unowned land. E6-S16: the land line stays drawn through the hold, so
## the boundary the ball crossed is in frame, and the
## camera is settled on the ball before the capture. `zoom_level` picks the zoom (0.5x, 1x,
## 2x); the cue keeps its size on screen at each.
## Run: scripts/screenshot.sh tests/fixtures/hazard_shot_ob.tscn (2x),
## tests/fixtures/hazard_shot_ob_1x.tscn, tests/fixtures/hazard_shot_ob_0_5x.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH: String = "res://tests/fixtures/flat_20x20.json"

@export var dropped: bool = false
@export var out_of_bounds: bool = false
## The camera zoom for the OB capture (one of CameraTuning.zoom_levels).
@export var zoom_level: float = 2.0


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = FLAT_PATH
	add_child(main)
	main.show_course(long_par3() if out_of_bounds else island_par3())
	main.mode_button.pressed.emit()
	var sc := main.swing_control
	main.shot_view.set_process(false)
	var plan := ScriptedRound.Plan.new()
	plan.club = sc.model.clubs.club("6i" if out_of_bounds else "9i")
	plan.aim_deg = sc.aim_deg
	plan.ticks = ScriptedRound.ticks_for(sc, 1.0)
	ScriptedRound.swing(sc, plan)
	var view := main.shot_view
	while view.playing and not view.ball.is_at_rest():
		view.advance(1.0 / 60.0)
	if dropped:
		while view.playing:
			view.advance(1.0 / 60.0)
	else:
		view.advance(1.0 / 60.0)
	main._process(0.0)
	main.camera.centre_on(main._ball_world(), true)
	if out_of_bounds:
		# After centre_on, which restores 1x.
		main.camera.set_zoom_level(zoom_level)
	# Settle the camera on the ball now (E6-S16): the capture comes before it eases there.
	main.camera.position = main.camera._clamped(main.camera.goal())
	print("hazard shot: hazard %s, showing %s, drawn %s, drop %s" % [view.ball.hazard,
			view.showing_hazard(), view.drawn_position(), view.ball.drop_point])


## A strip 40 x 10: tee at tile 2, fairway, water from tile 16 all round an island green
## (tiles 34 to 38 by rows 2 to 7) with the cup on tile 37.
static func island_par3() -> CourseData:
	var c := CourseData.create(40, 10, Surface.Type.FAIRWAY, 0)
	for y: int in 10:
		for x: int in 40:
			if x >= 34 and x <= 38 and y >= 2 and y <= 7:
				c.set_tile(x, y, 0, Surface.Type.GREEN)
			elif x >= 16:
				c.set_tile(x, y, 0, Surface.Type.WATER)
			elif x <= 3 and y >= 4 and y <= 6:
				c.set_tile(x, y, 0, Surface.Type.TEE)
	c.set_holes([HoleData.new(1, 3, Vector2i(2, 5), Vector2i(37, 5), false)])
	return c


## E6-S13: three parcels along +x (48 x 16 tiles, one parcel deep): tee at tile 2 of row 8,
## fairway, a green on tiles 22 to 27 with the cup on tile 25 (115 yd), all owned, and the
## third parcel (tiles 32 on, from 160 yd) not owned. A fixture writes CourseData directly,
## as tests may (CourseData WRITERS).
static func long_par3() -> CourseData:
	var c := CourseData.create(3 * CourseData.PARCEL_TILES, CourseData.PARCEL_TILES,
			Surface.Type.FAIRWAY, 0)
	for y: int in c.height:
		for x: int in c.width:
			if x >= 22 and x <= 27 and y >= 5 and y <= 10:
				c.set_tile(x, y, 0, Surface.Type.GREEN)
			elif x <= 3 and y >= 7 and y <= 9:
				c.set_tile(x, y, 0, Surface.Type.TEE)
	c.set_parcel_owned(Vector2i(2, 0), false)
	c.set_holes([HoleData.new(1, 3, Vector2i(2, 8), Vector2i(25, 8), false)])
	return c
