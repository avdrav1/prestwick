class_name Main
extends Node2D
## The one main scene. Build and Play are states on it, never separate scenes (D2).

enum Mode { BUILD, PLAY }

signal mode_changed(new_mode: Mode)

const TOGGLE_ACTION: StringName = &"toggle_mode"
## Fires the debug shot in Play, in debug builds only (E2-S8; F3).
const DEBUG_SHOT_ACTION: StringName = &"debug_shot"

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
	land_panel.bind(build_tool)
	swing_control.bind(shot_view, aim_view)
	swing_panel.bind(swing_control)
	swing_control.changed.connect(_refresh_label)
	swing_control.struck.connect(_on_struck)
	swing_control.hole_finished.connect(_on_hole_finished)
	shot_view.came_to_rest.connect(_on_came_to_rest)
	score_card.bind(swing_control)
	guest_view.bind(guest_sim)
	sim_speed_panel.bind(guest_sim)
	feed_panel.bind(guest_sim)
	feed_panel.hole_requested.connect(_on_feed_hole_requested)
	reaction_tags.bind(guest_sim.feed)
	hole_panel.bind_feed(guest_sim.feed)
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


## A feed line was clicked (E3-S7): jump_to_hole, unless a swing is under way or the ball is
## moving in Play, when the click is dropped so a line coming in under the cursor never ends a
## shot or the round. True when it jumped.
func _on_feed_hole_requested(number: int, slot: int = -1) -> bool:
	if mode == Mode.PLAY and (swing_control.swing.in_progress() or swing_control.is_ball_moving()):
		return false
	return jump_to_hole(number, slot)


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
	return h != null and frame_hole(h.number)


## Picks hole `number` in the hole list and frames it clear of the whole HUD (E3-S9; E3-S7's
## jump-to-hole reuses it): the camera centres its tee and cup in free_view_rect_for them,
## zoomed out until both show, as far as the farthest step (0.175x, D45, sized so every
## nine_holes fixture hole fits at 1280 x 720); a hole too long even for that keeps its tee
## inside the free view and runs off the screen toward its cup (CourseCamera.frame_points). False, changing nothing, when the
## course has no hole `number` with its tee and cup on the map. `slot` picks that one of several
## holes sharing `number` (E3-S11) while it still has the number.
func frame_hole(number: int, slot: int = -1) -> bool:
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
	var tee: Vector2 = tile_world(h.tee)
	var cup: Vector2 = tile_world(h.cup)
	camera.frame_points(tee, cup, free_view_rect_for(tee, cup))
	return true


## The HUD controls that sit over the view and are shown now, in three groups by the screen edge
## they hold: the left column (mode label, buttons, land panel), the right panels (hole panel,
## score card) and the bottom panels (build palette, swing panel).
func hud_controls() -> Array[Control]:
	var out: Array[Control] = []
	for group: Array in _hud_groups():
		for c: Control in group:
			if c.visible:
				out.append(c)
	return out


func _hud_groups() -> Array:
	return [
		[mode_label, mode_button, new_course_button, new_sandbox_button, land_panel, sim_speed_panel,
				feed_panel],
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
## the panel is the larger.
func free_view_rect_for(a: Vector2, b: Vector2) -> Rect2:
	var best: Rect2 = free_view_rect()
	var best_zoom: int = camera.frame_zoom_index(a, b, best.size)
	for strip: Rect2 in free_view_rects():
		if not strip.has_area():
			continue
		var z: int = camera.frame_zoom_index(a, b, strip.size)
		if z > best_zoom:
			best = strip
			best_zoom = z
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
	elif event.is_action_pressed(DEBUG_SHOT_ACTION) and mode == Mode.PLAY and OS.is_debug_build():
		fire_debug_shot()
		get_viewport().set_input_as_handled()


## Keeps the camera on a moving ball (E2-S8), unless the player panned away to scout.
## While aiming at rest it frames the ball and the aim marker together (pillar 2), so the
## player sees where the shot goes before striking.
func _process(_delta: float) -> void:
	if mode != Mode.PLAY:
		return
	if shot_view.playing:
		camera.clear_lead()
		camera.set_focus(_ball_world())
	elif aim_view.visible and aim_view.prediction != null:
		camera.set_focus(_ball_world())
		camera.set_lead(_aim_marker_world())
	else:
		camera.clear_lead()


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
## only in Build mode; the guests' day (GuestSim, GuestView, its speed panel) only in Play. Play never waits for the validator (pillar 1): a hole that fails a rule
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
	# The guests' day runs, shows and has its speed controls in Play (E3-S5); Build holds it.
	guest_sim.running = not building
	guest_view.visible = not building
	sim_speed_panel.visible = not building
	# The feed is read in Play, where the day runs; its tags stay on the map in Build (E3-S7).
	feed_panel.visible = not building
	mode_button.text = "Back to Build (Tab)" if not building else "Play hole (Tab)"
	course_view.issues_visible = building


func _on_tiles_changed(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		course_view.refresh_cell(cell)


## After every builder check: highlight each failing rule and update the hole panel.
func _on_checked(issues: Dictionary) -> void:
	course_view.show_issues(issues)
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
