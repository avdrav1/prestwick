class_name OpeningFlyover
extends Node
## The opening flyover (E21-S1, D77): a 20 to 30 s cutscene built from the game's own world,
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
## - GLIDE: the camera glides from the green down the fairway round the corner to the tee and
##   the clubhouse (the path's keys, a smooth curve through them, still at both ends);
## - WALK: a guest walks out of the clubhouse door to the tee (GuestWalk.route, played over
##   walk_s; the golfer sheet in a group shirt);
## - SWING: the address and the swing's six frames; the ball leaves at the impact frame;
## - FLIGHT: a real drive: ShotModel.full with the shape (D74), fired into a ShotView and its
##   Ball stepped at 60 Hz of the intro's clock as in play, deterministic by its seed. Its ground
##   track is drawn in sun_yellow beside its start line in chalk dots, so the bend reads; the
##   camera follows the ball and, from its landing, pulls back to frame the whole drive;
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

enum Beat { DAWN, GLIDE, WALK, SWING, FLIGHT, TITLE, DONE }

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
	hole = null
	if course != null:
		for h: HoleData in course.holes:
			if h.number == tuning.hole_number and h.tee != HoleData.UNPLACED \
					and h.cup != HoleData.UNPLACED:
				hole = h
				break
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
	# The drive, and how long its ball takes to rest (the prediction is the live ball's path).
	var tee := _field.tile_center(hole.tee)
	var turn: Vector2 = GuestHole.turn_of(course, hole)
	var aim := rad_to_deg((turn - tee).angle()) + tuning.aim_offset_deg
	launch = model.full(_field, model.clubs.club(tuning.club_id), tuning.power, tee, aim, 0.0,
			true, model.shapes.shape(tuning.shape_id))
	var predicted := ShotPrediction.run_launch(course, tuning.rng_seed, launch, null, null, hole.cup)
	_walk = GuestWalk.route(course, _field.tile_center(course.clubhouse_door()), tee,
			GuestTuning.load_default(), _field.yards_per_tile)
	_anchors = {
		"tee": tee, "turn": turn, "cup": _field.tile_center(hole.cup),
		"door": _field.tile_center(course.clubhouse_door()),
		"hole": (tee + turn + _field.tile_center(hole.cup)) / 3.0,
		"walk": (tee + _field.tile_center(course.clubhouse_door())) * 0.5,
	}
	_build_path()
	_walk_at = _key_t[-1]
	_walk_end = _walk_at + tuning.walk_s
	_swing_at = _walk_end + tuning.address_s
	var frames := _art.frames_per_dir(GolferArt.Anim.SWING)
	_strike_at = _swing_at + tuning.swing_s * float(_art.swing_impact_frame) / float(frames)
	_rest_at = _strike_at + float(predicted.ticks) / Ball.TICK_HZ / maxf(tuning.ball_speed, 0.01)
	_title_at = _rest_at + tuning.title_delay_s
	_fade_at = _title_at + tuning.title_in_s + tuning.title_hold_s
	_end_at = _fade_at + tuning.fade_out_s
	time = 0.0
	_struck = false
	_landed_at = -1.0
	shot_view.show_at_rest(course, tee)
	trail.bind(self)
	camera.make_current()
	playing = true
	_update(0.0)
	return true


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


## The world point of `p` on the smooth ground the ball rolls on (HeightField.height_at), water
## included: the drawn track and start line follow it, so they never step down at a pond's edge.
func track_point(p: Vector2) -> Vector2:
	var iso := _field.iso_point(Vector3(p.x, p.y, _field.height_at(p.x, p.y)))
	return Iso.tile_to_screen(Vector2(iso.x, iso.y), iso.z)


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


func _update_ball(step: float) -> void:
	shot_view.update_lift()
	if time < _strike_at:
		return
	if not _struck:
		_struck = true
		shot_view.fire_launch(course, launch, tuning.rng_seed, hole.cup)
		# The intro draws its own track; the landing cross would stand on it.
		shot_view.marker.self_modulate.a = 0.0
		if audio != null:
			audio.play(GameAudio.STRIKE.get(Surface.Type.TEE, &"strike_tee"))
		shot_view.advance((time - _strike_at) * tuning.ball_speed)
	elif shot_view.playing:
		shot_view.advance(step * tuning.ball_speed)


func _on_landed(at: Vector3) -> void:
	_landed_at = time
	if audio != null:
		audio.play(GameAudio.LAND.get(_field.surface_at(at.x, at.y), &"land_fairway"))


func _update_camera(step: float) -> void:
	var goal: Vector2
	var zoom_goal: float
	var ease_t := tuning.follow_time_s
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
		var lz: float = lerpf(_key_logz[-1], log(tuning.walk_zoom), s)
		_cam_logz = lz
		camera.zoom = Vector2.ONE * exp(lz)
		return
	if not _struck:
		goal = tee
		zoom_goal = tuning.walk_zoom
	elif _landed_at < 0.0:
		var b := shot_view.ball
		goal = (shot_view.ball_screen() + shot_view.shadow_screen()) * 0.5 if b != null else tee
		zoom_goal = tuning.flight_zoom
	else:
		# The whole drive below the title's band.
		var r := drive_rect()
		var room := camera.get_viewport_rect().size - Vector2.ONE * 2.0 * tuning.settle_margin_px \
				- Vector2(0.0, tuning.title_band_px)
		var fit := minf(room.x / maxf(r.size.x, 1.0), room.y / maxf(r.size.y, 1.0))
		zoom_goal = clampf(fit, 0.05, tuning.flight_zoom)
		goal = r.get_center() - Vector2(0.0, tuning.title_band_px * 0.5) / zoom_goal
	var k := 1.0 - exp(-step / maxf(ease_t, 0.001))
	camera.position = camera.position.lerp(goal, k)
	var kz := 1.0 - exp(-step / maxf(tuning.zoom_time_s, 0.001))
	_cam_logz = lerpf(_cam_logz, log(maxf(zoom_goal, 0.01)), kz)
	camera.zoom = Vector2.ONE * exp(_cam_logz)


## The whole drive in world space: the tee, the start line's end and the ball's whole track to
## its rest.
func drive_rect() -> Rect2:
	var r := Rect2(world_point(Vector2(launch.start.x, launch.start.y)), Vector2.ZERO)
	r = r.expand(world_point(trail.guide_end()))
	if shot_view.prediction != null:
		for p: Vector3 in shot_view.prediction.path:
			r = r.expand(world_point(Vector2(p.x, p.y)))
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


## The drive's drawn track: its start line (the launch heading, to the carry) in chalk dots and
## the ball's ground track so far in sun_yellow, over the terrain, a fixed width on screen.
class Trail:
	extends Node2D
	var _intro: OpeningFlyover

	func _init() -> void:
		z_index = 1

	func bind(intro: OpeningFlyover) -> void:
		_intro = intro

	## The start line's far end, yards: the launch heading out to the target carry.
	func guide_end() -> Vector2:
		var s := _intro.launch
		return Vector2(s.start.x, s.start.y) + Vector2.RIGHT.rotated(deg_to_rad(s.heading_deg)) * s.target_carry

	## The ball's ground track drawn so far, yards: the prediction's path to the live ball's tick.
	func track() -> PackedVector2Array:
		var out := PackedVector2Array()
		var sv := _intro.shot_view
		if sv == null or sv.ball == null or sv.prediction == null or not _intro._struck:
			return out
		var path := sv.prediction.path
		var upto := mini(sv.ball.steps + 1, path.size())
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
		if _intro == null or not _intro._struck or _intro.launch == null:
			return
		var t := _intro.tuning
		var k := HazardCue.screen_k(get_viewport().get_canvas_transform().get_scale().x)
		# The start line: dots every guide_gap_px on screen along the launch heading.
		var o := Vector2(_intro.launch.start.x, _intro.launch.start.y)
		var end := guide_end()
		var total := o.distance_to(end)
		var last := Vector2.INF
		var yd := 0.0
		while yd <= total:
			var w := _intro.track_point(o.lerp(end, yd / maxf(total, 0.001)))
			if last == Vector2.INF or w.distance_to(last) >= t.guide_gap_px * k:
				draw_circle(w, (t.guide_dot_px + 1.0) * k, Color(INK, t.guide_alpha))
				draw_circle(w, t.guide_dot_px * k, Color(CHALK, t.guide_alpha))
				last = w
			yd += 1.0
		# The ground track, ink under sun_yellow.
		var pts := PackedVector2Array()
		for p: Vector2 in track():
			var w := _intro.track_point(p)
			if pts.is_empty() or w.distance_squared_to(pts[-1]) > 0.25 * k * k:
				pts.append(w)
		if pts.size() >= 2:
			draw_polyline(pts, INK, (t.track_width_px + 2.0) * k, true)
			draw_polyline(pts, SUN_YELLOW, t.track_width_px * k, true)
