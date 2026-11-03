extends GutTest
## E2-S5: the /balance simulator's measuring functions (scripts/balance_sim.gd), called
## without the command line. Each table's rows hit their docs/design.md targets with the
## values in golf/clubs.tres, golf/lies.tres and course/surfaces.tres.

const RUNS: int = 3
const SEED: int = 1

var sim: BalanceSim


func before_each() -> void:
	sim = BalanceSim.new()


func _named(rows: Array[Dictionary], prefix: String) -> Dictionary:
	for r in rows:
		if String(r.name).begins_with(prefix):
			return r
	return {}


func _assert_all_hit(rows: Array[Dictionary], table: String) -> void:
	assert_gt(rows.size(), 0, "%s has rows" % table)
	for r in rows:
		assert_true(r.ok, "%s: %s measured %.3f, target %s" % [table, r.name, r.measured, r.target])


func test_clubs_rows_hit_their_targets() -> void:
	var rows := sim.measure_clubs(RUNS, SEED)
	_assert_all_hit(rows, "clubs")
	var driver := _named(rows, "driver carry")
	assert_between(float(driver.measured), 230.0, 260.0)
	assert_eq(driver.target, BalanceSim.DRIVER_CARRY, "printed next to its target")
	for i in BalanceSim.IRONS.size() - 1:
		var step := _named(rows, "%s to %s step" % [BalanceSim.IRONS[i], BalanceSim.IRONS[i + 1]])
		assert_false(step.is_empty(), "a row per iron step")
	assert_false(_named(rows, "putter legal on green only").is_empty())
	assert_false(_named(rows, "full putt on flat green").is_empty())


func test_lies_rows_hit_their_targets() -> void:
	var rows := sim.measure_lies(RUNS, SEED)
	_assert_all_hit(rows, "lies")
	assert_eq(rows.size(), 2, "uphill and sidehill")


func test_surfaces_rows_hit_their_targets() -> void:
	var rows := sim.measure_surfaces(RUNS, SEED)
	_assert_all_hit(rows, "surfaces")
	assert_false(_named(rows, "rough distance cost").is_empty())
	assert_false(_named(rows, "bunker sw at 50%").is_empty())
	assert_eq(rows.filter(func(r: Dictionary) -> bool: return String(r.name).begins_with("green:")).size(), 5,
			"the five green targets on GridHeightEvidence")


func test_the_lie_spots_read_what_d18_names() -> void:
	var at := (Vector2(4, BalanceSim.STRIP_H / 2) + Vector2(0.5, 0.5)) * 5.0
	var up := sim.model.lies.measure(HeightField.new(sim.uphill_course(), sim.model.params), at, 0.0)
	assert_almost_eq(up.rise, 2.0, 0.001, "a 2-step uphill lie")
	var side := sim.model.lies.measure(HeightField.new(sim.sidehill_course(), sim.model.params), at, 0.0)
	assert_almost_eq(absf(side.tilt), 1.0, 0.001, "a 1-step sidehill lie")


func test_same_seed_same_numbers() -> void:
	var a := sim.measure_clubs(RUNS, SEED)
	var b := BalanceSim.new().measure_clubs(RUNS, SEED)
	for i in a.size():
		assert_eq(a[i].measured, b[i].measured, a[i].name)


func test_a_missed_target_is_reported() -> void:
	var lies: LieTable = LieTable.load_default().duplicate()
	lies.uphill_k = 0.0
	var off := BalanceSim.new(ShotModel.new(null, lies))
	var missed := BalanceSim.misses(off.measure_lies(RUNS, SEED))
	assert_eq(missed.size(), 1, "with k at 0 the uphill target misses")
	var lines := BalanceSim.format(off.measure_lies(RUNS, SEED))
	assert_string_contains(lines[0], "MISS")
