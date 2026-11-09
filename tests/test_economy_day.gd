extends GutTest
## E4-S4: money flows in (docs/design.md Economy and time). A guest pays the green fee
## (Main.green_fee) as it arrives at the first tee; at the day's end (GuestSim.day_ended) the
## course pays upkeep_per_open_hole for each open hole; the next morning the HUD shows the day's
## income and costs (DayLedger). A save holds the balance as of the morning it resumes at, so a
## load that replays the day takes its fees once.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SAVE_PATH: String = "user://test_economy_day_save.json"
const START: int = 5000

var _econ: EconomyTuning


func before_all() -> void:
	_econ = EconomyTuning.load_default()


## Main on the guest course (three open par 3s) with START dollars, the day driven by the test.
func _main(base_seed: int = 3) -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	var c := GuestCourse.course()
	c.set_land_budget(START)
	m.land_seed = base_seed
	m.show_course(c)
	m.guest_sim.set_process(false)
	return m


func _skip(m: Main) -> void:
	m.guest_sim.skip_to_morning()
	var frames := 0
	while m.guest_sim.skipping and frames < 100000:
		m.guest_sim.skip_frame()
		frames += 1
	assert_false(m.guest_sim.skipping, "the skip reaches the morning")


## [guests arrived, the fees they paid]. E4-S6: the fee is read at each arrival, since a falling
## rating can lower it during the day.
func _arrivals(m: Main) -> Array[int]:
	var out: Array[int] = [0, 0]
	m.guest_sim.day_started.connect(func(_d: int) -> void:
		m.guest_sim.brain.guest_arrived.connect(func(_g: Guest) -> void:
			out[0] += 1
			out[1] += m.green_fee()))
	return out


func test_the_green_fee_is_the_sliders_fee() -> void:
	var m := _main()
	assert_eq(m.green_fee(), roundi(0.8 * _econ.fee_ceiling(3.0)), "E4-S6's start fee, 80% at 3 stars")
	assert_eq(m.green_fee(), 60, "D58's best fee at 3 stars")
	m.guest_sim.set_fee(45)
	assert_eq(m.green_fee(), 45, "the slider's fee (tests/test_fee.gd)")


func test_a_guest_pays_as_it_arrives_at_the_first_tee() -> void:
	var m := _main()
	var paid: Array[int] = []
	m.guest_sim.day_started.connect(func(_d: int) -> void:
		m.guest_sim.brain.guest_arrived.connect(func(_g: Guest) -> void:
			paid.append(m.build_tool.builder.balance())))
	m.guest_sim.advance(0.0)  # builds day 1
	while paid.is_empty() and m.guest_sim.day == 1:
		m.guest_sim.advance(1.0)
	assert_false(paid.is_empty(), "a guest arrives")
	# Main takes the fee in GuestSim's guest_arrived, connected to the brain before this test's.
	assert_eq(paid[0], START + m.green_fee(), "the first guest's fee is in by its arrival")
	assert_gt(m.ledger.guests, 0, "the first group in")
	assert_eq(m.ledger.fees, m.ledger.guests * m.green_fee(), "each of its guests paid")
	assert_eq(m.build_tool.builder.balance(), START + m.ledger.fees)


func test_upkeep_is_charged_once_at_the_days_end_per_open_hole() -> void:
	var m := _main()
	var arrived := _arrivals(m)
	var ended: Array[int] = []
	m.guest_sim.day_ended.connect(func(_d: int, _b: GuestBrain) -> void:
		ended.append(m.build_tool.builder.balance()))
	m.guest_sim.advance(0.0)
	_skip(m)
	assert_eq(ended.size(), 1, "one day ended")
	var upkeep: int = 3 * _econ.upkeep_per_open_hole
	assert_eq(upkeep, 15, "$5 a hole, three open (D56)")
	assert_gt(arrived[0], 0)
	assert_eq(m.build_tool.builder.balance(), START + arrived[1] - upkeep)
	assert_eq(ended[0], m.build_tool.builder.balance(), "upkeep is in by day_ended's other listeners")


func test_only_open_holes_cost_upkeep() -> void:
	var m := _main()
	assert_true(m.build_tool.builder.close_hole(3))
	var arrived := _arrivals(m)
	m.guest_sim.advance(0.0)
	_skip(m)
	assert_eq(m.build_tool.builder.balance(),
			START + arrived[1] - 2 * _econ.upkeep_per_open_hole)


func test_the_morning_shows_the_days_income_and_costs() -> void:
	var m := _main()
	var arrived := _arrivals(m)
	m.guest_sim.advance(0.0)
	assert_eq(m.money_panel.day_label.text, "", "nothing to report on day 1's morning")
	m.build_tool.builder.paint(Vector2i(10, 20), Surface.Type.BUNKER, 1)
	_skip(m)
	var fees: int = arrived[1]
	var line: String = m.money_panel.day_label.text
	assert_eq(line, "Day 1: fees +%s (%d guests), upkeep -$15, building -%s" % [
			LandPrices.money(fees), arrived[0], LandPrices.money(_econ.price_of(Surface.Type.BUNKER))])
	assert_true(m.money_panel.day_label.visible)
	assert_eq(m.ledger.last_net, fees - 15 - _econ.price_of(Surface.Type.BUNKER))


func test_a_sandbox_day_reports_but_never_moves_the_balance() -> void:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.show_course(GuestCourse.course())
	m.guest_sim.set_process(false)
	var arrived := _arrivals(m)
	m.guest_sim.advance(0.0)
	_skip(m)
	assert_true(m.build_tool.builder.has_unlimited_money())
	assert_gt(arrived[0], 0)
	assert_string_contains(m.money_panel.day_label.text, "fees +")


func test_upkeep_can_take_the_balance_below_0_and_the_day_goes_on() -> void:
	var m := _main()
	var quiet := EconomyTuning.load_default()
	quiet.arrivals_base = 0  # a day with no guests (E4-S5: arrivals by rating): upkeep and nothing in
	quiet.arrivals_per_star = 0
	m.guest_sim.economy = quiet
	m.build_tool.builder.debit(START - 10)
	m.guest_sim.advance(0.0)
	_skip(m)
	assert_eq(m.build_tool.builder.balance(), 10 - 3 * _econ.upkeep_per_open_hole)
	assert_eq(m.money_panel.balance_label.text, "Balance: -$5, building paused")
	assert_eq(m.guest_sim.day, 2, "the next morning comes")
	assert_eq(m.money_panel.day_label.text, "Day 1: no guests, upkeep -$15")


func test_a_load_replays_the_day_and_takes_its_fees_once() -> void:
	# The day run straight through.
	var a := _main()
	a.guest_sim.advance(0.0)
	_skip(a)
	var straight: int = a.build_tool.builder.balance()
	# The same day, saved part way (after some fees) and loaded, then run to its end.
	var b := _main()
	var arrived := _arrivals(b)
	b.guest_sim.advance(0.0)
	while arrived[0] < 1 and b.guest_sim.day == 1:
		b.guest_sim.advance(1.0)
	assert_gt(arrived[0], 0, "fees taken before the save")
	assert_eq(b.build_tool.builder.balance(), START + arrived[1])
	assert_eq(b.save_game(SAVE_PATH), OK)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	assert_eq(int(saved["money"]), START, "the save holds the morning's balance, before the day's fees")
	b.build_tool.builder.paint(Vector2i(10, 20), Surface.Type.BUNKER, 1)
	assert_true(b.load_game(SAVE_PATH))
	b.guest_sim.set_process(false)
	assert_eq(b.build_tool.builder.balance(), START)
	assert_eq(b.ledger.fees, 0, "the replayed day's ledger starts empty")
	b.guest_sim.advance(0.0)
	_skip(b)
	assert_eq(b.build_tool.builder.balance(), straight, "the same balance as the day run through")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func test_building_before_a_save_stays_paid_for_after_the_load() -> void:
	var m := _main()
	var arrived := _arrivals(m)
	m.guest_sim.advance(0.0)
	while arrived[0] < 1 and m.guest_sim.day == 1:
		m.guest_sim.advance(1.0)
	m.build_tool.builder.paint(Vector2i(10, 20), Surface.Type.GREEN, 1)
	var spent: int = _econ.price_of(Surface.Type.GREEN)
	assert_eq(m.save_game(SAVE_PATH), OK)
	assert_true(m.load_game(SAVE_PATH))
	assert_eq(m.build_tool.builder.balance(), START - spent,
			"the morning's balance less what was built since; the fee comes again as the day replays")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
