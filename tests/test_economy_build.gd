extends GutTest
## E4-S2: building is charged to the one balance (D56, D57; docs/design.md Economy and time).
## Painting pays the new surface's tile_price per tile changed, raising and lowering
## height_step_price per tile moved; a surface over itself, tees, cups, pars and opening are
## free. Repainting refunds nothing; undo gives back exactly what its step charged. An edit
## costing more than the balance is refused whole; a balance below 0 pauses building and
## nothing else. New sandbox charges nothing. The balance shows on the HUD in Build and Play,
## a save carries it, and /course-file inspect prints the build cost.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## The starting block of the 8 x 8 parcel map (D67: 4 x 4, parcels 2 to 5).
const BLOCK: Rect2i = Rect2i(2, 2, 4, 4)
## A parcel next to the block, and a tile inside the block.
const NEXT_PARCEL := Vector2i(1, 3)
const AT := Vector2i(60, 60)
const SAVE_PATH: String = "user://test_economy_build_save.json"

var _refusals: Array[String] = []
var _econ: EconomyTuning


func before_all() -> void:
	_econ = EconomyTuning.load_default()


func before_each() -> void:
	_refusals.clear()


## The 128 x 128 map, flat rough at height 2, owning only the starting block, with `money`.
func _land_course(money: int = 5000) -> CourseData:
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), BLOCK.has_point(Vector2i(p, q)))
	c.set_land_budget(money)
	return c


func _builder(c: CourseData) -> CourseBuilder:
	var b := CourseBuilder.new(c)
	b.refused.connect(func(reason: String) -> void: _refusals.append(reason))
	return b


# --- the rates ---

func test_the_rates_are_d56s_from_data() -> void:
	assert_eq(_econ.price_of(Surface.Type.FAIRWAY), 4)
	assert_eq(_econ.price_of(Surface.Type.GREEN), 20, "D56 at the money scale 0.78 (D67; 0.63 at E4-S8)")
	assert_eq(_econ.height_step_price, 8)
	assert_eq(LandPrices.load_default().land_budget, 5000, "the one starting balance (D57)")


func test_a_new_course_starts_with_the_one_balance_and_parcels_come_out_of_it() -> void:
	var c := CourseBuilder.new_course(7)
	var b := _builder(c)
	assert_eq(b.balance(), 5000)
	var price: int = b.parcel_price(NEXT_PARCEL)
	assert_true(b.buy_parcel(NEXT_PARCEL))
	assert_true(b.paint(AT, Surface.Type.GREEN, 1))
	assert_eq(b.balance(), 5000 - price - _econ.price_of(Surface.Type.GREEN),
			"land and building come out of the same balance")


# --- charges ---

func test_painting_charges_the_new_surface_per_tile_changed() -> void:
	var c := _land_course()
	var b := _builder(c)
	assert_eq(b.paint_cost(AT, Surface.Type.FAIRWAY, 3), 9 * _econ.price_of(Surface.Type.FAIRWAY))
	assert_true(b.paint(AT, Surface.Type.FAIRWAY, 3))
	assert_eq(b.balance(), 5000 - 9 * _econ.price_of(Surface.Type.FAIRWAY))
	# A 5 x 5 brush over the 3 x 3: only the 16 new tiles are charged.
	assert_eq(b.paint_cost(AT, Surface.Type.FAIRWAY, 5), 16 * _econ.price_of(Surface.Type.FAIRWAY))
	assert_true(b.paint(AT, Surface.Type.FAIRWAY, 5))
	assert_eq(b.balance(), 5000 - 25 * _econ.price_of(Surface.Type.FAIRWAY))


func test_painting_a_surface_over_itself_costs_nothing() -> void:
	var c := _land_course()
	var b := _builder(c)
	assert_eq(b.paint_cost(AT, Surface.Type.ROUGH, 5), 0)
	assert_false(b.paint(AT, Surface.Type.ROUGH, 5), "nothing changes")
	assert_eq(b.balance(), 5000)
	assert_false(b.can_undo())


func test_raising_and_lowering_charge_a_step_per_tile_moved() -> void:
	var c := _land_course()
	var b := _builder(c)
	assert_true(b.raise(AT, 3))
	assert_eq(b.balance(), 5000 - 9 * _econ.height_step_price)
	assert_true(b.lower(AT, 1))
	assert_eq(b.balance(), 5000 - 10 * _econ.height_step_price, "lowering costs as raising does")
	# A drag moves each tile once, so it pays once per tile.
	b.begin_stroke()
	for i: int in 5:
		b.raise(AT + Vector2i(10, 0), 1)
	b.end_stroke()
	assert_eq(b.balance(), 5000 - 11 * _econ.height_step_price)


func test_ground_at_the_clamp_costs_nothing() -> void:
	var c := _land_course()
	c.set_tile(AT.x, AT.y, 0, Surface.Type.ROUGH)
	var b := _builder(c)
	b.lower(AT + Vector2i(0, 0), 1)
	assert_eq(b.lift_cost(AT, 1, -1), 0, "height 0 cannot go lower")
	assert_eq(b.balance(), 5000)


func test_tees_cups_pars_and_opening_are_free() -> void:
	var c := _land_course(1000000)
	var b := _builder(c)
	# A par 3 that passes: tee box, fairway, green.
	for x: int in range(50, 80):
		for y: int in range(58, 63):
			b.paint(Vector2i(x, y), Surface.Type.FAIRWAY, 1)
	for x: int in range(50, 53):
		b.paint(Vector2i(x, 60), Surface.Type.TEE, 1)
	for x: int in range(74, 79):
		for y: int in range(58, 63):
			b.paint(Vector2i(x, y), Surface.Type.GREEN, 1)
	var before: int = b.balance()
	assert_true(b.place_tee(1, Vector2i(51, 60), 3))
	assert_true(b.place_cup(1, Vector2i(76, 60)))
	assert_true(b.set_par(1, 4))
	assert_true(b.set_par(1, 3))
	if b.can_open(1):
		assert_true(b.open_hole(1))
	assert_eq(b.balance(), before, "no charge for a tee, a cup, a par or opening")


# --- refunds ---

func test_repainting_refunds_nothing_for_the_old_surface() -> void:
	var c := _land_course()
	var b := _builder(c)
	b.paint(AT, Surface.Type.GREEN, 1)
	b.paint(AT, Surface.Type.FAIRWAY, 1)
	assert_eq(b.balance(), 5000 - _econ.price_of(Surface.Type.GREEN) - _econ.price_of(Surface.Type.FAIRWAY))


func test_undo_refunds_exactly_what_its_step_charged() -> void:
	var c := _land_course()
	var b := _builder(c)
	b.paint(AT, Surface.Type.GREEN, 3)
	var after_green: int = b.balance()
	b.paint(AT, Surface.Type.FAIRWAY, 1)
	assert_true(b.undo())
	assert_eq(b.balance(), after_green, "the fairway's charge back, not the green's")
	assert_true(b.undo())
	assert_eq(b.balance(), 5000)


func test_undoing_a_drag_refunds_the_whole_drag() -> void:
	var c := _land_course()
	var b := _builder(c)
	b.begin_stroke()
	for x: int in range(50, 60):
		b.paint(Vector2i(x, 60), Surface.Type.BUNKER, 1)
		b.raise(Vector2i(x, 70), 1)
	b.end_stroke()
	assert_eq(b.balance(), 5000 - 10 * _econ.price_of(Surface.Type.BUNKER) - 10 * _econ.height_step_price)
	assert_true(b.undo())
	assert_eq(b.balance(), 5000)


func test_undo_refunds_the_charge_whatever_the_balance_did_since() -> void:
	var c := _land_course()
	var b := _builder(c)
	b.level_water = false  # D66: water as a plain paint here, not a flood
	var price: int = b.parcel_price(NEXT_PARCEL)
	assert_true(b.buy_parcel(NEXT_PARCEL))
	b.paint(AT, Surface.Type.WATER, 1)
	b.credit(200)  # a green fee in between (E4-S4)
	b.debit(50)  # and upkeep
	assert_true(b.undo())
	assert_eq(b.balance(), 5000 - price + 150, "the water's price back, the fee and upkeep kept")
	assert_true(b.undo())
	assert_eq(b.balance(), 5000 + 150, "the parcel's price back (D27)")


# --- short of money ---

func test_an_edit_costing_more_than_the_balance_is_refused_whole() -> void:
	var c := _land_course(100)
	var b := _builder(c)
	var before := c.content_hash()
	assert_false(b.paint(AT, Surface.Type.GREEN, 3), "9 green tiles cost more than $100")
	assert_eq(c.content_hash(), before, "no tile painted")
	assert_eq(b.balance(), 100)
	assert_false(b.can_undo())
	assert_eq(_refusals, ["costs %s, you have $100" % LandPrices.money(9 * _econ.price_of(Surface.Type.GREEN))] as Array[String])
	assert_true(b.paint(AT, Surface.Type.GREEN, 1), "one tile it can pay for")
	assert_eq(b.balance(), 100 - _econ.price_of(Surface.Type.GREEN))


func test_a_drag_stops_charging_where_the_money_runs_out() -> void:
	var c := _land_course(10 * _econ.price_of(Surface.Type.WATER) + 5)
	var b := _builder(c)
	b.level_water = false  # D66: water as a plain paint here, not a flood
	b.begin_stroke()
	for x: int in range(50, 70):
		b.paint(Vector2i(x, 60), Surface.Type.WATER, 1)
	b.end_stroke()
	assert_eq(b.balance(), 5, "ten tiles painted, the rest refused")
	assert_eq(c.get_surface(59, 60), Surface.Type.WATER)
	assert_eq(c.get_surface(60, 60), Surface.Type.ROUGH)
	assert_true(b.undo())
	assert_eq(b.balance(), 10 * _econ.price_of(Surface.Type.WATER) + 5)


func test_a_negative_balance_pauses_building_and_nothing_else() -> void:
	var c := _land_course()
	var b := _builder(c)
	b.paint(AT, Surface.Type.TEE, 1)
	b.debit(5000)
	var owing: int = 5000 - _econ.price_of(Surface.Type.TEE) - 5000
	assert_eq(b.balance(), owing, "upkeep may take it below 0")
	assert_false(b.paint(AT + Vector2i(3, 0), Surface.Type.FAIRWAY, 1))
	assert_false(b.raise(AT + Vector2i(3, 0), 1))
	assert_eq(_refusals[0], "building is paused: the balance is %s" % LandPrices.money(owing))
	assert_ne(b.buy_refusal(NEXT_PARCEL), "", "no land either")
	assert_false(b.buy_parcel(NEXT_PARCEL))
	assert_false(b.paint(AT, Surface.Type.TEE, 1), "a surface over itself changes nothing")
	assert_true(b.place_tee(1, AT), "free placements still work")
	assert_true(b.place_cup(1, AT + Vector2i(15, 0)))
	assert_true(b.undo(), "undo still works")
	assert_true(b.undo())
	assert_true(b.undo(), "and gives the tee's price back")
	assert_eq(b.balance(), owing + _econ.price_of(Surface.Type.TEE))
	b.credit(1000)
	assert_true(b.paint(AT, Surface.Type.FAIRWAY, 1), "money in again, building again")


func test_a_negative_balance_never_ends_the_game() -> void:
	var m := MAIN_SCENE.instantiate() as Main
	m.start_seed = 7
	add_child_autofree(m)
	m.build_tool.builder.debit(9000)
	assert_eq(m.money_panel.balance_label.text, "Balance: -$4,000, building paused")
	m.set_mode(Main.Mode.PLAY)
	assert_eq(m.mode, Main.Mode.PLAY, "Play still starts")
	assert_true(m.guest_sim.running, "the day still runs")
	var day: int = m.guest_sim.day
	m.guest_sim.advance(1.0)
	assert_true(m.guest_sim.day >= day)
	m.set_mode(Main.Mode.BUILD)
	assert_eq(m.mode, Main.Mode.BUILD)


# --- sandbox ---

func test_new_sandbox_charges_nothing() -> void:
	var c := CourseBuilder.new_sandbox()
	var b := _builder(c)
	b.level_water = false  # D66: water as a plain paint here, not a flood
	assert_true(b.has_unlimited_money())
	assert_eq(b.paint_cost(AT, Surface.Type.WATER, 5), 0)
	assert_true(b.paint(AT, Surface.Type.WATER, 5))
	assert_true(b.raise(AT, 5))
	assert_true(b.has_unlimited_money(), "still unlimited")
	assert_eq(b.balance(), CourseData.UNLIMITED_BUDGET)
	assert_true(_refusals.is_empty())
	b.credit(100)
	b.debit(100)
	assert_true(b.has_unlimited_money(), "fees and upkeep leave it unlimited")
	assert_true(b.undo())
	assert_true(b.has_unlimited_money())


# --- the HUD ---

func test_the_balance_is_on_the_hud_in_build_and_play() -> void:
	var m := MAIN_SCENE.instantiate() as Main
	m.start_seed = 7
	add_child_autofree(m)
	await wait_process_frames(2)
	assert_true(m.money_panel.visible)
	assert_eq(m.money_panel.balance_label.text, "Balance: $5,000")
	m.build_tool.builder.paint(AT, Surface.Type.GREEN, 1)
	assert_eq(m.money_panel.balance_label.text, "Balance: %s" % LandPrices.money(5000 - _econ.price_of(Surface.Type.GREEN)))
	for c: Control in [m.mode_button, m.new_course_button, m.new_sandbox_button, m.land_panel, m.sim_speed_panel]:
		if c.visible:
			assert_false(c.get_global_rect().intersects(m.money_panel.get_global_rect()),
					"the balance clears %s in Build" % c.name)
	m.set_mode(Main.Mode.PLAY)
	await wait_process_frames(2)
	assert_true(m.money_panel.visible, "and in Play")
	for c: Control in [m.mode_button, m.sim_speed_panel, m.feed_panel]:
		assert_false(c.get_global_rect().intersects(m.money_panel.get_global_rect()),
				"the balance clears %s in Play" % c.name)
	assert_false(m.sim_speed_panel.get_global_rect().intersects(m.feed_panel.get_global_rect()),
			"the feed moved down under the speed panel")
	m.set_mode(Main.Mode.BUILD)
	m.new_sandbox()
	assert_eq(m.money_panel.balance_label.text, "Balance: unlimited")


# --- the save ---

func test_a_save_carries_the_balance() -> void:
	var m := MAIN_SCENE.instantiate() as Main
	m.start_seed = 7
	add_child_autofree(m)
	m.build_tool.builder.paint(AT, Surface.Type.GREEN, 1)
	var balance: int = m.build_tool.builder.balance()
	assert_eq(m.save_game(SAVE_PATH), OK)
	m.build_tool.builder.paint(AT + Vector2i(2, 0), Surface.Type.WATER, 3)
	assert_true(m.load_game(SAVE_PATH))
	assert_eq(m.build_tool.builder.balance(), balance)
	assert_eq(m.money_panel.balance_label.text, "Balance: %s" % LandPrices.money(balance))
	m.new_sandbox()
	assert_eq(m.save_game(SAVE_PATH), OK)
	m.new_course(7)
	assert_true(m.load_game(SAVE_PATH))
	assert_true(m.build_tool.builder.has_unlimited_money(), "unlimited comes back unlimited")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func test_a_save_restores_a_negative_balance() -> void:
	var m := MAIN_SCENE.instantiate() as Main
	m.start_seed = 7
	add_child_autofree(m)
	m.build_tool.builder.debit(5300)
	assert_eq(m.save_game(SAVE_PATH), OK)
	m.new_course(7)
	assert_true(m.load_game(SAVE_PATH))
	assert_eq(m.build_tool.builder.balance(), -300)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# --- /course-file inspect ---

func test_inspect_prints_the_build_cost() -> void:
	var path := "user://test_economy_build_inspect.json"
	var c := CourseGenerator.generate(3, false, false)
	assert_eq(CourseSave.save_file(c, path), OK)
	var expected: int = 0
	for y: int in c.height:
		for x: int in c.width:
			var s: int = c.get_surface(x, y)
			if s != Surface.Type.ROUGH:
				expected += _econ.price_of(s)
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["inspect", path]), out), 0, "\n".join(out))
	var text := "\n".join(out)
	assert_string_contains(text, "build cost: %s to paint every tile not rough" % LandPrices.money(expected))
	assert_string_contains(text, "  green: ")
	assert_between(expected, 800, 1600, "a basic par 3 in the design doc's band times the money scale 0.78 (D56, D67)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
