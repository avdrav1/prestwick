class_name Sweep
extends RefCounted
## E2-S16: how dense the settle sweeps in tests/test_ball.gd run. By default each sweep keeps
## its worst cases and a few depths, so `scripts/run_tests.sh` stays under a minute and every
## D16 case in docs/design.md Settle targets is still asserted. `scripts/run_tests.sh --full`
## (PRESTWICK_FULL_SWEEPS=1) runs the full grids the Measured-for column was measured on,
## for `/balance surfaces` work and before a ship. E6-S22: it also gates the noisy-chip grid in
## tests/test_round_flow.gd and the brute-force nearest putts in tests/test_shot_prediction.gd.

const ENV := "PRESTWICK_FULL_SWEEPS"


static func full() -> bool:
	return OS.get_environment(ENV) == "1"


## `dense` with --full, else `quick`.
static func pick(quick: Array, dense: Array) -> Array:
	return dense if full() else quick
