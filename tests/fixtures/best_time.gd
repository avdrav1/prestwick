class_name BestTime
extends RefCounted
## E6-S22 review: the wall-clock budget asserts (tests/test_validator.gd, test_issue_marker.gd)
## time the fastest of a few runs, not one. scripts/run_tests.sh runs one Godot per physical
## core, so a single sample can land on a moment when the machine is busy with other work (a
## 30 ms check measured 62 ms once). The fastest run is what the code costs; a real slowdown
## slows every run, so it still fails.

const RUNS := 5


## Calls `f` `runs` times and returns the fastest call in milliseconds. `f` must give the same
## result each call (a pure check, an idempotent layout).
static func ms(f: Callable, runs: int = RUNS) -> float:
	var best: int = -1
	for i: int in runs:
		var t0: int = Time.get_ticks_usec()
		f.call()
		var took: int = Time.get_ticks_usec() - t0
		if best < 0 or took < best:
			best = took
	return best / 1000.0


## E6-S30: a test that times itself against wall-clock limits starts with
## `if BestTime.later(self): return`. scripts/run_tests.sh finds those tests by that call, and
## while its parallel batch runs (PRESTWICK_TEST_PHASE=batch) `later` passes them at once;
## after the batch it runs each alone, one at a time, with the variable unset, so a busy
## machine (the other jobs, a playtest beside the run) cannot slow them. Without the variable
## (GUT on its own) the test runs in place.
const PHASE_ENV := "PRESTWICK_TEST_PHASE"


static func later(test: GutTest) -> bool:
	if OS.get_environment(PHASE_ENV) != "batch":
		return false
	test.pass_test("timed: runs alone after the parallel batch (scripts/run_tests.sh)")
	return true
