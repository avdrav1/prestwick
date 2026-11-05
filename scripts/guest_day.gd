extends SceneTree
## E3-S4: a guest day on the nine-hole fixture (tests/fixtures/nine_holes.gd, LandGenerator
## seed 7, every parcel owned, nine open holes), with no scene: GuestBrain stepped once per
## simulated second. Prints, per day seed, how many guests finished nine, round and hole
## times, pace waits, Ball work (ticks a second, seconds at the sim's cap, the costliest plans)
## and the CPU per simulated second; then a pair and a foursome alone on the course. The
## figures go in docs/design.md Guests and reactions (Guest day). E3-S6: each hole's static
## checks (blind, interesting) and their cost, and each day's reactions (praise, neutral,
## complaint, and how often each check failed). E3-S8: the holes reached each day (teed off by a
## group, GuestBrain.teed_off) and finished by someone, with the records a hole.
##
##   godot --headless --path . -s res://scripts/guest_day.gd [-- seeds=1,2,3]

const NineHoles := preload("res://tests/fixtures/nine_holes.gd")


func _initialize() -> void:
	var seeds: Array[int] = [1, 2, 3, 4, 5]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seeds="):
			seeds.clear()
			for s in arg.substr(6).split(","):
				seeds.append(int(s))
	var course := NineHoles.land(7)
	var opened := NineHoles.build(CourseBuilder.new(course))
	print("nine holes: %d open" % opened.size())
	var model := ShotModel.new()
	var tuning := GuestTuning.load_default()
	GuestClubTable.warm(model)
	_statics(course, tuning, model)
	var all_plans: Array[int] = []
	for s in seeds:
		_day(course, s, tuning, model, all_plans)
	all_plans.sort()
	if not all_plans.is_empty():
		var near := 0
		for p in all_plans:
			if p >= 10000:
				near += 1
		print("plan ticks a stroke (all days): median %d, p95 %d, p99 %d, worst %d; %d of %d at 10,000 or more (worst case about 23,700)" % [
			all_plans[all_plans.size() / 2], all_plans[int(all_plans.size() * 0.95)],
			all_plans[int(all_plans.size() * 0.99)], all_plans[-1], near, all_plans.size()])
	for speed in [1.0, 3.0]:
		_frames(course, seeds[0], tuning, model, speed)
	for spec: Array in [[2, 10], [2, 5], [2, 1], [1, 5], [4, 10], [4, 5]]:
		var size: int = spec[0]
		var skill: int = spec[1]
		var specs := []
		for i in size:
			specs.append([skill, 5, Guest.Taste.CASUAL, 900 + i])
		var alone := GuestBrain.new(course, 1, tuning, model, [GuestSpawner.group(0, 0.0, specs)])
		alone.run_day()
		var g: Guest = alone.guests[0]
		print("a group of %d (skill %d) alone: %d holes, round %d s (left at %d, %s), waits %d s, %.1f strokes a guest" % [
			size, skill, g.records.size(), g.left_s - g.arrived_s, g.left_s, "dusk" if g.left_at_dusk else "done",
			_sum_waits(alone), _strokes(alone) / float(size)])
	quit(0)


func _day(course: CourseData, day_seed: int, tuning: GuestTuning, model: ShotModel,
		all_plans: Array[int]) -> void:
	var brain := GuestBrain.new(course, day_seed, tuning, model)
	var cpu: Array[float] = []
	var moves: Array[float] = []
	while not brain.day_over:
		var t0 := Time.get_ticks_usec()
		brain.serve(-1)
		var t1 := Time.get_ticks_usec()
		brain.step()
		var t2 := Time.get_ticks_usec()
		cpu.append((t2 - t0) / 1000.0)
		moves.append((t2 - t1) / 1000.0)
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
