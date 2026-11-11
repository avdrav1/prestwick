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
##                       swing, the ball holes out.                               (here)
##   E3 Guests           Play on courses/example_par3.json at 3x: the day's first guest
##                       arrives, plays hole 1 and leaves a reaction naming it, the same
##                       one a headless GuestBrain of that day's seed gives.     (here)
##   E4 Economy          on the E3 course with a balance, skip the rest of day 1 to the
##                       morning: the day ends with money changed by its fees less its
##                       upkeep, and the morning report shows.                   (here)
##
## Exit code 0 when every check passes, 1 when one fails. Prints one line per check.

## The last milestone whose smoke stage exists in this script.
const BUILT_MILESTONE: int = 4
const MAIN_SCENE := "res://scenes/main.tscn"
## What each stage expects, from docs/design.md. Kept as data so the numbers are not
## literals here, and so a silent fallback course or a physics change fails the smoke.
const EXPECT_PATH := "res://data/playtest_smoke.json"
## Frames to wait for the shot to finish: the ball's own 3600-tick cap plus a margin.
const MAX_FRAMES: int = 4000
## E2: the most strokes the scripted player may take (double par on a par 5).
const MAX_STROKES: int = 10

enum Phase { START, FLYING, E2_START, E2_SWING, E2_FLYING, E3_START, E3_RUN, E4_RUN, DONE }

var _main: Main
var _phase: Phase = Phase.START
var _frames: int = 0
var _failures: int = 0
var _landed_at: Variant = null
var _rest_at: Variant = null
var _expect: Dictionary = {}
var _expect_e2: Dictionary = {}
var _e2_hash: String = ""
var _e2_strokes: int = 0
var _expect_e3: Dictionary = {}
## E3: the first reaction Play gave, with the simulated second it came at, and the guests
## that had arrived by then.
var _e3_reaction: GuestReaction = null
var _e3_second: int = -1
var _e3_arrived: int = 0
var _expect_e4: Dictionary = {}
## E4: when day 1 ended (Main's upkeep already paid): the balance and the day's fees.
var _e4_ended: Array[int] = []


func _initialize() -> void:
	print("playtest smoke: milestone E%d stages" % BUILT_MILESTONE)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECT_PATH))
	if not parsed is Dictionary or not (parsed as Dictionary).get("e1") is Dictionary \
			or not (parsed as Dictionary).get("e2") is Dictionary \
			or not (parsed as Dictionary).get("e3") is Dictionary \
			or not (parsed as Dictionary).get("e4") is Dictionary:
		_fail("expectations load (%s)" % EXPECT_PATH)
		_finish()
		return
	_expect = (parsed as Dictionary)["e1"]
	_expect_e2 = (parsed as Dictionary)["e2"]
	_expect_e3 = (parsed as Dictionary)["e3"]
	_expect_e4 = (parsed as Dictionary)["e4"]
	if not _add_main(_expect["course_path"]):
		_finish()


## A fresh main scene on `course_path`, set before add_child (no load UI is implied).
func _add_main(course_path: String) -> bool:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("main scene loads (%s)" % MAIN_SCENE)
		return false
	_main = packed.instantiate() as Main
	_main.course_path = course_path
	root.add_child(_main)
	return true


func _process(_delta: float) -> bool:
	match _phase:
		Phase.START:
			_start_shot()
		Phase.FLYING:
			_frames += 1
			if not _main.shot_view.playing or _frames >= MAX_FRAMES:
				_check_shot()
				_main.queue_free()
				_main = null
				_phase = Phase.E2_START
		Phase.E2_START:
			_start_hole()
		Phase.E2_SWING:
			_swing()
		Phase.E2_FLYING:
			_frames += 1
			if not _main.shot_view.playing or _frames >= MAX_FRAMES:
				_check(not _main.shot_view.playing,
						"stroke %d comes to rest within %d frames" % [_e2_strokes, MAX_FRAMES])
				_phase = Phase.E2_SWING
		Phase.E3_START:
			_start_guests()
		Phase.E3_RUN:
			_frames += 1
			if _e3_reaction != null or _frames >= _e3_max_frames():
				_check_guests()
				_start_day_end()
		Phase.E4_RUN:
			_frames += 1
			if not _e4_ended.is_empty() or _frames >= int(_expect_e4["max_frames"]):
				_check_day_end()
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
	_check(_main.can_fire_debug_shot(), "the debug key is live in Play")
	_main.shot_view.landed.connect(func(at: Vector3) -> void: _landed_at = at)
	_main.shot_view.came_to_rest.connect(func(at: Vector3) -> void: _rest_at = at)
	_main.fire_debug_shot()
	_check(_main.shot_view.playing, "the debug shot launches a ball")
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
	_check(land_tile == want_land, "it lands where design.md says, tile %s" % want_land)
	# The rest point is checked within a tolerance, not by tile: it lies 0.03 yd from a tile
	# border (E6-S10 review), so a small surface retune must not flip the smoke.
	var rest_list: Array = _expect["rest_yd"]
	var want_rest := Vector2(float(rest_list[0]), float(rest_list[1]))
	var tolerance := float(_expect["rest_tolerance_yd"])
	var off := Vector2(rest.x, rest.y).distance_to(want_rest)
	_check(off <= tolerance, "it rests where design.md says, within %.1f yd of %s (%.2f yd off)" % [
			tolerance, want_rest, off])
	print("  shot: %d ticks in %d frames" % [view.ball.steps, _frames])


# --- E2: play the hole with a scripted swing and hole out ---

func _start_hole() -> void:
	if not _add_main(_expect_e2["course_path"]):
		_finish()
		return
	var course := _main.course
	_check(course != null and course.holes.size() == 1
			and course.holes[0].par == int(_expect_e2["par"]),
			"the course is %s, one par %d" % [_expect_e2["course_path"], int(_expect_e2["par"])])
	if course == null or course.holes.is_empty():
		_finish()
		return
	_e2_hash = course.content_hash()
	# E10-S1: Play hole is enabled once a hole has a tee and a cup.
	_check(not _main.mode_button.disabled, "E2: Play hole is enabled on a course with a hole")
	_main.mode_button.pressed.emit()
	var sc := _main.swing_control
	_check(_main.mode == Main.Mode.PLAY, "one click from Build to Play")
	_check(sc.ball_at == sc.field.tile_center(course.holes[0].tee), "the ball is on the tee")
	_phase = Phase.E2_SWING


func _swing() -> void:
	var sc := _main.swing_control
	if sc.is_finished() or _e2_strokes >= MAX_STROKES:
		_check_hole()
		_main.queue_free()
		_main = null
		_phase = Phase.E3_START
		return
	var plan := ScriptedRound.plan(sc)
	if plan == null:
		_fail("stroke %d can be planned" % (_e2_strokes + 1))
		_finish()
		return
	var from := sc.field.tile_at(sc.ball_at.x, sc.ball_at.y)
	ScriptedRound.swing(sc, plan)
	_e2_strokes += 1
	print("  stroke %d: %s, %d bar ticks, from tile %s" % [_e2_strokes, plan.club.id,
			plan.ticks, from])
	if not _main.shot_view.playing:
		_fail("stroke %d is struck" % _e2_strokes)
		_finish()
		return
	_frames = 0
	_phase = Phase.E2_FLYING


func _check_hole() -> void:
	var sc := _main.swing_control
	var score := sc.score
	_check(score.holed, "the ball holes out")
	_check(score.total() == int(_expect_e2["strokes"]),
			"in %d strokes, as data/playtest_smoke.json says (%d)" % [score.total(),
			int(_expect_e2["strokes"])])
	_check(_main.score_card.strokes_label.text == "Strokes %d" % score.total(),
			"the scorecard shows %d strokes" % score.total())
	_check(_main.score_card.to_par_label.text == "Total %s" % HoleScore.to_par_text(score.to_par()),
			"and the total to par, %s" % HoleScore.to_par_text(score.to_par()))
	_main.mode_button.pressed.emit()
	_check(_main.mode == Main.Mode.BUILD, "one click back to Build")
	_check(_main.course.content_hash() == _e2_hash, "the course is unchanged")


# --- E3: a guest plays and leaves a reaction ---

## Play on the E3 course at the smoke's speed; the guests' day starts with Play (GuestSim).
func _start_guests() -> void:
	if not _add_main(_expect_e3["course_path"]):
		_finish()
		return
	var sim := _main.guest_sim
	# E4: the example course is a version 1 file (unlimited money): give it a balance first.
	_main.build_tool.builder.restore_balance(int(_expect_e4["balance"]))
	sim.day_started.connect(func(_d: int) -> void:
		sim.brain.guest_arrived.connect(func(_g: Guest) -> void: _e3_arrived += 1)
		sim.brain.reacted.connect(func(_g: Guest, r: GuestReaction) -> void:
			if _e3_reaction == null:
				_e3_reaction = r
				_e3_second = sim.brain.second))
	_main.mode_button.pressed.emit()
	_check(_main.mode == Main.Mode.PLAY, "E3: one click to Play on %s" % _expect_e3["course_path"])
	sim.set_speed(float(_expect_e3["speed"]))
	_check(sim.running, "the guests' day runs in Play")
	_frames = 0
	_phase = Phase.E3_RUN


## Frames for `max_sim_s` simulated seconds at the smoke's speed, plus a second's margin.
func _e3_max_frames() -> int:
	return ceili(float(_expect_e3["max_sim_s"]) * 60.0 / float(_expect_e3["speed"])) + 60


func _check_guests() -> void:
	var sim := _main.guest_sim
	_check(_e3_arrived > 0, "a guest arrives at the first tee (%d by then)" % _e3_arrived)
	_check(_e3_reaction != null, "a guest leaves a reaction within %d simulated s (%d frames)" % [
			int(_expect_e3["max_sim_s"]), _frames])
	if _e3_reaction == null:
		return
	var r := _e3_reaction
	print("  reaction: guest %d, second %d, %s: %s" % [r.guest_id, _e3_second, r.kind_name(), r.text])
	var hole := int(_expect_e3["hole"])
	_check(r.hole_number == hole and r.text.begins_with("Hole %d:" % hole),
			"it names hole %d" % hole)
	_check(sim.feed.total >= 1, "the feed holds it")
	# The same seed gives the same day: a headless brain of the day's seed, stepped once a
	# simulated second, gives the same first reaction at the same second. It draws the day's
	# guests by the morning's rating, as the sim did (E4-S5).
	var brain := GuestBrain.new(_main.course, GuestSim.day_seed(sim.base_seed, 1), null, null, [],
			null, sim.day_arrivals)
	# The handler must not hold the brain (a reference cycle through its own signal).
	var first: Array[GuestReaction] = []
	brain.reacted.connect(func(_g: Guest, x: GuestReaction) -> void:
		if first.is_empty():
			first.append(x))
	while first.is_empty() and not brain.day_over:
		brain.step()
	_check(not first.is_empty(), "a headless day of the same seed gives a reaction")
	if first.is_empty():
		return
	var h := first[0]
	var at := brain.second - 1  # the step that gave it played second `at`
	_check(h.guest_id == r.guest_id and h.kind == r.kind and h.text == r.text and at == _e3_second,
			"the same reaction as a headless day of seed %d (guest %d, second %d)" % [
				GuestSim.day_seed(sim.base_seed, 1), h.guest_id, at])


# --- E4: the day ends with money changed ---

## Skips the rest of day 1 to the morning (the speed panel's Morning).
func _start_day_end() -> void:
	var sim := _main.guest_sim
	sim.day_ended.connect(func(_d: int, _b: GuestBrain) -> void:
		if _e4_ended.is_empty():
			_e4_ended.append_array([_main.build_tool.builder.balance(), _main.ledger.fees]))
	_main.sim_speed_panel.skip_button.pressed.emit()
	_check(sim.skipping, "E4: Morning skips the rest of the day")
	_frames = 0
	_phase = Phase.E4_RUN


func _check_day_end() -> void:
	var b := _main.build_tool.builder
	var start := int(_expect_e4["balance"])
	_check(not _e4_ended.is_empty(), "day 1 ends within %d frames (%d)" % [int(_expect_e4["max_frames"]), _frames])
	if _e4_ended.is_empty():
		return
	var open := 0
	for h: HoleData in _main.course.holes:
		open += 1 if h.open else 0
	var upkeep: int = open * b.economy.upkeep_per_open_hole
	var at_end: int = _e4_ended[0]
	var fees: int = _e4_ended[1]
	print("  %s" % _main.ledger.last_line)
	_check(fees > 0 and fees % _main.green_fee() == 0, "guests paid %s at the first tee" % LandPrices.money(fees))
	_check(at_end != start, "the day ends with money changed (%s to %s)" % [
			LandPrices.money(start), LandPrices.money(at_end)])
	_check(at_end == start + fees - upkeep, "by its fees (%s) less its upkeep (%s)" % [
			LandPrices.money(fees), LandPrices.money(upkeep)])
	_check(_main.money_panel.day_label.visible and _main.money_panel.day_label.text.begins_with("Day 1:"),
			"the morning shows the day's income and costs")


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
