class_name ScoringEdges
extends RefCounted
## E3-S24: guest scoring at the edges, part of /balance reactions (ReactionField.measure,
## scripts/sim.gd --table reactions; docs/design.md Balance targets, reactions). Guests play
## with no scene (GuestHole.play_out), one guest at a time, so these rows read the swing and
## the short game alone, without the queue.
##
## - The top of the skill range: skill 10 on E3-S1's spike holes (D40: example_par3, the
##   generated flat par 4, hilly par 4, hilly par 4 with water, hilly par 5 and flat par 5
##   with water), against D40's expected score of par: the mean of the six holes within
##   SKILL_10_WITHIN. Each hole is recorded too; no full_sigma_best puts all six within it
##   (E3-S24: the par 5s, reached in two (D35), play under par whatever the noise that keeps
##   the hilly par 4s near par, and the hilly par 4s over it).
## - Putting on sloped greens (tests/fixtures/short_game_holes.gd): one-, two- and
##   three-putt shares by skill, and noise-free (every sigma 0), on the sloped, tiered and
##   flat greens from 10 and 15 yd in eight directions. Guests aim every putt at the cup
##   (D41), so a noise-free guest still misses a breaking putt by its break.
## - Chips with `guest_min_power`: strokes to hole out from the fairway 5, 10, 20 and 30 yd
##   off a flat green, and the share of chips struck at the power floor, by skill.
##
## Rows are BalanceSim's: {name, measured, target, ok, note}; only the spike holes' mean has
## a target, the rest are recorded.

## D40: skill 10 expects par; E3-S24's Accept: its mean over the spike holes within this of par.
const SKILL_10_WITHIN: float = 0.25
## The skills the short-game rows are read at, and -1 for noise-free.
const SKILLS: Array[int] = [1, 4, 7, 10]
## E3-S1's spike holes (spike_hole), in row order, and their pars; the short-game greens.
const SPIKE_HOLES: Array[String] = ["example_par3", "flat par 4", "hilly par 4",
		"hilly par 4 water", "hilly par 5", "flat par 5 water"]
const SPIKE_PARS := {"example_par3": 3, "flat par 4": 4, "hilly par 4": 4,
		"hilly par 4 water": 4, "hilly par 5": 5, "flat par 5 water": 5}
const GREENS: Array[String] = ["sloped green", "tier green", "flat green"]
const NOISE_FREE: int = -1
## A putt from this close (yards, ball to cup centre) is a tap-in: the putting rows count how
## many of them drop.
const SHORT_PUTT_YD: float = 2.0
## Chip starts, tiles off the green's edge (5 yd a tile).
const CHIP_OFF_TILES: Array[int] = [1, 2, 4, 6]
## Guest seeds: rng_seed + SEED_STEP × i, as tests/test_guest_shot.gd's skill test steps them.
const SEED_STEP: int = 100
const EPS := 0.001

var model: Variant
var tuning: GuestTuning


## `p_model` the ShotModel guests play with, `p_tuning` their tunables (the defaults when
## null; /balance passes a variant to try a number before it goes in data/guests.json).
func _init(p_model: Variant = null, p_tuning: GuestTuning = null) -> void:
	model = p_model if p_model != null else ShotModel.new()
	tuning = p_tuning if p_tuning != null else GuestTuning.load_default()


static func _row(row_name: String, measured: float, target: Vector2, note: String = "") -> Dictionary:
	return {"name": row_name, "measured": measured, "target": target,
			"ok": measured >= target.x - EPS and measured <= target.y + EPS, "note": note}


## Every row: `runs` guests (at least 1) a spike hole at skill 10, and as many putts and
## chips a skill on the short-game greens, seeds from `rng_seed`. E3-S48: the work is
## jobs(), each run by run_job (here, or in its own Godot by ReactionField.run_jobs), and the
## rows are rows_from() of the results.
func measure(runs: int, rng_seed: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for job: Dictionary in jobs(runs, rng_seed):
		results.append(run_job(job))
	return rows_from(runs, rng_seed, results)


## The jobs measure is made of, in the order rows_from reads them: each spike hole at skill
## 10 and skill 1, each green's putts noise-free and at SKILLS, the chips at SKILLS.
func jobs(runs: int, rng_seed: int) -> Array[Dictionary]:
	var n := maxi(runs, 1)
	var out: Array[Dictionary] = []
	for hole_name: String in SPIKE_HOLES:
		for skill: int in [10, 1]:
			out.append({"kind": "edge_hole", "hole": hole_name, "skill": skill, "n": n, "seed": rng_seed})
	for green_name: String in GREENS:
		for skill: int in [NOISE_FREE] + SKILLS:
			out.append({"kind": "edge_putts", "green": green_name, "skill": skill, "n": n, "seed": rng_seed})
	for skill: int in SKILLS:
		out.append({"kind": "edge_chips", "skill": skill, "n": n, "seed": rng_seed})
	return out


## One of jobs()' results: mean_over_par, putts or chips.
func run_job(job: Dictionary) -> Dictionary:
	var n := int(job.n)
	var s := int(job.seed)
	var skill := int(job.skill)
	match String(job.kind):
		"edge_hole":
			var course := spike_hole(String(job.hole))
			return mean_over_par(course, course.holes[0], skill, n, s)
		"edge_putts":
			return putts(green(String(job.green)), skill, n, s)
		"edge_chips":
			return chips(skill, n, s)
	push_error("no edges job %s" % job.kind)
	return {}


## The rows of jobs(`runs`, `rng_seed`)' `results`, in that order.
func rows_from(runs: int, rng_seed: int, results: Array[Dictionary]) -> Array[Dictionary]:
	var n := maxi(runs, 1)
	var rows: Array[Dictionary] = []
	var k := 0
	var sum := 0.0
	var parts_10 := PackedStringArray()
	for hole_name: String in SPIKE_HOLES:
		var m := results[k]
		var worst := results[k + 1]
		k += 2
		sum += float(m.over)
		parts_10.append("%s %+.2f" % [hole_name, m.over])
		rows.append(_row("skill 10 on %s: strokes over par (mean)" % hole_name, m.over,
				Vector2(-INF, INF), "%d guests, par %d; skill 1 %+.2f" % [n, SPIKE_PARS[hole_name],
					worst.over]))
	rows.append(_row("skill 10 on the spike holes: strokes over par (mean of the holes)",
			sum / SPIKE_HOLES.size(), Vector2(-SKILL_10_WITHIN, SKILL_10_WITHIN),
			"full_sigma_best %.3f; %s" % [tuning.full_sigma_best, ", ".join(parts_10)]))
	for green_name: String in GREENS:
		var parts := PackedStringArray()
		var noise_free := 0.0
		var skill_10 := 0.0
		for skill: int in [NOISE_FREE] + SKILLS:
			var p := results[k]
			k += 1
			parts.append("%s: 1 putt %.2f, 2 %.2f, 3+ %.2f, mean %.2f, inside %d yd holed %.2f of %d" % [
					_skill_name(skill), p.one, p.two, p.three, p.mean, SHORT_PUTT_YD, p.short_holed, p.short])
			if skill == NOISE_FREE:
				noise_free = p.three
			elif skill == 10:
				skill_10 = p.three
		rows.append(_row("%s: three-putt share, noise-free" % green_name, noise_free,
				Vector2(-INF, INF), "skill 10 %.2f; %s" % [skill_10, "; ".join(parts)]))
	var chip_parts := PackedStringArray()
	var chip_10 := 0.0
	for skill: int in SKILLS:
		var c := results[k]
		k += 1
		chip_parts.append("%s: %s" % [_skill_name(skill), c.note])
		if skill == 10:
			chip_10 = c.mean
	rows.append(_row("chips, flat green: strokes to hole out, skill 10 (mean)", chip_10,
			Vector2(-INF, INF), "guest_min_power %.2f; %s" % [tuning.guest_min_power,
				"; ".join(chip_parts)]))
	return rows


## E3-S1's spike holes (D40), each a course of one open hole.
static func spike_holes() -> Dictionary:
	var out := {}
	for hole_name: String in SPIKE_HOLES:
		out[hole_name] = spike_hole(hole_name)
	return out


## The spike hole of that name, a course of one open hole.
static func spike_hole(hole_name: String) -> CourseData:
	match hole_name:
		"example_par3":
			return CourseSave.load_file("res://courses/example_par3.json")
		"flat par 4":
			return CourseGenerator.generate(4, false, false)
		"hilly par 4":
			return CourseGenerator.generate(4, true, false)
		"hilly par 4 water":
			return CourseGenerator.generate(4, true, true)
		"hilly par 5":
			return CourseGenerator.generate(5, true, false)
		"flat par 5 water":
			return CourseGenerator.generate(5, false, true)
	push_error("no spike hole %s" % hole_name)
	return null


## The short-game green of that name (GREENS).
static func green(green_name: String) -> CourseData:
	match green_name:
		"sloped green":
			return ShortGameHoles.sloped_green()
		"tier green":
			return ShortGameHoles.tier_green()
	return ShortGameHoles.flat_green()


## `n` guests of `skill` play `hole` alone: {over: mean strokes over par, mean}.
func mean_over_par(course: CourseData, hole: HoleData, skill: int, n: int, rng_seed: int) -> Dictionary:
	var sum := 0
	for i in n:
		var g := GuestHole.new(course, hole, skill, _seed(rng_seed, i), tuning, model)
		g.play_out()
		sum += g.score.total()
	var mean := float(sum) / n
	return {"mean": mean, "over": mean - hole.par}


## About `n` putts by guests of `skill` (NOISE_FREE: every sigma 0) on `course`, spread over
## ShortGameHoles.putt_starts (at least one each), each holed out: {one, two, three (3 or
## more), mean} putts, and of the putts struck from SHORT_PUTT_YD or less, how many and the
## share holed (short, short_holed).
func putts(course: CourseData, skill: int, n: int, rng_seed: int) -> Dictionary:
	var t := tuning if skill != NOISE_FREE else noise_free_tuning()
	var starts := ShortGameHoles.putt_starts()
	var each := maxi(1, ceili(float(n) / starts.size()))
	var counts := [0, 0, 0]
	var total := 0
	var played := 0
	var short := 0
	var short_holed := 0
	for j: int in starts.size():
		var hole := ShortGameHoles.with_start(course, starts[j])
		for i in each:
			var g := GuestHole.new(course, hole, maxi(skill, t.skill_min),
					_seed(rng_seed, i * starts.size() + j), t, model)
			g.play_out()
			var cup := g.field.tile_center(hole.cup)
			for r: GuestHole.StrokeRecord in g.strokes:
				if Vector2(r.start.x, r.start.y).distance_to(cup) <= SHORT_PUTT_YD:
					short += 1
					short_holed += 1 if r.holed else 0
			var k := g.score.total()
			counts[clampi(k, 1, 3) - 1] += 1
			total += k
			played += 1
	return {"one": counts[0] / float(played), "two": counts[1] / float(played),
		"three": counts[2] / float(played), "mean": total / float(played),
		"short_holed": short_holed / float(maxi(short, 1)), "short": short}


## About `n` chips by guests of `skill` from the fairway CHIP_OFF_TILES off the flat green,
## each holed out: {mean strokes, note: by distance, with the share struck at the floor}.
func chips(skill: int, n: int, rng_seed: int) -> Dictionary:
	var course := ShortGameHoles.flat_green()
	var each := maxi(1, ceili(float(n) / CHIP_OFF_TILES.size()))
	var parts := PackedStringArray()
	var all := 0
	var played := 0
	for j: int in CHIP_OFF_TILES.size():
		var off: int = CHIP_OFF_TILES[j]
		var hole := ShortGameHoles.with_start(course, ShortGameHoles.chip_start(off))
		var sum := 0
		var floored := 0
		var up_down := 0
		for i in each:
			var g := GuestHole.new(course, hole, skill,
					_seed(rng_seed, i * CHIP_OFF_TILES.size() + j), tuning, model)
			g.play_out()
			sum += g.score.total()
			if g.score.total() <= 2:
				up_down += 1
			if g.strokes[0].power <= tuning.guest_min_power + 1e-6:
				floored += 1
		all += sum
		played += each
		parts.append("%d yd off %.2f (up and down %.2f, floored %.2f)" % [5 * off,
				float(sum) / each, up_down / float(each), floored / float(each)])
	return {"mean": all / float(played), "note": ", ".join(parts)}


## The default tuning with every click sigma 0: a guest who strikes exactly what it plans.
func noise_free_tuning() -> GuestTuning:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GuestTuning.PATH))
	for key: String in ["full_sigma_best", "full_sigma_worst", "putt_aim_sigma_best",
			"putt_aim_sigma_worst", "putt_power_sigma_best", "putt_power_sigma_worst"]:
		d[key] = 0.0
	var errors: Array[String] = []
	return GuestTuning.from_dict(d, errors)


## Guest `i`'s seed: one seed per guest and start, so no two starts replay the same noise.
static func _seed(rng_seed: int, i: int) -> int:
	return rng_seed + SEED_STEP * i


static func _skill_name(skill: int) -> String:
	return "noise-free" if skill == NOISE_FREE else "skill %d" % skill
