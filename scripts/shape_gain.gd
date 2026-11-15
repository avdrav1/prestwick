extends SceneTree
## E20-S2 (D75): what shot shape gives skilled guests on the dogleg courses. Each bending hole
## (a turn of shape_turn_min_deg or more at its corner, from the tee) of Dogleg Hollow and Dogleg
## Hollow (Championship) is played by `--runs` guests of each skill from shape_skill_min to
## skill_max, alone through GuestHole (no queue), twice with the same seeds: with
## data/guests.json as it is, and with shaping turned off (shape_skill_min over skill_max), so
## the only difference is the shape. Prints, per hole and per course: the share of tee shots
## planned shaped and the shape picked most, the mean score shaped and forced straight, the
## gain (straight less shaped, strokes a hole) and its standard error over the paired plays,
## and the share of shaped tee shots that cut the corner; and under each hole the tee shot itself, shaped
## against straight: its mean distance to the cup (40 yd a penalty stroke), fairway share and shanks.
##
## `--set key=json` tries another value of a data/guests.json key for both runs (scratch
## tuning; the file is not touched), `--course N` plays only the Nth course of the two.
##
##   godot --headless --path . -s res://scripts/shape_gain.gd [-- --runs 100 --seed 1
##       --set shape_gain_yd=5 --course 1]

const COURSES: Array[String] = ["res://courses/dogleg_hollow.json",
		"res://courses/dogleg_hollow_championship.json"]


func _initialize() -> void:
	var runs := 100
	var base_seed := 1
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == "--runs" and i + 1 < args.size():
			runs = int(args[i + 1])
		elif args[i] == "--seed" and i + 1 < args.size():
			base_seed = int(args[i + 1])
	var model := ShotModel.new()
	var sets := {}
	var only := 0
	for i: int in args.size():
		if args[i] == "--set" and i + 1 < args.size():
			var kv := args[i + 1].split("=", true, 1)
			sets[kv[0]] = JSON.parse_string(kv[1])
		elif args[i] == "--course" and i + 1 < args.size():
			only = int(args[i + 1])
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GuestTuning.PATH))
	d.merge(sets, true)
	var errors: Array[String] = []
	var tuning := GuestTuning.from_dict(d.duplicate(true), errors)
	assert(errors.is_empty(), str(errors))
	d["shape_skill_min"] = tuning.skill_max + 1
	d["strong_shape_skill_min"] = tuning.skill_max + 1
	var straight := GuestTuning.from_dict(d, errors)
	assert(errors.is_empty(), str(errors))
	GuestClubTable.warm(model)
	var t0 := Time.get_ticks_msec()
	print("shape gain: skills %d to %d, %d guests a skill a hole, seed %d; shape_turn_min_deg %.0f, cut shares %s, shape_gain_yd %.1f" % [
			tuning.shape_skill_min, tuning.skill_max, runs, base_seed, tuning.shape_turn_min_deg,
			tuning.shape_cut_shares, tuning.shape_gain_yd])
	for ci: int in COURSES.size():
		if only > 0 and ci + 1 != only:
			continue
		var path := COURSES[ci]
		var course := CourseSave.load_file(path)
		var field := HeightField.new(course, model.params)
		var c_plays := 0
		var c_shaped := 0
		var c_cut := 0
		var c_diff := 0.0
		var c_diff2 := 0.0
		var c_on := 0.0
		var holes_bending := 0
		var holes_shaped := 0
		print(course.course_name)
		for h: HoleData in course.holes:
			var turn: Variant = GuestHole.turn_of(course, h)
			if turn == null:
				continue
			var tee := field.tile_center(h.tee)
			var cup := field.tile_center(h.cup)
			var deg := rad_to_deg(((turn as Vector2) - tee).angle_to(cup - (turn as Vector2)))
			if absf(deg) < tuning.shape_turn_min_deg:
				continue
			holes_bending += 1
			var plays := 0
			var shaped := 0
			var cut := 0
			var on_sum := 0.0
			var off_sum := 0.0
			var diff2 := 0.0
			var picks := {}
			var tee_d := [0.0, 0.0]
			var shanks := [0, 0]
			var fairway := [0, 0]
			for skill: int in range(tuning.shape_skill_min, tuning.skill_max + 1):
				for i: int in runs:
					var guest_seed := base_seed * 100000 + skill * 1000 + i
					var hs := GuestHole.hole_seed(guest_seed, h.number)
					var a := GuestHole.new(course, h, skill, hs, tuning, model, null, turn)
					a.play_out()
					var b := GuestHole.new(course, h, skill, hs, straight, model, null, turn)
					b.play_out()
					var first: GuestHole.StrokeRecord = a.strokes[0]
					for k: int in 2:
						var r: GuestHole.StrokeRecord = (a if k == 0 else b).strokes[0]
						tee_d[k] += Vector2(r.rest.x, r.rest.y).distance_to(cup) + 40.0 * r.penalty_strokes
						shanks[k] += 1 if r.shank else 0
						var sf := field.surface_at(r.rest.x, r.rest.y)
						fairway[k] += 1 if r.penalty_strokes == 0 and (sf == Surface.Type.FAIRWAY or sf == Surface.Type.GREEN) else 0
					if first.planned_shape != "":
						shaped += 1
					if first.shape_id != "":
						picks[first.shape_id] = int(picks.get(first.shape_id, 0)) + 1
					if first.cut_corner:
						cut += 1
					var sa := a.score.total()
					var sb := b.score.total()
					on_sum += sa
					off_sum += sb
					diff2 += float(sb - sa) * float(sb - sa)
					plays += 1
			var mean_diff := (off_sum - on_sum) / plays
			var sd := sqrt(maxf(diff2 / plays - mean_diff * mean_diff, 0.0))
			var top := ""
			for k: String in picks:
				if top == "" or int(picks[k]) > int(picks[top]):
					top = k
			if shaped * 2 > plays:
				holes_shaped += 1
			print("  hole %d par %d, turns %s %.0f deg: shaped %.0f%% (%s), cut the corner %.0f%% of those; mean %.3f shaped, %.3f straight, gain %+.3f +/- %.3f" % [
					h.number, h.par, "right" if deg > 0 else "left", absf(deg),
					100.0 * shaped / plays, top if top != "" else "none",
					100.0 * cut / maxi(shaped, 1), on_sum / plays, off_sum / plays, mean_diff,
					sd / sqrt(plays)])
			print("    tee shot: to the cup %.0f / %.0f yd, fairway %.0f%% / %.0f%%, shanks %.1f%% / %.1f%% (shaped / straight)" % [
					tee_d[0] / plays, tee_d[1] / plays, 100.0 * fairway[0] / plays,
					100.0 * fairway[1] / plays, 100.0 * shanks[0] / plays, 100.0 * shanks[1] / plays])
			c_plays += plays
			c_shaped += shaped
			c_cut += cut
			c_diff += off_sum - on_sum
			c_diff2 += diff2
			c_on += on_sum
		var cm := c_diff / c_plays
		var csd := sqrt(maxf(c_diff2 / c_plays - cm * cm, 0.0))
		print("  %s: %d of %d bending holes shaped on most tee shots; %.0f%% of %d tee shots shaped, %.0f%% of those cut the corner; mean %.3f shaped against %.3f straight a hole, gain %+.3f +/- %.3f strokes a hole (%+.2f a round of its bending holes)" % [
				course.course_name, holes_shaped, holes_bending, 100.0 * c_shaped / c_plays, c_plays,
				100.0 * c_cut / maxi(c_shaped, 1), c_on / c_plays, (c_on + c_diff) / c_plays, cm,
				csd / sqrt(c_plays), cm * holes_bending])
	print("%.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()

