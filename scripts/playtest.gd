extends SceneTree
## The /playtest smoke run, used by /ship-it. Run it with scripts/playtest.sh, which runs
## Godot headless at a fixed 60 fps so every frame is exactly one ball tick.
##
## It drives the real main scene the way a player would and asserts only what the
## milestones built so far can do. The full bar in .claude/skills/playtest/SKILL.md grows
## one stage per milestone; the epic that builds a stage adds its check here and raises
## BUILT_MILESTONE:
##
##   E1 Ball on a tile   switch to Play, fire the debug shot, it lands on the course where
##                       the prediction said, and comes to rest on the course.   (here)
##   E2 One hole         load courses/example_par3.json, play the hole with a scripted
##                       swing, the ball holes out.
##   E3 Guests           spawn one guest, it plays and leaves a reaction.
##   E4 Economy          run one in-game day, it ends with money changed.
##
## Exit code 0 when every check passes, 1 when one fails. Prints one line per check.

## The last milestone whose smoke stage exists in this script.
const BUILT_MILESTONE: int = 1
const MAIN_SCENE := "res://scenes/main.tscn"
## What each stage expects, from docs/design.md. Kept as data so the numbers are not
## literals here, and so a silent fallback course or a physics change fails the smoke.
const EXPECT_PATH := "res://data/playtest_smoke.json"
## Frames to wait for the shot to finish: the ball's own 3600-tick cap plus a margin.
const MAX_FRAMES: int = 4000

enum Phase { START, FLYING, DONE }

var _main: Main
var _phase: Phase = Phase.START
var _frames: int = 0
var _failures: int = 0
var _landed_at: Variant = null
var _rest_at: Variant = null
var _expect: Dictionary = {}


func _initialize() -> void:
	print("playtest smoke: milestone E%d stages" % BUILT_MILESTONE)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECT_PATH))
	if not parsed is Dictionary or not (parsed as Dictionary).get("e1") is Dictionary:
		_fail("expectations load (%s)" % EXPECT_PATH)
		_finish()
		return
	_expect = (parsed as Dictionary)["e1"]
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("main scene loads (%s)" % MAIN_SCENE)
		_finish()
		return
	_main = packed.instantiate() as Main
	root.add_child(_main)


func _process(_delta: float) -> bool:
	match _phase:
		Phase.START:
			_start_shot()
		Phase.FLYING:
			_frames += 1
			if not _main.shot_view.playing or _frames >= MAX_FRAMES:
				_check_shot()
				_finish()
	return false


# --- E1: fire a shot and land it ---

func _start_shot() -> void:
	_check(_main.course != null, "main scene shows a course")
	if _main.course == null:
		_finish()
		return
	var course := _main.course
	var size := _vec2i(_expect["course_size"])
	var start := _vec2i(_expect["start_tile"])
	_check(Vector2i(course.width, course.height) == size
			and course.get_height(start.x, start.y) == int(_expect["start_height"]),
			"the course is %s (%dx%d, height %d at %s)" % [_expect["course_path"], size.x,
			size.y, int(_expect["start_height"]), start])
	_main.set_mode(Main.Mode.PLAY)
	_check(_main.mode == Main.Mode.PLAY, "switches to Play")
	_check(_main.fire_button.visible, "the fire button shows in Play")
	_main.shot_view.landed.connect(func(at: Vector3) -> void: _landed_at = at)
	_main.shot_view.came_to_rest.connect(func(at: Vector3) -> void: _rest_at = at)
	_main.fire_button.pressed.emit()
	_check(_main.shot_view.playing, "the fire button launches a ball")
	if not _main.shot_view.playing:
		_finish()
		return
	_phase = Phase.FLYING


func _check_shot() -> void:
	var view := _main.shot_view
	_check(not view.playing, "the ball comes to rest within %d frames" % MAX_FRAMES)
	_check(_landed_at != null, "the ball lands")
	_check(_rest_at != null, "the ball reports where it rests")
	if _landed_at == null or _rest_at == null:
		return
	var course := _main.course
	var field := view.ball.field
	var landed: Vector3 = _landed_at
	var rest: Vector3 = _rest_at
	var land_tile := field.tile_at(landed.x, landed.y)
	var rest_tile := field.tile_at(rest.x, rest.y)
	_check(course.in_bounds(land_tile.x, land_tile.y),
			"it lands on the course, tile %s" % land_tile)
	_check(absf(landed.z - field.height_at(landed.x, landed.y)) < 0.01,
			"it lands on the ground, not in the air")
	_check(land_tile == view.prediction.landing_tile,
			"it lands on the predicted tile %s" % view.prediction.landing_tile)
	_check(course.in_bounds(rest_tile.x, rest_tile.y),
			"it comes to rest on the course, tile %s" % rest_tile)
	_check(rest_tile == view.prediction.rest_tile,
			"it rests on the predicted tile %s" % view.prediction.rest_tile)
	var want_land := _vec2i(_expect["landing_tile"])
	var want_rest := _vec2i(_expect["rest_tile"])
	_check(land_tile == want_land, "it lands where design.md says, tile %s" % want_land)
	_check(rest_tile == want_rest, "it rests where design.md says, tile %s" % want_rest)
	print("  shot: %d ticks in %d frames" % [view.ball.steps, _frames])


# --- reporting ---

func _vec2i(pair: Variant) -> Vector2i:
	var a: Array = pair
	return Vector2i(int(a[0]), int(a[1]))


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _fail(what: String) -> void:
	_check(false, what)


func _finish() -> void:
	if _phase == Phase.DONE:
		return
	_phase = Phase.DONE
	if _failures == 0:
		print("playtest smoke: PASS")
	else:
		print("playtest smoke: FAIL (%d)" % _failures)
	if _main != null:
		_main.queue_free()
	quit(0 if _failures == 0 else 1)
