extends SceneTree
## The /balance simulator (.claude/skills/balance/SKILL.md). Measures one table through the
## real ShotModel and Ball (scripts/balance_sim.gd) and prints each measured value next to
## its docs/design.md target. Exit code 0 when every target is hit, 1 when one misses,
## 2 on bad arguments.
##
##   godot --headless --path . -s res://scripts/sim.gd -- --table clubs --runs 200 --seed 1
##
## Tables: clubs, lies, surfaces. --runs defaults to 200 and --seed to 1 (fixed, so two runs
## differ only by what was tuned).

const TABLES: PackedStringArray = ["clubs", "lies", "surfaces"]


func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	if args.is_empty():
		print("usage: sim.gd -- --table clubs|lies|surfaces [--runs N] [--seed S]")
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
	var out := {"table": "", "runs": 200, "seed": 1}
	var i := 0
	while i < argv.size():
		var key := argv[i]
		var value := argv[i + 1] if i + 1 < argv.size() else ""
		match key:
			"--table":
				out.table = value
			"--runs":
				out.runs = maxi(1, value.to_int())
			"--seed":
				out.seed = value.to_int()
			_:
				i += 1
				continue
		i += 2
	if not TABLES.has(out.table):
		return {}
	return out
