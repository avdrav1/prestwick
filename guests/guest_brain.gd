class_name GuestBrain
extends RefCounted
## The guests' day (E3-S4; docs/design.md Guests and reactions, Guest day), with no scene:
## it spawns the day's groups (GuestSpawner) at the first open hole's tee, walks them, takes
## their turns and plays their holes (GuestHole) in number order, once per simulated second.
##
## Time: `step()` is one simulated second, and the only place guests change state (walk,
## wait, swing, finish a hole, leave). It never runs per frame: `advance_real(delta, speed)`
## turns real time into steps, one a real second at 1x and three at 3x, and between steps
## only spends Ball work.
##
## Ball work (E3-S1, Guest Ball work): each simulated second every guest may spend up to
## `guest_ticks_per_s` Ball ticks, and the whole sim `sim_ticks_per_s`, guests served in a
## fixed order (arrival order, which is group then place) on whatever work they have: the plan
## of their next stroke, the putt solve, their own ball. Work left over carries to the next
## second. `advance_real` slices a second's ticks over that second's frames in proportion to
## its need (E3-S14): the share of the second gone by, times the most the second can spend
## (`guest_ticks_per_s` for each guest with work when it began, at most the sim's cap; work
## only starts in a step, so no second spends more), and never more than `frame_ticks_max` in
## one frame. A step that is due waits, frame by frame, until its second's work is served
## (`held_frames`), and `step` itself first finishes whatever that second still owes, so a day
## plays the same however it is sliced into frames: the same seed gives the same day. No clock
## is read and every random number comes from the day's seed. A long frame (a hitch) runs at
## most `max_steps_per_frame` steps and lets the rest of its time go: the day runs late, never
## differently.
##
## A hole (E3-S4): the group stands on the tee until all of it is there and the tee is clear
## (groups queue in the order they head for the hole): it is first in the queue, or the group
## just ahead has teed off and every ball of it rests `tee_clear_yd` out or is holed (E3-S8,
## `tee_clear`), so it waits behind a slower group, and on a par 3 for it to finish. The guest
## away (farthest from the cup; on the tee, the group's order; with `ready_golf`, E3-S8, the
## farthest of those not walking) plays next, once every ball in the group is at rest, no
## stroke is under way and it stands at its ball, and no group ahead on the hole is in reach
## of the stroke (E3-S8 review, `play_clear`; else the whole group waits on the group ahead):
## it strikes and is PLAYING for `stroke_s`, then walks to where its ball rested once it rests.
## A guest whose plan is unfinished at its turn waits for it (reading the green, on a putt;
## not counted against pace). The group leaves the hole when every one
## of it has holed out or picked up (D12) and stands still, and heads for the open hole with
## the next number. With none left, it goes home.
##
## Edits while guests play (holes are edited by copy, GuestHole.hole_still_stands): a group
## whose hole is closed, removed, renumbered or changed before it struck a ball there walks to
## that hole's new tee if it is still open, else heads for the next; once it has struck a ball,
## the hole ends for the group with no record and it heads for the next open number.
##
## Dusk (D38): at `day_s` every guest still on the course leaves; the hole it was playing
## gives no record. Each finished hole gave its record (`hole_finished`) when the guest holed
## out or picked up, with the guest's reaction to it (E3-S6, D39: `reacted`, the four checks,
## GuestReaction). The hole's static checks (blind, interesting) are measured once per hole
## and kept while its tee, cup and the course's terrain stay the same (HoleChecks).

signal guest_arrived(guest: Guest)
signal hole_finished(guest: Guest, record: Guest.HoleRecord)
signal guest_left(guest: Guest)
## A guest's reaction to the hole it just finished (D39), right after its `hole_finished`.
signal reacted(guest: Guest, reaction: GuestReaction)

## A step is due when the clock is this close to a whole second (float sums of frame deltas).
const CLOCK_EPS: float = 1e-6

var course: CourseData
var tuning: GuestTuning
var model: ShotModel
var field: HeightField
var day_seed: int = 0
## Every group of the day, in arrival order.
var groups: Array[GuestGroup] = []
## Every guest that has arrived, in arrival order (Ball work's fixed order).
var guests: Array[Guest] = []
## Simulated seconds of the day stepped so far: the next step plays second `second`.
var second: int = 0
var day_over: bool = false
## Groups that arrived to no open hole and went home at once.
var turned_away: int = 0
## The most Ball ticks one simulated second spent, sim-wide and by one guest; and the
## seconds that reached the sim's cap.
var max_second_ticks: int = 0
var max_guest_second_ticks: int = 0
var capped_seconds: int = 0
var ticks: int = 0
## E3-S14: Ball ticks the last `advance_real` frame served, the most any frame served, and the
## frames in which a due step waited for its second's work (the day running late).
var frame_ticks: int = 0
var max_frame_ticks: int = 0
var held_frames: int = 0
## The holes' static checks (blind, interesting), kept per hole until it or the terrain changes.
var checks: HoleChecks
## {hole number: groups that teed off it today} (E3-S8: a day reaches every hole).
var teed_off: Dictionary = {}

var _swing_tuning: SwingTuning
## {hole number: [GuestGroup]}: the groups heading for or playing each hole, in order.
var _queues: Dictionary = {}
## Ball work this second: the guest being served, and the sim's ticks spent.
var _cursor: int = 0
var _sim_used: int = 0
## The most Ball ticks this second can spend (E3-S14, `_measure_need`): what advance_real paces by.
var _need: int = 0
## Share of the current simulated second gone by in real time (advance_real).
var _clock: float = 0.0
## Cart path searches this step ({Vector4i(from tile, to tile): tiles}, GuestWalk.route). The
## course cannot change inside a step, so a search is shared by every walk of the step (a
## group setting off from one cup, its pace walk) and the cache is dropped before the next.
var _route_cache: Dictionary = {}
## HoleChecks.terrain_key of the course this step ("" until a reaction needs it); dropped
## before the next step, as the route cache is.
var _terrain_key: String = ""


## The day of `day_seed` on `course`. `p_groups` replaces the drawn arrivals (tests, scripts).
## Measures the guests' club table now (GuestClubTable.warm), before any guest ticks.
func _init(p_course: CourseData, p_day_seed: int, p_tuning: GuestTuning = null,
		p_model: ShotModel = null, p_groups: Array[GuestGroup] = [],
		p_swing_tuning: SwingTuning = null) -> void:
	course = p_course
	day_seed = p_day_seed
	tuning = p_tuning if p_tuning != null else GuestTuning.load_default()
	model = p_model if p_model != null else ShotModel.new()
	_swing_tuning = p_swing_tuning if p_swing_tuning != null else SwingTuning.load_default()
	field = HeightField.new(course, model.params)
	checks = HoleChecks.new(tuning, model.params)
	groups = p_groups if not p_groups.is_empty() else GuestSpawner.day(tuning, day_seed)
	GuestClubTable.warm(model)


## Real time passing in Play: `delta` real seconds at `speed` (0 paused, 1, 3). Runs a step
## for every whole simulated second gone by, at most `max_steps_per_frame` (a hitch's extra
## time is let go), and spends the current second's Ball work in proportion to its need, all
## inside `frame_ticks_max` (E3-S14). A due step whose second's work is not yet served waits
## for later frames. Returns the steps it ran.
func advance_real(delta: float, speed: float) -> int:
	frame_ticks = 0
	if day_over or speed <= 0.0 or delta <= 0.0:
		return 0
	_clock = minf(_clock + delta * speed, float(tuning.max_steps_per_frame))
	var left := tuning.frame_ticks_max
	var stepped := 0
	while _clock >= 1.0 - CLOCK_EPS and not day_over:
		left -= serve(left)
		if not second_served():
			held_frames += 1  # the step waits for its work: the day runs late
			break
		_clock = maxf(_clock - 1.0, 0.0)
		step()
		stepped += 1
	if not day_over and left > 0:
		var due := ceili(minf(_clock, 1.0) * _need)
		if due > _sim_used:
			left -= serve(mini(due - _sim_used, left))
	frame_ticks = tuning.frame_ticks_max - left
	max_frame_ticks = maxi(max_frame_ticks, frame_ticks)
	return stepped


## True when this second's Ball work is all served: every guest has had what it needs, or the
## sim's cap is spent.
func second_served() -> bool:
	return _cursor >= guests.size()


## How much of the current simulated second has gone by in real time (0 to 1): what a view
## interpolates walks and swings by between steps (E3-S5). Reads only.
func step_fraction() -> float:
	return clampf(_clock, 0.0, 1.0)


## Steps simulated seconds until dusk.
func run_day() -> void:
	while not day_over:
		step()


## One simulated second: finishes the second's Ball work, then moves every guest.
func step() -> void:
	if day_over:
		return
	serve(-1)
	max_second_ticks = maxi(max_second_ticks, _sim_used)
	if _sim_used >= tuning.sim_ticks_per_s:
		capped_seconds += 1
	for g: Guest in guests:
		max_guest_second_ticks = maxi(max_guest_second_ticks, g.second_ticks)
		g.second_ticks = 0
	_cursor = 0
	_sim_used = 0
	_route_cache.clear()
	_terrain_key = ""
	_update(second)
	second += 1
	_measure_need()


## The most this second can spend (E3-S14): `guest_ticks_per_s` for every guest with Ball work
## now (a plan, a putt solve or a ball in flight), at most the sim's cap. Work only starts in
## a step (a strike, a new hole), and a resting ball's next plan is the same guest's work, so
## no second spends more; a guest waiting to strike, holed out or gone needs none.
func _measure_need() -> void:
	var n := 0
	for g: Guest in guests:
		if not g.is_done() and g.hole != null and (g.hole.state == GuestHole.State.PLANNING
				or g.hole.state == GuestHole.State.FLYING):
			n += 1
	_need = mini(n * tuning.guest_ticks_per_s, tuning.sim_ticks_per_s)


## Spends up to `max_ticks` (below 0: all that is owed) of this second's Ball work, guests in
## fixed order, each up to its own budget and all within the sim's. Returns the ticks spent.
## Guests with nothing to do are passed over even with no ticks left to give, so a second
## whose work is done reads as served (second_served).
func serve(max_ticks: int) -> int:
	var used := 0
	while _cursor < guests.size():
		var sim_left := tuning.sim_ticks_per_s - _sim_used
		if sim_left <= 0:
			_cursor = guests.size()
			break
		var g := guests[_cursor]
		if g.is_done() or g.hole == null or g.hole.is_finished():
			_cursor += 1
			continue
		var give := mini(tuning.guest_ticks_per_s - g.second_ticks, sim_left)
		if give <= 0:
			_cursor += 1
			continue
		if max_ticks >= 0:
			if used >= max_ticks:
				break
			give = mini(give, max_ticks - used)
		var n := g.hole.advance(give)
		g.second_ticks += n
		g.ticks += n
		_sim_used += n
		used += n
		ticks += n
		if n < give:
			_cursor += 1  # no more work this second (READY, or its ball waits on a turn)
	return used


## The guests on the course now.
func on_course() -> Array[Guest]:
	var out: Array[Guest] = []
	for g: Guest in guests:
		if not g.is_done():
			out.append(g)
	return out


## The open hole with the lowest number above `after` (0: the first open hole); 0 if none.
## Holes go by number, never by their place in CourseData.holes (E3-S2 renumbers by copy).
func next_open_hole(after: int) -> int:
	var best := 0
	for h: HoleData in course.holes:
		if h.number > after and (best == 0 or h.number < best) and _playable(h.number):
			best = h.number
	return best


## The hole numbered `number` as GuestHole.hole_still_stands reads it: the first with it.
func hole_numbered(number: int) -> HoleData:
	for h: HoleData in course.holes:
		if h.number == number:
			return h
	return null


func group_of(guest: Guest) -> GuestGroup:
	return groups[guest.group_id]


# --- the step ---

func _update(t: int) -> void:
	if t >= tuning.day_s:
		_dusk(t)
		return
	for g: GuestGroup in groups:
		if g.phase == GuestGroup.Phase.PENDING and g.arrive_s <= t:
			_arrive(g, t)
	for g: GuestGroup in groups:
		if g.phase == GuestGroup.Phase.TO_TEE:
			_update_to_tee(g, t)
		elif g.phase == GuestGroup.Phase.ON_HOLE:
			_update_on_hole(g, t)


func _arrive(g: GuestGroup, t: int) -> void:
	var n := next_open_hole(0)
	if n == 0:
		g.phase = GuestGroup.Phase.DONE
		turned_away += 1
		return
	var tee := field.tile_center(hole_numbered(n).tee)
	for guest: Guest in g.guests:
		guest.position = tee
		guest.state = Guest.State.WAITING
		guest.arrived_s = t
		guests.append(guest)
	guests.sort_custom(func(a: Guest, b: Guest) -> bool: return a.id < b.id)
	for guest: Guest in g.guests:
		guest_arrived.emit(guest)
	_head_for(g, n, t, false)  # the step's group pass moves it


## Group `g` heads for hole `n`: joins its queue and, with `update`, starts this second's
## walk to its tee.
func _head_for(g: GuestGroup, n: int, t: int, update: bool = true) -> void:
	g.phase = GuestGroup.Phase.TO_TEE
	g.hole_number = n
	g.struck = false
	if not _queues.has(n):
		_queues[n] = []
	(_queues[n] as Array).append(g)
	for guest: Guest in g.guests:
		guest.hole = null
		guest.ball_moved = false
		guest.hole_recorded = false
		guest.wait_s = 0
		guest.walk_yd = -1.0
	if update:
		_update_to_tee(g, t)


func _update_to_tee(g: GuestGroup, t: int) -> void:
	if not _playable(g.hole_number):
		_move_on(g, t)
		return
	var h := hole_numbered(g.hole_number)
	var tee := field.tile_center(h.tee)
	for guest: Guest in g.guests:
		if guest.hole != null and not guest.hole.hole_still_stands():
			guest.hole = null  # the tee moved, or the par changed: plan afresh
		if guest.is_walking() and guest.walk.end() != tee:
			guest.walk = null
			guest.state = Guest.State.WAITING
		if not guest.is_walking() and guest.position != tee:
			_start_walk(guest, tee)
		if guest.is_walking():
			_walk(guest, t)
		if not guest.is_walking() and guest.hole == null:
			guest.hole = GuestHole.new(course, h, guest.skill,
					GuestHole.hole_seed(guest.guest_seed, h.number), tuning, model, _swing_tuning)
			guest.hole.slot = course.holes.find(h)
	var clear := tee_clear(g, h)
	var all_there := true
	for guest: Guest in g.guests:
		all_there = all_there and not guest.is_walking()
	if clear and all_there:
		_tee_off(g, h, t)
		return
	for guest: Guest in g.guests:
		if guest.is_walking():
			continue
		if clear:
			guest.waiting_for = Guest.Wait.PARTNERS
		else:
			guest.waiting_for = Guest.Wait.GROUP_AHEAD
			guest.wait_s += 1


func _tee_off(g: GuestGroup, h: HoleData, t: int) -> void:
	g.phase = GuestGroup.Phase.ON_HOLE
	g.start_s = t
	teed_off[h.number] = int(teed_off.get(h.number, 0)) + 1
	g.struck = false
	var tee := field.tile_center(h.tee)
	var walk_yd := (GuestWalk.route(course, g.prev_cup, tee, tuning, field.yards_per_tile,
			_route_cache).length if g.has_prev_cup else -1.0)
	for guest: Guest in g.guests:
		guest.walk_yd = walk_yd
	_update_on_hole(g, t)


func _update_on_hole(g: GuestGroup, t: int) -> void:
	for guest: Guest in g.guests:
		if not guest.hole.is_finished() and not guest.hole.hole_still_stands():
			if g.struck:
				# The hole changed under the group: no record, on to the next. It left no green,
				# so the next hole has no pace walk (an older cup is not where it stood).
				g.has_prev_cup = false
				_move_on(g, t)
			else:
				g.phase = GuestGroup.Phase.TO_TEE
				_update_to_tee(g, t)
			return
	# Strokes under way end; balls at rest are walked to; finished holes give their record.
	for guest: Guest in g.guests:
		if guest.state == Guest.State.PLAYING:
			guest.stroke_left -= 1.0
			if guest.stroke_left <= 0.0:
				guest.state = Guest.State.WAITING
		if guest.state != Guest.State.PLAYING and guest.ball_moved \
				and guest.hole.state != GuestHole.State.FLYING:
			guest.ball_moved = false
			_start_walk(guest, Vector2(guest.hole.ball_at.x, guest.hole.ball_at.y))
		if guest.is_walking():
			_walk(guest, t)
		if guest.hole.is_finished() and not guest.hole_recorded and not guest.ball_moved:
			_record(guest, g, t)
	var cup := field.tile_center(guest_hole_cup(g))
	var done := true
	var busy := false
	for guest: Guest in g.guests:
		done = done and guest.hole.is_finished() and guest.state == Guest.State.WAITING
		busy = busy or guest.state == Guest.State.PLAYING \
				or guest.hole.state == GuestHole.State.FLYING
	if done:
		g.prev_cup = cup
		g.has_prev_cup = true
		_move_on(g, t)
		return
	var away: Guest = null
	var away_d := -1.0
	if not busy:
		for guest: Guest in g.guests:
			if guest.hole.is_finished() or (tuning.ready_golf and guest.is_walking()):
				continue
			var d := Vector2(guest.hole.ball_at.x, guest.hole.ball_at.y).distance_to(cup)
			if d > away_d:
				away_d = d
				away = guest
	var held := false
	if away != null and not away.is_walking():
		if away.hole.state == GuestHole.State.READY:
			if play_clear(away, g):
				_strike(away, g)
			else:
				held = true
		elif away.hole.plan != null and away.hole.plan.is_putt():
			# Its own putt solve: shown, but never counted against pace (E3-S8 review).
			away.waiting_for = Guest.Wait.READING_GREEN
		else:
			away.waiting_for = Guest.Wait.PLANNING
	for guest: Guest in g.guests:
		if guest.state != Guest.State.WAITING or (guest == away and not held):
			continue
		if guest.hole.is_finished():
			guest.waiting_for = Guest.Wait.HOLED_OUT
		elif guest.hole.state == GuestHole.State.FLYING:
			guest.waiting_for = Guest.Wait.BALL
		elif held:
			# The group ahead is in reach of the stroke: the whole group waits on it.
			guest.waiting_for = Guest.Wait.GROUP_AHEAD
			guest.wait_s += 1
		else:
			guest.waiting_for = Guest.Wait.TURN


## True when group `g`, heading for hole `h`, may tee off as far as the groups ahead go
## (E3-S8, docs/design.md Guests and reactions, Tee clear): it is first in the hole's queue,
## or the group just ahead of it has teed off and is out of reach: every one of that group
## has struck, no ball of it is in the air or a stroke under way, and every ball not yet holed
## or picked up rests at least `tee_clear_yd` from this tee. On a hole shorter than that
## (a par 3) the group ahead must finish first.
func tee_clear(g: GuestGroup, h: HoleData) -> bool:
	var q: Array = _queues[g.hole_number]
	var i := q.find(g)
	if i <= 0:
		return true
	var ahead: GuestGroup = q[i - 1]
	if ahead.phase != GuestGroup.Phase.ON_HOLE:
		return false
	var tee := field.tile_center(h.tee)
	for guest: Guest in ahead.guests:
		if guest.hole == null:
			return false
		if guest.hole.is_finished():
			continue
		if guest.state == Guest.State.PLAYING or guest.hole.state == GuestHole.State.FLYING \
				or guest.hole.strokes.is_empty():
			return false
		if Vector2(guest.hole.ball_at.x, guest.hole.ball_at.y).distance_to(tee) < tuning.tee_clear_yd:
			return false
	return true


## True when `guest` of group `g`, ready to strike, may play as far as the groups ahead on
## its hole go (E3-S8 review, docs/design.md Guests and reactions, Tee clear and ready golf):
## no guest of a group ahead in the hole's queue that is on the hole, and no ball of it not
## yet holed or picked up, lies nearer the cup than the guest's ball and within the stroke's
## planned distance (its plan's perfect-swing rest) plus `play_clear_yd`. So the group behind
## never plays into the group ahead, nor onto a green it is still on; a group it has passed
## (nearer the tee) never holds it, so no two groups wait on each other.
func play_clear(guest: Guest, g: GuestGroup) -> bool:
	var q: Array = _queues[g.hole_number]
	var i := q.find(g)
	if i <= 0:
		return true
	var at := Vector2(guest.hole.ball_at.x, guest.hole.ball_at.y)
	var cup := field.tile_center(guest_hole_cup(g))
	var to_cup := at.distance_to(cup)
	var reach := tuning.play_clear_yd
	var p := guest.hole.plan.prediction if guest.hole.plan != null else null
	if p != null:
		reach += at.distance_to(Vector2(p.rest.x, p.rest.y))
	for j in i:
		var ahead: GuestGroup = q[j]
		if ahead.phase != GuestGroup.Phase.ON_HOLE:
			continue
		for other: Guest in ahead.guests:
			if _in_the_way(other.position, at, cup, to_cup, reach):
				return false
			if other.hole != null and not other.hole.is_finished() \
					and not other.hole.strokes.is_empty() \
					and _in_the_way(Vector2(other.hole.ball_at.x, other.hole.ball_at.y), at, cup,
							to_cup, reach):
				return false
	return true


static func _in_the_way(point: Vector2, at: Vector2, cup: Vector2, to_cup: float,
		reach: float) -> bool:
	return point.distance_to(cup) < to_cup and point.distance_to(at) < reach


## The cup tile of the hole group `g` is playing (from its guests' play, which is the hole
## as they started it).
func guest_hole_cup(g: GuestGroup) -> Vector2i:
	return g.guests[0].hole.hole.cup


func _strike(guest: Guest, g: GuestGroup) -> void:
	guest.hole.strike()
	guest.state = Guest.State.PLAYING
	guest.waiting_for = Guest.Wait.NONE
	guest.stroke_left = tuning.stroke_s
	guest.ball_moved = true
	g.struck = true


func _record(guest: Guest, g: GuestGroup, t: int) -> void:
	guest.hole_recorded = true
	var r := Guest.HoleRecord.new()
	r.number = guest.hole.hole.number
	r.par = guest.hole.hole.par
	r.score = guest.hole.score.total()
	r.holed = guest.hole.score.holed
	r.picked_up = guest.hole.score.picked_up
	r.wait_s = guest.wait_s
	r.walk_yd = guest.walk_yd
	r.start_s = g.start_s
	r.end_s = t
	r.play = guest.hole
	if _terrain_key == "":
		_terrain_key = HoleChecks.terrain_key(course)
	r.reaction = GuestReaction.judge(guest, r, checks.statics(course, guest.hole.hole, _terrain_key),
			tuning)
	guest.records.append(r)
	hole_finished.emit(guest, r)
	reacted.emit(guest, r.reaction)


## Group `g` is done with its hole (finished, or the hole was taken away): it leaves the
## hole's queue and heads for the next open number, or goes home.
func _move_on(g: GuestGroup, t: int) -> void:
	(_queues[g.hole_number] as Array).erase(g)
	var n := next_open_hole(g.hole_number)
	if n == 0:
		g.phase = GuestGroup.Phase.DONE
		for guest: Guest in g.guests:
			_leave(guest, t, false)
		return
	_head_for(g, n, t)


func _dusk(t: int) -> void:
	for g: GuestGroup in groups:
		if g.phase == GuestGroup.Phase.DONE:
			continue
		if g.phase != GuestGroup.Phase.PENDING:
			for guest: Guest in g.guests:
				_leave(guest, t, true)
		g.phase = GuestGroup.Phase.DONE
	_queues.clear()
	day_over = true


func _leave(guest: Guest, t: int, at_dusk: bool) -> void:
	guest.state = Guest.State.DONE
	guest.waiting_for = Guest.Wait.NONE
	guest.left_s = t
	guest.left_at_dusk = at_dusk
	guest.hole = null
	guest.walk = null
	guest_left.emit(guest)


func _start_walk(guest: Guest, to: Vector2) -> void:
	if guest.position == to:
		return
	guest.walk = GuestWalk.route(course, guest.position, to, tuning, field.yards_per_tile,
			_route_cache)
	guest.state = Guest.State.WALKING
	guest.waiting_for = Guest.Wait.NONE


## One second's walk (at most one a second).
func _walk(guest: Guest, t: int) -> void:
	if guest.last_walk_s == t or guest.walk == null:
		return
	guest.last_walk_s = t
	guest.position = guest.walk.move(tuning.walk_yd_per_s)
	if guest.walk.is_done():
		guest.position = guest.walk.end()
		guest.walk = null
		guest.state = Guest.State.WAITING


## True when hole `number` is there and open (an open hole passed every rule).
func _playable(number: int) -> bool:
	var h := hole_numbered(number)
	return h != null and h.open
