extends GutTest
## E6-S30: the test run's own machinery. scripts/run_tests.sh gives each run (and each GUT job
## in it) its own user:// folder, slices a parted sweep (Sweep.part) and runs the timed tests
## after the parallel batch (BestTime.later).

var _saved := {}


func before_each() -> void:
	for key: String in [Sweep.PART_ENV, BestTime.PHASE_ENV]:
		_saved[key] = OS.get_environment(key)


func after_each() -> void:
	for key: String in _saved:
		OS.set_environment(key, _saved[key])


func test_a_run_writes_user_files_inside_its_own_folder() -> void:
	var run_dir := OS.get_environment("PRESTWICK_TEST_RUN_DIR")
	var user_dir := ProjectSettings.globalize_path("user://")
	if run_dir.is_empty():
		pass_test("not under scripts/run_tests.sh: user:// is %s" % user_dir)
		return
	assert_true(user_dir.begins_with(run_dir + "/"), "user:// (%s) is inside the run's folder %s" % [user_dir, run_dir])
	var path := "user://test_harness_%d.txt" % OS.get_process_id()
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f, "user:// is writable")
	if f != null:
		f.store_string("ok")
		f.close()
	var on_disk := ProjectSettings.globalize_path(path)
	assert_true(on_disk.begins_with(run_dir + "/") and FileAccess.file_exists(on_disk),
			"and the file is in the run's folder (%s)" % on_disk)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_without_a_part_a_sweep_runs_whole() -> void:
	var items := range(10)
	for v: String in ["", "x", "4/4", "-1/3", "1/0", "2"]:
		OS.set_environment(Sweep.PART_ENV, v)
		assert_eq(Sweep.part(items), items, "PRESTWICK_SWEEP_PART \"%s\": the whole list" % v)


func test_the_parts_of_a_sweep_cover_it_once() -> void:
	var items := range(11)
	var seen: Array = []
	for k: int in 4:
		OS.set_environment(Sweep.PART_ENV, "%d/4" % k)
		var mine := Sweep.part(items)
		assert_between(mine.size(), 2, 3, "part %d takes a quarter" % k)
		seen.append_array(mine)
	OS.set_environment(Sweep.PART_ENV, "1/4")
	assert_eq(Sweep.part(items), [1, 5, 9], "every 4th from the 1st")
	seen.sort()
	assert_eq(seen, items, "every item once over the four parts")


func test_a_timed_test_waits_only_in_the_batch() -> void:
	OS.set_environment(BestTime.PHASE_ENV, "")
	assert_false(BestTime.later(self), "alone (or GUT on its own): the test runs")
	OS.set_environment(BestTime.PHASE_ENV, "batch")
	assert_true(BestTime.later(self), "in the parallel batch: it passes now and runs later")


## E3-S32: a timed assert's message carries the load average, and says the machine is the likely
## cause when it is past BestTime.LOAD_HIGH.
func test_a_timed_assert_says_the_load() -> void:
	var f := FileAccess.open("/proc/loadavg", FileAccess.READ)
	if f == null:
		assert_eq(BestTime.load_note(), "", "no load average to read")
		return
	# /proc reports a size of 0, so read it by line, as load_note does.
	var one := float(f.get_line().split(" ")[0])
	var note := BestTime.load_note()
	assert_string_contains(note, "load average")
	# Away from the bound, where the load cannot cross it between the two reads.
	if absf(one - BestTime.LOAD_HIGH) > 0.5:
		assert_eq(note.contains("likely the machine"), one > BestTime.LOAD_HIGH,
				"names the machine only under load (now %.2f)" % one)
