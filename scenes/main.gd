class_name Main
extends Node2D
## The one main scene. Build and Play are states on it, never separate scenes (D2).

enum Mode { BUILD, PLAY }

signal mode_changed(new_mode: Mode)

const TOGGLE_ACTION: StringName = &"toggle_mode"
## Fires the debug shot in Play, in debug builds only (E2-S8; F3).
const DEBUG_SHOT_ACTION: StringName = &"debug_shot"
## Save and load the game (E4-S7; F5 and F9 until E5's menus).
const SAVE_ACTION: StringName = &"save_game"
const LOAD_ACTION: StringName = &"load_game"

## Course loaded at start (E2-S8). Empty, the default, starts on a New course (E6-S6,
## CourseBuilder.new_course: generated land, the starting block, the land budget); a failed
## load warns and does the same.
@export_file("*.json") var course_path: String = ""
## The land seed of the New course the game starts on. -1, the default, picks one at random.
@export var start_seed: int = -1
## The fixed shot the debug key fires (E1-S7, E2-S8). Null loads golf/debug_shot.tres.
@export var debug_shot: DebugShot

var mode: Mode = Mode.BUILD
## The course being built and played. Only course/builder.gd and course/save.gd write it.
var course: CourseData
## The seed of the latest New course's land (new_course), so it can be made again.
var land_seed: int = -1
## The course rating at each day's end, oldest first: E4-S5 fills it; a save carries it (E4-S7).
var rating_history: Array[float] = []
## E4-S4: today's green fees and the balance at the morning; its last line is the morning report.
var ledger := DayLedger.new()

## E4-S4's green fee until E4-S6's slider: this share of the fee ceiling at PLACEHOLDER_STARS,
## the fee that earns most under D58's curve. Lane B (E4-S5, E4-S6) replaces green_fee's body.
const PLACEHOLDER_FEE_SHARE: float = 0.8
const PLACEHOLDER_STARS: float = 3.0

## The left column's gap between controls, px (as main.tscn spaces them).
const SPEED_PANEL_GAP: float = 8.0
## The speed panel's top as main.tscn places it, for Play (_place_speed_panel); -1 until read.
var _speed_panel_top: float = -1.0
## The feed panel's top as main.tscn places it (E4-S2: Play moves it under the balance).
var _feed_panel_top: float = -1.0

@onready var mode_label: Label = $HUD/ModeLabel
@onready var course_view: CourseView = $CourseView
@onready var camera: CourseCamera = $Camera
@onready var build_tool: BuildTool = $BuildTool
@onready var build_palette: BuildPalette = $HUD/BuildPalette
@onready var shot_view: ShotView = $CourseView/ShotView
@onready var mode_button: Button = $HUD/ModeButton
@onready var score_card: ScoreCard = $HUD/ScoreCard
@onready var new_sandbox_button: Button = $HUD/NewSandboxButton
@onready var new_course_button: Button = $HUD/NewCourseButton
@onready var hole_panel: HolePanel = $HUD/HolePanel
@onready var land_panel: LandPanel = $HUD/LandPanel
@onready var swing_control: SwingControl = $SwingControl
@onready var aim_view: AimView = $AimView
@onready var swing_panel: SwingPanel = $HUD/SwingPanel
@onready var guest_sim: GuestSim = $GuestSim
@onready var guest_view: GuestView = $CourseView/GuestView
@onready var sim_speed_panel: SimSpeedPanel = $HUD/SimSpeedPanel
@onready var feed_panel: FeedPanel = $HUD/FeedPanel
@onready var reaction_tags: ReactionTags = $CourseView/ReactionTags
## After BuildTool and SwingControl, so a click on a map tag is hit-tested ahead of them (E3-S19).
@onready var tag_clicks: TagClicks = $TagClicks
## The overhead green view (E3-S52, D48): Play only, opened while the ball is on a green.
@onready var green_view: GreenView = $HUD/GreenView
## The off-screen cup's edge marker (E3-S64): Play only, while the played hole's cup is outside
## the free view.
@onready var cup_pointer: CupPointer = $HUD/CupPointer
## The save and load notice (E4-S7).
@onready var save_notice: SaveNotice = $HUD/SaveNotice
## The balance, in Build and Play (E4-S2).
@onready var money_panel: MoneyPanel = $HUD/MoneyPanel


func _ready() -> void:
	if debug_shot == null:
		debug_shot = DebugShot.load_default()
	mode_button.pressed.connect(toggle_mode)
	new_sandbox_button.pressed.connect(new_sandbox)
	new_course_button.pressed.connect(func() -> void: new_course())
	_refresh_label()
	build_palette.bind(build_tool)
	hole_panel.bind(build_tool)
	hole_panel.play_requested.connect(play_hole)
	# A row's tag picks and frames its hole as the map tag does (E3-S43).
	hole_panel.tag_requested.connect(func(number: int, slot: int) -> void: _on_tag_link(number, slot))
	land_panel.bind(build_tool)
	# Build stands the speed panel under the land panel, whose height follows its rows (E3-S62).
	land_panel.resized.connect(_place_speed_panel)
	land_panel.visibility_changed.connect(_place_speed_panel)
	money_panel.resized.connect(_place_speed_panel)
	sim_speed_panel.resized.connect(_place_speed_panel)
	swing_control.bind(shot_view, aim_view)
	swing_panel.bind(swing_control)
	green_view.bind(swing_control, shot_view, aim_view)
	swing_control.changed.connect(_refresh_label)
	swing_control.struck.connect(_on_struck)
	swing_control.hole_finished.connect(_on_hole_finished)
	shot_view.came_to_rest.connect(_on_came_to_rest)
	score_card.bind(swing_control)
	guest_view.bind(guest_sim)
	sim_speed_panel.bind(guest_sim)
	feed_panel.bind(guest_sim)
	feed_panel.hole_requested.connect(_on_hole_link)
	reaction_tags.bind(guest_sim.feed)
	reaction_tags.guests = guest_view  # a tag over a golfer fades (E3-S63)
	tag_clicks.bind(reaction_tags, _on_tag_link, tag_click_taken)
	hole_panel.bind_feed(guest_sim.feed)
	# E4-S4: fees at the first tee, upkeep at the day's end, the ledger each morning.
	guest_sim.guest_arrived.connect(_on_guest_arrived)
	guest_sim.day_ended.connect(_on_day_ended)
	guest_sim.day_started.connect(_on_day_started)
	_apply_mode()
	var errors: Array[String] = []
	var loaded: CourseData = null
	if not course_path.is_empty():
		loaded = CourseSave.load_file(course_path, errors)
	if loaded != null:
		show_course(loaded)
		return
	if not errors.is_empty():
		push_warning("main: %s" % "; ".join(errors))
	new_course(start_seed)


## Shows `c`, frames the camera on it and hands it to a fresh builder (empty undo stack).
## A course with holes frames hole 1 and picks it in the hole list (E3-S2, frame_first_hole);
## one with none frames the course centre at the player's zoom.
func show_course(c: CourseData) -> void:
	course = c
	rating_history.clear()
	shot_view.clear()
	# The guests' day of this course (E3-S5): day 1 starts when Play first runs it.
	guest_sim.start(c, maxi(land_seed, 0))
	reaction_tags.show_course(c)
	# The builder first: it closes any open hole the course brought in failing a rule, and the
	# view then draws the holes as they are.
	var builder := CourseBuilder.new(c)
	course_view.show_course(c)
	camera.frame(course_view.screen_bounds())
	camera.restore_zoom()
	builder.tiles_changed.connect(_on_tiles_changed)
	builder.holes_changed.connect(course_view.refresh_holes)
	builder.checked.connect(_on_checked)
	builder.land_changed.connect(course_view.refresh_parcel)
	# An edit clears the verdicts guests gave the hole it changed (E3-S17).
	guest_sim.watch(builder)
	build_tool.builder = builder
	var first: HoleData = SwingControl.hole_to_play(c, 1)
	build_tool.select_hole(first.number if first != null else 1)
	frame_first_hole()
	land_panel.watch(builder)
	ledger.clear(builder.balance(), builder.has_unlimited_money())
	money_panel.watch(builder, ledger)
	# New sandbox (and every version 1 file) has an unlimited budget and owns every parcel:
	# nothing to buy, so the Buy land tool is hidden (E6-S6).
	build_palette.set_buying(not c.has_unlimited_budget())
	_on_checked(builder.issues)
	if mode == Mode.PLAY:
		_begin_play()


## Starts a new course on the blank plot (D10, BuilderTuning), with a fresh builder.
func new_sandbox() -> void:
	show_course(CourseBuilder.new_sandbox())


## Starts a New course (E6-S6, D19): the generated land of `seed_value` (-1 picks one at
## random), owning only the starting block, with the full land budget and a fresh builder.
## The camera frames the map's centre, where the block is (D26).
func new_course(seed_value: int = -1) -> void:
	land_seed = seed_value if seed_value >= 0 else randi() % 1000000
	show_course(CourseBuilder.new_course(land_seed))


## Plays hole `number` (a hole list row's Play, E3-S2): picks it in the list and starts Play
## on its tee, from Build or from Play. `slot` picks one of several holes sharing `number`
## (E3-S11, a duplicate's row).
func play_hole(number: int, slot: int = -1) -> void:
	build_tool.select_hole(number, slot)
	if mode == Mode.PLAY:
		_begin_play()
	else:
		set_mode(Mode.PLAY)


## A feed line (E3-S7) or a map tag (E3-S19, TagClicks) was clicked: jump_to_hole, so Build
## picks the hole and frames it (frame_hole with its slot), unless a swing is under way or the
## ball is moving in Play, when the click is dropped so a line coming in under the cursor never
## ends a shot or the round (a tag then leaves the click to the swing). True when it jumped.
func _on_hole_link(number: int, slot: int = -1) -> bool:
	if mode == Mode.PLAY and (swing_control.swing.in_progress() or swing_control.is_ball_moving()):
		return false
	return jump_to_hole(number, slot)


## A map tag was clicked (E3-S19, TagClicks): as a feed line (_on_hole_link), but in Play only
## while the hole is not under way, before its first stroke or once it is finished. A tag sits on
## the map, where the player aims and clicks to swing (a neighbouring green's tag is often under
## the cursor), so mid-hole the click is left to the swing and the round in progress is kept
## (E3-S19 review). True when it jumped.
func _on_tag_link(number: int, slot: int = -1) -> bool:
	if mode == Mode.PLAY and tag_waits_for_swing():
		return false
	return _on_hole_link(number, slot)


## True when a click on a map tag would be taken now (_on_tag_link): always in Build; in Play
## only while the hole is not under way and no swing or ball is moving. A hovered tag shows the
## pointing hand only then (E3-S43).
func tag_click_taken() -> bool:
	if mode != Mode.PLAY:
		return true
	return not tag_waits_for_swing() and not swing_control.swing.in_progress() \
			and not swing_control.is_ball_moving()


## True in Play while the hole is under way: at least one stroke counted and not finished, so a
## click on the map is the swing's.
func tag_waits_for_swing() -> bool:
	var score: HoleScore = swing_control.score
	return score != null and score.strokes > 0 and not score.is_finished()


## Switches to Build, picks hole `number` in the hole list and frames it (frame_hole). `slot`
## (its index in CourseData.holes, as the feed keeps it) picks that hole while the course still
## has it, whatever its number now; else the hole goes by `number`. A hole whose tee or cup is
## off the map is picked without framing. False when the course has neither (the hole was
## removed since the guest named it): Build shows, the pick and camera stay.
func jump_to_hole(number: int, slot: int = -1) -> bool:
	set_mode(Mode.BUILD)
	var at: int = ReactionFeed.resolve_slot(course, slot, number)
	if at < 0:
		return false
	var h: HoleData = course.holes[at]
	if frame_hole(h.number, at):
		return true
	build_tool.select_hole(h.number, at)
	return true


## Frames hole 1 (or, without one placed, the lowest-numbered hole with a tee) when its tee and
## cup are on the map: frame_hole (E3-S2). False, leaving the camera, when there is no such hole.
func frame_first_hole() -> bool:
	var h: HoleData = SwingControl.hole_to_play(course, 1)
	# A course opens with its list as the player left it (E3-S65 collapses only on a framing
	# the player asked for).
	return h != null and frame_hole(h.number, -1, false)


## Picks hole `number` in the hole list and frames it clear of the whole HUD (E3-S9; E3-S7's
## jump-to-hole reuses it): the camera centres its tee and cup in free_view_rect_for them,
## zoomed out until both show, as far as the farthest step (0.175x, D45, sized so every
## nine_holes fixture hole fits at 1280 x 720); a hole too long even for that keeps its tee
## inside the free view and runs off the screen toward its cup (CourseCamera.frame_points),
## its cup either off the screen or in the free view, never under a control (E3-S26). False, changing nothing, when the
## course has no hole `number` with its tee and cup on the map. `slot` picks that one of several
## holes sharing `number` (E3-S11) while it still has the number. With `collapse` (E3-S65, the
## default) it collapses the hole list first, so the framed hole gets the room the list frees
## (the strip under the collapsed panel, free_view_rect_for); the player's own expand holds until
## the next framing.
func frame_hole(number: int, slot: int = -1, collapse: bool = true) -> bool:
	var h: HoleData = null
	if slot >= 0 and slot < course.holes.size() and course.holes[slot].number == number:
		h = course.holes[slot]
	else:
		slot = -1
		for each: HoleData in course.holes:
			if each.number == number:
				h = each
				break
	if h == null or not course.in_bounds(h.tee.x, h.tee.y) or not course.in_bounds(h.cup.x, h.cup.y):
		return false
	build_tool.select_hole(number, slot)
	if collapse:
		hole_panel.set_collapsed(true)
	# Its issue boxes keep off its line of play where they can (E3-S40).
	course_view.framed_slot = course.holes.find(h)
	var tee: Vector2 = tile_world(h.tee)
	var cup: Vector2 = tile_world(h.cup)
	camera.frame_points(tee, cup, free_view_rect_for(tee, cup), free_view_rects())
	return true


## The HUD controls that sit over the view and are shown now, in three groups by the screen edge
## they hold: the left column (mode label, buttons, land panel), the right panels (hole panel,
## score card) and the bottom panels (build palette, swing panel). The green view (E3-S52) is not
## one: it sits inside the free view, centred in it, not on an edge, and only in Play, where no
## hole is framed.
func hud_controls() -> Array[Control]:
	var out: Array[Control] = []
	for group: Array in _hud_groups():
		for c: Control in group:
			if c.visible:
				out.append(c)
	return out


func _hud_groups() -> Array:
	return [
		[mode_label, mode_button, new_course_button, new_sandbox_button, land_panel, money_panel,
				sim_speed_panel, feed_panel],
		[hole_panel, score_card],
		[build_palette, swing_panel],
	]


## The part of the view, in screen px, that the HUD leaves free (E3-S9): right of the left
## column, left of the right panels and above the bottom panels, counting only those shown
## (hud_controls), so it overlaps none of them. Hole framing (frame_hole) fits the hole inside
## it, so no control covers the tee or the pin. It follows the right panels' height (E3-S10):
## of the strip left of them and the strip under them (free_view_rects), it takes the larger.
func free_view_rect() -> Rect2:
	var strips: Array[Rect2] = free_view_rects()
	return strips[1] if strips[1].get_area() > strips[0].get_area() else strips[0]


## The free view hole framing uses for world points `a` and `b` (a tee and cup, E3-S10): of the
## strip beside the right panels and the strip under them, the one that shows both at the
## nearest zoom (CourseCamera.frame_zoom_index), or at a tie the larger. So a collapsed hole
## list frees the map under it for a hole that fits there better, even when the strip beside
## the panel is the larger. When neither fits them even at the farthest zoom (E3-S26), the one
## whose framing keeps the cup clear of the controls and shows more of the tee-to-cup line
## (CourseCamera.frame_placement) wins, the larger at a tie.
func free_view_rect_for(a: Vector2, b: Vector2) -> Rect2:
	var strips: Array[Rect2] = free_view_rects()
	var best: Rect2 = free_view_rect()
	var best_zoom: int = camera.frame_zoom_index(a, b, best.size)
	for strip: Rect2 in strips:
		if not strip.has_area():
			continue
		var z: int = camera.frame_zoom_index(a, b, strip.size)
		if z > best_zoom:
			best = strip
			best_zoom = z
	if best_zoom > 0 or camera.fits(a, b, camera.tuning.zoom_levels[0], best.size):
		return best
	var best_f: CourseCamera.Framing = camera.frame_placement(a, b, best, strips)
	for strip: Rect2 in strips:
		if not strip.has_area() or strip == best:
			continue
		var f: CourseCamera.Framing = camera.frame_placement(a, b, strip, strips)
		if (f.cup_clear and not best_f.cup_clear) or (f.cup_clear == best_f.cup_clear and f.shown > best_f.shown + 0.001):
			best = strip
			best_f = f
	return best


## The two strips of the view the HUD leaves free (E3-S10), in screen px, both right of the
## left column and above the bottom panels: [0] left of the right panels, full height; [1]
## under the right panels, full width. Neither overlaps a shown control.
func free_view_rects() -> Array[Rect2]:
	var r := Rect2(Vector2.ZERO, camera.view_size())
	var left: float = r.position.x
	var right: float = r.end.x
	var below: float = r.position.y
	var bottom: float = r.end.y
	var groups: Array = _hud_groups()
	for c: Control in groups[0]:
		if c.visible:
			left = maxf(left, _hud_rect(c).end.x)
	for c: Control in groups[1]:
		if c.visible:
			right = minf(right, _hud_rect(c).position.x)
			below = maxf(below, _hud_rect(c).end.y)
	for c: Control in groups[2]:
		if c.visible:
			bottom = minf(bottom, _hud_rect(c).position.y)
	var beside := Rect2(left, r.position.y, maxf(right - left, 0.0), maxf(bottom - r.position.y, 0.0))
	var under := Rect2(left, below, maxf(r.end.x - left, 0.0), maxf(bottom - below, 0.0))
	return [beside, under]


## Where HUD control `c` sits on screen as the layout will place it: its anchored size, at
## least its minimum size, grown from its anchored edge (Control.grow_horizontal and
## grow_vertical). A panel whose rows just changed has not been resized yet (that is deferred),
## so this reads its anchors and offsets rather than its current size, whether it is about to
## grow or, its list collapsed (E3-S10), to shrink.
func _hud_rect(c: Control) -> Rect2:
	var parent: Vector2 = c.get_parent_area_size()
	var anchored := Rect2(
			Vector2(c.anchor_left * parent.x + c.offset_left, c.anchor_top * parent.y + c.offset_top),
			Vector2.ZERO)
	anchored.end = Vector2(c.anchor_right * parent.x + c.offset_right,
			c.anchor_bottom * parent.y + c.offset_bottom)
	var size: Vector2 = anchored.size.max(c.get_combined_minimum_size())
	var pos: Vector2 = anchored.position
	match c.grow_horizontal:
		Control.GROW_DIRECTION_BEGIN:
			pos.x = anchored.end.x - size.x
		Control.GROW_DIRECTION_BOTH:
			pos.x = anchored.get_center().x - size.x * 0.5
	match c.grow_vertical:
		Control.GROW_DIRECTION_BEGIN:
			pos.y = anchored.end.y - size.y
		Control.GROW_DIRECTION_BOTH:
			pos.y = anchored.get_center().y - size.y * 0.5
	# From the parent's space to the screen's, as the control's own transform sits now.
	return Rect2(c.get_global_rect().position - c.position + pos, size)


## The centre of tile `cell`'s top in the camera's space.
func tile_world(cell: Vector2i) -> Vector2:
	var at: Vector2 = Iso.tile_to_screen(Vector2(cell), course.get_height(cell.x, cell.y))
	return camera.get_parent().to_local(course_view.to_global(at))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		toggle_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(SAVE_ACTION):
		save_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(LOAD_ACTION):
		load_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(DEBUG_SHOT_ACTION) and mode == Mode.PLAY and OS.is_debug_build():
		fire_debug_shot()
		get_viewport().set_input_as_handled()


## Saves the game to `path` (E4-S7, GameSave): the course, the guests' seed, the morning of the
## day under way, the economy (economy_to_save) and the feed as it stood that morning. The notice
## says so, and names any half-placed hole the file leaves out.
func save_game(path: String = GameSave.PATH) -> Error:
	var s := GameSave.State.new()
	s.course = course
	s.seed_value = guest_sim.base_seed
	s.day = guest_sim.morning_day()
	s.feed_data = guest_sim.feed.to_save(s.day)
	economy_to_save(s)
	var dropped: Array[int] = []
	var err := GameSave.save_file(s, path, dropped)
	save_notice.show_lines(SaveNotice.save_lines(err, s.day, dropped, course))
	return err


## Loads the game saved at `path` (E4-S7): the course with a fresh builder, the morning of the
## saved day, its feed and economy; the notice lists every hole the builder closed on load with
## its reason (D35, D47). A missing or faulty save changes nothing but the notice. True when
## it loaded.
func load_game(path: String = GameSave.PATH) -> bool:
	var errors: Array[String] = []
	var s := GameSave.load_file(path, errors, guest_sim.tuning.rating_window,
			guest_sim.feed_tuning.max_entries)
	if s == null:
		save_notice.show_lines(SaveNotice.load_lines(errors, 0, []))
		return false
	land_seed = s.seed_value
	show_course(s.course)
	guest_sim.resume_at(s.day)
	guest_sim.feed.copy_from(s.feed)
	economy_from_save(s)
	save_notice.show_lines(SaveNotice.load_lines([], s.day, build_tool.builder.closed_on_load))
	return true


## The save's economy fields (E4-S7's interface): `money` is the balance (E4-S2) as of the
## morning the load replays from (E4-S4): less the fees taken today, which the replayed day takes
## again; what was built today stays paid for. E4-S5 fills `rating_history` from the rating.
func economy_to_save(s: GameSave.State) -> void:
	var b: CourseBuilder = build_tool.builder
	s.unlimited_money = b.has_unlimited_money()
	s.money = 0 if s.unlimited_money else b.balance() - ledger.fees
	s.rating_history = rating_history.duplicate()


## Takes the economy back from a loaded save (economy_to_save's other half): the balance, through
## the builder (CourseBuilder.restore_balance), an empty ledger, and the rating history.
func economy_from_save(s: GameSave.State) -> void:
	build_tool.builder.restore_balance(s.money, s.unlimited_money)
	ledger.clear(build_tool.builder.balance(), build_tool.builder.has_unlimited_money())
	money_panel.refresh()
	rating_history = s.rating_history.duplicate()


## The green fee a guest pays at the first tee (E4-S4). The one place the fee is read: E4-S6's
## slider replaces this body. Until then 80% of D56's ceiling at 3 stars ($60, D58's best fee).
func green_fee() -> int:
	return roundi(PLACEHOLDER_FEE_SHARE * build_tool.builder.economy.fee_ceiling(PLACEHOLDER_STARS))


## A guest arrived at the first tee (E4-S4): it pays the green fee.
func _on_guest_arrived(_guest: Guest) -> void:
	var fee: int = green_fee()
	build_tool.builder.credit(fee)
	ledger.add_fee(fee)


## The day's end (E4-S4, GuestSim.day_ended): upkeep for each hole open at dusk, and the day's
## line for the next morning.
func _on_day_ended(_day: int, _finished: GuestBrain) -> void:
	var b: CourseBuilder = build_tool.builder
	var open: int = 0
	for h: HoleData in course.holes:
		if h.open:
			open += 1
	var upkeep: int = open * b.economy.upkeep_per_open_hole
	ledger.close(b.balance(), upkeep)
	b.debit(upkeep)
	money_panel.refresh()


## A new morning (E4-S4): the ledger starts on it.
func _on_day_started(d: int) -> void:
	var b: CourseBuilder = build_tool.builder
	ledger.start(d, b.balance(), b.has_unlimited_money())


## Keeps the camera on a moving ball (E2-S8), unless the player panned away to scout.
## While aiming at rest it frames the ball and the aim marker together (pillar 2), so the
## player sees where the shot goes before striking.
func _process(_delta: float) -> void:
	if mode != Mode.PLAY:
		return
	# The green view opens, follows the putt and closes (E3-S52), centred in the free view.
	green_view.follow(free_view_rect())
	update_cup_pointer()
	if shot_view.playing:
		camera.clear_lead()
		camera.set_focus(_ball_world())
	elif aim_view.visible and aim_view.prediction != null:
		camera.set_focus(_ball_world())
		camera.set_lead(_aim_marker_world())
	else:
		camera.clear_lead()


## Points the edge marker at the played hole's cup while it is outside the free view (E3-S64),
## so a neighbouring hole's flag on screen never reads as this hole's; hidden otherwise and in
## Build.
func update_cup_pointer() -> void:
	var h: HoleData = swing_control.hole
	if mode != Mode.PLAY or h == null or not course.in_bounds(h.cup.x, h.cup.y):
		cup_pointer.hide_marker()
		return
	cup_pointer.follow(camera.screen_point(tile_world(h.cup)), free_view_rect(), h.number)


func toggle_mode() -> void:
	set_mode(Mode.PLAY if mode == Mode.BUILD else Mode.BUILD)


func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	_apply_mode()
	if mode == Mode.PLAY:
		_begin_play()
	else:
		shot_view.clear()
		reaction_tags.played_hole = null
	_refresh_label()
	mode_changed.emit(mode)


## Puts the ball on the picked hole's tee aimed at its cup (SwingControl.hole_to_play: the
## hole list's pick, E3-S2, else the lowest-numbered hole with a tee; or, when the course has
## no tee yet, on no_hole_tile) for the swing (E2-S7), with a fresh score, and centres the
## camera on it (E2-S8).
func _begin_play() -> void:
	swing_control.begin(course, no_hole_tile(), debug_shot.heading_deg, build_tool.hole_number,
			build_tool.picked_slot())
	# The played hole's map tag would stand over the back of its green (E3-S7 review).
	reaction_tags.played_hole = swing_control.hole
	camera.centre_on(_ball_world(), true)


## Where Play rests the ball on a course with no hole: the debug shot's tile when the player
## owns it (New sandbox, the fixture courses); else the centre of the starting block (D26),
## else the first owned tile, so the ball never starts out of bounds on unowned land (D29).
func no_hole_tile() -> Vector2i:
	var t: Vector2i = debug_shot.start_tile
	if course.is_owned(t.x, t.y):
		return t
	var block := LandGenerator.start_block(course.width, course.height)
	var centre: Vector2i = block.get_center()
	if course.is_owned(centre.x, centre.y):
		return centre
	for y: int in course.height:
		for x: int in course.width:
			if course.is_owned(x, y):
				return Vector2i(x, y)
	return t


## The ball's drawn point in the camera's space.
func _ball_world() -> Vector2:
	var p := shot_view.get_parent() as Node2D
	return camera.get_parent().to_local(p.to_global(shot_view.ball_screen())) \
			if shot_view.ball != null else camera.position


## The aim marker's drawn point in the camera's space.
func _aim_marker_world() -> Vector2:
	return camera.get_parent().to_local(aim_view.to_global(aim_view.marker_screen))


## A shot starts: centre on the ball alone (E2-S8), even after a pan. The zoom stays as
## the aim framed it, so the flight is followed at the same scale.
func _on_struck(_shot: ShotLaunch) -> void:
	camera.clear_lead()
	camera.centre_on(_ball_world())


## Holed or picked up: no more swings, so the swing panel goes until Play starts again.
func _on_hole_finished(_score: HoleScore) -> void:
	swing_panel.visible = false


## The ball rests (or was dropped): centre on it for the next shot (E2-S8).
func _on_came_to_rest(_at: Vector3) -> void:
	if mode == Mode.PLAY:
		camera.centre_on(_ball_world(), true)


## The build tool, its palette, the hole and land panels, New course, New sandbox and the issue highlights exist
## only in Build mode; the guests' day (GuestSim, GuestView, its speed panel) in both (D53), its feed panel in Play. Play never waits for the validator (pillar 1): a hole that fails a rule
## is still played; the rules only decide whether guests may play it (Open).
func _apply_mode() -> void:
	var building: bool = mode == Mode.BUILD
	build_tool.active = building
	swing_control.active = not building
	swing_panel.visible = not building
	build_palette.visible = building
	hole_panel.visible = building
	land_panel.visible = building
	new_sandbox_button.visible = building
	new_course_button.visible = building
	score_card.visible = not building
	# The guests' day runs, shows and has its speed controls in Build as in Play (D53, E3-S62, as
	# SimGolf; E3-S5 held it in Build). Pause (P) is Build's quiet mode.
	guest_sim.running = true
	guest_view.visible = true
	sim_speed_panel.visible = true
	# The balance shows in Build and Play (E4-S2).
	money_panel.visible = true
	_place_speed_panel()
	# The feed panel is read in Play (its lines link to Build): it shows from the start of Play,
	# so the free view never shifts at its first line (E3-S67). In Build the feed still takes every
	# line, and its map tags and the hole panel's reaction line update as guests finish (E3-S7).
	feed_panel.set_in_play(not building)
	mode_button.text = "Back to Build (Tab)" if not building else "Play hole (Tab)"
	course_view.issues_visible = building
	# The placeholder tiles' two-letter labels are for Build; Play draws the label-free sheets
	# (E3-S55). A texture swap, not a redraw.
	course_view.play_art = not building
	# The contour overlay is Play's (E3-S57), on unless the player hid it (toggle_topo, T).
	course_view.topo.enabled = not building
	# The line of play is Build's (E3-S46): Play has its own aim line.
	course_view.play_lines.enabled = building
	# The green view is Play's only (E3-S52); Main._process opens it there.
	if building:
		green_view.close()
		cup_pointer.hide_marker()


## The speed panel stands in the left column under the controls shown (E3-S62): in Play where
## the scene puts it, under the mode button; in Build under the land panel (or New sandbox when
## it hides). The balance (E4-S2) stands just above it in both, so in Play the feed panel moves
## down under the speed panel by the balance's height. The land panel changes height with its
## rows, so it calls this again (_ready connects its resized, and the money and speed panels').
func _place_speed_panel() -> void:
	if _speed_panel_top < 0.0:
		_speed_panel_top = sim_speed_panel.offset_top
		_feed_panel_top = feed_panel.offset_top
	var top: float = _speed_panel_top
	if mode == Mode.BUILD:
		var above: float = mode_button.offset_bottom
		for c: Control in [new_course_button, new_sandbox_button, land_panel]:
			if c.visible:
				above = maxf(above, _bottom_of(c))
		top = maxf(above + SPEED_PANEL_GAP, _speed_panel_top)
	top = _stack(money_panel, top)
	top = _stack(sim_speed_panel, top)
	if mode == Mode.PLAY:
		_stack(feed_panel, maxf(top, _feed_panel_top))


## Puts `c` at `top` keeping its height, and returns where the next control under it goes.
func _stack(c: Control, top: float) -> float:
	var h: float = c.offset_bottom - c.offset_top
	c.offset_top = top
	c.offset_bottom = top + h
	return _bottom_of(c) + SPEED_PANEL_GAP


## Where `c`'s bottom will be: its top plus its anchored height, at least its minimum height.
func _bottom_of(c: Control) -> float:
	return c.offset_top + maxf(c.offset_bottom - c.offset_top, c.get_combined_minimum_size().y)


## One batch per builder tiles_changed: each issue box is tested once per batch (E3-S16).
func _on_tiles_changed(cells: Array[Vector2i]) -> void:
	course_view.refresh_cells(cells)


## After every builder check: highlight each failing rule and update the hole panel.
func _on_checked(issues: Dictionary) -> void:
	course_view.show_issues(issues, build_tool.builder.slot_issues() if build_tool.builder != null else [])
	# The line of play follows every tee, cup and corner edit (E3-S46).
	if build_tool.builder != null:
		course_view.show_play_lines(build_tool.builder.slot_lines())
	hole_panel.refresh()
	# A tag stands on its hole's cup, which an edit can move.
	reaction_tags.queue_redraw()


## True when the debug shot may fire: in Play, with no swing in progress and no ball moving.
func can_fire_debug_shot() -> bool:
	return (course != null and mode == Mode.PLAY and not swing_control.swing.in_progress()
			and not swing_control.is_ball_moving())


## The tile the debug shot is struck from (E6-S21): no_hole_tile, so its own tile where the
## player owns it (New sandbox, the fixture courses, which play it tick for tick as before) and
## owned land on a New course, where (15, 4) is unowned and the shot would go out of bounds.
func debug_shot_tile() -> Vector2i:
	return no_hole_tile()


## Fires the debug shot at its fixed power and angle, from debug_shot_tile, predicting the landing first (the
## debug key, E2-S8). Only when can_fire_debug_shot, so it never replaces the player's ball
## in flight; and it never moves the swing ball or counts a stroke (SwingControl rests only
## its own strokes).
func fire_debug_shot() -> void:
	if not can_fire_debug_shot():
		return
	var field := HeightField.new(course, BallParams.load_default())
	aim_view.clear_aim()
	shot_view.fire(course, debug_shot.start_position(field, debug_shot_tile()), debug_shot.velocity(),
			debug_shot.rng_seed)
	_refresh_label()


func _refresh_label() -> void:
	mode_label.text = Mode.keys()[mode]
