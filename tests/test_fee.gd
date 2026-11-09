extends GutTest
## E4-S6 (D56, D58): the fee slider, the player's one pricing decision. The ceiling is $25 a star
## a round at the stars shown, and the slider cannot pass it; arrivals are full up to 70% of the
## ceiling, then fall in a straight line to two thirds at it; a falling rating that drops the
## ceiling below the fee lowers the fee. The fee is saved, and Main.green_fee() is what a guest
## pays at the first tee (E4-S4). By hand: checklist item 7.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var economy: EconomyTuning


func before_all() -> void:
	economy = EconomyTuning.load_default()


func _reaction(kind: GuestReaction.Kind, hole: int = 1) -> GuestReaction:
	var r := GuestReaction.new()
	r.hole_number = hole
	r.kind = kind
	r.text = "Hole %d: %s." % [hole, GuestReaction.KIND_NAMES[kind]]
	return r


func _push(feed: ReactionFeed, kind: GuestReaction.Kind, n: int, hole: int = 1) -> void:
	for i in n:
		feed.push(_reaction(kind, hole), 1, i, hole - 1)


func _sim() -> GuestSim:
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.set_process(false)
	sim.start(GuestCourse.course(), 7)
	return sim


func _guests(sim: GuestSim) -> int:
	var n := 0
	for g: GuestGroup in sim.brain.groups:
		n += g.guests.size()
	return n


func test_the_ceiling_is_25_dollars_a_star_at_the_stars_shown() -> void:
	assert_eq(economy.fee_ceiling_per_star, 25)
	var sim := _sim()
	assert_eq(sim.fee_ceiling(), 75, "a new course: 3 stars, $75")
	_push(sim.feed, GuestReaction.Kind.PRAISE, 13)
	assert_eq(sim.stars(), 3.5)
	assert_eq(sim.fee_ceiling(), 87, "3.5 stars: $87.50, whole dollars down")
	_push(sim.feed, GuestReaction.Kind.PRAISE, 50)
	assert_eq(sim.fee_ceiling(), 125, "5 stars: $125")


func test_a_new_course_starts_at_the_start_fee() -> void:
	var sim := _sim()
	assert_eq(sim.fee, economy.start_fee)
	assert_eq(sim.fee, roundi(0.8 * economy.fee_ceiling(3.0)),
			"$60: 80% of the 3-star ceiling, D58's best fee and the economy sim's")
	sim.set_fee(90)
	sim.start(GuestCourse.course(), 8)
	assert_eq(sim.fee, economy.start_fee, "a new course starts it again")


func test_the_fee_cannot_pass_the_ceiling_or_go_below_free() -> void:
	var sim := _sim()
	sim.set_fee(60)
	assert_eq(sim.fee, 60)
	sim.set_fee(100)
	assert_eq(sim.fee, 75, "held at the ceiling")
	sim.set_fee(-5)
	assert_eq(sim.fee, 0, "free at the least")


func test_arrivals_follow_d58s_curve() -> void:
	# 3 stars: 20 guests at full arrivals; the ceiling $75, 70% of it $52.50.
	var cases := [[0, 20], [52, 20], [60, 18], [75, 13]]
	for c: Array in cases:
		var sim := _sim()
		sim.set_fee(c[0])
		assert_eq(sim.arrivals_today(), c[1], "$%d at 3 stars" % c[0])
		sim.advance(0.0)
		assert_eq(_guests(sim), c[1], "and the morning draws them ($%d)" % c[0])
	# The curve itself: flat to 70%, then a straight line to two thirds at the ceiling.
	assert_almost_eq(economy.fee_arrivals_share(0.0), 1.0, 1e-9)
	assert_almost_eq(economy.fee_arrivals_share(0.7), 1.0, 1e-9)
	assert_almost_eq(economy.fee_arrivals_share(0.85), 1.0 - (1.0 - 0.6667) * 0.5, 1e-9, "halfway down")
	assert_almost_eq(economy.fee_arrivals_share(1.0), 0.6667, 1e-9, "a third fewer at the ceiling")


func test_a_falling_rating_lowers_the_fee_and_a_rising_one_leaves_it() -> void:
	var sim := _sim()
	sim.set_fee(75)
	watch_signals(sim)
	_push(sim.feed, GuestReaction.Kind.COMPLAINT, 25)
	assert_eq(sim.stars(), 2.0)
	assert_eq(sim.fee, 50, "the ceiling fell to $50 under the fee: the fee follows it")
	assert_signal_emitted_with_parameters(sim, "fee_changed", [50])
	_push(sim.feed, GuestReaction.Kind.PRAISE, 50)
	assert_eq(sim.fee_ceiling(), 125)
	assert_eq(sim.fee, 50, "a rising rating does not raise it back")
	sim.set_fee(40)
	_push(sim.feed, GuestReaction.Kind.COMPLAINT, 30)
	assert_eq(sim.stars(), 2.5, "20 praise and 30 complaints: 2.6")
	assert_eq(sim.fee_ceiling(), 62)
	assert_eq(sim.fee, 40, "a fee under the new ceiling stays")


func test_a_cleared_hole_can_lower_the_fee_too() -> void:
	var sim := _sim()
	_push(sim.feed, GuestReaction.Kind.PRAISE, 50, 2)
	sim.set_fee(125)
	sim.feed.clear_slot(GuestCourse.course().holes, 1)
	assert_eq(sim.stars(), 3.0, "hole 2's praise cleared: neutral")
	assert_eq(sim.fee, 75)


func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.show_course(GuestCourse.course())
	m.guest_sim.set_process(false)
	return m


func test_the_slider_sets_the_fee_and_stops_at_the_ceiling() -> void:
	var m := _main()
	var panel: FeePanel = m.fee_panel
	var slider: HSlider = panel.slider
	assert_true(slider.is_visible_in_tree(), "Build shows the slider")
	assert_eq(slider.min_value, 0.0)
	assert_eq(slider.max_value, 75.0, "the slider ends at the ceiling")
	assert_eq(slider.value, float(economy.start_fee))
	slider.value = 60
	assert_eq(m.guest_sim.fee, 60, "the slider sets the fee")
	assert_eq(m.green_fee(), 60, "and Main.green_fee is it")
	assert_eq(panel.fee_label.text, "Fee $60")
	slider.value = 200
	assert_eq(slider.value, 75.0, "the slider cannot pass the ceiling")
	assert_eq(m.green_fee(), 75)
	_push(m.guest_sim.feed, GuestReaction.Kind.COMPLAINT, 50)
	assert_eq(slider.max_value, 25.0, "1 star: the slider's end moves down")
	assert_eq(slider.value, 25.0, "and the fee with it")
	assert_eq(m.green_fee(), 25)
	assert_eq(panel.ceiling_label.text, "of $25")
	await get_tree().process_frame
	assert_true(panel in m.hud_controls(), "the free view counts it")
	assert_true(m._hud_rect(panel).position.y >= m._hud_rect(m.sim_speed_panel).end.y,
			"under the speed panel")
	m.set_mode(Main.Mode.PLAY)
	await get_tree().process_frame
	assert_false(panel.is_visible_in_tree(), "the fee is set in Build")
	assert_false(panel in m.hud_controls())
	assert_true(m._hud_rect(m.feed_panel).position.y <= m._hud_rect(m.sim_speed_panel).end.y
			+ Main.SPEED_PANEL_GAP + 0.5, "Play's feed stays right under the speed panel")


func test_the_fee_is_saved_and_loaded() -> void:
	var m := _main()
	m.guest_sim.set_fee(64)
	var s := GameSave.State.new()
	s.course = m.course
	s.feed_data = m.guest_sim.feed.to_save(1)
	m.economy_to_save(s)
	assert_eq(s.fee, 64)
	var errors: Array[String] = []
	var back := GameSave.from_json(GameSave.to_json(s), errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(back.fee, 64, "the file carries it")
	m.show_course(GuestCourse.course())
	assert_eq(m.green_fee(), economy.start_fee)
	m.economy_from_save(back)
	assert_eq(m.green_fee(), 64, "a load brings it back")


func test_a_save_without_a_fee_loads_the_start_fee() -> void:
	var m := _main()
	var s := GameSave.State.new()
	s.course = m.course
	s.feed_data = m.guest_sim.feed.to_save(1)
	var d: Dictionary = JSON.parse_string(GameSave.to_json(s))
	d.erase("fee")
	var errors: Array[String] = []
	var back := GameSave.from_json(JSON.stringify(d), errors)
	assert_eq(errors, [] as Array[String], "an E4-S7 save still loads")
	m.guest_sim.set_fee(10)
	m.economy_from_save(back)
	assert_eq(m.green_fee(), economy.start_fee)


func test_a_loaded_fee_over_the_loaded_ceiling_is_lowered() -> void:
	var m := _main()
	var s := GameSave.State.new()
	s.fee = 100
	m.economy_from_save(s)
	assert_eq(m.green_fee(), 75, "3 stars: $75 at most")
