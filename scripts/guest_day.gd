extends SceneTree
## E3-S4: a guest day on the nine-hole fixture (tests/fixtures/nine_holes.gd, LandGenerator
## seed 7, every parcel owned, nine open holes), with no scene: GuestBrain stepped once per
## simulated second. Prints, per day seed, how many guests finished nine, round and hole
## times, pace waits, Ball work (ticks a second, seconds at the sim's cap, the costliest plans)
## and the CPU per simulated second; then a pair and a foursome alone on the course. The
## figures go in docs/design.md Guests and reactions (Guest day). E3-S6: each hole's static
## checks (blind, interesting) and their cost, and each day's reactions (praise, neutral,
## complaint, and how often each check failed). E3-S8: the holes reached each day (teed off by a
## group, GuestBrain.teed_off) and finished by someone, with the records a hole. E3-S23:
## `fixture=hazards` plays tests/fixtures/nine_holes_hazards.gd instead (the same holes with a
## bunker on each line and hole 1's crest cut), and each day prints the holes praised.
## E3-S21 (D46): each day prints whether every group that teed off finished its nine (the
## latest finish against dusk), the pace walks (previous cup to tee) and the Ball work left
## over (guest-seconds standing at its turn on an unfinished plan or putt solve); then the
## same day with a skill-1 foursome in each arrival slot in turn (D46 review); and the groups alone run on a day
## long enough to finish, so their whole round is measured. `day_s=N` plays the days at that
## length instead of data/guests.json's (`arrival_window_s=N` likewise); `quick` leaves out the statics and the 60 fps runs.
## E4-S5: `arrivals=N` draws N guests a day instead of `arrivals_per_day` (the game draws 12 to
## 24 by rating, D58), to check every group still finishes.
## E3-S32: `frames` runs only the statics and each seed's day in 60 fps frames at 1x and 3x (the
## CPU a frame, E3-S23's figures), with the load average at the start and end.
## E3-S22: `--lines` prints each day's reaction lines as they came (the feed's text, neutrals
## too, with the second, the guest's skill, patience and taste, its wait and walk), and each
## day prints its pace fails by hole and where the counted waits were (on the tee, on the hole
## behind its own queue, or held for a group on another hole, on the tee or the hole).
##
##   godot --headless --path . -s res://scripts/guest_day.gd [-- seeds=1,2,3] [fixture=hazards]
##       [day_s=540] [arrival_window_s=90] [arrivals=24] [quick] [--lines]

const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
const NineHolesHazards := preload("res://tests/fixtures/nine_holes_hazards.gd")

## `--lines`: print every reaction line of each day's own draws.
var lines: bool = false
## E3-S32 `frames`: only the statics and the 60 fps frame runs.
var frames_only: bool = false


func _initialize() -> void:
	var seeds: Array[int] = [1, 2, 3, 4, 5]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seeds="):
			seeds.clear()
			for s in arg.substr(6).split(","):
				seeds.append(int(s))
	var fixture: GDScript = NineHoles
	for arg in OS.get_cmdline_user_args():
		if arg == "fixture=hazards":
			fixture = NineHolesHazards
	var course: CourseData = fixture.land(7)
	var opened: Array[int] = fixture.build(CourseBuilder.new(course))
	print("nine holes (%s): %d open" % [fixture.resource_path.get_file(), opened.size()])
	var model := ShotModel.new()
	var tuning := GuestTuning.load_default()
	var quick := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("day_s="):
			tuning = _tuning_with({"day_s": float(arg.substr(6))}, tuning)
		elif arg.begins_with("arrival_window_s="):
			tuning = _tuning_with({"arrival_window_s": float(arg.substr(17))}, tuning)
		elif arg.begins_with("arrivals="):
			tuning = _tuning_with({"arrivals_per_day": int(arg.substr(9))}, tuning)
		elif arg == "quick":
			quick = true
		elif arg == "--lines" or arg == "lines":
			lines = true
		elif arg == "frames":
			frames_only = true
	print("day_s %d s (%d guests a day, arriving over the first %d s)" % [tuning.day_s, tuning.arrivals_per_day, tuning.arrival_window_s])
	GuestClubTable.warm(model)
	if not quick:
		_statics(course, tuning, model)
	if frames_only:
		var NineHolesPerf: GDScript = load("res://scripts/nine_holes_perf.gd")
		print("load average at the start: %s" % [NineHolesPerf.load_average()])
		for s in seeds:
			for speed in [1.0, 3.0]:
				_frames(course, s, tuning, model, speed)
		print("load average at the end: %s" % [NineHolesPerf.load_average()])
		quit(0)
		return
	var all_plans: Array[int] = []
	var all_finished := 0
	var stress_finished := 0
	for s in seeds:
		if _day(course, s, tuning, model, all_plans):
			all_finished += 1
		# D46 review: the skill-1 foursome in every arrival slot in turn, not only last, since a
		# slow group early in the day holds up everyone behind it.
		var drawn := GuestSpawner.day(tuning, s)
		var day_ok := true
		var failed_slots := PackedStringArray()
		var worst_latest := 0
		var worst_slot := 0
		for slot in drawn.size():
			var latest_out: Array[int] = [0]
			var ok := _day(course, s, tuning, model, all_plans, with_foursome(drawn, slot),
					"group %d a skill-1 foursome" % slot, latest_out)
			if not ok:
				day_ok = false
				failed_slots.append(str(slot))
			if latest_out[0] > worst_latest:
				worst_latest = latest_out[0]
				worst_slot = slot
		print("day %d with a skill-1 foursome in each of %d slots: %s; latest finish %d s (foursome as group %d)" % [
				s, drawn.size(), "EVERY SLOT HOLDS" if day_ok else "short with the foursome as group " + ",".join(failed_slots),
				worst_latest, worst_slot])
		if day_ok:
			stress_finished += 1
	print("every group that teed off finished its nine on %d of %d days; with a skill-1 foursome in every slot on %d of %d" % [
			all_finished, seeds.size(), stress_finished, seeds.size()])
	all_plans.sort()
	if not all_plans.is_empty():
		var near := 0
		for p in all_plans:
			if p >= 10000:
				near += 1
		print("plan ticks a stroke (all days): median %d, p95 %d, p99 %d, worst %d; %d of %d at 10,000 or more (worst case about 23,700)" % [
			all_plans[all_plans.size() / 2], all_plans[int(all_plans.size() * 0.95)],
			all_plans[int(all_plans.size() * 0.99)], all_plans[-1], near, all_plans.size()])
	if not quick:
		for speed in [1.0, 3.0]:
			_frames(course, seeds[0], tuning, model, speed)
	# Alone on a day long enough to finish, so the round is measured whole.
	var long_day := _tuning_with({"day_s": 3600.0}, tuning)
	for spec: Array in [[2, 10], [2, 5], [2, 1], [1, 5], [1, 1], [4, 10], [4, 5], [4, 1]]:
		var size: int = spec[0]
		var skill: int = spec[1]
		var specs := []
		for i in size:
			specs.append([skill, 5, Guest.Taste.CASUAL, 900 + i])
		var alone := GuestBrain.new(course, 1, long_day, model, [GuestSpawner.group(0, 0.0, specs)])
		while not alone.day_over and alone.guests.any(func(x: Guest) -> bool: return x.state != Guest.State.DONE) \
				or alone.second == 0:
			alone.serve(-1)
			alone.step()
		var g: Guest = alone.guests[0]
		print("a group of %d (skill %d) alone: %d holes, round %d s (left at %d, %s), waits %d s, %.1f strokes a guest" % [
			size, skill, g.records.size(), g.left_s - g.arrived_s, g.left_s, "dusk" if g.left_at_dusk else "done",
			_sum_waits(alone), _strokes(alone) / float(size)])
	quit(0)


## Returns whether every group that teed off finished its nine before dusk. `p_groups`
## replaces the day's draws (`label` names the change in the output).
func _day(course: CourseData, day_seed: int, tuning: GuestTuning, model: ShotModel,
		all_plans: Array[int], p_groups: Array[GuestGroup] = [], label: String = "",
		latest_out: Array[int] = []) -> bool:
	var brain := GuestBrain.new(course, day_seed, tuning, model, p_groups)
	if lines and label.is_empty():
		brain.reacted.connect(func(g: Guest, r: GuestReaction) -> void:
			print(reaction_line(day_seed, brain.second, g, r)))
	var cpu: Array[float] = []
	var moves: Array[float] = []
	# Guest-seconds standing at its own turn on unfinished Ball work (plan or putt solve).
	var left_over := {}
	while not brain.day_over:
		var t0 := Time.get_ticks_usec()
		brain.serve(-1)
		var t1 := Time.get_ticks_usec()
		brain.step()
		var t2 := Time.get_ticks_usec()
		cpu.append((t2 - t0) / 1000.0)
		moves.append((t2 - t1) / 1000.0)
		for g: Guest in brain.guests:
			if g.state == Guest.State.WAITING and (g.waiting_for == Guest.Wait.PLANNING
					or g.waiting_for == Guest.Wait.READING_GREEN):
				left_over[g.id] = int(left_over.get(g.id, 0)) + 1
	var teed := 0
	var nine_groups := 0
	var latest := 0
	for gr: GuestGroup in brain.groups:
		if not brain.guests.has(gr.guests[0]):
			continue
		teed += 1
		var all_nine := true
		for guest: Guest in gr.guests:
			all_nine = all_nine and guest.records.size() == 9 and not guest.left_at_dusk
			latest = maxi(latest, guest.left_s)
		if all_nine:
			nine_groups += 1
	var pace_walks: Array[float] = []
	var nine_left_over: Array[int] = []
	for guest: Guest in brain.guests:
		for r: Guest.HoleRecord in guest.records:
			if r.walk_yd > 0.0:
				pace_walks.append(r.walk_yd)
		if guest.records.size() == 9:
			nine_left_over.append(int(left_over.get(guest.id, 0)))
	pace_walks.sort()
	nine_left_over.sort()
	var every := nine_groups == teed and teed == brain.groups.size()
	if not latest_out.is_empty():
		latest_out[0] = latest
	var tag := "" if label.is_empty() else " (%s)" % label
	print("day %d%s dusk at %d: %d of %d groups teed off, %d finished nine; %s; latest finish %d s; pace walks %d, %d to %d yd (median %d); Ball work left over a guest's nine median %d s, worst %d" % [
			day_seed, tag, tuning.day_s, teed, brain.groups.size(), nine_groups,
			"EVERY GROUP FINISHED" if every else "some ended short",
			latest, pace_walks.size(),
			roundi(pace_walks[0]) if not pace_walks.is_empty() else 0,
			roundi(pace_walks[-1]) if not pace_walks.is_empty() else 0,
			roundi(pace_walks[pace_walks.size() / 2]) if not pace_walks.is_empty() else 0,
			_at(nine_left_over, 0.5), _at(nine_left_over, 1.0)])
	if not label.is_empty():
		return every
	var nine := 0
	var at_dusk := 0
	var holes := 0
	var hole_s: Array[int] = []
	var waits: Array[int] = []
	var rounds: Array[int] = []
	for g: Guest in brain.guests:
		holes += g.records.size()
		if g.records.size() == 9:
			nine += 1
			rounds.append(g.left_s - g.arrived_s)
		if g.left_at_dusk:
			at_dusk += 1
		for r: Guest.HoleRecord in g.records:
			hole_s.append(r.end_s - r.start_s)
			waits.append(r.wait_s)
			for st: GuestHole.StrokeRecord in r.play.strokes:
				all_plans.append(st.plan_ticks)
	var sizes := PackedStringArray()
	for gr: GuestGroup in brain.groups:
		sizes.append(str(gr.size()))
	cpu.sort()
	moves.sort()
	hole_s.sort()
	waits.sort()
	var mean_cpu := 0.0
	for c in cpu:
		mean_cpu += c
	mean_cpu /= cpu.size()
	print("day %d: groups %s; %d guests, %d finished nine (rounds %s s), %d out at dusk, %d hole records; hole time median %d s, p90 %d; pace wait a hole median %d s, p90 %d, worst %d; ticks a second worst %d (a guest %d), %d s at the sim cap; CPU a simulated second mean %.1f ms, median %.1f, p95 %.1f, worst %.1f, of which the step's moves (no Ball work) median %.2f, worst %.2f" % [
		day_seed, "-".join(sizes), brain.guests.size(), nine, rounds, at_dusk, holes,
		_at(hole_s, 0.5), _at(hole_s, 0.9), _at(waits, 0.5), _at(waits, 0.9), _at(waits, 1.0),
		brain.max_second_ticks, brain.max_guest_second_ticks, brain.capped_seconds,
		mean_cpu, cpu[cpu.size() / 2], cpu[int(cpu.size() * 0.95)], cpu[-1],
		moves[moves.size() / 2], moves[-1]])
	var kinds := [0, 0, 0]
	var fails := [0, 0, 0, 0]
	for g: Guest in brain.guests:
		for r: Guest.HoleRecord in g.records:
			kinds[r.reaction.kind] += 1
			for c: int in GuestReaction.Check.size():
				if not r.reaction.passed[c]:
					fails[c] += 1
	var reached := {}
	for g: Guest in brain.guests:
		for r: Guest.HoleRecord in g.records:
			reached[r.number] = int(reached.get(r.number, 0)) + 1
	var per_hole := PackedStringArray()
	for number: int in range(1, 10):
		per_hole.append("%d:%d" % [number, int(reached.get(number, 0))])
	print("day %d holes reached (teed off): %d of 9, finished by someone: %d of 9 (records a hole %s)" % [
			day_seed, brain.teed_off.size(), reached.size(), " ".join(per_hole)])
	var n := maxi(holes, 1)
	print("day %d reactions: praise %d, neutral %d, complaint %d of %d; fails fair %d%%, interesting %d%%, pace %d%%, challenge %d%%; statics measured %d times" % [
		day_seed, kinds[0], kinds[1], kinds[2], holes, roundi(100.0 * fails[0] / n),
		roundi(100.0 * fails[1] / n), roundi(100.0 * fails[2] / n), roundi(100.0 * fails[3] / n),
		brain.checks.measured])
	# E3-S22: pace fails by hole, and where the counted waits were.
	var pace := {}
	var waits_at := [0, 0, 0]
	for g: Guest in brain.guests:
		for r: Guest.HoleRecord in g.records:
			var acc: Array = pace.get(r.number, [0, 0])
			pace[r.number] = [int(acc[0]) + 1,
					int(acc[1]) + (0 if r.reaction.passed[GuestReaction.Check.PACE] else 1)]
			waits_at[0] += r.tee_wait_s
			waits_at[2] += r.cross_wait_s
			waits_at[1] += r.wait_s - r.tee_wait_s - r.cross_wait_s
	var pace_by_hole := PackedStringArray()
	for number: int in range(1, 10):
		var acc: Array = pace.get(number, [0, 0])
		pace_by_hole.append("%d:%d%%" % [number, roundi(100.0 * int(acc[1]) / maxi(int(acc[0]), 1))])
	print("day %d pace fails by hole %s; counted waits %d s on the tee, %d s on the hole behind its queue, %d s held for a group on another hole" % [
			day_seed, " ".join(pace_by_hole), waits_at[0], waits_at[1], waits_at[2]])
	var praised := {}
	for g: Guest in brain.guests:
		for r: Guest.HoleRecord in g.records:
			if r.reaction.is_praise():
				praised[r.number] = int(praised.get(r.number, 0)) + 1
	var praise_by_hole := PackedStringArray()
	for number: int in range(1, 10):
		praise_by_hole.append("%d:%d" % [number, int(praised.get(number, 0))])
	print("day %d holes praised: %d of 9 (praise a hole %s)" % [
			day_seed, praised.size(), " ".join(praise_by_hole)])
	return every


## One reaction as `--lines` prints it: "day 1 s 41 guest 3 (skill 4, patience 2, purist)
## complaint, wait 9 s of 4, walk 66 yd, 1.7 s of 2.0: Hole 1: slow, waited 9 s. Also ...".
static func reaction_line(day_seed: int, second: int, g: Guest, r: GuestReaction) -> String:
	return "day %d s %d guest %d (skill %d, patience %d, %s) %s, wait %d s of %d, walk %s: %s" % [
			day_seed, second, g.id, g.skill, g.patience,
			String(Guest.Taste.keys()[g.taste]).to_lower(), r.kind_name(), r.wait_s,
			roundi(r.wait_limit_s),
			"none" if r.walk_yd < 0.0 else "%d yd, %.1f s of %.1f" % [roundi(r.walk_yd), r.walk_s,
					r.walk_limit_s],
			r.text]


## The day of `day_seed` in 60 fps frames at `speed` (GuestBrain.advance_real, as Play runs it):
## CPU a frame.
func _frames(course: CourseData, day_seed: int, tuning: GuestTuning, model: ShotModel,
		speed: float) -> void:
	var brain := GuestBrain.new(course, day_seed, tuning, model)
	var cpu: Array[float] = []
	while not brain.day_over:
		var t0 := Time.get_ticks_usec()
		brain.advance_real(1.0 / 60.0, speed)
		cpu.append((Time.get_ticks_usec() - t0) / 1000.0)
	cpu.sort()
	var mean := 0.0
	for c in cpu:
		mean += c
	mean /= cpu.size()
	var over := 0
	for c in cpu:
		if c > 8.0:
			over += 1
	print("day %d at %.0fx in 60 fps frames: CPU a frame mean %.2f ms, median %.2f, p95 %.2f, p99 %.2f, worst %.2f; %d of %d frames over 8 ms" % [
		day_seed, speed, mean, cpu[cpu.size() / 2], cpu[int(cpu.size() * 0.95)],
		cpu[int(cpu.size() * 0.99)], cpu[-1], over, cpu.size()])


## Each hole's static checks (HoleChecks) and their cost headless.
func _statics(course: CourseData, tuning: GuestTuning, model: ShotModel) -> void:
	var checks := HoleChecks.new(tuning, model.params)
	var t0 := Time.get_ticks_usec()
	var key := HoleChecks.terrain_key(course)
	var key_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var parts := PackedStringArray()
	var worst := 0.0
	for h: HoleData in course.holes:
		var t1 := Time.get_ticks_usec()
		var s := checks.statics(course, h, key)
		worst = maxf(worst, (Time.get_ticks_usec() - t1) / 1000.0)
		parts.append("%d %s%s" % [h.number, "blind" if s.blind else "seen",
				", interesting" if s.interesting() else (", hazard, no way round" if s.hazard_on_line else ", bare")])
	print("statics: %s; terrain key %.2f ms, a hole's measure worst %.2f ms" % ["; ".join(parts), key_ms, worst])


func _at(a: Array[int], q: float) -> int:
	if a.is_empty():
		return 0
	return a[mini(int(a.size() * q), a.size() - 1)]


func _sum_waits(brain: GuestBrain) -> int:
	var n := 0
	for g: Guest in brain.guests:
		for r: Guest.HoleRecord in g.records:
			n += r.wait_s
	return n


func _strokes(brain: GuestBrain) -> int:
	var n := 0
	for g: Guest in brain.guests:
		for r: Guest.HoleRecord in g.records:
			n += r.play.strokes.size()
	return n


## `drawn` with group `slot` replaced by a skill-1 foursome at its arrival time, every guest
## renumbered in arrival order (the other groups keep their own draws).
static func with_foursome(drawn: Array[GuestGroup], slot: int) -> Array[GuestGroup]:
	var out: Array[GuestGroup] = []
	var id := 0
	for gr: GuestGroup in drawn:
		var specs := []
		if gr.index == slot:
			for i in 4:
				specs.append([1, 5, Guest.Taste.CASUAL, 700 + i])
		else:
			for g: Guest in gr.guests:
				specs.append([g.skill, g.patience, g.taste, g.guest_seed])
		out.append(GuestSpawner.group(gr.index, gr.arrive_s, specs, id))
		id += specs.size()
	return out


## data/guests.json with `base`'s day_s and arrival_window_s, then `changes` (the sweep for D46).
func _tuning_with(changes: Dictionary, base: GuestTuning) -> GuestTuning:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GuestTuning.PATH))
	d["day_s"] = base.day_s
	d["arrival_window_s"] = base.arrival_window_s
	d["arrivals_per_day"] = base.arrivals_per_day
	d.merge(changes, true)
	var errors: Array[String] = []
	var t := GuestTuning.from_dict(d, errors)
	assert(errors.is_empty(), str(errors))
	return t
