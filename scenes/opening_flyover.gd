class_name OpeningFlyover
extends Node
## The opening flyover (E21-S1, D77): a 28 to 32 s cutscene built from the game's own world,
## played on the main scene as a third state beside Build and Play (D2), never a scene of its
## own. Main plays it on first launch (HintSettings' `intro` flag unseen) and from the menu's
## Watch intro; it hides Main's course, camera and HUD while it plays and hands back to the menu.
##
## It reads, never writes: the famous course of IntroTuning.course_id is loaded into a
## CourseData of its own (FamousCourses.load_course), drawn by a CourseView of its own and
## looked at by a Camera2D of its own, all under `world`, freed when it ends. Main's course, its
## builder, its save and its guests' day are not touched (Main holds the day while it plays).
##
## Beats (every time and the camera path in scenes/intro_tuning.tres):
## - DAWN: from black, a warm tint over the course easing to day (dawn_colors), the camera high
##   over the hole and descending;
## - GLIDE: the camera glides down onto the green and back down the fairway round the corner to
##   the tee (the path's keys, a smooth curve through them, still at both ends);
## - WALK: a guest walks off the previous hole's green (or out of the clubhouse door) to the tee
##   (GuestWalk.route, played over walk_s; the golfer sheet in a group shirt);
## - AIM: the guest stands over the ball while the camera pulls out to frame the corner (the
##   whole predicted drive) and the start line draws out from the tee, straight at the trees;
## - SWING: the swing's six frames; the ball leaves at the impact frame;
## - FLIGHT: a real drive: ShotModel.full with the shape (D74), its Ball stepped at 60 Hz ticks
##   as in play, deterministic by its seed. Only its playback is eased: a slow motion through
##   the bend (slow_rate round the apex) on a presentation clock of its own, the ball drawn
##   between ticks from the prediction's path (the live ball's, tick for tick). Drawn over the
##   map: the start line fading to faint chalk dots, the ground track in sun_yellow growing under
##   the ball, the ball's shadow on it, the ball at its height with a fading trail, and a ring
##   where it lands. The camera pushes in and leads the ball, nearer through the slow motion,
##   pulls back a little as it lands and, once it rests, frames the whole drive;
## - TITLE: "Prestwick" and its line fade in, then the screen fades to black and the menu fades
##   in.
## The strike and the landing play their sounds (GameAudio); the music is Scaffold, Build's.
##
## Skip: while it plays the intro takes every input event first (`_input`; it is Main's last
## child, so nothing else sees one): a key, a mouse button or a pad button ends it at once,
## straight to the menu (`finished` with skipped true), and nothing under it sees the event.
##
## The wrappers' switch: PRESTWICK_SKIP_INTRO=1 in the environment, or `--skip-intro` after `--`
## on the command line, and Main never plays it at start (skip_requested).

## The intro ended, played out or skipped. Main opens the menu.
signal finished(skipped: bool)

enum Beat { DAWN, GLIDE, WALK, AIM, SWING, FLIGHT, TITLE, DONE }

const SKIP_ENV: String = "PRESTWICK_SKIP_INTRO"
const SKIP_ARG: String = "--skip-intro"
## Above Main's HUD (layer 1) and everything else on screen.
const OVERLAY_LAYER: int = 100
## art/palette.gpl: sun_yellow (the flight, as AimView's dots), chalk and ink.
const SUN_YELLOW := Color8(240, 200, 58)
const CHALK := Color8(240, 236, 224)
const INK := Color8(26, 28, 34)
## art/palette.gpl tree_dark: the woods past the map's edge.
const BEYOND := Color8(31, 74, 42)

@export var tuning: IntroTuning
## Steps itself each frame (_process). Tests turn it off and call advance.
var auto_advance: bool = true
## True from play until it ends.
var playing: bool = false
## The intro's clock, seconds since it began.
var time: float = 0.0
## The intro's own course and the hole it plays (never Main's).
var course: CourseData
var hole: HoleData
## The drive (ShotModel.full with the shape).
var launch: ShotLaunch
## Everything the intro shows on the map, under one node; null when it is not playing.
var world: Node2D
var view: CourseView
var camera: Camera2D
var shot_view: ShotView
var trail: Trail
var figure: Figure
## Plays the strike and the landing; Main binds its own.
var audio: GameAudio


var _field: HeightField
var _art: GolferArt
var _walk: GuestWalk
var _walk_at: float = 0.0
var _walk_end: float = 0.0
var _swing_at: float = 0.0
var _strike_at: float = 0.0
var _rest_at: float = 0.0
var _title_at: float = 0.0
var _fade_at: float = 0.0
var _end_at: float = 0.0
var _struck: bool = false
var _landed_at: float = -1.0
## The drive's prediction, made at play: the live ball's path, tick for tick.
var _pred: ShotPrediction
## The slow motion's clock: presentation seconds from the strike to each of the ball's ticks.
var _tick_at: PackedFloat32Array = PackedFloat32Array()
## The flight's apex and first touchdown, ticks.
var _apex_tick: int = 0
var _land_tick: int = 0
## Each tick's ground track point (the ball's shadow) and ball point, world (CourseView) space.
var _track_w: PackedVector2Array = PackedVector2Array()
var _ball_w: PackedVector2Array = PackedVector2Array()
## The start line, a point a yard, world space.
var _guide_w: PackedVector2Array = PackedVector2Array()
## The ball's tick now, fractional (drawn between two of the path's), and the shot seconds fed
## to the live ball (whole ticks).
var _tick: float = 0.0
var _fed_s: float = 0.0
## The corner frame the camera pulls out to while the guest aims.
var _aim_pos: Vector2 = Vector2.ZERO
var _aim_zoom: float = 1.0
## The camera path in world space: positions, times, log zooms, and their tangents.
var _key_pos: PackedVector2Array = PackedVector2Array()
var _key_t: PackedFloat32Array = PackedFloat32Array()
var _key_logz: PackedFloat32Array = PackedFloat32Array()
var _key_dpos: PackedVector2Array = PackedVector2Array()
var _key_dlogz: PackedFloat32Array = PackedFloat32Array()
var _anchors: Dictionary = {}
var _cam_logz: float = 0.0
var _overlay: CanvasLayer
var _black: ColorRect
var _titles: Control
var _walk_fps: float = 8.0


## True when the environment variable or the command line asks to skip the intro.
static func skip_requested() -> bool:
	return skip_requested_by(OS.get_environment(SKIP_ENV), OS.get_cmdline_user_args())


## skip_requested's rule: `env` (PRESTWICK_SKIP_INTRO) set to anything but "" or "0", or
## `args` (the user arguments) holding `--skip-intro`.
static func skip_requested_by(env: String, args: PackedStringArray) -> bool:
	return (not env.is_empty() and env != "0") or args.has(SKIP_ARG)


func _ready() -> void:
	if tuning == null:
		tuning = IntroTuning.load_default()


## Starts the intro: loads its course, builds its world and its titles, and takes the screen.
## False, with a warning and nothing shown, when the course does not load.
func play() -> bool:
	if playing:
		return true
	if tuning == null:
		tuning = IntroTuning.load_default()
	var errors: Array[String] = []
	course = FamousCourses.load_course(tuning.course_id, errors)
	hole = _hole(tuning.hole_number) if course != null else null
	if course == null or hole == null:
		push_warning("intro: cannot play %s hole %d: %s" % [tuning.course_id, tuning.hole_number,
				"; ".join(errors)])
		course = null
		return false
	_art = GolferArt.load_default()
	_walk_fps = GuestViewTuning.load_default().walk_fps
	var model := ShotModel.new()
	_field = HeightField.new(course, model.params)
	_build_world()
	_build_overlay()
	# The drive, and its path to rest (the prediction is the live ball's path).
	var tee := _field.tile_center(hole.tee)
	var cup := _field.tile_center(hole.cup)
	var turn_v: Variant = GuestHole.turn_of(course, hole)
	var turn: Vector2 = turn_v if turn_v != null else cup
	var aim := rad_to_deg((turn - tee).angle()) + tuning.aim_offset_deg
	launch = model.full(_field, model.clubs.club(tuning.club_id), tuning.power, tee, aim, 0.0,
			true, model.shapes.shape(tuning.shape_id))
	_pred = ShotPrediction.run_launch(course, tuning.rng_seed, launch, null, null, hole.cup)
	var from := _walk_from()
	_walk = GuestWalk.route(course, from, tee, GuestTuning.load_default(), _field.yards_per_tile)
	_anchors = {
		"tee": tee, "turn": turn, "cup": cup,
		"door": _field.tile_center(course.clubhouse_door()),
		"hole": (tee + turn + cup) / 3.0,
		"from": from,
		"walk": (tee + from) * 0.5,
	}
	_build_path()
	_build_flight()
	_walk_at = _key_t[-1]
	_walk_end = _walk_at + tuning.walk_s
	_swing_at = _walk_end + tuning.address_s
	var frames := _art.frames_per_dir(GolferArt.Anim.SWING)
	_strike_at = _swing_at + tuning.swing_s * float(_art.swing_impact_frame) / float(frames)
	_rest_at = _strike_at + _tick_at[-1]
	_title_at = _rest_at + tuning.title_delay_s
	_fade_at = _title_at + tuning.title_in_s + tuning.title_hold_s
	_end_at = _fade_at + tuning.fade_out_s
	time = 0.0
	_struck = false
	_landed_at = -1.0
	_tick = 0.0
	_fed_s = 0.0
	shot_view.show_at_rest(course, tee)
	trail.bind(self)
	camera.make_current()
	_frame_corner()
	playing = true
	_update(0.0)
	return true


## The course's placed hole numbered `number`, or null.
func _hole(number: int) -> HoleData:
	for h: HoleData in course.holes:
		if h.number == number and h.tee != HoleData.UNPLACED and h.cup != HoleData.UNPLACED:
			return h
	return null


## Where the guest's walk starts, yards: the cup of walk_from_hole, else the clubhouse door.
func _walk_from() -> Vector2:
	var from := _hole(tuning.walk_from_hole) if tuning.walk_from_hole > 0 else null
	if from != null and from != hole:
		return _field.tile_center(from.cup)
	return _field.tile_center(course.clubhouse_door())


## Ends the intro at once (a key or click while it plays): no fade, straight to the menu.
func skip() -> void:
	if playing:
		_finish(true)


## The clock time the ball leaves the club.
func strike_time() -> float:
	return _strike_at


## The clock time the ball rests.
func rest_time() -> float:
	return _rest_at


## The clock time the title begins to fade in.
func title_time() -> float:
	return _title_at


## The intro's whole length, seconds.
func duration() -> float:
	return _end_at


## The beat at the clock's time now.
func beat() -> Beat:
	return beat_at(time)


func beat_at(t: float) -> Beat:
	if not playing and t >= _end_at:
		return Beat.DONE
	if t < tuning.dawn_s:
		return Beat.DAWN
	if t < _walk_at:
		return Beat.GLIDE
	if t < _walk_end:
		return Beat.WALK
	if t < _swing_at:
		return Beat.AIM
	if t < _strike_at:
		return Beat.SWING
	if t < _title_at:
		return Beat.FLIGHT
	if t < _end_at:
		return Beat.TITLE
	return Beat.DONE


func _process(delta: float) -> void:
	if playing and auto_advance:
		advance(delta)


## Moves the intro on by `delta` seconds (at most IntroTuning.max_step_s a call, so the frame
## that built the course view skips nothing).
func advance(delta: float) -> void:
	if not playing:
		return
	var step := clampf(delta, 0.0, tuning.max_step_s)
	time += step
	_update(step)
	if time >= _end_at:
		_finish(false)


## Every input event while it plays is the intro's: a press of a key, a mouse button or a pad
## button skips it; the rest (mouse motion, releases) are swallowed.
func _input(event: InputEvent) -> void:
	if not playing:
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	var mb := event as InputEventMouseButton
	var pad := event as InputEventJoypadButton
	if (key != null and key.pressed and not key.echo) or (mb != null and mb.pressed) \
			or (pad != null and pad.pressed):
		skip()


func _finish(skipped: bool) -> void:
	playing = false
	time = maxf(time, 0.0)
	if world != null:
		world.queue_free()
	world = null
	view = null
	camera = null
	shot_view = null
	trail = null
	figure = null
	course = null
	if _overlay != null:
		if skipped or tuning.menu_fade_s <= 0.0:
			_overlay.queue_free()
		else:
			# The menu fades in from the black the intro ended on.
			_titles.queue_free()
			var tw := _overlay.create_tween()
			tw.tween_property(_black, "color:a", 0.0, tuning.menu_fade_s)
			tw.tween_callback(_overlay.queue_free)
	_overlay = null
	_black = null
	_titles = null
	finished.emit(skipped)


# --- building ---

func _build_world() -> void:
	world = Node2D.new()
	world.name = "IntroWorld"
	add_child(world)
	# Past the map's edge, dark woods rather than the empty backdrop: Dogleg Hollow
	# (Championship)'s 1st runs to the north edge, which every wide shot of it shows.
	var woods := Polygon2D.new()
	woods.name = "IntroWoods"
	woods.color = BEYOND
	var r := 1.0e5
	woods.polygon = PackedVector2Array([Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)])
	world.add_child(woods)
	view = CourseView.new()
	view.name = "IntroCourse"
	world.add_child(view)
	view.show_course(course)
	view.issues_visible = false
	view.play_art = true
	view.topo.enabled = false
	view.play_lines.enabled = false
	shot_view = ShotView.new()
	shot_view.name = "IntroShot"
	view.add_child(shot_view)
	shot_view.set_process(false)
	shot_view.landed.connect(_on_landed)
	figure = Figure.new()
	figure.name = "IntroGuest"
	figure.material = _art.shirt_material(posmod(tuning.shirt, maxi(_art.shirt_count(), 1)))
	figure.visible = false
	view.add_child(figure)
	trail = Trail.new()
	trail.name = "IntroTrail"
	view.add_child(trail)
	camera = Camera2D.new()
	camera.name = "IntroCamera"
	world.add_child(camera)


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "IntroOverlay"
	_overlay.layer = OVERLAY_LAYER
	add_child(_overlay)
	_titles = VBoxContainer.new()
	_titles.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_titles.offset_top = 64.0
	_titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_titles.modulate.a = 0.0
	_overlay.add_child(_titles)
	for line: Array in [[tuning.title, tuning.title_size, 12], [tuning.tagline, tuning.tagline_size, 6]]:
		var l := Label.new()
		l.text = line[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", line[1])
		l.add_theme_color_override("font_color", CHALK)
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", line[2])
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_titles.add_child(l)
	# Over the titles: the fade from black at the start and to black at the end.
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_black)


## The camera path's keys in world space, and their tangents (Catmull-Rom by time; still at
## the ends).
func _build_path() -> void:
	_key_pos = PackedVector2Array()
	_key_t = PackedFloat32Array()
	_key_logz = PackedFloat32Array()
	var n: int = mini(mini(tuning.path_times.size(), tuning.path_anchors.size()), tuning.path_zooms.size())
	for i: int in n:
		var at: Vector2 = _anchors.get(tuning.path_anchors[i], _anchors["hole"])
		if i < tuning.path_offsets.size():
			at += tuning.path_offsets[i]
		_key_pos.append(world_point(at))
		_key_t.append(tuning.path_times[i])
		_key_logz.append(log(maxf(tuning.path_zooms[i], 0.01)))
	_key_dpos.resize(n)
	_key_dlogz.resize(n)
	for i: int in n:
		if i == 0 or i == n - 1:
			_key_dpos[i] = Vector2.ZERO
			_key_dlogz[i] = 0.0
		else:
			var span: float = maxf(_key_t[i + 1] - _key_t[i - 1], 0.001)
			_key_dpos[i] = (_key_pos[i + 1] - _key_pos[i - 1]) / span
			_key_dlogz[i] = (_key_logz[i + 1] - _key_logz[i - 1]) / span


## The world (CourseView) point of a ground point `p` in yards, on the drawn ground.
func world_point(p: Vector2) -> Vector2:
	return _field.ground_screen(Vector3(p.x, p.y, 0.0))


## The world point of the point `p` in yards at its own height (yards).
func _world3(p: Vector3) -> Vector2:
	return Iso.point_to_screen(_field.iso_point(p))


## The flight drawn from the prediction: the slow motion's clock, the apex and the touchdown,
## and each tick's track and ball point; and the start line's points.
func _build_flight() -> void:
	var path := _pred.path
	var n := path.size()
	_apex_tick = 0
	_land_tick = n - 1
	var top := -INF
	var near := INF
	var land := Vector2(_pred.landing.x, _pred.landing.y)
	for i: int in n:
		var p := path[i]
		var up := p.z - _field.height_at(p.x, p.y)
		if up > top:
			top = up
			_apex_tick = i
	for i: int in range(_apex_tick, n):
		var d := Vector2(path[i].x, path[i].y).distance_squared_to(land)
		if d < near:
			near = d
			_land_tick = i
	# The clock: each tick takes DT / (rate × ball_speed) of presentation time.
	_tick_at = PackedFloat32Array()
	_tick_at.resize(n)
	_tick_at[0] = 0.0
	for i: int in range(1, n):
		var rate := slow_rate_at((float(i) - 0.5) / Ball.TICK_HZ) * maxf(tuning.ball_speed, 0.01)
		_tick_at[i] = _tick_at[i - 1] + Ball.DT / rate
	# The ground track: in flight on the ground under it, smoothed and pinned to the tee and
	# the touchdown (so it leaves a raised tee in a curve, not a step); on the ground, the ball.
	var flight := PackedVector2Array()
	for i: int in _land_tick + 1:
		flight.append(Vector2(path[i].x, path[i].y))
	var hs := smoothed_heights(flight, path[0].z, path[_land_tick].z)
	_track_w = PackedVector2Array()
	_ball_w = PackedVector2Array()
	for i: int in n:
		var p := path[i]
		var h: float = hs[i] if i <= _land_tick else _field.height_at(p.x, p.y)
		_track_w.append(_world3(Vector3(p.x, p.y, h)))
		_ball_w.append(_world3(p) if i <= _land_tick else _track_w[i])
	# The start line, likewise.
	var o := Vector2(launch.start.x, launch.start.y)
	var end := Trail.guide_end_of(launch)
	var steps := maxi(ceili(o.distance_to(end)), 1)
	var line := PackedVector2Array()
	for i: int in steps + 1:
		line.append(o.lerp(end, float(i) / steps))
	var gh := smoothed_heights(line, launch.start.z, _field.height_at(end.x, end.y))
	_guide_w = PackedVector2Array()
	for i: int in line.size():
		_guide_w.append(_world3(Vector3(line[i].x, line[i].y, gh[i])))


## The heights (yards) of the ground under the points `pts` (a path, about a yard apart),
## averaged over IntroTuning.track_smooth_yd each way along it and pinned to `first` and `last`
## at its ends: a smooth line over the ground with no step where a raised tee drops away.
func smoothed_heights(pts: PackedVector2Array, first: float, last: float) -> PackedFloat32Array:
	var n := pts.size()
	var out := PackedFloat32Array()
	out.resize(n)
	if n == 0:
		return out
	var along := PackedFloat32Array()
	along.resize(n)
	var sums := PackedFloat64Array()
	sums.resize(n + 1)
	sums[0] = 0.0
	for i: int in n:
		along[i] = 0.0 if i == 0 else along[i - 1] + pts[i].distance_to(pts[i - 1])
		sums[i + 1] = sums[i] + _field.height_at(pts[i].x, pts[i].y)
	var w := tuning.track_smooth_yd
	var lo := 0
	var hi := 0
	for i: int in n:
		while along[lo] < along[i] - w:
			lo += 1
		while hi + 1 < n and along[hi + 1] <= along[i] + w:
			hi += 1
		out[i] = (sums[hi + 1] - sums[lo]) / float(hi - lo + 1)
	var a0 := out[0]
	var a1 := out[n - 1]
	var total := maxf(along[n - 1], 0.001)
	for i: int in n:
		var s := along[i] / total
		out[i] += (1.0 - s) * (first - a0) + s * (last - a1)
	return out


## The ball's playback rate `t` seconds of ball time after the strike: 1 (as in play), easing
## down to IntroTuning.slow_rate round the apex and back, and up to roll_rate over roll_ramp_s
## from the touchdown, so the run out to rest does not drag.
func slow_rate_at(t: float) -> float:
	var land := float(_land_tick) / Ball.TICK_HZ
	var base := lerpf(1.0, tuning.roll_rate, smoothstep(land, land + maxf(tuning.roll_ramp_s, 0.001), t))
	return lerpf(base, tuning.slow_rate, slowness_at(t))


## The slow motion's weight at ball time `t`: 1 through its hold, 0 outside it, eased between.
func slowness_at(t: float) -> float:
	var centre := float(_apex_tick) / Ball.TICK_HZ + tuning.slow_center_s
	var d := absf(t - centre)
	var half := tuning.slow_hold_s * 0.5
	if d <= half:
		return 1.0
	return 1.0 - smoothstep(half, half + maxf(tuning.slow_ramp_s, 0.001), d)


## The ball's tick (fractional) `s` presentation seconds after the strike.
func tick_after(s: float) -> float:
	var n := _tick_at.size()
	if n == 0 or s <= 0.0:
		return 0.0
	if s >= _tick_at[n - 1]:
		return float(n - 1)
	var i := _tick_at.bsearch(s, false) - 1
	i = clampi(i, 0, n - 2)
	var span := maxf(_tick_at[i + 1] - _tick_at[i], 1e-6)
	return float(i) + clampf((s - _tick_at[i]) / span, 0.0, 1.0)


## The world point of `points` at fractional index `at`.
static func _at(points: PackedVector2Array, at: float) -> Vector2:
	var n := points.size()
	if n == 0:
		return Vector2.ZERO
	var i := clampi(floori(at), 0, n - 1)
	if i >= n - 1:
		return points[n - 1]
	return points[i].lerp(points[i + 1], at - float(i))


## The ball now, world space: at its height, and its shadow on the drawn track under it.
func ball_world() -> Vector2:
	return _at(_ball_w, _tick)


func shadow_world() -> Vector2:
	return _at(_track_w, _tick)


## The ball's drawn ground track to now, world space.
func track_world() -> PackedVector2Array:
	var out := PackedVector2Array()
	if not _struck:
		return out
	var upto := mini(floori(_tick), _track_w.size() - 1)
	out = _track_w.slice(0, upto + 1)
	out.append(shadow_world())
	return out


## The world point of the ball's tick `at` on its ground track.
func track_at(at: float) -> Vector2:
	return _at(_track_w, at)


## The start line's share drawn: 0 until guide_delay_s into the address, 1 after guide_grow_s.
func guide_share() -> float:
	var from := _walk_end + tuning.guide_delay_s
	if time <= from:
		return 0.0
	return clampf((time - from) / maxf(tuning.guide_grow_s, 0.001), 0.0, 1.0)


## The start line's alpha: guide_alpha while the guest aims, fading to guide_flight_alpha.
func guide_alpha() -> float:
	if not _struck:
		return tuning.guide_alpha
	return lerpf(tuning.guide_alpha, tuning.guide_flight_alpha,
			smoothstep(_strike_at, _strike_at + maxf(tuning.guide_fade_s, 0.001), time))


## The start line's points, world space.
func guide_world() -> PackedVector2Array:
	return _guide_w


## The apex and the touchdown, ticks.
func apex_tick() -> int:
	return _apex_tick


func land_tick() -> int:
	return _land_tick


## The ball's tick now (fractional).
func ball_tick() -> float:
	return _tick


## The clock time the ball reaches tick `at` of its path.
func time_of_tick(at: int) -> float:
	return _strike_at + _tick_at[clampi(at, 0, _tick_at.size() - 1)]


## The camera path at clock time `t`: [position, zoom].
func path_at(t: float) -> Array:
	var n := _key_t.size()
	if n == 0:
		return [Vector2.ZERO, 1.0]
	if t <= _key_t[0]:
		return [_key_pos[0], exp(_key_logz[0])]
	if t >= _key_t[n - 1]:
		return [_key_pos[n - 1], exp(_key_logz[n - 1])]
	var i := 0
	while i < n - 2 and t >= _key_t[i + 1]:
		i += 1
	var dt: float = maxf(_key_t[i + 1] - _key_t[i], 0.001)
	var s: float = (t - _key_t[i]) / dt
	var s2 := s * s
	var s3 := s2 * s
	var h00 := 2.0 * s3 - 3.0 * s2 + 1.0
	var h10 := s3 - 2.0 * s2 + s
	var h01 := -2.0 * s3 + 3.0 * s2
	var h11 := s3 - s2
	var p: Vector2 = h00 * _key_pos[i] + h10 * dt * _key_dpos[i] + h01 * _key_pos[i + 1] \
			+ h11 * dt * _key_dpos[i + 1]
	var lz: float = h00 * _key_logz[i] + h10 * dt * _key_dlogz[i] + h01 * _key_logz[i + 1] \
			+ h11 * dt * _key_dlogz[i + 1]
	return [p, exp(lz)]


# --- each frame ---

func _update(step: float) -> void:
	_update_light()
	_update_guest()
	_update_ball(step)
	_update_camera(step)
	trail.queue_redraw()


func _update_light() -> void:
	world.modulate = dawn_color(time)
	var a := 1.0 - smoothstep(0.0, maxf(tuning.fade_in_s, 0.001), time)
	if time >= _fade_at:
		a = smoothstep(_fade_at, _end_at, time)
	_black.color.a = a
	_titles.modulate.a = smoothstep(_title_at, _title_at + maxf(tuning.title_in_s, 0.001), time)


## The light over the course at clock time `t`: dawn_colors eased between dawn_times, white
## after the last.
func dawn_color(t: float) -> Color:
	var cs := tuning.dawn_colors
	var ts := tuning.dawn_times
	var n := mini(cs.size(), ts.size())
	if n == 0:
		return Color.WHITE
	if t <= ts[0]:
		return cs[0]
	for i: int in range(1, n):
		if t < ts[i]:
			return cs[i - 1].lerp(cs[i], smoothstep(ts[i - 1], ts[i], t))
	return cs[n - 1]


func _update_guest() -> void:
	if time < _walk_at:
		figure.visible = false
		return
	figure.visible = true
	var tee := _field.tile_center(hole.tee)
	var aim_dir := GolferArt.direction_of(_screen_vector(Vector2.RIGHT.rotated(deg_to_rad(launch.heading_deg))))
	if time < _walk_end:
		var share := (time - _walk_at) / maxf(tuning.walk_s, 0.001)
		var at := _walk.point_at_time(_walk.duration * share)
		var ahead := _walk.point_at_time(minf(_walk.duration * share + 0.05, _walk.duration))
		figure.at = at
		var d := GolferArt.direction_of(_screen_vector(ahead - at))
		if d >= 0:
			figure.dir = d
		figure.anim = GolferArt.Anim.WALK
		figure.frame = floori((time - _walk_at) * _walk_fps)
	else:
		figure.at = tee
		figure.dir = aim_dir
		var frames := _art.frames_per_dir(GolferArt.Anim.SWING)
		if time >= _swing_at and time < _swing_at + tuning.swing_s:
			figure.anim = GolferArt.Anim.SWING
			figure.frame = mini(floori((time - _swing_at) / tuning.swing_s * frames), frames - 1)
		else:
			figure.anim = GolferArt.Anim.IDLE
			figure.frame = 0
	figure.place(_field, _art)


func _update_ball(_step: float) -> void:
	shot_view.update_lift()
	if time < _strike_at:
		return
	if not _struck:
		_struck = true
		shot_view.fire_launch(course, launch, tuning.rng_seed, hole.cup)
		# The intro draws the ball, its shadow and its track itself, between ticks; the landing
		# cross would stand on the track.
		shot_view.sprite.visible = false
		shot_view.marker.self_modulate.a = 0.0
		if audio != null:
			audio.play(GameAudio.STRIKE.get(Surface.Type.TEE, &"strike_tee"))
	_tick = tick_after(time - _strike_at)
	# The live ball steps whole 60 Hz ticks up to the tick drawn: the same Ball, the same path.
	var want := floorf(_tick + 1e-4) / Ball.TICK_HZ
	if shot_view.playing and want > _fed_s:
		shot_view.advance(want - _fed_s)
		_fed_s = want


func _on_landed(at: Vector3) -> void:
	_landed_at = time
	if audio != null:
		audio.play(GameAudio.LAND.get(_field.surface_at(at.x, at.y), &"land_fairway"))


func _update_camera(step: float) -> void:
	if time <= _walk_at:
		var p: Array = path_at(time)
		camera.position = p[0]
		_cam_logz = log(p[1])
		camera.zoom = Vector2.ONE * float(p[1])
		return
	var tee := world_point(_field.tile_center(hole.tee))
	if time < _walk_end:
		# From the path's last key toward the tee as the guest walks, both in view.
		var s := smoothstep(_walk_at, _walk_end, time)
		var from: Vector2 = _key_pos[-1]
		camera.position = from.lerp(tee, s)
		_set_logz(lerpf(_key_logz[-1], log(tuning.walk_zoom), s))
		return
	if not _struck:
		# The corner: out from the tee to the whole drive while the guest aims.
		var s := smoothstep(_walk_end, _walk_end + maxf(tuning.aim_ease_s, 0.001), time)
		camera.position = tee.lerp(_aim_pos, s)
		_set_logz(lerpf(log(tuning.walk_zoom), log(_aim_zoom), s))
		return
	var goal: Vector2
	var zoom_goal: float
	if _landed_at < 0.0:
		# Lead the ball (its track ahead of it, lifted by half its height), down the start line:
		# the camera runs straight out along the line and follows only lateral_follow of the
		# ball's drift off it, so the ball is seen bending away across the screen.
		var lead := _tick + tuning.lead_s * Ball.TICK_HZ
		var ahead := track_at(lead) + (ball_world() - shadow_world()) * 0.5
		var o := _guide_w[0]
		var u := (_guide_w[-1] - o).normalized()
		var off := ahead - o
		var along := u * off.dot(u)
		goal = o + along + (off - along) * tuning.lateral_follow
		zoom_goal = tuning.flight_zoom * lerpf(1.0, tuning.slow_zoom, slowness_at(_tick / Ball.TICK_HZ))
	elif time < _rest_at:
		# A small pull-back as it lands, still ahead of it as it runs out.
		goal = track_at(_tick + tuning.lead_s * Ball.TICK_HZ * 0.5)
		zoom_goal = tuning.land_zoom
	else:
		# The whole drive below the title's band.
		var r := drive_rect()
		var room := camera.get_viewport_rect().size - Vector2.ONE * 2.0 * tuning.settle_margin_px \
				- Vector2(0.0, tuning.title_band_px)
		var fit := minf(room.x / maxf(r.size.x, 1.0), room.y / maxf(r.size.y, 1.0))
		zoom_goal = clampf(fit, 0.05, tuning.land_zoom)
		goal = r.get_center() - Vector2(0.0, tuning.title_band_px * 0.5) / zoom_goal
	var k := 1.0 - exp(-step / maxf(tuning.follow_time_s, 0.001))
	camera.position = camera.position.lerp(goal, k)
	var kz := 1.0 - exp(-step / maxf(tuning.zoom_time_s, 0.001))
	_set_logz(lerpf(_cam_logz, log(maxf(zoom_goal, 0.01)), kz))


func _set_logz(lz: float) -> void:
	_cam_logz = lz
	camera.zoom = Vector2.ONE * exp(lz)


## The corner frame: the whole predicted drive (the tee, the start line, the track and the ball
## at its height) and the fairway past the turn (aim_past_turn of the way on to the cup) inside
## the view less aim_margin_px each side, never nearer than aim_zoom_max.
func _frame_corner() -> void:
	var r := drive_rect()
	for i: int in range(0, _ball_w.size(), 6):
		r = r.expand(_ball_w[i])
	# And the fairway past the corner, toward the cup.
	var turn: Vector2 = _anchors["turn"]
	r = r.expand(world_point(turn.lerp(_anchors["cup"], tuning.aim_past_turn)))
	var room := camera.get_viewport_rect().size - Vector2.ONE * 2.0 * tuning.aim_margin_px
	var fit := minf(room.x / maxf(r.size.x, 1.0), room.y / maxf(r.size.y, 1.0))
	_aim_zoom = clampf(fit, 0.05, tuning.aim_zoom_max)
	_aim_pos = r.get_center()


## The corner frame's camera position and zoom.
func aim_frame() -> Array:
	return [_aim_pos, _aim_zoom]


## The whole drive in world space: the tee, the start line and the ball's whole ground track.
func drive_rect() -> Rect2:
	var r := Rect2(world_point(Vector2(launch.start.x, launch.start.y)), Vector2.ZERO)
	for p: Vector2 in _guide_w:
		r = r.expand(p)
	for p: Vector2 in _track_w:
		r = r.expand(p)
	return r


## Screen vector (world space) of a step `d` in yards.
func _screen_vector(d: Vector2) -> Vector2:
	var t := d / _field.yards_per_tile
	return Vector2((t.x - t.y) * Iso.HALF_W, (t.x + t.y) * Iso.HALF_H)


## The guest: one golfer figure, Y-sorted with the course like GuestView's.
class Figure:
	extends Node2D
	## Where its feet stand, yards.
	var at: Vector2 = Vector2.ZERO
	var dir: int = 0
	var anim: GolferArt.Anim = GolferArt.Anim.IDLE
	var frame: int = 0
	var _feet: Vector2 = Vector2.ZERO
	var _tex: Texture2D
	var _anchor: Vector2 = Vector2.ZERO
	var _scale: float = 1.0
	var _min_scale: float = -1.0

	func place(field: HeightField, art: GolferArt) -> void:
		var ground := Vector3(at.x, at.y, 0.0)
		var iso := field.iso_point(ground)
		_feet = field.ground_screen(ground)
		position = Vector2(_feet.x, Iso.object_sort_key(Vector2(iso.x, iso.y), field.drawn_steps(at.x, at.y)))
		_tex = art.frame(anim, dir, frame)
		_anchor = Vector2(art.anchor())
		var view_scale := get_viewport().get_canvas_transform().get_scale().x if is_inside_tree() else 1.0
		if _min_scale < 0.0:
			_min_scale = GuestViewTuning.load_default().figure_min_screen_scale
		_scale = maxf(1.0, _min_scale * HazardCue.screen_k(view_scale))
		queue_redraw()

	func _draw() -> void:
		if _tex == null:
			return
		var feet := _feet - position
		draw_set_transform(feet, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 7.0 * _scale, Color(INK, 0.6))
		draw_set_transform(feet, 0.0, Vector2(_scale, _scale))
		draw_texture(_tex, -_anchor)
		draw_set_transform(Vector2.ZERO)


## The drive, drawn over the map at a fixed width on screen: its start line (the launch heading,
## to the carry) in chalk dots, bright while the guest aims and faint in flight; the ball's
## ground track so far in sun_yellow on ink; a ring where it lands; and the ball itself, between
## ticks, at its height over its shadow on the track, with a fading chalk trail behind it.
class Trail:
	extends Node2D
	var _intro: OpeningFlyover

	func _init() -> void:
		z_index = 1

	func bind(intro: OpeningFlyover) -> void:
		_intro = intro

	## The start line's far end, yards: the launch heading out to the target carry.
	static func guide_end_of(s: ShotLaunch) -> Vector2:
		return Vector2(s.start.x, s.start.y) + Vector2.RIGHT.rotated(deg_to_rad(s.heading_deg)) * s.target_carry

	func guide_end() -> Vector2:
		return guide_end_of(_intro.launch)

	## The ball's ground track drawn so far, yards: the prediction's path to the ball's tick.
	func track() -> PackedVector2Array:
		var out := PackedVector2Array()
		var sv := _intro.shot_view
		if sv == null or sv.prediction == null or not _intro._struck:
			return out
		var path := sv.prediction.path
		var upto := mini(floori(_intro.ball_tick()) + 1, path.size())
		for i: int in upto:
			out.append(Vector2(path[i].x, path[i].y))
		return out

	## How far the track drawn so far has bent off its start line, yards (the most, square to
	## the line).
	func bend_yd() -> float:
		var s := _intro.launch
		var o := Vector2(s.start.x, s.start.y)
		var d := Vector2.RIGHT.rotated(deg_to_rad(s.heading_deg))
		var most := 0.0
		for p: Vector2 in track():
			most = maxf(most, absf(d.cross(p - o)))
		return most

	func _draw() -> void:
		if _intro == null or _intro.launch == null or not _intro.playing:
			return
		var t := _intro.tuning
		var k := HazardCue.screen_k(get_viewport().get_canvas_transform().get_scale().x)
		_draw_guide(t, k)
		if not _intro._struck:
			return
		# The ground track, ink under sun_yellow.
		var pts := PackedVector2Array()
		for w: Vector2 in _intro.track_world():
			if pts.is_empty() or w.distance_squared_to(pts[-1]) > 0.25 * k * k:
				pts.append(w)
		if pts.size() >= 2:
			draw_polyline(pts, Color(SUN_YELLOW, 0.25), (t.track_width_px + 8.0) * k, true)
			draw_polyline(pts, INK, (t.track_width_px + 2.5) * k, true)
			draw_polyline(pts, SUN_YELLOW, t.track_width_px * k, true)
		_draw_landing(t, k)
		_draw_ball(t, k)

	func _draw_guide(t: IntroTuning, k: float) -> void:
		var line := _intro.guide_world()
		var share := _intro.guide_share()
		if share <= 0.0 or line.is_empty():
			return
		var a := _intro.guide_alpha()
		var upto := floori(share * (line.size() - 1))
		var last := Vector2.INF
		for i: int in upto + 1:
			var w := line[i]
			if last == Vector2.INF or w.distance_to(last) >= t.guide_gap_px * k:
				draw_circle(w, (t.guide_dot_px + 1.0) * k, Color(INK, a))
				draw_circle(w, t.guide_dot_px * k, Color(CHALK, a))
				last = w

	## A ring growing out of the landing point, 2:1 like the tile footprint, fading.
	func _draw_landing(t: IntroTuning, k: float) -> void:
		var since := _intro.time - _intro.time_of_tick(_intro.land_tick())
		if since < 0.0 or since > t.land_ring_s:
			return
		var s := since / maxf(t.land_ring_s, 0.001)
		var at := _intro.track_at(float(_intro.land_tick()))
		var r := t.land_ring_px * k * lerpf(0.3, 1.0, sqrt(s))
		draw_set_transform(at, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(INK, 0.5 * (1.0 - s)), 5.0 * k, true)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(CHALK, 1.0 - s), 3.0 * k, true)
		draw_set_transform(Vector2.ZERO)

	## The ball between ticks over its shadow, and its trail in the air.
	func _draw_ball(t: IntroTuning, k: float) -> void:
		var tick := _intro.ball_tick()
		var land := float(_intro.land_tick())
		var ball := _intro.ball_world()
		var shadow := _intro.shadow_world()
		# The flight's arc: the ball's path through the air to now, chalk, bright over its last
		# trail_s and fading to trail_alpha behind, so the whole bend stays drawn.
		var span := t.trail_s * Ball.TICK_HZ
		var head := minf(tick, land)
		if head > 1.0:
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			var at := 0.0
			while true:
				pts.append(_intro._at(_intro._ball_w, at))
				var fresh := clampf(1.0 - (tick - at) / maxf(span, 0.001), 0.0, 1.0)
				cols.append(Color(CHALK, lerpf(t.trail_alpha, 0.95, fresh)))
				if at >= head:
					break
				at = minf(at + 3.0, head)
			draw_polyline_colors(pts, cols, t.trail_width_px * k, true)
		# The shadow, smaller as the ball climbs.
		var lift := (shadow.y - ball.y) / Iso.STEP_PX
		var sv := _intro.shot_view
		var ss := lerpf(1.0, sv.shadow_min_scale, clampf(lift / sv.shadow_fade_steps, 0.0, 1.0))
		draw_set_transform(shadow, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, maxf(sv.shadow_radius, 5.0 * k) * ss, Color(INK, 0.6))
		draw_set_transform(Vector2.ZERO)
		var r := sv.ball_draw_radius(k)
		BallArt.draw(self, ball, r + sv.ball_outline_width(k), false,
				tick < land and BallArt.spin_at(_intro.time))
