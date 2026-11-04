class_name Sweep
extends RefCounted
## E2-S16: how dense the settle sweeps in tests/test_ball.gd run. By default each sweep keeps
## its worst cases and a few depths, so `scripts/run_tests.sh` stays under a minute and every
## D16 case in docs/design.md Settle targets is still asserted. `scripts/run_tests.sh --full`
## (PRESTWICK_FULL_SWEEPS=1) runs the full grids the Measured-for column was measured on,
## for `/balance surfaces` work and before a ship. E6-S22: it also gates the noisy-chip grid in
## tests/test_round_flow.gd and the brute-force nearest putts in tests/test_shot_prediction.gd,
## and E6-S29 the club sweep over the hilly holes in tests/test_settle.gd (one Godot per test).

const ENV := "PRESTWICK_FULL_SWEEPS"


static func full() -> bool:
	return OS.get_environment(ENV) == "1"


## `dense` with --full, else `quick`.
static func pick(quick: Array, dense: Array) -> Array:
	return dense if full() else quick


## E6-S30: `scripts/run_tests.sh --full` runs a test that names `Sweep.part` in its own body
## as SWEEP_PARTS Godots at once (scripts/run_tests.sh), each with PRESTWICK_SWEEP_PART set to
## "<k>/<n>", so no one sweep bounds the run. Each takes every n-th item of the list from its
## k-th. A parted test
## asserts only what holds for any slice (a worst under a bound, none capped); without the
## variable (the default run, GUT on its own) `part` returns the whole list.
const PART_ENV := "PRESTWICK_SWEEP_PART"


## [k, n] from PRESTWICK_SWEEP_PART, or [0, 1] when it is unset or malformed.
static func part_of() -> Array[int]:
	var bits := OS.get_environment(PART_ENV).split("/")
	if bits.size() == 2 and bits[0].is_valid_int() and bits[1].is_valid_int():
		var k := bits[0].to_int()
		var n := bits[1].to_int()
		if n >= 1 and k >= 0 and k < n:
			return [k, n] as Array[int]
	return [0, 1] as Array[int]


## The items of `items` this part runs: every n-th from the k-th.
static func part(items: Array) -> Array:
	var kn := part_of()
	if kn[1] == 1:
		return items
	var mine: Array = []
	for i: int in range(kn[0], items.size(), kn[1]):
		mine.append(items[i])
	return mine
