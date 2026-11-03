extends SceneTree
## The E6-S8 scripted /playtest session: a start on land. Drives the real main scene the way a
## player would: a New course on seed `--seed` (default 1), the Buy land tool and its confirm
## for two parcels in a line off the starting block (the cheapest such line), a par 4 built
## with the palette's tools from the block across both parcels, Open, then Play with the
## scripted player (scripts/scripted_round.gd) until it holes out. Then it measures D29's
## reading from that tee: every full-club stroke aimed toward the land line is predicted on
## the course and on a fully owned copy, to count shots that are OB because they rolled onto
## unowned land although they would have rolled back. Findings: docs/playtests/.
##
##   godot --headless --path . --fixed-fps 60 -s res://scripts/land_playtest.gd -- [--seed N]
##
## Prints one ok or FAIL line per check and exits 0 only when every check passes. Not part
## of the smoke (scripts/playtest.sh): the smoke's stages are one per milestone.

const MAIN_SCENE := "res://scenes/main.tscn"
const MAX_FRAMES: int = 4000
const MAX_STROKES: int = 10
## The two bought parcels' sides of the block: +x, -x, +y, -y.
const SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
## Tiles from the block's far edge to the tee, and into the far parcel to the cup.
const TEE_IN: int = 2
const CUP_IN: int = 10
## The D29 sweep: aim offsets from the cup line, degrees, either side.
const SWEEP_DEG: int = 60
const SWEEP_STEP: int = 3

enum Phase { BUILD, PLAY, FLYING, DONE }

var _main: Main
var _phase: Phase = Phase.BUILD
var _frames: int = 0
var _failures: int = 0
var _seed: int = 1
var _strokes: int = 0
var _hash: String = ""


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var i := argv.find("--seed")
	if i >= 0 and i + 1 < argv.size():
		_seed = argv[i + 1].to_int()
	print("land playtest: seed %d" % _seed)
	var packed := load(MAIN_SCENE) as PackedScene
	_main = packed.instantiate() as Main
	_main.course_path = ""
	_main.start_seed = _seed
	root.add_child(_main)


func _process(_delta: float) -> bool:
	match _phase:
		Phase.BUILD:
			if not _build():
				_finish()
				return false
			_phase = Phase.PLAY
		Phase.PLAY:
			_swing()
		Phase.FLYING:
			_frames += 1
			if not _main.shot_view.playing or _frames >= MAX_FRAMES:
				_check(not _main.shot_view.playing, "stroke %d comes to rest" % _strokes)
				_report_rest()
				_phase = Phase.PLAY
	return false


# --- Build: buy two parcels and build a par 4 across them ---

func _build() -> bool:
	var c := _main.course
	_check(c != null and _main.land_seed == _seed, "the game opens on a New course, seed %d" % _seed)
	if c == null:
		return false
	var lp := LandPrices.load_default()
	_check(c.land_budget == lp.land_budget, "with the land budget, %s" % LandPrices.money(lp.land_budget))
	_check(_main.land_panel.budget_label.text.contains(LandPrices.money(lp.land_budget)),
			"the land panel shows it: \"%s\"" % _main.land_panel.budget_label.text)
	_check(_main.build_palette.buy_button.visible, "Buy land is on the palette")
	var b: CourseBuilder = _main.build_tool.builder
	var block := LandGenerator.start_block(c.width, c.height)
	var lane := _cheapest_lane(b, block)
	if lane.is_empty():
		_fail("two parcels in a line off the block fit the budget")
		return false
	var parcels: Array[Vector2i] = lane.parcels
	print("  lane: %s, parcels %s at %s and %s" % [lane.side, parcels,
			LandPrices.money(b.parcel_price(parcels[0])), LandPrices.money(b.parcel_price(parcels[1]))])
	_print_neighbours(b, block)
	# Buy them with the Buy land tool and its confirm.
	_main.build_palette.buy_button.pressed.emit()
	_check(_main.build_tool.tool == BuildTool.Tool.BUY, "the Buy land tool is picked")
	_check(_main.build_tool.builder.buy_refusal(parcels[1]) == "not next to your land",
			"the far parcel cannot be bought first: \"%s\"" % b.buy_refusal(parcels[1]))
	for p: Vector2i in parcels:
		var before: int = c.land_budget
		var price: int = b.parcel_price(p)
		_click(_tile_of(c, p))
		_check(_main.land_panel.pending_parcel == p, "a click on parcel %s asks to confirm: \"%s\"" % [
				p, _main.land_panel.confirm_label.text.replace("\n", " ")])
		_check(_main.land_panel.confirm_buy(), "the confirm buys parcel %s" % p)
		_check(c.is_parcel_owned(p) and c.land_budget == before - price,
				"parcel %s is owned and the budget falls by %s to %s" % [p, LandPrices.money(price),
				LandPrices.money(c.land_budget)])
	# The hole: tee in the block, cup in the far parcel, along the lane's middle.
	var tee: Vector2i = lane.tee
	var cup: Vector2i = lane.cup
	var yd: int = roundi(Vector2(cup - tee).length() * CourseValidator.YARDS_PER_TILE)
	print("  hole: tee %s, cup %s, %d yd" % [tee, cup, yd])
	_main.hole_panel.par_buttons[1].pressed.emit()
	_pick_surface(Surface.Type.TEE, 3)
	_click(tee)
	_pick_surface(Surface.Type.FAIRWAY, 5)
	var dir := Vector2(cup - tee).normalized()
	var from := tee + Vector2i((dir * (TEE_IN)).round())
	var to := cup - Vector2i((dir * 3.0).round())
	_drag(from, to)
	_pick_surface(Surface.Type.GREEN, 5)
	_drag(cup - Vector2i((dir * 2.0).round()), cup + Vector2i((dir * 2.0).round()))
	_main.build_palette.tee_button.pressed.emit()
	_click(tee)
	_main.build_palette.cup_button.pressed.emit()
	_click(cup)
	var h: HoleData = b.hole(1)
	_check(h != null and h.tee == tee and h.cup == cup and h.par == 4,
			"hole 1 is a par 4 from %s to %s" % [tee, cup])
	_check(b.issues_for(1).is_empty(), "it passes every validator rule %s" % _issue_text(b))
	_main.hole_panel.open_button.pressed.emit()
	_check(h != null and b.hole(1).open, "Open opens it")
	_check(c.land_budget >= 0, "%s of land budget left" % LandPrices.money(c.land_budget))
	_hash = c.content_hash()
	_main.mode_button.pressed.emit()
	_check(_main.mode == Main.Mode.PLAY, "one click to Play")
	var sc := _main.swing_control
	_check(sc.ball_at == sc.field.tile_center(tee), "the ball is on the tee")
	_d29_sweep(sc)
	return _failures == 0


## The cheapest two parcels in a line off the block that the budget buys, nearest first:
## {side, parcels, tee, cup}, or {} when none fits.
func _cheapest_lane(b: CourseBuilder, block: Rect2i) -> Dictionary:
	var c := b.course
	var bp := Rect2i(block.position / CourseData.PARCEL_TILES, block.size / CourseData.PARCEL_TILES)
	var best := {}
	var best_cost := c.land_budget + 1
	for side: Vector2i in SIDES:
		for k: int in 2:
			var start: Vector2i
			if side.x != 0:
				start = Vector2i(bp.end.x if side.x > 0 else bp.position.x - 1, bp.position.y + k)
			else:
				start = Vector2i(bp.position.x + k, bp.end.y if side.y > 0 else bp.position.y - 1)
			var pair: Array[Vector2i] = [start, start + side]
			if not c.parcel_in_bounds(pair[1]):
				continue
			var cost := b.parcel_price(pair[0]) + b.parcel_price(pair[1])
			if cost < best_cost:
				best_cost = cost
				best = {"side": side, "parcels": pair, "tee": Vector2i.ZERO, "cup": Vector2i.ZERO}
	if best.is_empty():
		return best
	var side: Vector2i = best.side
	var far: Rect2i = c.parcel_rect((best.parcels as Array[Vector2i])[1])
	var mid := Vector2i(far.position + far.size / 2)
	var tee := Vector2i.ZERO
	var cup := Vector2i.ZERO
	if side.x != 0:
		tee = Vector2i(block.position.x + TEE_IN if side.x > 0 else block.end.x - 1 - TEE_IN, mid.y)
		cup = Vector2i(far.position.x + CUP_IN if side.x > 0 else far.end.x - 1 - CUP_IN, mid.y)
	else:
		tee = Vector2i(mid.x, block.position.y + TEE_IN if side.y > 0 else block.end.y - 1 - TEE_IN)
		cup = Vector2i(mid.x, far.position.y + CUP_IN if side.y > 0 else far.end.y - 1 - CUP_IN)
	best.tee = tee
	best.cup = cup
	return best


func _print_neighbours(b: CourseBuilder, block: Rect2i) -> void:
	var c := b.course
	var out: PackedStringArray = []
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			var parcel := Vector2i(p, q)
			if b.buy_refusal(parcel).is_empty():
				var t := BalanceSim.parcel_tally(c, parcel)
				out.append("%s %s (relief %d, %d trees, %d water)" % [parcel, LandPrices.money(b.parcel_price(parcel)),
						t.relief, t.trees, t.water])
	print("  for sale next to the block %s: %s" % [block, "; ".join(out)])


# --- Play: the scripted player holes out ---

func _swing() -> void:
	var sc := _main.swing_control
	if sc.is_finished() or _strokes >= MAX_STROKES:
		_check_round()
		_finish()
		return
	var plan := ScriptedRound.plan(sc)
	if plan == null:
		_fail("stroke %d can be planned" % (_strokes + 1))
		_finish()
		return
	var from := sc.field.tile_at(sc.ball_at.x, sc.ball_at.y)
	ScriptedRound.swing(sc, plan)
	_strokes += 1
	print("  stroke %d: %s, %d bar ticks, from tile %s" % [_strokes, plan.club.id, plan.ticks, from])
	if not _main.shot_view.playing:
		_fail("stroke %d is struck" % _strokes)
		_finish()
		return
	_frames = 0
	_phase = Phase.FLYING


func _report_rest() -> void:
	var sc := _main.swing_control
	var at := sc.field.tile_at(sc.ball_at.x, sc.ball_at.y)
	print("    rests on tile %s, %s, %s land" % [at, Surface.Type.keys()[sc.course.get_surface(at.x, at.y)],
			"owned" if sc.course.is_owned(at.x, at.y) else "UNOWNED"])


func _check_round() -> void:
	var sc := _main.swing_control
	_check(sc.score != null and sc.score.holed, "the ball holes out")
	if sc.score != null:
		print("  score: %d strokes (%d penalty) on a par %d" % [sc.score.total(), sc.score.penalty_strokes,
				sc.score.par])
	_main.mode_button.pressed.emit()
	_check(_main.mode == Main.Mode.BUILD, "one click back to Build")
	_check(_main.course.content_hash() == _hash, "playing changed nothing on the course")


# --- D29: OB on a roll that would have come back ---

## From the tee, every full club at every FULL_TICKS power, aimed every SWEEP_STEP degrees
## within SWEEP_DEG of the cup: how many strokes end OB on unowned land, how many of those
## touched down on owned land and rolled on, and how many of those would have come to rest on
## owned land had the line not stopped them (the same stroke on a fully owned copy).
func _d29_sweep(sc: SwingControl) -> void:
	var c := sc.course
	var d := c.to_dict()
	d["owned"] = CourseData.all_owned_rows(c.width, c.height)
	var errors: Array[String] = []
	var open := CourseData.from_dict(d, errors)
	if open == null:
		_fail("a fully owned copy loads %s" % errors)
		return
	var cup := sc.cup_tile()
	var base := rad_to_deg((sc.field.tile_center(cup) - sc.ball_at).angle())
	var shots := 0
	var ob := 0
	var rolled_on := 0
	var came_back := 0
	var example := ""
	for club: Club in sc.legal:
		if club.is_putter():
			continue
		for t: int in ScriptedRound.FULL_TICKS:
			for off: int in range(-SWEEP_DEG, SWEEP_DEG + 1, SWEEP_STEP):
				var aim := fposmod(base + off, 360.0)
				var shot := _launch(sc, club, aim, t)
				var p := ShotPrediction.run_launch(c, sc.next_seed(), shot, null, null, cup)
				shots += 1
				if p.hazard != Ball.Hazard.OB:
					continue
				ob += 1
				if not c.is_owned(p.landing_tile.x, p.landing_tile.y):
					continue
				rolled_on += 1
				var q := ShotPrediction.run_launch(open, sc.next_seed(), shot, null, null, cup)
				if q.hazard == Ball.Hazard.NONE and c.is_owned(q.rest_tile.x, q.rest_tile.y):
					came_back += 1
					if example.is_empty():
						example = "%s %d ticks %+d deg: lands %s, OB at %s; unstopped it rests at %s" % [
								club.id, t, off, p.landing_tile, sc.field.tile_at(p.hazard_position.x,
								p.hazard_position.y), q.rest_tile]
	print("  D29 sweep from the tee: %d strokes, %d OB on unowned land, %d of them touched down on owned land and rolled over the line, %d of those would have rolled back to owned land" % [
			shots, ob, rolled_on, came_back])
	if not example.is_empty():
		print("    e.g. %s" % example)
	_check(ob > 0, "the sweep reaches the land line (it is in play)")


func _launch(sc: SwingControl, club: Club, aim_deg: float, ticks: int) -> ShotLaunch:
	var s := Swing.new(sc.tuning)
	s.bar_speed = sc.swing.bar_speed
	s.click()
	for i in ticks:
		s.tick(Ball.DT)
	s.click()
	for i in ticks:
		s.tick(Ball.DT)
	s.click()
	return s.launch(sc.model, sc.field, club, sc.ball_at, aim_deg)


# --- input through the real tools ---

func _pick_surface(s: Surface.Type, brush: int) -> void:
	var i: int = CourseBuilder.PALETTE.find(s)
	_main.build_palette.surface_buttons[i].pressed.emit()
	var k: int = _main.build_tool.builder.tuning.brush_sizes.find(brush)
	_main.build_palette.brush_buttons[k].pressed.emit()


## A click on `cell`, at its top's centre, through BuildTool's press and release.
func _click(cell: Vector2i) -> void:
	var tool := _main.build_tool
	tool.press_at(_screen(cell))
	tool.release()
	if tool.hover != cell:
		_fail("the click on %s picks it (picked %s)" % [cell, tool.hover])


## A drag from `a` to `b`, one tile at a time along the grid line, as one undo step.
func _drag(a: Vector2i, b: Vector2i) -> void:
	var tool := _main.build_tool
	tool.press_at(_screen(a))
	for cell: Vector2i in BuildTool.grid_line(a, b):
		tool.drag_to(_screen(cell))
	tool.release()


func _screen(cell: Vector2i) -> Vector2:
	var c := _main.course
	return Iso.tile_to_screen(Vector2(cell), c.get_height(cell.x, cell.y)) + Vector2(0.5, 0.5)


func _tile_of(c: CourseData, p: Vector2i) -> Vector2i:
	var r := c.parcel_rect(p)
	return r.position + r.size / 2


func _issue_text(b: CourseBuilder) -> String:
	var out: PackedStringArray = []
	for issue: CourseValidator.Issue in b.issues_for(1):
		out.append(str(issue.rule) + " " + issue.reason)
	return "" if out.is_empty() else "(%s)" % "; ".join(out)


# --- reporting ---

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
	print("land playtest: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	if _main != null:
		_main.queue_free()
	quit(0 if _failures == 0 else 1)
