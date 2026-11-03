class_name SwingControl
extends Node2D
## Play-mode stroke input (E2-S7): the ball the next swing strikes, the aim, the club picker
## and the three-click swing (golf/swing.gd). It keeps the aim line and marker (AimView) on a
## perfect swing's prediction and fires the struck ball through ShotView. Active in Play
## only (Main toggles `active`). A reader of the course; it never writes it.
##
## Input: the `swing` action (Space) or a left click on the map is a swing click (the click
## does not re-aim; the motion before it already did). The mouse aims at the tile the player
## sees under it (TilePicker, the same top-surface pick Build uses) while no swing is in
## progress; `aim_left` and `aim_right` (arrow keys) turn the aim by
## SwingTuning.aim_key_step_deg, and after a key turn the mouse takes the aim back only once
## it moves SwingTuning.mouse_reaim_px from where it was; `club_prev` and
## `club_next` (up and down) step through the clubs the lie and stroke allow (D13). Sits at
## the CourseView's origin, so local points are course screen space.
##
## The hole (E2-S8): the ball and the aim know hole 1's cup, so a ball can be holed, and a
## HoleScore (golf/hole_score.gd) counts each stroke the control struck, its penalty
## strokes (a water or OB drop, D15) and whether it holed. The next stroke starts where the
## ball rests or was dropped. Play goes on until the ball is holed or picked up at the
## stroke limit (D12); after that no swing starts until the hole begins again.

## Emitted when the club, the legal clubs, the aim or the swing's phase changes.
signal changed
## Emitted when a swing strikes the ball.
signal struck(shot: ShotLaunch)
## Emitted when a struck ball comes to rest and its stroke is counted.
signal stroke_counted(score: HoleScore)
## Emitted once when the hole is finished: holed, or picked up at the limit.
signal hole_finished(score: HoleScore)

const SWING_ACTION: StringName = &"swing"
const AIM_LEFT: StringName = &"aim_left"
const AIM_RIGHT: StringName = &"aim_right"
const CLUB_PREV: StringName = &"club_prev"
const CLUB_NEXT: StringName = &"club_next"

## golf/swing_tuning.tres.
var tuning: SwingTuning

var swing: Swing
var model: ShotModel
var course: CourseData
var field: HeightField
## Where the ball the next swing strikes rests, yards.
var ball_at: Vector2 = Vector2.ZERO
## The aim, degrees from +x toward +y (Ball.launch_velocity).
var aim_deg: float = 0.0
## The selected club, always one of `legal`.
var club: Club
## The clubs this stroke may use (ClubSet.legal), in bag order.
var legal: Array[Club] = []
## Swings struck since the ball was set on the tee (begin).
var strokes: int = 0
## The hole being played (hole 1), or null when the course has no tee yet.
var hole: HoleData
## The hole's score, or null with no hole.
var score: HoleScore
## True when the next stroke is the hole's first from its tee marker (the driver, D13).
var driver_stroke: bool = false
## The perfect swing's prediction the aim shows, or null.
var aim_prediction: ShotPrediction
var active: bool = false:
	set(value):
		active = value
		if not active:
			if swing != null:
				swing.reset()
			if _aim_view != null:
				_aim_view.clear()
			changed.emit()

var _shot_view: ShotView
var _aim_view: AimView
var _aim_dirty: bool = false
## True from a stroke this control struck until it comes to rest: only that ball moves
## `ball_at` (the debug shot, or any other fire through ShotView, does not).
var _own_shot: bool = false
## Viewport mouse position when an aim key last turned the aim, or null when the mouse aims.
var _key_aim_mouse: Variant = null


func _init() -> void:
	tuning = SwingTuning.load_default()
	swing = Swing.new(tuning)
	model = ShotModel.new()


## Draws through these views from now on.
func bind(shot_view: ShotView, aim_view: AimView) -> void:
	_shot_view = shot_view
	_aim_view = aim_view
	_shot_view.came_to_rest.connect(_on_came_to_rest)


## Sets the ball for a new hole on `c`: on hole 1's tee, aimed at its cup, when the course
## has them; else on `fallback_tile` aimed `fallback_aim_deg`.
func begin(c: CourseData, fallback_tile: Vector2i, fallback_aim_deg: float) -> void:
	course = c
	field = HeightField.new(c, model.params)
	strokes = 0
	_own_shot = false
	swing.reset()
	hole = _first_hole(c)
	score = HoleScore.new(hole.par) if hole != null else null
	if hole != null:
		place_ball(field.tile_center(hole.tee), true)
		if c.in_bounds(hole.cup.x, hole.cup.y):
			var to := field.tile_center(hole.cup) - ball_at
			aim_deg = rad_to_deg(to.angle())
		else:
			aim_deg = fallback_aim_deg
	else:
		place_ball(field.tile_center(fallback_tile), false)
		aim_deg = fallback_aim_deg
	_aim_dirty = true
	_refresh_aim()


## Rests the ball at `at` (yards) for the next swing. `p_driver_stroke` is D13's "first
## stroke from the tee marker". `show` draws it there (a ball that came to rest in ShotView
## is already drawn).
func place_ball(at: Vector2, p_driver_stroke: bool = false, show: bool = true) -> void:
	ball_at = at
	driver_stroke = p_driver_stroke
	_key_aim_mouse = null
	_refresh_legal()
	if show and _shot_view != null and course != null:
		_shot_view.show_at_rest(course, at)
	_aim_dirty = true


## The surface the ball rests on.
func lie_surface() -> Surface.Type:
	return field.surface_at(ball_at.x, ball_at.y)


## Picks `c` when the stroke allows it.
func select_club(c: Club) -> void:
	if c == null or not legal.has(c) or swing.in_progress():
		return
	club = c
	_aim_dirty = true
	changed.emit()


## Steps `dir` (+1 shorter, -1 longer) through the legal clubs, stopping at the ends.
func cycle_club(dir: int) -> void:
	if legal.is_empty():
		return
	var i := clampi(legal.find(club) + dir, 0, legal.size() - 1)
	select_club(legal[i])


## Turns the aim by `deg` (positive turns right on screen).
func rotate_aim(deg: float) -> void:
	if swing.in_progress() or is_ball_moving():
		return
	aim_deg = fposmod(aim_deg + deg, 360.0)
	_aim_dirty = true
	changed.emit()


## Aims at the ground point `p` (yards).
func aim_at(p: Vector2) -> void:
	if swing.in_progress() or is_ball_moving():
		return
	var to := p - ball_at
	if to.length() < 0.5:
		return
	aim_deg = fposmod(rad_to_deg(to.angle()), 360.0)
	_aim_dirty = true
	changed.emit()


## The cup the ball can drop into: hole 1's, or Ball.NO_CUP when it has none on the map.
func cup_tile() -> Vector2i:
	if hole != null and course != null and course.in_bounds(hole.cup.x, hole.cup.y):
		return hole.cup
	return Ball.NO_CUP


## True once the hole is holed or the ball picked up (D12): no more swings.
func is_finished() -> bool:
	return score != null and score.is_finished()


## True while a struck ball is still moving.
func is_ball_moving() -> bool:
	return _shot_view != null and _shot_view.playing


## One swing click. Ignored while a ball is moving or with no club.
func press() -> void:
	if not active or club == null or is_ball_moving() or is_finished():
		return
	swing.click()
	if swing.is_done():
		_strike()
	changed.emit()


## Moves the swing bar by `delta` seconds, and strikes when the bar finishes on its own.
func advance(delta: float) -> void:
	if not swing.in_progress():
		return
	var before := swing.phase
	swing.tick(delta)
	if swing.is_done():
		_strike()
	if swing.phase != before:
		changed.emit()


## The stroke a perfect swing would make now (the aim's).
func perfect_launch() -> ShotLaunch:
	return swing.perfect_launch(model, field, club, ball_at, aim_deg)


## The ball's seed for the next stroke, so the aim prediction and the live ball agree.
func next_seed() -> int:
	return strokes + 1


func _process(delta: float) -> void:
	if not active:
		return
	advance(delta)
	if _aim_dirty:
		_refresh_aim()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if not swing.in_progress() and course != null and mouse_takes_aim(motion.position):
			aim_at(_ground_under(get_local_mouse_position()))
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		press()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(SWING_ACTION):
		press()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(AIM_LEFT, true):
		_key_turn(-tuning.aim_key_step_deg)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(AIM_RIGHT, true):
		_key_turn(tuning.aim_key_step_deg)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(CLUB_PREV):
		cycle_club(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(CLUB_NEXT):
		cycle_club(1)
		get_viewport().set_input_as_handled()


## True when mouse motion to `mouse` (viewport px) should aim: always, unless an aim key
## turned the aim and the mouse has not yet moved SwingTuning.mouse_reaim_px from there.
func mouse_takes_aim(mouse: Vector2) -> bool:
	if _key_aim_mouse == null:
		return true
	if mouse.distance_to(_key_aim_mouse as Vector2) < tuning.mouse_reaim_px:
		return false
	_key_aim_mouse = null
	return true


func _key_turn(deg: float) -> void:
	rotate_aim(deg)
	_key_aim_mouse = get_viewport().get_mouse_position()


## The ground point (yards) the player sees under the screen point `local` (CourseView
## space): the tile TilePicker picks, unprojected at that tile's height for the point inside
## its top (a riser face aims at the tile's centre). Off the map, read at the ball's height.
func _ground_under(local: Vector2) -> Vector2:
	var cell := TilePicker.pick(course, local)
	var t: Vector2
	if cell == TilePicker.NONE:
		var steps := field.height_at(ball_at.x, ball_at.y) / field.yards_per_step
		t = Iso.screen_to_tile(local, steps)
	else:
		t = Iso.screen_to_tile(local, course.get_height(cell.x, cell.y))
		if absf(t.x - cell.x) > 0.5 or absf(t.y - cell.y) > 0.5:
			t = Vector2(cell)
	return (t + Vector2(0.5, 0.5)) * field.yards_per_tile


func _strike() -> void:
	var shot := swing.launch(model, field, club, ball_at, aim_deg)
	var rng_seed := next_seed()
	strokes += 1
	_own_shot = true
	swing.reset()
	if _aim_view != null:
		_aim_view.clear()
	if _shot_view != null:
		_shot_view.fire_launch(course, shot, rng_seed, cup_tile())
	struck.emit(shot)


func _on_came_to_rest(at: Vector3) -> void:
	if course == null:
		return
	if not _own_shot:
		# Someone else's ball (the debug shot): the swing ball stays where it was.
		_aim_dirty = true
		changed.emit()
		return
	_own_shot = false
	place_ball(Vector2(at.x, at.y), false, false)
	if score != null:
		var ball := _shot_view.ball
		score.record_stroke(ball.penalty_strokes, ball.holed)
		stroke_counted.emit(score)
		if score.picked_up:
			# D12: the ball is picked up.
			_shot_view.clear()
		if score.is_finished():
			hole_finished.emit(score)
	if active:
		_refresh_aim()
	changed.emit()


func _refresh_legal() -> void:
	legal = model.clubs.legal(lie_surface(), driver_stroke)
	if club == null or not legal.has(club):
		club = legal[0] if not legal.is_empty() else null
	changed.emit()


func _refresh_aim() -> void:
	_aim_dirty = false
	if not active or course == null or club == null or is_ball_moving() or is_finished():
		if _aim_view != null and (not active or is_finished()):
			_aim_view.clear()
		return
	var shot := perfect_launch()
	aim_prediction = ShotPrediction.run_launch(course, next_seed(), shot, null, null, cup_tile())
	if _aim_view != null:
		_aim_view.show_prediction(field, aim_prediction, shot.is_putt(), shot.start)


static func _first_hole(c: CourseData) -> HoleData:
	for h: HoleData in c.holes:
		if h.number == 1 and c.in_bounds(h.tee.x, h.tee.y):
			return h
	return null
