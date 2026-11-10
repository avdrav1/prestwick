class_name ClubhouseShot
extends Node2D
## Screenshot fixture for E5-S10: the playtest nine's clubhouse (courses/playtest_nine.json) in
## Build, centred at CLUB_ZOOM (0.175, 0.5 or 1; default 0.5). CLUB_HOVER puts the Clubhouse
## tool's outline on a spot: `ok` (an allowed spot beside it), `refused` (across hole 1's line),
## or none. CLUB_FACING turns it first (0 to 3, CourseData.FACINGS). E5-S11: CLUB_DAY=<second>
## plays the day to that second in Play (CLUB_STAGE=1 stands guests round the clubhouse);
## CLUB_AT=x,y moves the clubhouse there first. CLUB_NEW=<seed> shows a New
## course of that land seed instead (its clubhouse in the starting block, Buy land on the bar).
##   CLUB_ZOOM=1 CLUB_HOVER=ok scripts/screenshot.sh tests/fixtures/clubhouse_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## An allowed spot east of the clubhouse, and one across hole 1's line of play (tee (10, 56)).
const OK_SPOT := Vector2i(15, 60)
const REFUSED_SPOT := Vector2i(14, 47)


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = PlaytestNine.PATH
	add_child(main)
	if OS.get_environment("CLUB_NEW") != "":
		main.new_course(OS.get_environment("CLUB_NEW").to_int())
	var c: CourseData = main.course
	var tool: BuildTool = main.build_tool
	var f := OS.get_environment("CLUB_FACING")
	if f != "":
		tool.builder.move_clubhouse(c.clubhouse, f.to_int())
	var to := OS.get_environment("CLUB_AT").split(",")
	if to.size() == 2:
		tool.builder.move_clubhouse(Vector2i(to[0].to_int(), to[1].to_int()), c.clubhouse_facing)
	var zs := OS.get_environment("CLUB_ZOOM")
	main.camera.set_zoom_level(zs.to_float() if zs != "" else 0.5)
	var at: Vector2 = main.tile_world(c.clubhouse + Vector2i(2, 0))
	var free: Rect2 = main.free_view_rect()
	var shift: Vector2 = (main.camera.view_size() * 0.5 - free.get_center()) / main.camera.zoom.x
	main.camera.centre_on(at + shift)
	main.camera.position = at + shift
	if OS.get_environment("CLUB_DAY") != "":
		if OS.get_environment("CLUB_AT") != "":
			# Hold the camera between the door and hole 1's tee, so the walk out shows.
			var mid: Vector2 = (main.tile_world(c.clubhouse_door()) + main.tile_world(c.holes[0].tee)) * 0.5
			main.camera.centre_on(mid + shift)
			main.camera.position = mid + shift
		_day(main, OS.get_environment("CLUB_DAY").to_int())
		return
	match OS.get_environment("CLUB_HOVER"):
		"ok":
			_hover(main, OK_SPOT)
		"refused":
			_hover(main, REFUSED_SPOT)


func _hover(main: Main, cell: Vector2i) -> void:
	var tool: BuildTool = main.build_tool
	tool.select_tool(BuildTool.Tool.CLUBHOUSE)
	tool.hover_at(Iso.tile_to_screen(Vector2(cell), main.course.get_height(cell.x, cell.y)))
	main.land_panel.refresh()


## E5-S11: Play, the day run to second `until` (below 0: until a guest walks home, 3 tiles or
## more from the door) and paused there, the camera held on the
## clubhouse. With CLUB_STAGE=1 four guests are stood round it (a fixture may write guest data):
## behind it (the -x -y side), at its back corner, at its door and in front of it, so the
## picture shows it hiding the ones behind and the ones in front drawn over it.
func _day(main: Main, until: int) -> void:
	var at: Vector2 = main.camera.position
	main.set_mode(Main.Mode.PLAY)
	main.swing_panel.visible = false
	var sim := main.guest_sim
	sim.advance(0.0)
	while sim.brain != null and not sim.brain.day_over and (sim.brain.second < until
			or (until < 0 and not _walking_home(sim.brain))):
		sim.brain.step()
	sim.set_speed(0.0)
	if OS.get_environment("CLUB_STAGE") == "1":
		var c: CourseData = main.course
		var field := sim.brain.field
		var spots: Array[Vector2i] = [c.clubhouse + Vector2i(-2, -1), c.clubhouse + Vector2i(0, -2),
				c.clubhouse_door(), c.clubhouse + Vector2i(1, 3)]
		var guests: Array[Guest] = sim.brain.on_course()
		for i: int in mini(spots.size(), guests.size()):
			var g: Guest = guests[i]
			g.position = field.tile_center(spots[i])
			g.step_from = g.position
			g.walk = null
			g.state = Guest.State.WAITING
			g.place = 0
	main.guest_view.clear()
	main.set_process(false)
	main.aim_view.visible = false
	main.camera.tracking = false
	main.camera.position = at


## True when a guest walking back to the clubhouse is still 3 tiles or more from its door.
func _walking_home(brain: GuestBrain) -> bool:
	for g: GuestGroup in brain.groups:
		if g.phase != GuestGroup.Phase.TO_CLUBHOUSE:
			continue
		for guest: Guest in g.guests:
			if not guest.is_done() and guest.position.distance_to(brain.door()) >= 15.0:
				return true
	return false

