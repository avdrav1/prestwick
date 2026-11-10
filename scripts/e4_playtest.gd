extends SceneTree
## The E4-S8 scripted /playtest full session: the parts of docs/playtests/checklist.md's eight
## items a script can do, through the real main scene, with what a script cannot judge (how
## the swing bar feels, whether a reaction matches the player's own, whether a cost feels fair,
## whether a choice is real, whether the feed reads, whether a drop in arrivals is noticed)
## left to the hand checklist in the findings file (docs/playtests/2026-11-09-e4-full.md).
##
##   godot --headless --path . --fixed-fps 60 -s res://scripts/e4_playtest.gd -- [--seed N]
##
##   1. A New course on seed N (with money, so the cost reads): a par 3 in the starting block
##      built with the palette's tools; the validator's reasons while it is half built, then it
##      passes; what it cost against $1,500.
##   2. Play it with the scripted player: each stroke lands and rests on the tiles the aim
##      line's prediction named, and it holes out.
##   3. Open it; the rest of day 1 and day 2 skipped to morning: guests' reactions to hole 1.
##   4. A par 5 with water on the direct line (/course-file generate 5 flat water) priced at
##      data/economy.json's table, with the land a 520 yd hole needs, against the balance.
##   5. Hand only (lay up or go for it).
##   6. courses/playtest_nine.json with $5,000: two days at 3x in 60 fps frames: lines, guests
##      and real time per day, and the busiest 10 real seconds of the feed.
##   7. The fee slider set to the ceiling for day 4, at day 3's dusk once day 4's stars are set
##      (E4-S13, D59): day 4's arrivals and fees against day 3's.
##   8. Save part way through day 4, quit (free the scene), load into a fresh one: the day, the
##      balance, the fee, the rating history and the course come back, and the replayed day
##      ends on the uninterrupted day's balance and feed. The save goes to SAVE_PATH, not the
##      player's user://save.json, and is removed at the end.
##
## Prints one ok or FAIL line per check and exits 0 only when every check passes. Not part of
## the smoke (scripts/playtest.sh).

const MAIN_SCENE := "res://scenes/main.tscn"
const NINE_PATH := "res://courses/playtest_nine.json"
const SAVE_PATH := "user://e4_playtest_save.json"
const START_MONEY: int = 5000
## Frames to wait for one shot to finish: the ball's own 3600-tick cap plus a margin.
const MAX_FRAMES: int = 4000
## Double par on a par 5.
const MAX_STROKES: int = 10
## Item 1: the design doc's basic par 3 budget, the checklist's "under $1,500".
const PAR3_BUDGET: int = 1500
## Item 1: the par 3's tee and cup, tiles in from the starting block's corner, and its brushes.
const TEE_IN := Vector2i(3, 3)
const CUP_IN := Vector2i(24, 24)
## Item 6: 3x, and the feed's busiest stretch read over this many real seconds.
const FAST: float = 3.0
const READ_WINDOW_REAL_S: float = 10.0
## Item 8: simulated seconds into day 4 at which the game is saved.
const SAVE_AT_S: int = 150

enum Phase { BUILD, SWING, FLYING, DAY1_SKIP, DAY2_SKIP, NINE_RUN, FEE_WAIT, FEE_LATE, FEE_SKIP, DAY4_RUN, DAY4_SKIP,
		LOAD_SKIP, DONE }

var _main: Main
var _phase: Phase = Phase.BUILD
var _frames: int = 0
var _failures: int = 0
var _seed: int = 1
var _strokes: int = 0
var _hash: String = ""
var _landed_at: Variant = null
var _rest_at: Variant = null
## Item 3: reactions to hole 1 on days 1 and 2, as feed lines.
var _hole1: Array[String] = []
var _hole1_kinds: Array[int] = [0, 0, 0]
## Item 6 to 8: per day {day, arrivals, fees, lines, reactions, frames, stars, fee, end}.
var _days: Dictionary = {}
var _day_frames: int = 0
## Item 8: the uninterrupted day 4 and the state at the save.
var _saved: Dictionary = {}
var _uninterrupted: Dictionary = {}


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var i := argv.find("--seed")
	if i >= 0 and i + 1 < argv.size():
		_seed = argv[i + 1].to_int()
	print("e4 playtest: seed %d" % _seed)
	_add_main("", _seed)


func _add_main(path: String, seed_value: int = -1) -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	_main = packed.instantiate() as Main
	_main.course_path = path
	_main.start_seed = seed_value
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	_day_frames += 1
	match _phase:
		Phase.BUILD:
			print("1. Build a par 3 under %s" % LandPrices.money(PAR3_BUDGET))
			if not _build():
				_finish()
				return false
			print("2. Play it")
			_phase = Phase.SWING
		Phase.SWING:
			_swing()
		Phase.FLYING:
			if not _main.shot_view.playing or _frames >= MAX_FRAMES:
				_check_stroke()
				_phase = Phase.SWING
		Phase.DAY1_SKIP, Phase.DAY2_SKIP:
			if not _main.guest_sim.skipping:
				if _phase == Phase.DAY1_SKIP:
					_phase = Phase.DAY2_SKIP
					_main.guest_sim.skip_to_morning()
				else:
					_report_guests()
					_item4()
					print("5. Lay up or go for it: hand only")
					_start_nine()
		Phase.NINE_RUN:
			if _main.guest_sim.day >= 3:
				_report_fast_days()
				print("7. The fee at the ceiling")
				# Day 3's guests are drawn already: the fee moves day 4's. It is set at day 3's
				# dusk (_on_day_ended), when the stars shown for day 4 are set (D59).
				_main.guest_sim.skip_to_morning()
				_phase = Phase.FEE_WAIT
		Phase.FEE_WAIT:
			if _main.guest_sim.brain.second >= _main.guest_sim.tuning.day_s - 60:
				_main.guest_sim.set_speed(FAST)
				_phase = Phase.FEE_LATE
		Phase.FEE_LATE:
			pass  # _on_day_ended moves the slider at day 3's dusk.
		Phase.FEE_SKIP:
			if _main.guest_sim.day >= 4:
				_report_fee()
				print("8. Save, quit, load")
				_main.guest_sim.set_speed(FAST)
				_phase = Phase.DAY4_RUN
		Phase.DAY4_RUN:
			if _main.guest_sim.brain != null and _main.guest_sim.brain.second >= SAVE_AT_S:
				_save()
		Phase.DAY4_SKIP:
			if not _main.guest_sim.skipping and _main.guest_sim.day >= 5:
				_load()
		Phase.LOAD_SKIP:
			if not _main.guest_sim.skipping and _main.guest_sim.day >= 5:
				_check_replay()
				_finish()
	return false


# --- 1. Build a par 3 under $1,500 ---

func _build() -> bool:
	var c := _main.course
	_check(c != null and _main.land_seed == _seed and not c.has_unlimited_budget(),
			"the game opens on a New course, seed %d, with money" % _seed)
	if c == null:
		return false
	var b: CourseBuilder = _main.build_tool.builder
	var start := b.balance()
	var block := LandGenerator.start_block(c.width, c.height)
	var tee := block.position + TEE_IN
	var cup := block.position + CUP_IN
	var yd := CourseValidator.yardage(tee, cup)
	print("  hole 1: tee %s, cup %s, %d yd, in the starting block %s" % [tee, cup, yd, block])
	_main.hole_panel.par_buttons[0].pressed.emit()
	_pick_surface(Surface.Type.TEE, 3)
	_click(tee)
	_main.build_palette.tee_button.pressed.emit()
	_click(tee)
	_print_issues(b, "tee placed, no cup")
	_check(not b.issues_for(1).is_empty(), "with the tee alone the validator names what is missing")
	_main.build_palette.cup_button.pressed.emit()
	_click(cup)
	_print_issues(b, "cup placed on rough")
	var on_rough := b.issues_for(1)
	_check(on_rough.size() == 1 and on_rough[0].rule == 2,
			"a cup on rough fails rule 2 alone, and the hole panel says why")
	var dir := Vector2(cup - tee).normalized()
	_pick_surface(Surface.Type.FAIRWAY, 3)
	_drag(tee + Vector2i((dir * 3.0).round()), cup - Vector2i((dir * 4.0).round()))
	_pick_surface(Surface.Type.GREEN, 5)
	_click(cup)
	_print_issues(b, "green painted round the cup")
	_check(b.issues_for(1).is_empty(), "then it passes every rule")
	_main.hole_panel.open_button.pressed.emit()
	_check(b.hole(1) != null and b.hole(1).open, "Open opens it")
	var cost := start - b.balance()
	print("  cost: %s (balance %s to %s); the HUD reads \"%s\"" % [LandPrices.money(cost),
			LandPrices.money(start), LandPrices.money(b.balance()), _main.money_panel.balance_label.text])
	_check(cost > 0 and cost < PAR3_BUDGET, "the par 3 costs %s, under %s" % [LandPrices.money(cost),
			LandPrices.money(PAR3_BUDGET)])
	_hash = _course_key(c)
	_main.mode_button.pressed.emit()
	_check(_main.mode == Main.Mode.PLAY, "one click to Play")
	var sc := _main.swing_control
	_check(sc.ball_at == sc.field.tile_center(tee), "the ball is on the tee")
	_main.shot_view.landed.connect(func(at: Vector3) -> void: _landed_at = at)
	_main.shot_view.came_to_rest.connect(func(at: Vector3) -> void: _rest_at = at)
	# Items 3 and 6: count the reactions and the day's guests.
	_watch_days()
	return _failures == 0


func _print_issues(b: CourseBuilder, what: String) -> void:
	var out: PackedStringArray = []
	for issue: CourseValidator.Issue in b.issues_for(1):
		out.append("rule %d: %s" % [issue.rule, issue.reason])
	print("  %s: %s; panel: \"%s\"" % [what, "passes" if out.is_empty() else "; ".join(out),
			_main.hole_panel.issues_label.text.replace("\n", " / ")])


# --- 2. Play it ---

func _swing() -> void:
	var sc := _main.swing_control
	if sc.is_finished() or _strokes >= MAX_STROKES:
		_check(sc.score != null and sc.score.holed, "the ball holes out")
		if sc.score != null:
			print("  score: %d strokes on a par %d (%d penalty)" % [sc.score.total(), sc.score.par,
					sc.score.penalty_strokes])
		_main.mode_button.pressed.emit()
		_check(_main.mode == Main.Mode.BUILD and _course_key(_main.course) == _hash,
				"back in Build, the course unchanged (its balance aside: guests paid meanwhile)")
		print("3. Open it, watch three guests")
		_main.guest_sim.skip_to_morning()
		_phase = Phase.DAY1_SKIP
		return
	var plan := ScriptedRound.plan(sc)
	if plan == null:
		_fail("stroke %d can be planned" % (_strokes + 1))
		_finish()
		return
	_landed_at = null
	_rest_at = null
	ScriptedRound.swing(sc, plan)
	_strokes += 1
	print("  stroke %d: %s, %d bar ticks" % [_strokes, plan.club.id, plan.ticks])
	if not _main.shot_view.playing:
		_fail("stroke %d is struck" % _strokes)
		_finish()
		return
	_frames = 0
	_phase = Phase.FLYING


func _check_stroke() -> void:
	var view := _main.shot_view
	_check(not view.playing and _rest_at != null, "stroke %d comes to rest" % _strokes)
	if _rest_at == null:
		return
	var field := view.ball.field
	var rest: Vector3 = _rest_at
	var rest_tile := field.tile_at(rest.x, rest.y)
	if _landed_at != null:
		var landed: Vector3 = _landed_at
		var land_tile := field.tile_at(landed.x, landed.y)
		_check(land_tile == view.prediction.landing_tile,
				"  it lands on the tile the aim line predicted, %s" % view.prediction.landing_tile)
	_check(rest_tile == view.prediction.rest_tile or _main.swing_control.is_finished(),
			"  it rests on the predicted tile %s" % view.prediction.rest_tile)


# --- 3. Guests on hole 1 ---

func _on_day_started(d: int) -> void:
	var sim := _main.guest_sim
	_day_frames = 0
	_days[d] = {"day": d, "arrivals": sim.day_arrivals, "paid": 0, "lines": 0, "reactions": 0,
			"stars": sim.stars(), "fee": sim.fee, "ceiling": sim.fee_ceiling(), "seconds": [],
			"lo": sim.stars(), "hi": sim.stars(), "mlo": sim.rating(), "mhi": sim.rating(), "moves": []}
	sim.brain.reached_first_tee.connect(func(_g: Guest) -> void: _days[d].paid += 1)
	sim.brain.reacted.connect(func(_g: Guest, r: GuestReaction) -> void:
		_days[d].reactions += 1
		if d <= 2 and r.hole_number == 1:
			_hole1_kinds[r.kind] += 1
			if _hole1.size() < 3:
				_hole1.append("day %d guest %d, %s: %s" % [d, r.guest_id, r.kind_name(), r.text])
	)


func _on_day_ended(d: int, _b: GuestBrain) -> void:
	if not _days.has(d):
		return
	_days[d].frames = _day_frames
	_days[d].fees = _main.ledger.fees
	# Main's handler ran first (connected in _ready): the upkeep is paid.
	_days[d].end = _main.build_tool.builder.balance()
	_days[d].line = _main.ledger.last_line
	if d == 3 and _phase == Phase.FEE_LATE:
		_set_ceiling()


## The stars shown through the day (E4-S13: they should hold until dusk) and the mean, which
## turns over about three times a day on the nine, and every fee change with its second.
func _on_rating_changed(r: float) -> void:
	var sim := _main.guest_sim
	if not _days.has(sim.day):
		return
	_days[sim.day].lo = minf(_days[sim.day].lo, sim.stars())
	_days[sim.day].hi = maxf(_days[sim.day].hi, sim.stars())
	_days[sim.day].mlo = minf(_days[sim.day].mlo, r)
	_days[sim.day].mhi = maxf(_days[sim.day].mhi, r)


func _on_fee_changed(f: int) -> void:
	var sim := _main.guest_sim
	if _days.has(sim.day) and sim.brain != null:
		(_days[sim.day].moves as Array).append("%d s %s" % [sim.brain.second, LandPrices.money(f)])


func _watch_days() -> void:
	_main.guest_sim.day_started.connect(_on_day_started)
	_main.guest_sim.day_ended.connect(_on_day_ended)
	_main.guest_sim.feed.added.connect(_on_feed_added)
	_main.guest_sim.rating_changed.connect(_on_rating_changed)
	_main.guest_sim.fee_changed.connect(_on_fee_changed)


func _on_feed_added(e: ReactionFeed.Entry) -> void:
	if _days.has(e.day):
		_days[e.day].lines += 1
		(_days[e.day].seconds as Array).append(e.second)


func _report_guests() -> void:
	var k := _hole1_kinds
	print("  hole 1, days 1 and 2: %d praise, %d neutral, %d complaints" % [
			k[GuestReaction.Kind.PRAISE], k[GuestReaction.Kind.NEUTRAL], k[GuestReaction.Kind.COMPLAINT]])
	for line: String in _hole1:
		print("    %s" % line)
	_check(_hole1.size() >= 3, "three guests or more react to hole 1")
	for d: int in [1, 2]:
		if _days.has(d):
			print("  day %d: %d drawn at %.1f stars and %s, \"%s\"" % [d, _days[d].arrivals,
					_days[d].stars, LandPrices.money(_days[d].fee), _days[d].get("line", "")])
	print("  rating %.2f, %.1f stars; balance %s" % [_main.guest_sim.rating(), _main.guest_sim.stars(),
			LandPrices.money(_main.build_tool.builder.balance())])


# --- 4. A par 5 with water ---

func _item4() -> void:
	print("4. A par 5 with water on the direct line")
	var econ := EconomySim.new()
	var fx := econ.fixtures()
	var table := econ.chosen_table()
	var par5: Dictionary = fx[2]
	var build := EconomySim.price(par5.diff, table)
	var lp := LandPrices.load_default()
	var parcel := econ.median_parcel(10, lp)
	var parcels := ceili(BalanceSim.footprint_parcels(520.0) - EconomySim.BLOCK_PARCELS)
	var bal := _main.build_tool.builder.balance()
	print("  %s: %s to build (%s), and about %d parcels of land at the median %s, %s; balance now %s" % [
			par5.name, LandPrices.money(build), EconomySim._tiles_note(par5.diff), parcels,
			LandPrices.money(parcel), LandPrices.money(parcels * parcel), LandPrices.money(bal)])
	var water := int(par5.diff.painted["water"]) * int(table["water"])
	print("  the pond: %d water tiles, %s of it" % [par5.diff.painted["water"], LandPrices.money(water)])
	var band := econ.chosen_band(EconomySim.PAR5_TARGET)
	_check(build >= band.x and build <= band.y, "it costs %s, inside Balance targets' %s to %s" % [
			LandPrices.money(build), LandPrices.money(int(band.x)), LandPrices.money(int(band.y))])


# --- 6. Two days at 3x on the nine ---

func _start_nine() -> void:
	print("6. Two days at 3x on %s" % NINE_PATH)
	_main.queue_free()
	_days.clear()
	_add_main(NINE_PATH)
	_main.build_tool.builder.restore_balance(START_MONEY)
	_watch_days()
	_main.mode_button.pressed.emit()
	_main.guest_sim.set_speed(FAST)
	_check(_main.guest_sim.running, "the day runs at 3x in Play")
	_frames = 0
	_phase = Phase.NINE_RUN


func _report_fast_days() -> void:
	for d: int in [1, 2]:
		var x: Dictionary = _days.get(d, {})
		if x.is_empty() or not x.has("frames"):
			_fail("day %d ran to its end" % d)
			continue
		var busiest := _busiest(x.seconds, READ_WINDOW_REAL_S * FAST)
		print("  day %d: %d guests at %.1f stars (%.1f to %.1f shown during it, the mean %.2f to %.2f), %d reactions as %d feed lines, %.1f real s at 3x (%d frames), busiest %d real s %d lines; \"%s\"" % [
				d, x.paid, x.stars, x.lo, x.hi, x.mlo, x.mhi, x.reactions, x.lines, x.frames / 60.0, x.frames,
				READ_WINDOW_REAL_S, busiest, x.line])
		_check(x.lo == x.stars and x.hi == x.stars, "day %d's stars shown hold until dusk (D59)" % d)
		_check(x.frames <= ceili(_main.guest_sim.tuning.day_s / FAST * 60.0 * 1.02),
				"day %d at 3x keeps its 3 real minutes, within 2%%" % d)
	_check(_main.feed_panel.visible, "the feed is on screen in Play")


## The most feed lines in any `span` simulated seconds.
static func _busiest(seconds: Array, span: float) -> int:
	var best := 0
	var j := 0
	for i in seconds.size():
		while float(seconds[i]) - float(seconds[j]) >= span:
			j += 1
		best = maxi(best, i - j + 1)
	return best


# --- 7. The fee at the ceiling ---

func _set_ceiling() -> void:
	_main.mode_button.pressed.emit()
	_check(_main.mode == Main.Mode.BUILD and _main.fee_panel.visible, "the fee slider is on screen in Build")
	var sim := _main.guest_sim
	var before := sim.fee
	var at_fee := sim.arrivals_today()
	var slider := _main.fee_panel.slider
	slider.value = slider.max_value
	print("  slider %s to %s (the ceiling at %.1f stars): tomorrow's guests %d to %d; \"%s %s\"" % [
			LandPrices.money(before), LandPrices.money(sim.fee), sim.stars(), at_fee, sim.arrivals_today(),
			_main.fee_panel.fee_label.text, _main.fee_panel.ceiling_label.text])
	print("  tooltip: \"%s\"" % _main.fee_panel.slider.tooltip_text.replace("\n", " / "))
	_check(sim.fee == sim.fee_ceiling(), "the slider's end is the ceiling, %s" % LandPrices.money(sim.fee_ceiling()))
	_check(sim.arrivals_today() < at_fee, "the ceiling draws fewer guests than %s" % LandPrices.money(before))
	_phase = Phase.FEE_SKIP


func _report_fee() -> void:
	for d: int in [3, 4]:
		var x: Dictionary = _days[d]
		print("  day %d: %d guests drawn at %s of %s (%.1f stars; %.1f to %.1f during day %d); fee changes %s; \"%s\"" % [
				d, x.arrivals, LandPrices.money(x.fee), LandPrices.money(x.ceiling), x.stars, x.lo, x.hi,
				d, x.moves, x.get("line", "")])
	var e := _main.guest_sim.economy
	var x4: Dictionary = _days[4]
	var at_start := e.arrivals(x4.stars, float(e.start_fee) / maxf(x4.ceiling, 1.0))
	print("  day 4 at the start fee %s would have drawn %d" % [LandPrices.money(e.start_fee), at_start])
	_check(int(x4.fee) == int(x4.ceiling), "day 4's morning draws at the ceiling, %s" % LandPrices.money(x4.ceiling))
	var x3: Dictionary = _days[3]
	_check(x3.lo == x3.stars and x3.hi == x3.stars, "day 3's stars shown hold until dusk (D59)")
	var mid: Array = (x3.moves as Array).filter(func(m: String) -> bool:
		return int(m.split(" ")[0]) < _main.guest_sim.tuning.day_s)
	_check(mid.is_empty(), "the fee does not move during day 3 (moves %s)" % [x3.moves])
	_check(int(x4.arrivals) < at_start, "at the ceiling day 4 draws %d, under the %d at %s" % [
			x4.arrivals, at_start, LandPrices.money(e.start_fee)])


# --- 8. Save, quit, load ---

func _save() -> void:
	var sim := _main.guest_sim
	var err := _main.save_game(SAVE_PATH)
	_check(err == OK, "F5's save writes %s at day %d, %d s" % [SAVE_PATH, sim.day, sim.brain.second])
	_saved = {"day": sim.day, "fee": sim.fee, "stars": sim.stars(), "history": _main.rating_history.duplicate(),
			"hash": _course_key(_main.course), "money": _main.build_tool.builder.balance() - _main.ledger.fees,
			"notice": _main.save_notice.text_shown() if _main.save_notice.has_method("text_shown") else ""}
	sim.skip_to_morning()
	_phase = Phase.DAY4_SKIP


func _load() -> void:
	_uninterrupted = {"end": _days[4].end, "history": _main.rating_history.duplicate(),
			"total": _main.guest_sim.feed.total, "fee": _main.guest_sim.fee}
	print("  uninterrupted day 4 ends on %s, feed %d reactions, %d days of rating history" % [
			LandPrices.money(_uninterrupted.end), _uninterrupted.total, _uninterrupted.history.size()])
	_main.queue_free()
	_days.clear()
	_add_main("", _seed + 1)
	var ok := _main.load_game(SAVE_PATH)
	_check(ok, "a fresh game loads it (F9)")
	if not ok:
		_finish()
		return
	var sim := _main.guest_sim
	_main.guest_sim.day_started.connect(_on_day_started)
	_main.guest_sim.day_ended.connect(_on_day_ended)
	_check(sim.morning_day() == int(_saved.day), "it resumes at the morning of day %d" % _saved.day)
	_check(_main.build_tool.builder.balance() == int(_saved.money),
			"the balance is that morning's, %s" % LandPrices.money(_saved.money))
	_check(sim.fee == int(_saved.fee), "the fee is as the player left it, %s" % LandPrices.money(sim.fee))
	_check(sim.stars() == float(_saved.stars), "the stars shown are that morning's, %.1f" % sim.stars())
	_check(_main.rating_history == _saved.history, "the rating history is back (%d days)" % _main.rating_history.size())
	_check(_course_key(_main.course) == String(_saved.hash), "the course is the same (its tiles, holes and land)")
	sim.skip_to_morning()
	_phase = Phase.LOAD_SKIP


func _check_replay() -> void:
	var b := _main.build_tool.builder
	print("  replayed day 4 ends on %s, feed %d reactions" % [LandPrices.money(b.balance()),
			_main.guest_sim.feed.total])
	_check(b.balance() == int(_uninterrupted.end), "the replayed day ends on the uninterrupted balance")
	_check(_main.rating_history == _uninterrupted.history, "and the same rating history")
	_check(_main.guest_sim.fee == int(_uninterrupted.fee), "and the same fee")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# --- input through the real tools (as scripts/land_playtest.gd) ---

func _pick_surface(s: Surface.Type, brush: int) -> void:
	var i: int = CourseBuilder.PALETTE.find(s)
	_main.build_palette.surface_buttons[i].pressed.emit()
	var k: int = _main.build_tool.builder.tuning.brush_sizes.find(brush)
	_main.build_palette.brush_buttons[k].pressed.emit()


func _click(cell: Vector2i) -> void:
	var tool := _main.build_tool
	tool.press_at(_screen(cell))
	tool.release()
	if tool.hover != cell:
		_fail("the click on %s picks it (picked %s)" % [cell, tool.hover])


func _drag(a: Vector2i, b: Vector2i) -> void:
	var tool := _main.build_tool
	tool.press_at(_screen(a))
	for cell: Vector2i in BuildTool.grid_line(a, b):
		tool.drag_to(_screen(cell))
	tool.release()


func _screen(cell: Vector2i) -> Vector2:
	var c := _main.course
	return Iso.tile_to_screen(Vector2(cell), c.get_height(cell.x, cell.y)) + Vector2(0.5, 0.5)


# --- reporting ---

## The course as saved, less its balance (CourseData keeps the balance as land_budget, which the
## guests' fees move while the scene runs).
static func _course_key(c: CourseData) -> String:
	var d := c.to_dict()
	d.erase("land_budget")
	return JSON.stringify(d, "", true).sha256_text()


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
	print("e4 playtest: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	if _main != null:
		_main.queue_free()
	quit(0 if _failures == 0 else 1)
