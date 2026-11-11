class_name GuestBrain
extends RefCounted
## The guests' day (E3-S4; docs/design.md Guests and reactions, Guest day), with no scene:
## it spawns the day's groups (GuestSpawner), walks them, takes their turns and plays their
## holes (GuestHole) in number order, once per simulated second.
##
## The clubhouse (D60, E5-S11): a group appears at the clubhouse door (CourseData.clubhouse_door)
## and walks to the first open hole's tee; after its last hole it walks back to the door, and
## each guest leaves as it reaches it. Both walks take the cart path search (route), like the
## walks between holes, and take the day's time. The walk out is the first hole's pace walk
## (Guest.HoleRecord.walk_yd, from_clubhouse; before E5-S11 a first hole had none), judged
## against the same walk limit as the walk from a previous cup, so a far clubhouse fails pace
## with "a long walk from the clubhouse"; the walk home comes after the last record and costs
## only time. Walking off its last green it holds the stroke behind it (hold_for) while a guest
## of it still stands on the green when the club would meet the ball (E5-S12, D61,
## stands_at_impact), as a group walking to its next tee does; before E5-S11 it left the
## course at hole-out. The door is read when each
## walk starts. With no clubhouse, no group arrives
## (turned_away counts them). The green fee is still paid at the first tee (E4-S4): GuestSim
## takes it on reached_first_tee, not on guest_arrived.
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
## one frame (a putt solve's tick counting `putt_tick_weight` there, E3-S34), nor more than
## `frame_ticks_per_real_s` times the frame's length (E3-S35: the day keeps time at 30 fps). A step that is due waits, frame by frame, until its second's work is served
## (`held_frames`), and `step` itself first finishes whatever that second still owes, so a day
## plays the same however it is sliced into frames: the same seed gives the same day. No clock
## is read and every random number comes from the day's seed. A long frame (a hitch) runs at
## most `max_steps_per_frame` steps and lets the rest of its time go: the day runs late, never
## differently.
##
## A hole (E3-S4): the group stands on the tee until all of it is there and the tee is clear
## (groups queue in the order they head for the hole): it is first in the queue, or the group
## just ahead is on the hole, every one of it has struck and no ball of it is moving (E3-S8,
## `tee_clear`). It is then on the hole, and its tee shots wait like any stroke (since E3-S22
## the reach of a tee shot is play_clear's, so on a par 3 it waits for the group ahead to
## leave the green); it tees off with its first stroke (`start_s`, `teed_off`). The guest away
## (farthest from the cup; on the tee, the group's order; with `ready_golf`, E3-S8, the
## farthest of those not walking) plays next, once every ball in the group is at rest, no
## stroke is under way and it stands at its ball, and nobody is in the stroke's way: no guest
## or ball of a group ahead on the hole (E3-S8 review), nor of a group out on another hole
## (E3-S22) (`play_clear`, `hold_for`; else the whole group waits): it strikes and is PLAYING
## for `stroke_s`, then walks to where its ball rested once it rests as GuestView draws it
## (E3-S20, ball_shown_s: the swing's impact, then the replay), setting off part way into a
## second if that is when; it strikes again no sooner than the second after its walk ends,
## unless the walk ended within the swing's address (at_ball). So the figure on screen never
## walks off under its ball's flight nor swings before it has walked up to its ball.
## A guest whose plan is unfinished at its turn waits for it (reading the green, on a putt;
## not counted against pace). The group leaves the hole when every one
## of it has holed out or picked up (D12) and stands still, and heads for the open hole with
## the next number. With none left, it walks back to the clubhouse and goes home.
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
## E5-S11: a guest reached the first tee of its round, having walked from the clubhouse door:
## where it pays its green fee (E4-S4, GuestSim). Once a guest, the second its walk ends.
signal reached_first_tee(guest: Guest)
signal hole_finished(guest: Guest, record: Guest.HoleRecord)
signal guest_left(guest: Guest)
## A guest's reaction to the hole it just finished (D39), right after its `hole_finished`.
signal reacted(guest: Guest, reaction: GuestReaction)

## What holds a guest ready to strike (hold_for): nobody, a group ahead on its hole, or a
## group on another hole (E3-S22).
enum Hold { CLEAR, SAME_HOLE, CROSSING }

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
## Groups that arrived to no open hole, or to a course with no clubhouse (E5-S11), and went
## home at once, and (E8-S2) groups a late start had no time for; a group a late start sends out
## again no longer counts.
var turned_away: int = 0
## E8-S2 (D64): the day's late starts, in order, each Vector3i(first group, second, groups sent).
## When groups went home to a closed course and a hole is open again at a step, that step sends
## every group not yet out (those turned away and any still to come) from its second, in arrival
## order, one every `arrival_window_s` / groups as on a normal morning, while the time left before
## dusk holds a round of the open holes by the normal day's finish rule (`late_round_s`); the rest
## do not come today. GuestSim saves them (E4-S11's replay) and a loaded day's brain takes them
## (`p_late_starts`), so its replay sends the same groups at the same seconds.
var late_starts: Array[Vector3i] = []
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
## Measures each hole's dogleg turn as a group starts it (D54, GuestHole.turn_of).
var _validator: CourseValidator = CourseValidator.new()
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
## Cart path searches (GuestWalk.route's cache) kept across steps while the course's cart path
## stands unchanged (E3-S15): every walk of the day between the same two path tiles shares one
## search, and the cache is dropped at the first walk after a tile turned to or from cart path
## (E3-S74; before, any tile or parcel write; GuestWalk.Cache.follow). A cached route is the one
## a fresh search finds, so the day is the same with or without it.
var _route_cache := GuestWalk.Cache.new()
## E7-S4: the batch serve_ahead left running on the pool (-1: none), its guests, their ticks
## before it and the index after them, until `settle` counts it.
var _ahead_task: int = -1
var _ahead: Array[Guest] = []
var _ahead_before := PackedInt32Array()
var _ahead_end: int = 0
## HoleChecks.terrain_key of the course this step ("" until a reaction needs it); dropped
## before the next step.
var _terrain_key: String = ""


## The day of `day_seed` on `course`. `p_groups` replaces the drawn arrivals (tests, scripts).
## `p_arrivals` 0 or more is how many guests the day draws (E4-S5: GuestSim's arrivals by
## rating), else `arrivals_per_day`. Measures the guests' club table now
## (GuestClubTable.warm), before any guest ticks.
func _init(p_course: CourseData, p_day_seed: int, p_tuning: GuestTuning = null,
		p_model: ShotModel = null, p_groups: Array[GuestGroup] = [],
		p_swing_tuning: SwingTuning = null, p_arrivals: int = -1,
		p_late_starts: Array[Vector3i] = []) -> void:
	course = p_course
	day_seed = p_day_seed
	tuning = p_tuning if p_tuning != null else GuestTuning.load_default()
	model = p_model if p_model != null else ShotModel.new()
	_swing_tuning = p_swing_tuning if p_swing_tuning != null else SwingTuning.load_default()
	field = HeightField.new(course, model.params)
	checks = HoleChecks.new(tuning, model.params)
	groups = p_groups if not p_groups.is_empty() else GuestSpawner.day(tuning, day_seed, p_arrivals)
	# E8-S2: a loaded day's late starts, replayed as the day under way made them.
	for ls: Vector3i in p_late_starts:
		_send_late(ls.x, ls.y, ls.z)
	GuestClubTable.warm(model)


## Real time passing in Play: `delta` real seconds at `speed` (0 paused, 1, 3). Runs a step
## for every whole simulated second gone by, at most `max_steps_per_frame` (a hitch's extra
## time is let go), and spends the current second's Ball work in proportion to its need, all
## inside the frame's budget: `frame_ticks_per_real_s` x `delta`, at most `frame_ticks_max`
## (E3-S14, E3-S35). A due step whose second's work is not yet served waits
## for later frames. Returns the steps it ran.
func advance_real(delta: float, speed: float) -> int:
	settle()
	frame_ticks = 0
	if day_over or speed <= 0.0 or delta <= 0.0:
		return 0
	if dusk_due():
		# E4-S3: dusk falls in the frame after the day's last second, owing no Ball work, so a
		# day at 1x takes `day_s` real seconds and a frame, not a second more.
		step()
		return 1
	_clock = minf(_clock + delta * speed, float(tuning.max_steps_per_frame))
	# E3-S35: the frame's budget goes with its length (frame_ticks_per_real_s), so a day takes
	# the same real time at 30 fps as at 60.
	var budget := mini(ceili(tuning.frame_ticks_per_real_s * delta - 1e-6), tuning.frame_ticks_max)
	var left := budget
	var stepped := 0
	while _clock >= 1.0 - CLOCK_EPS and not day_over and not dusk_due():
		left -= serve(left)
		if not second_served():
			held_frames += 1  # the step waits for its work: the day runs late
			break
		_clock = maxf(_clock - 1.0, 0.0)
		step()
		stepped += 1
	if not day_over and not dusk_due() and left > 0:
		var due := ceili(minf(_clock, 1.0) * _need)
		if due > _sim_used:
			left -= serve(left, due - _sim_used)
	frame_ticks = budget - left
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


## Skip to morning (E4-S3): runs the day on as fast as one frame allows, the same steps
## `step` and `advance_real` run, so the day is the same. E7-S4: whole seconds, each served at
## once (serve_second, its guests' Ball work spread over threads unless `threads` is false)
## and then stepped, at most `max_steps` of them, and none that would pass `max_usec` (below
## 0: no limit) of real time since the call began, taking the next second to cost what the
## last one did; at least one second runs. How the day
## is cut into frames changes when it ends in real time, never what happens in it (E3-S14), so
## reading the clock here is safe. `frame_ticks` holds the Ball ticks it served. The clock's
## share of a second (`step_fraction`) is left where it was. Returns the steps run.
func advance_skip(max_steps: int, max_usec: int = -1, threads: bool = true) -> int:
	frame_ticks = 0
	var t0 := Time.get_ticks_usec()
	var before := ticks
	var stepped := 0
	while not day_over and stepped < max_steps:
		var s0 := Time.get_ticks_usec()
		if not dusk_due():
			serve_second(threads)
		step()
		stepped += 1
		# A second costs about what the one before it did: stop before one that would not fit.
		var now := Time.get_ticks_usec()
		if max_usec >= 0 and now - t0 + (now - s0) > max_usec:
			break
	frame_ticks = ticks - before
	return stepped


## E7-S4: spends all of this second's Ball work still owed, exactly as `serve(-1)` does, with
## the guests' work run side by side on WorkerThreadPool's threads (`threads`; else one after
## another on this one). A guest's work reads only its own play and the course, which nothing
## writes while this runs (CourseData is read-only to guests, and the builder runs on this
## thread, which waits here), so guests can run at once. What ties them is the sim's cap: each
## guest in turn gets the rest of its own budget or what the sim has left, whichever is less.
## So a batch (_gather) is the guests from `_cursor` on whose own budgets all fit in what the
## sim has left: none of them can be cut by those before it, and each gets its full budget, as
## in turn. A guest that might be cut waits for the batch's real use: then its whole budget
## fits and it starts the next batch, or it does not and it is served alone, cut, as serve
## would. Returns the ticks served (with what serve_ahead had served of this second).
func serve_second(threads: bool = true) -> int:
	var served := settle()
	while _cursor < guests.size():
		var sim_left := tuning.sim_ticks_per_s - _sim_used
		if sim_left <= 0:
			_cursor = guests.size()
			break
		var batch: Array[Guest] = []
		var gives := PackedInt32Array()
		var i := _gather(batch, gives)
		if batch.is_empty():
			if i < guests.size():
				# Its budget is more than the sim has left: served alone, cut, as serve does.
				var g := guests[i]
				served += _served(g, g.hole.advance(mini(tuning.guest_ticks_per_s - g.second_ticks,
						sim_left)))
			_cursor = i + 1
			continue
		if batch.size() == 1 or not threads:
			for k in batch.size():
				served += _served(batch[k], batch[k].hole.advance(gives[k]))
		else:
			var before := PackedInt32Array()
			for g: Guest in batch:
				before.append(g.hole.ticks)
			# The pool's threads take all but the first; this thread, which would only wait,
			# takes the first.
			var task := WorkerThreadPool.add_group_task(func(k: int) -> void:
				batch[k + 1].hole.advance(gives[k + 1]), batch.size() - 1, -1, true)
			batch[0].hole.advance(gives[0])
			WorkerThreadPool.wait_for_group_task_completion(task)
			for k in batch.size():
				served += _served(batch[k], batch[k].hole.ticks - before[k])
		_cursor = i
	return served


## E7-S4: fills `batch` and `gives` with the guests from `_cursor` on that have Ball work this
## second and the rest of their own budget for it, while those budgets all fit in what the sim
## has left; passes over guests with none. Returns the index it stopped at: the first guest
## whose budget did not fit, or the end.
func _gather(batch: Array[Guest], gives: PackedInt32Array) -> int:
	var room := tuning.sim_ticks_per_s - _sim_used
	var i := _cursor
	while i < guests.size():
		var g := guests[i]
		var give := tuning.guest_ticks_per_s - g.second_ticks
		if g.is_done() or g.hole == null or g.hole.is_finished() or give <= 0:
			i += 1
			continue
		if give > room:
			break
		room -= give
		batch.append(g)
		gives.append(give)
		i += 1
	return i


## E7-S4: starts the next batch of this second's Ball work (_gather) on the pool's threads and
## returns at once, so it runs while this thread does something else: GuestSim calls it while
## the frame is drawn (RenderingServer.frame_pre_draw), when no script runs, and `settle`
## counts it once drawing is done. Until then nothing may read or change the guests' plays or
## write the course: every other GuestBrain entry settles first. Returns true when it started
## one (not when one is already out, the day is over or at dusk, or nothing is owed).
func serve_ahead() -> bool:
	if _ahead_task >= 0 or day_over or dusk_due() or _cursor >= guests.size() \
			or tuning.sim_ticks_per_s - _sim_used <= 0:
		return false
	var batch: Array[Guest] = []
	var gives := PackedInt32Array()
	var end := _gather(batch, gives)
	if batch.is_empty():
		return false
	_ahead = batch
	_ahead_end = end
	_ahead_before.clear()
	for g: Guest in batch:
		_ahead_before.append(g.hole.ticks)
	_ahead_task = WorkerThreadPool.add_group_task(func(k: int) -> void:
		batch[k].hole.advance(gives[k]), batch.size(), -1, true)
	return true


## E7-S4: waits for the batch serve_ahead started, if any, and counts it as serve_second would
## have. Returns the ticks it served.
func settle() -> int:
	if _ahead_task < 0:
		return 0
	WorkerThreadPool.wait_for_group_task_completion(_ahead_task)
	_ahead_task = -1
	var served := 0
	for k in _ahead.size():
		served += _served(_ahead[k], _ahead[k].hole.ticks - _ahead_before[k])
	_cursor = _ahead_end
	_ahead = []
	return served


## Counts `n` ticks `g` just spent, as serve does. Returns `n`.
func _served(g: Guest, n: int) -> int:
	g.second_ticks += n
	g.ticks += n
	_sim_used += n
	ticks += n
	return n


## True when every second of the day has been played and only dusk is left (E4-S3): it is
## due at once (advance_real's next frame), so a day at 1x takes `day_s` real seconds, not one more.
func dusk_due() -> bool:
	return not day_over and second >= tuning.day_s


## One simulated second: finishes the second's Ball work, then moves every guest. Past the
## day's last second it is dusk (D38): everyone still out leaves; no Ball work is owed, since
## no stroke still in the air can give a record (E4-S3).
func step() -> void:
	settle()
	if day_over:
		return
	if dusk_due():
		_dusk(second)
		second += 1
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
## fixed order, each up to its own budget and all within the sim's. Returns the ticks spent,
## as the frame budget counts them: a putt solve's tick as `putt_tick_weight` (E3-S34), every
## other as 1; a guest's and the sim's budgets for the second count every tick as 1.
## `max_raw` (below 0: no cap) caps the ticks themselves, each counted as 1 (advance_real's
## share of the second's need).
## Guests with nothing to do are passed over even with no ticks left to give, so a second
## whose work is done reads as served (second_served).
func serve(max_ticks: int, max_raw: int = -1) -> int:
	settle()
	var cost := 0.0
	var raw := 0
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
		var w := 1.0
		if g.hole.state == GuestHole.State.PLANNING and g.hole.plan != null and g.hole.plan.is_putt():
			w = tuning.putt_tick_weight
		if max_ticks >= 0:
			var room := floori((max_ticks - cost) / w + 1e-6)
			if room <= 0:
				break
			give = mini(give, room)
		if max_raw >= 0:
			if raw >= max_raw:
				break
			give = mini(give, max_raw - raw)
		var n := g.hole.advance(give)
		g.second_ticks += n
		g.ticks += n
		_sim_used += n
		cost += n * w
		raw += n
		ticks += n
		if n < give:
			_cursor += 1  # no more work this second (READY, or its ball waits on a turn)
	return ceili(cost - 1e-6)


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
	for guest: Guest in guests:
		guest.step_from = guest.position
	_start_late(t)
	for g: GuestGroup in groups:
		if g.phase == GuestGroup.Phase.PENDING and g.arrive_s <= t:
			_arrive(g, t)
	for g: GuestGroup in groups:
		if g.phase == GuestGroup.Phase.TO_TEE:
			_update_to_tee(g, t)
		elif g.phase == GuestGroup.Phase.ON_HOLE:
			_update_on_hole(g, t)
		elif g.phase == GuestGroup.Phase.TO_CLUBHOUSE:
			_update_to_clubhouse(g, t)


## The middle of the clubhouse's door tile, yards (E5-S11): where guests appear and leave.
## Only meaningful when the course has a clubhouse.
func door() -> Vector2:
	return field.tile_center(course.clubhouse_door())


func _arrive(g: GuestGroup, t: int) -> void:
	var n := next_open_hole(0)
	if n == 0 or not course.has_clubhouse():
		g.phase = GuestGroup.Phase.DONE
		g.turned_away = true
		turned_away += 1
		return
	# E5-S11: out of the clubhouse door; the walk to the first tee is the first hole's pace walk.
	var at := door()
	g.prev_cup = at
	g.has_prev_cup = true
	g.from_clubhouse = true
	for guest: Guest in g.guests:
		guest.position = at
		guest.state = Guest.State.WAITING
		guest.arrived_s = t
		guests.append(guest)
	guests.sort_custom(func(a: Guest, b: Guest) -> bool: return a.id < b.id)
	for guest: Guest in g.guests:
		guest_arrived.emit(guest)
	_head_for(g, n, t, false)  # the step's group pass moves it


## E8-S2 (D64): the seconds of day a late group needs before dusk to play the course's open
## holes by the normal day's finish rule: the last group of a normal morning arrives at
## `arrival_window_s` with `day_s` less that left, which D46 sized for a round of the most holes
## a course holds (BuilderTuning.max_holes), so each open hole asks for that share.
func late_round_s() -> float:
	var open := 0
	var seen := {}
	for h: HoleData in course.holes:
		if not seen.has(h.number) and _playable(h.number):
			open += 1
		seen[h.number] = true
	var per_hole := (tuning.day_s - tuning.arrival_window_s) / float(maxi(_max_holes(), 1))
	return open * per_hole


static func _max_holes() -> int:
	return BuilderTuning.load_default().max_holes


## E8-S2: at second `t`, when groups went home to a closed course (turned away, not cut) and a
## hole is open now with the clubhouse standing, sends every group not yet out from `t` (see
## `late_starts`). The groups turned away and those still to come follow one another in
## arrival order, so they are the groups from the first turned-away one on.
func _start_late(t: int) -> void:
	var from := -1
	for i: int in groups.size():
		var g := groups[i]
		if g.turned_away and not g.cut:
			from = i
			break
	if from < 0 or next_open_hole(0) == 0 or not course.has_clubhouse():
		return
	var gap := tuning.arrival_window_s / maxf(groups.size(), 1.0)
	var need := late_round_s()
	var count := 0
	while from + count < groups.size() and tuning.day_s - (t + count * gap) >= need:
		count += 1
	_send_late(from, t, count)


## Sends groups `from` on out again from second `t`: the first `count` one every
## `arrival_window_s` / groups seconds, the rest cut (they do not come today). Kept in
## `late_starts`.
func _send_late(from: int, t: int, count: int) -> void:
	var gap := tuning.arrival_window_s / maxf(groups.size(), 1.0)
	for i: int in range(maxi(from, 0), groups.size()):
		var g := groups[i]
		if g.turned_away:
			g.turned_away = false
			turned_away -= 1
		var k := i - from
		if k < count:
			g.phase = GuestGroup.Phase.PENDING
			g.arrive_s = t + k * gap
		else:
			g.phase = GuestGroup.Phase.DONE
			g.turned_away = true
			g.cut = true
			turned_away += 1
	late_starts.append(Vector3i(from, t, count))


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
		guest.tee_wait_s = 0
		guest.cross_wait_s = 0
		guest.walk_yd = -1.0
		guest.walk_s = -1.0
		guest.walk_bare_s = -1.0
		guest.walk_path_share = 0.0
		guest.walk_from_hole = 0
	g.cross_held_s = 0
	if update:
		_update_to_tee(g, t)


func _update_to_tee(g: GuestGroup, t: int) -> void:
	if not _playable(g.hole_number):
		_move_on(g, t)
		return
	var h := hole_numbered(g.hole_number)
	var tee := field.tile_center(h.tee)
	# D54: the hole's dogleg turn, measured once for the group as its first guest starts the hole.
	var turn: Variant = GuestHole.FIND_TURN
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
		if not guest.is_walking() and not guest.at_first_tee and guest.position == tee:
			guest.at_first_tee = true
			reached_first_tee.emit(guest)
		if not guest.is_walking() and guest.hole == null:
			if typeof(turn) == TYPE_STRING:
				turn = GuestHole.turn_of(course, h, _validator)
			guest.hole = GuestHole.new(course, h, guest.skill,
					GuestHole.hole_seed(guest.guest_seed, h.number), tuning, model, _swing_tuning, turn)
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
			guest.tee_wait_s += 1


func _tee_off(g: GuestGroup, h: HoleData, t: int) -> void:
	g.phase = GuestGroup.Phase.ON_HOLE
	g.start_s = t
	g.struck = false
	var tee := field.tile_center(h.tee)
	var walk := route(g.prev_cup, tee) if g.has_prev_cup else null
	for guest: Guest in g.guests:
		guest.walk_yd = walk.length if walk != null else -1.0
		guest.walk_s = walk.duration if walk != null else -1.0
		guest.walk_bare_s = walk.bare_s if walk != null else -1.0
		guest.walk_path_share = walk.path_share() if walk != null else 0.0
		guest.walk_from_clubhouse = g.from_clubhouse and g.has_prev_cup
		guest.walk_from_hole = 0 if g.from_clubhouse else g.left_hole
	g.from_clubhouse = false
	_update_on_hole(g, t)


func _update_on_hole(g: GuestGroup, t: int) -> void:
	for guest: Guest in g.guests:
		if not guest.hole.is_finished() and not guest.hole.hole_still_stands():
			if g.struck:
				# The hole changed under the group: no record, on to the next. It left no green,
				# so the next hole has no pace walk (an older cup is not where it stood).
				g.has_prev_cup = false
				g.from_clubhouse = false
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
		# E3-S20: it sets off once its ball rests as drawn, which may be part way into this
		# second: the walk's first leg starts there (a share of the second, `leg_start`).
		if guest.state != Guest.State.PLAYING and guest.ball_moved \
				and guest.hole.state != GuestHole.State.FLYING \
				and ball_shown_s(guest) < float(t + 1) - CLOCK_EPS:
			guest.ball_moved = false
			_start_walk(guest, Vector2(guest.hole.ball_at.x, guest.hole.ball_at.y),
					clampf(ball_shown_s(guest) - float(t), 0.0, 1.0))
		if guest.is_walking():
			_walk(guest, t)
		if guest.hole.is_finished() and not guest.hole_recorded and not guest.ball_moved:
			_record(guest, g, t)
	var cup := field.tile_center(guest_hole_cup(g))
	var done := true
	var busy := false
	for guest: Guest in g.guests:
		done = done and guest.hole.is_finished() and guest.state == Guest.State.WAITING \
				and not guest.ball_moved
		busy = busy or guest.state == Guest.State.PLAYING \
				or guest.hole.state == GuestHole.State.FLYING
	if done:
		g.prev_cup = cup
		g.has_prev_cup = true
		g.left_hole = g.hole_number
		g.left_s = t
		_move_on(g, t)
		return
	var away: Guest = null
	var away_d := -1.0
	if not busy:
		for guest: Guest in g.guests:
			if guest.hole.is_finished() or (tuning.ready_golf and not at_ball(guest, t)):
				continue
			var d := Vector2(guest.hole.ball_at.x, guest.hole.ball_at.y).distance_to(cup)
			if d > away_d:
				away_d = d
				away = guest
	var held := false
	var held_by := Hold.CLEAR
	if away != null and not at_ball(away, t):
		# Its ball is still showing in flight, or it reached it this second (E3-S20).
		away.waiting_for = Guest.Wait.BALL if away.ball_moved else Guest.Wait.TURN
	elif away != null:
		if away.hole.state == GuestHole.State.READY:
			held_by = hold_for(away, g)
			if held_by == Hold.CLEAR:
				_strike(away, g)
			else:
				held = true
				g.cross_held_s = g.cross_held_s + 1 if held_by == Hold.CROSSING else 0
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
			# Someone is in the stroke's way: the whole group waits on them.
			guest.waiting_for = Guest.Wait.GROUP_AHEAD
			guest.wait_s += 1
			if held_by == Hold.CROSSING:
				guest.cross_wait_s += 1
			elif guest.hole.strokes.is_empty():
				guest.tee_wait_s += 1
		else:
			guest.waiting_for = Guest.Wait.TURN


## E3-S49: Build edited the hole in slot `slot` (its tee, cup or par, or the terrain on its
## line) while guests play it. A group that has not struck there yet replans its first stroke
## on the course as it is now (GuestHole.replan; a moved tee, cup or par also makes the next
## step start the hole afresh), so it plays and judges the new version. Returns the plays of
## groups that have struck: they judge a version that is gone (GuestSim drops their verdicts).
func slot_edited(slot: int) -> Array[GuestHole]:
	settle()
	var stale: Array[GuestHole] = []
	for guest: Guest in guests:
		if guest.hole == null or guest.hole_recorded or guest.hole.slot != slot or guest.is_done():
			continue
		if group_of(guest).struck:
			stale.append(guest.hole)
		else:
			guest.hole.replan()
	return stale


## True when `guest` stands at its ball, ready to swing in second `t` (E3-S20): not walking,
## not waiting for its last ball to rest on screen (`ball_moved`), and not just arrived: a
## walk that ended this second is drawn over it (at walk speed, to `leg_end`), so the guest
## strikes the second after, unless the walk ended within the swing's address
## (`swing_address_share` of `stroke_s`), when the view draws its last steps in the address.
## Either way its figure finishes its walk on screen before it swings.
func at_ball(guest: Guest, t: int) -> bool:
	return not guest.is_walking() and not guest.ball_moved \
			and (guest.last_walk_s != t or guest.leg_end <= tuning.address_s() + CLOCK_EPS)


## The simulated second (from the day's start, a fraction) at which `guest`'s last stroke has
## come to rest as GuestView draws it (E3-S20): the club meets the ball at
## `swing_impact_share` of `stroke_s` after the strike, and the recorded path then takes
## `flight_draw_speed` times less than real time to draw. The guest walks to its ball no
## sooner, so its figure never leaves while its ball is still landing. The same whether the
## stroke is watched or not, so the day never depends on the camera. Only meaningful once
## the ball has rested (GuestHole not FLYING).
func ball_shown_s(guest: Guest) -> float:
	return float(guest.strike_s) + tuning.impact_s() \
			+ tuning.flight_shown_s(guest.hole.last_path.size() - 1)


## True when group `g`, heading for hole `h`, may step onto its tee as far as the groups
## ahead go (E3-S8, docs/design.md Guests and reactions, Tee clear): it is first in the hole's
## queue, or the group just ahead of it is on the hole, every one of that group has struck,
## and no ball of it is in the air nor a stroke under way. E3-S22 folded E3-S8's
## `tee_clear_yd` (every ball of the group ahead 250 yd out) into play_clear: each tee shot
## then waits on the tee, like any stroke, until nobody is in its way (hold_for), so on a
## par 3 the group behind tees off once the group ahead has left the green, and on a longer
## hole once its guests and balls are out of the drive's landing area. E3-S37: and only while
## the next hole's tee is not backed up (next_tee_free).
func tee_clear(g: GuestGroup, _h: HoleData) -> bool:
	if not next_tee_free(g):
		return false
	var q: Array = _queues[g.hole_number]
	var i := q.find(g)
	if i <= 0:
		return true
	var ahead: GuestGroup = q[i - 1]
	if ahead.phase != GuestGroup.Phase.ON_HOLE:
		return false
	for guest: Guest in ahead.guests:
		if guest.hole == null:
			return false
		if guest.hole.is_finished():
			continue
		if guest.state == Guest.State.PLAYING or guest.hole.state == GuestHole.State.FLYING \
				or guest.hole.strokes.is_empty():
			return false
	return true


## E3-S37: true when fewer than `next_tee_queue_max` groups (0: no limit) are heading for, or
## standing at, the tee of the open hole after group `g`'s (none: always true). A group held
## here waits on its own tee, counted against pace on its hole like any wait for the group
## ahead. On the nine-hole fixture groups reach hole 8 (a par 5, the round's slowest) bunched
## after hole 7 (a par 3, its quickest) and queued on its tee 11 to 12 s a record; spacing
## them at hole 7's tee splits that wait between the two holes. A group at the next tee always
## moves on, since its own hole's queue does not wait on this one, so no two groups wait on
## each other.
func next_tee_free(g: GuestGroup) -> bool:
	if tuning.next_tee_queue_max <= 0:
		return true
	var m := next_open_hole(g.hole_number)
	if m == 0 or not _queues.has(m):
		return true
	var heading := 0
	for o: GuestGroup in _queues[m]:
		if o.phase == GuestGroup.Phase.TO_TEE:
			heading += 1
	return heading < tuning.next_tee_queue_max


## True when `guest` of group `g`, ready to strike, may play: nobody is in the stroke's way
## (hold_for is CLEAR).
func play_clear(guest: Guest, g: GuestGroup) -> bool:
	return hold_for(guest, g) == Hold.CLEAR


## What holds `guest` of group `g`, ready to strike (E3-S8 review, E3-S22; docs/design.md
## Guests and reactions, Tee clear and ready golf): a guest, or a ball not yet holed or picked
## up, in the stroke's way (in_the_way: nearer the guest's cup than its ball, and within
## `play_clear_yd` of the ball or inside the landing area round the plan's perfect-swing rest,
## landing_radius). SAME_HOLE: of a group ahead in the hole's queue that is on the hole, so
## the group behind never plays into the group ahead, nor onto a green it is still on; a group
## it has passed (nearer the tee) never holds it, so no two groups on a hole wait on each
## other. CROSSING: of a group out on another hole (a hole that crosses this one, or a
## fairway beside it), or a guest waiting on another hole's tee (E3-S39: a tee in this hole's
## approach), so guests do not play into each other across holes; after
## `cross_hold_max_s` seconds held in a row by such groups alone, the group plays on, so two
## groups on crossing holes never wait on each other for ever.
func hold_for(guest: Guest, g: GuestGroup) -> Hold:
	var at := Vector2(guest.hole.ball_at.x, guest.hole.ball_at.y)
	var cup := field.tile_center(guest_hole_cup(g))
	var rest := at
	var p := guest.hole.plan.prediction if guest.hole.plan != null else null
	if p != null:
		rest = Vector2(p.rest.x, p.rest.y)
	var radius := landing_radius(at.distance_to(rest))
	var q: Array = _queues[g.hole_number]
	for j in q.find(g):
		var ahead: GuestGroup = q[j]
		if ahead.phase == GuestGroup.Phase.ON_HOLE and _group_in_the_way(ahead, at, rest, cup,
				tuning.play_clear_yd, radius, false):
			return Hold.SAME_HOLE
	# E3-S38: a group that holed out leaves the queue in the step its last guest stands at the
	# cup and walks off the green, to its next tee or home to the clubhouse (E5-S11). E5-S12
	# (D61): it holds the stroke only while a guest of it still stands on the green when the
	# club would meet the ball (stands_at_impact), for as long as that takes, and not once it
	# has stepped off. It walks away from the green, so a ball struck then comes down on a
	# green it has left. Before, any guest on the green as the second began held it, for up to
	# 2 s. A group counts while it walks (to its next tee or home) and in the second it left
	# and the one after (it may already be on its next hole, a tee within a second's walk).
	for other: GuestGroup in groups:
		if other == g or other.left_hole != g.hole_number:
			continue
		if other.phase != GuestGroup.Phase.TO_CLUBHOUSE and other.phase != GuestGroup.Phase.TO_TEE \
				and other.left_s < second - 1:
			continue
		for o: Guest in other.guests:
			if o.is_done():
				continue
			var o_at := stands_at_impact(o)
			if field.surface_at(o_at.x, o_at.y) == Surface.Type.GREEN \
					and in_the_way(o_at, at, rest, cup, tuning.play_clear_yd, radius):
				return Hold.SAME_HOLE
	if g.cross_held_s >= tuning.cross_hold_max_s:
		return Hold.CLEAR
	for other: GuestGroup in groups:
		if other == g or other.hole_number == g.hole_number:
			continue
		if other.phase == GuestGroup.Phase.ON_HOLE and _group_in_the_way(other, at, rest, cup,
				tuning.cross_clear_yd, tuning.cross_clear_yd, true):
			return Hold.CROSSING
		if (other.phase == GuestGroup.Phase.ON_HOLE or other.phase == GuestGroup.Phase.TO_TEE) \
				and _waiting_on_tee_in_the_way(other, at, rest, cup, tuning.cross_clear_yd):
			return Hold.CROSSING
	return Hold.CLEAR


## E5-S12: where `guest` stands when a stroke struck this second meets the ball (impact_s into
## the second): along the leg it walked this second (leg_start to leg_end, E3-S20; E9-S1: by
## time along its walk) if its group has stepped already, else where it stands (where it
## began the second).
func stands_at_impact(guest: Guest) -> Vector2:
	if guest.walk == null or guest.last_walk_s != second:
		return guest.position
	var s := clampf(tuning.impact_s(), guest.leg_start, guest.leg_end)
	return guest.walk.point_at_time(guest.walk.elapsed - (guest.leg_end - s))


## True when a guest of group `other` stands waiting on its tee, not yet struck there (E3-S39:
## its group queued for the tee, or on the hole while a partner tees off), in the way of a
## stroke from `at` planned to rest at `rest` (in_the_way, `near` both ways). A guest still
## walking to the tee does not count.
func _waiting_on_tee_in_the_way(other: GuestGroup, at: Vector2, rest: Vector2, cup: Vector2,
		near: float) -> bool:
	for o: Guest in other.guests:
		if o.is_done() or o.is_walking():
			continue
		if o.hole != null and not o.hole.strokes.is_empty():
			continue
		if in_the_way(o.position, at, rest, cup, near, near):
			return true
	return false


## The landing area's radius round a stroke's planned rest `distance` yd away (E3-S22): the
## larger of `play_clear_yd` and `play_clear_share` of the distance, so a long club's area
## covers the power error that sends it well short of or past its plan.
func landing_radius(distance: float) -> float:
	return maxf(tuning.play_clear_yd, tuning.play_clear_share * distance)


## True when `point` is in the way of a stroke from `at` planned to rest at `rest`, toward
## `cup`: nearer the cup than the ball, and within `near` of the ball or `radius` of the rest.
static func in_the_way(point: Vector2, at: Vector2, rest: Vector2, cup: Vector2, near: float,
		radius: float) -> bool:
	if point.distance_to(cup) >= at.distance_to(cup):
		return false
	return point.distance_to(at) < near or point.distance_to(rest) < radius


## True when a guest of group `other` (on its hole), or a ball of it not yet holed or picked
## up, is in the way (in_the_way). With `out_only`, only guests who have struck on their hole
## count: a guest still on its tee is not out on the hole.
func _group_in_the_way(other: GuestGroup, at: Vector2, rest: Vector2, cup: Vector2,
		near: float, radius: float, out_only: bool) -> bool:
	for o: Guest in other.guests:
		if o.is_done() or o.hole == null:
			continue
		if out_only and o.hole.strokes.is_empty():
			continue
		if in_the_way(o.position, at, rest, cup, near, radius):
			return true
		if not o.hole.is_finished() and not o.hole.strokes.is_empty() \
				and in_the_way(Vector2(o.hole.ball_at.x, o.hole.ball_at.y), at, rest, cup, near,
						radius):
			return true
	return false


## The cup tile of the hole group `g` is playing (from its guests' play, which is the hole
## as they started it).
func guest_hole_cup(g: GuestGroup) -> Vector2i:
	return g.guests[0].hole.hole.cup


func _strike(guest: Guest, g: GuestGroup) -> void:
	g.cross_held_s = 0
	if not g.struck:
		# E3-S22: the group tees off with its first stroke (it may have stood on the tee, on
		# the hole, held for the group ahead).
		g.start_s = second
		teed_off[g.hole_number] = int(teed_off.get(g.hole_number, 0)) + 1
	guest.hole.strike()
	guest.strike_s = second
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
	r.tee_wait_s = guest.tee_wait_s
	r.cross_wait_s = guest.cross_wait_s
	r.walk_yd = guest.walk_yd
	r.walk_s = guest.walk_s
	r.walk_bare_s = guest.walk_bare_s
	r.walk_path_share = guest.walk_path_share
	r.walk_from_hole = guest.walk_from_hole
	r.walk_from_clubhouse = guest.walk_from_clubhouse
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
## hole's queue and heads for the next open number, or walks back to the clubhouse (E5-S11).
func _move_on(g: GuestGroup, t: int) -> void:
	(_queues[g.hole_number] as Array).erase(g)
	var n := next_open_hole(g.hole_number)
	if n == 0:
		_head_home(g, t)
		return
	_head_for(g, n, t)


## E5-S11: group `g` has played its last hole and walks back to the clubhouse door, starting
## this second; each guest leaves on reaching it. With no clubhouse they leave where they stand.
func _head_home(g: GuestGroup, t: int) -> void:
	g.phase = GuestGroup.Phase.TO_CLUBHOUSE
	for guest: Guest in g.guests:
		guest.hole = null
		guest.ball_moved = false
		guest.waiting_for = Guest.Wait.NONE
	_update_to_clubhouse(g, t)


## One second of the walk home: each guest walks to the door (the door as it is when its walk
## starts) and leaves there; the group is done once all of it has left.
func _update_to_clubhouse(g: GuestGroup, t: int) -> void:
	var all_gone := true
	for guest: Guest in g.guests:
		if guest.is_done():
			continue
		if not course.has_clubhouse():
			_leave(guest, t, false)
			continue
		var to := door()
		if guest.is_walking() and guest.walk.end() != to:
			guest.walk = null  # the clubhouse moved under it
			guest.state = Guest.State.WAITING
		if not guest.is_walking() and guest.position != to:
			_start_walk(guest, to)
		if guest.is_walking():
			_walk(guest, t)
		if not guest.is_walking():
			_leave(guest, t, false)
		else:
			all_gone = false
	if all_gone:
		g.phase = GuestGroup.Phase.DONE


func _dusk(t: int) -> void:
	for g: GuestGroup in groups:
		if g.phase == GuestGroup.Phase.DONE:
			continue
		if g.phase != GuestGroup.Phase.PENDING:
			# E5-S11: a group walking home has played its round: it leaves, not cut short by dusk.
			var home: bool = g.phase == GuestGroup.Phase.TO_CLUBHOUSE
			for guest: Guest in g.guests:
				if not guest.is_done():
					_leave(guest, t, not home)
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


## Starts `guest`'s walk to `to`, its first leg setting off `start_share` of the way into the
## second (E3-S20: as its ball comes to rest on screen; 0 for every other walk).
func _start_walk(guest: Guest, to: Vector2, start_share: float = 0.0) -> void:
	if guest.position == to:
		return
	guest.next_leg_start = start_share
	guest.walk = route(guest.position, to)
	guest.state = Guest.State.WALKING
	guest.waiting_for = Guest.Wait.NONE


## One second's walk (at most one a second): the rest of the second after the walk's first
## leg sets off, at the speed of the ground under it (E9-S1: GuestWalk walks by time). Its leg
## runs from `leg_start` to `leg_end` (shares of the second), which GuestView draws it over
## (E3-S20).
func _walk(guest: Guest, t: int) -> void:
	if guest.last_walk_s == t or guest.walk == null:
		return
	guest.last_walk_s = t
	var s0 := guest.next_leg_start
	guest.next_leg_start = 0.0
	var was := guest.walk.elapsed
	guest.position = guest.walk.advance(1.0 - s0)
	guest.leg_start = s0
	guest.leg_end = minf(s0 + (guest.walk.elapsed - was), 1.0)
	if guest.walk.is_done():
		guest.position = guest.walk.end()
		guest.walk = null
		guest.state = Guest.State.WAITING


## A guest's walk from `from` to `to` (yards) on the course as it is now (GuestWalk.route),
## its cart path search shared through `_route_cache`, which is dropped first if any tile or
## parcel was written since it was filled (E3-S15). Reads only.
func route(from: Vector2, to: Vector2) -> GuestWalk:
	return GuestWalk.route(course, from, to, tuning, field.yards_per_tile, _route_cache)


## Cart path searches kept (start and end tile pairs), for tests and the perf script.
func route_cache_size() -> int:
	return _route_cache.size()


## True when hole `number` is there and open (an open hole passed every rule).
func _playable(number: int) -> bool:
	var h := hole_numbered(number)
	return h != null and h.open
