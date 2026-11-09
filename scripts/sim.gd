extends SceneTree
## The /balance simulator (.claude/skills/balance/SKILL.md). Measures one table through the
## real ShotModel and Ball (scripts/balance_sim.gd) and prints each measured value next to
## its docs/design.md target. Exit code 0 when every target is hit, 1 when one misses,
## 2 on bad arguments.
##
##   godot --headless --path . -s res://scripts/sim.gd -- --table clubs --runs 200 --seed 1
##
## Tables: clubs, lies, surfaces, land, reactions, putting, economy. --runs defaults to 200 and --seed to 1
## (fixed, so two runs differ only by what was tuned). For land, --runs is the number of
## generated seeds, counted up from --seed (E6-S8). For reactions (E3-S8), --runs is the
## field, how many guests play each fixture hole (the target is read at --runs 50); the
## field's days count up from --seed, which is also the corridor par 4's land seed. For
## putting (E3-S51, scripts/putting_sim.gd), --runs is the hole-outs from each length on each
## green. E3-S48: --jobs N runs reactions' jobs N at a time, each in its own headless Godot
## (the figures are the same as --jobs 1, which runs them all in this one); it defaults to
## the machine's processor count, at most DEFAULT_JOBS_MAX. E4-S1: economy
## (scripts/economy_sim.gd) prints every candidate cost table's measured hole costs, the
## guests' measured reaction mix on PlaytestNine (--runs guest days for each of its nine
## stages, 1 unless --runs is given) and each candidate economy's day and 40-day run; `--log`
## adds each run's day-by-day lines. The candidates are proposals, so some rows miss by design.

const TABLES: PackedStringArray = ["clubs", "lies", "surfaces", "land", "reactions", "putting",
		"economy"]
const DEFAULT_JOBS_MAX: int = 16


func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	if args.is_empty():
		print("usage: sim.gd -- --table clubs|lies|surfaces|land|reactions|putting|economy [--runs N] [--seed S] [--jobs N]")
		quit(2)
		return
	var sim := BalanceSim.new()
	var table: String = args.table
	var runs: int = args.runs
	var rng_seed: int = args.seed
	var rows: Array[Dictionary]
	match table:
		"clubs":
			rows = sim.measure_clubs(runs, rng_seed)
		"lies":
			rows = sim.measure_lies(runs, rng_seed)
		"land":
			rows = sim.measure_land(runs, rng_seed)
		"reactions":
			rows = sim.measure_reactions(runs, rng_seed, ReactionField.NINE_DAYS, args.jobs)
		"putting":
			rows = sim.measure_putting(runs, rng_seed)
		"economy":
			var econ := EconomySim.new()
			rows = econ.measure(runs if args.runs_given else 1, rng_seed)
			if args.log:
				for economy: String in econ.run_logs:
					print("-- run %s" % economy)
					for line: String in econ.run_logs[economy]:
						print(line)
		_:
			rows = sim.measure_surfaces(runs, rng_seed)
	print("== /balance %s, %d runs, seed %d" % [table, runs, rng_seed])
	for line in BalanceSim.format(rows):
		print(line)
	var missed := BalanceSim.misses(rows)
	print("== %s: %s" % [table, "every target hit" if missed.is_empty() else "%d missed" % missed.size()])
	quit(0 if missed.is_empty() else 1)


## {table, runs, seed}, or {} when the table is missing or unknown.
static func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {"table": "", "runs": 200, "seed": 1, "runs_given": false, "log": false,
		"jobs": mini(OS.get_processor_count(), DEFAULT_JOBS_MAX)}
	var i := 0
	while i < argv.size():
		var key := argv[i]
		var value := argv[i + 1] if i + 1 < argv.size() else ""
		match key:
			"--table":
				out.table = value
			"--runs":
				out.runs = maxi(1, value.to_int())
				out.runs_given = true
			"--log":
				out.log = true
				i += 1
				continue
			"--seed":
				out.seed = value.to_int()
			"--jobs":
				out.jobs = maxi(1, value.to_int())
			_:
				i += 1
				continue
		i += 2
	if not TABLES.has(out.table):
		return {}
	return out
