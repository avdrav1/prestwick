extends GutTest
## E3-S36: the rest of the guest tunables have a bound in GuestTuning._check_ranges, and every
## check's message names its keys and the bad value. (E3-S13's bounds are in test_guest_shot.gd.)


## Each new bound fails a bad value with its key, and the value, named; the edge passes.
func test_each_new_bound_fails_a_bad_value_with_its_key_named() -> void:
	# [key, a bad value, a good edge value]
	var cases: Array = [
		["wait_base_s", -1.0, 0.0],
		["wait_per_patience_s", -0.5, 0.0],
		["walk_base_yd", -10.0, 0.0],
		["walk_per_patience_yd", -1.0, 0.0],
		["challenge_within", -1.0, 0.0],
		["eye_height_yd", 0.0, 0.25],
		["eye_height_yd", -1.75, 0.25],
		["mark_height_yd", -2.0, 0.0],
		["over_par_worst", -2.0, 0.0],
		["rating_window", 0, 1],
		["rating_window", -5, 1],
	]
	for c: Array in cases:
		var d := _shipped()
		d[c[0]] = c[1]
		var errors := _errors(d)
		assert_eq(errors.size(), 1, "%s = %s: one error (%s)" % [c[0], c[1], errors])
		assert_true(_named(errors, c[0]), "%s is named: %s" % [c[0], errors])
		assert_true(_named(errors, "(%s)" % _shown(c[1])), "the value %s is named: %s" % [c[1], errors])
		var ok := _shipped()
		ok[c[0]] = c[2]
		assert_eq(_errors(ok), [] as Array[String], "%s = %s is inside the range" % [c[0], c[2]])


## A Casual guest's challenge band is the wider one (D42): casual_challenge_within at least
## challenge_within, and 0 or more.
func test_the_casual_band_must_be_at_least_the_challenge_band() -> void:
	var d := _shipped()
	d["casual_challenge_within"] = 1.0
	var errors := _errors(d)
	assert_eq(errors.size(), 1, str(errors))
	assert_true(_named(errors, "casual_challenge_within") and _named(errors, "challenge_within"),
			str(errors))
	assert_true(_named(errors, "(1.0)"), str(errors))
	var neg := _shipped()
	neg["casual_challenge_within"] = -1.0
	neg["challenge_within"] = -1.0
	var both := _errors(neg)
	assert_true(_named(both, "casual_challenge_within (-1"), str(both))
	assert_true(_named(both, "challenge_within (-1"), str(both))
	var even := _shipped()
	even["casual_challenge_within"] = even["challenge_within"]
	assert_eq(_errors(even), [] as Array[String], "an equal band is inside the range")


## Every check's message names its key and the bad value: break each key the checks cover, one
## at a time, and each message carries a "(value)".
func test_every_check_names_its_key_and_the_bad_value() -> void:
	var cases: Array = [
		["sim_ticks_per_s", 100], ["play_clear_yd", -1.0], ["play_clear_share", -0.1],
		["cross_clear_yd", -1.0], ["cross_hold_max_s", 0], ["cart_path_max_detour", 0.5],
		["max_steps_per_frame", 0], ["frame_ticks_max", 0], ["frame_guest_ms_max", 0.0],
		["putt_tick_weight", 0.5],
		["praise_passes", 5], ["complaint_fails", 0], ["sight_step_yd", 0.0],
		["guest_putt_max_runs", 1], ["group_size_min", 0], ["day_s", 0.0], ["stroke_s", -1.0],
		["arrival_window_s", -1.0], ["arrivals_per_day", -1], ["guest_min_power", 2.0],
		["swing_impact_share", 1.0], ["swing_address_share", 0.9], ["walk_yd_per_s", 0.0],
	]
	for c: Array in cases:
		var d := _shipped()
		d[c[0]] = c[1]
		var errors := _errors(d)
		assert_eq(errors.size(), 1, "%s = %s: one error (%s)" % [c[0], c[1], errors])
		assert_true(_named(errors, "%s (%s)" % [c[0], _shown(c[1])]),
				"%s = %s: the message names the key and its value: %s" % [c[0], c[1], errors])
	# The tick pair names both keys and both values.
	var ticks := _shipped()
	ticks["sim_ticks_per_s"] = 100
	var e2 := _errors(ticks)
	assert_true(_named(e2, "sim_ticks_per_s (100)") and _named(e2, "guest_ticks_per_s (%s)"
			% int(ticks["guest_ticks_per_s"])), str(e2))


## As the messages format it: a float key's value as a float ("1.0"), an int key's as an int.
func _shown(v: Variant) -> String:
	return str(v)


func _shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(GuestTuning.PATH))


func _errors(d: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	GuestTuning.from_dict(d, errors)
	return errors


func _named(errors: Array[String], needle: String) -> bool:
	for e: String in errors:
		if e.contains(needle):
			return true
	return false
