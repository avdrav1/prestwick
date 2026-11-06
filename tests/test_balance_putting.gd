extends GutTest
## E3-S51: /balance putting (scripts/putting_sim.gd, PuttingSim.measure; scripts/sim.gd
## --table putting). A human-like putter (a skill-7 guest's D40 putt click error, the aim
## marker's pace and line) holes out from 1, 3 and 8 yd on a flat green and on a one-step
## contour; docs/design.md Balance targets, putting, sets the made and three-putt bands.

const SEED: int = 1
const RUNS: int = 200

var rows: Array[Dictionary]


func before_all() -> void:
	rows = PuttingSim.new().measure(RUNS, SEED)


func _named(name: String) -> Dictionary:
	for r in rows:
		if r.name == name:
			return r
	return {}


func test_every_putting_target_is_hit_at_200_runs() -> void:
	assert_eq(rows.size(), 8, "made from 1, 3 and 8 yd and three-putts from 8, on two greens")
	for r in rows:
		gut.p("%s %.3f %s" % [r.name, r.measured, r.note])
		assert_true(r.ok, "%s: %.3f against %s" % [r.name, r.measured, r.target])


func test_the_bands_are_the_design_targets() -> void:
	assert_eq(PuttingSim.MADE[1.0], Vector2(0.90, 1.0))
	assert_eq(PuttingSim.MADE[3.0], Vector2(0.55, 0.75))
	assert_eq(PuttingSim.MADE[8.0], Vector2(0.15, 0.35))
	assert_eq(PuttingSim.THREE_PUTT_MAX, Vector2(0.0, 0.20))
	var guests := GuestTuning.load_default()
	var sim := PuttingSim.new()
	assert_almost_eq(sim.power_sigma, guests.putt_power_sigma(PuttingSim.HUMAN_SKILL), 1e-9,
			"the click error is a skill-7 guest's (D40)")
	assert_almost_eq(sim.aim_sigma, guests.putt_aim_sigma(PuttingSim.HUMAN_SKILL), 1e-9)


func test_shorter_putts_drop_more_often_on_both_greens() -> void:
	for green: String in ["flat green", "one-step contour"]:
		var one: float = _named("%s: made from 1 yd" % green).measured
		var three: float = _named("%s: made from 3 yd" % green).measured
		var eight: float = _named("%s: made from 8 yd" % green).measured
		assert_gt(one, three, green)
		assert_gt(three, eight, green)


func test_the_noise_free_plan_holes_every_start() -> void:
	# The plan the putter clicks round must itself drop, so a miss is the click's alone.
	for r in rows:
		assert_string_contains(r.note, "noise-free plan holes 8 of 8", false)


func test_a_click_with_no_error_holes_from_every_start() -> void:
	var sim := PuttingSim.new(null, null, null, 0.0, 0.0)
	var r := sim.hole_outs(ShortGameHoles.sloped_green(), 3.0, PuttingSim.DIRECTIONS, SEED)
	assert_eq(r.one, 1.0, "no click error: every 3 yd putt on the contour drops")
