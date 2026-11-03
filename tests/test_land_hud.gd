extends GutTest
## E6-S5: Build shows land and buys parcels. The land budget is always on the Build HUD;
## hovering a parcel shows its price and whether it can be bought; the Buy land tool buys
## only after a confirm; a tool over unowned land says so before the click, and a refused
## click shows the builder's reason. The pictures are checked by hand
## (tests/fixtures/land_buy_shot.tscn).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## The starting block of the 8 x 8 parcel map (D26).
const BLOCK: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)]
## A parcel west of the block (buyable) and one in the far corner (out of reach).
const BUYABLE := Vector2i(2, 3)
const FAR := Vector2i(0, 0)

var _main: Main
var _tool: BuildTool
var _panel: LandPanel


func before_each() -> void:
	_main = MAIN_SCENE.instantiate() as Main
	_main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(_main)
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), Vector2i(p, q) in BLOCK)
	c.set_land_budget(5000)
	_main.show_course(c)
	_tool = _main.build_tool
	_panel = _main.land_panel


func _at(cell: Vector2i) -> Vector2:
	return Iso.tile_to_screen(Vector2(cell), _main.course.get_height(cell.x, cell.y))


func _tile_in(parcel: Vector2i) -> Vector2i:
	return parcel * CourseData.PARCEL_TILES + Vector2i(8, 8)


func _price(parcel: Vector2i) -> int:
	return _tool.builder.parcel_price(parcel)


func test_budget_is_always_on_the_build_hud() -> void:
	assert_true(_panel.visible)
	assert_eq(_panel.budget_label.text, "Land budget: $5,000")
	_main.toggle_mode()
	assert_false(_panel.visible, "Build HUD only")
	_main.toggle_mode()
	_main.new_sandbox()
	assert_eq(_panel.budget_label.text, "Land budget: unlimited")


func test_hover_shows_price_and_whether_it_can_be_bought() -> void:
	_tool.hover_at(_at(_tile_in(BUYABLE)))
	assert_eq(_panel.parcel_label.text, "Parcel 2, 3: %s, for sale (Buy land)" % LandPrices.money(_price(BUYABLE)))
	_tool.select_tool(BuildTool.Tool.BUY)
	assert_eq(_panel.parcel_label.text, "Parcel 2, 3: %s, click to buy" % LandPrices.money(_price(BUYABLE)))
	_tool.hover_at(_at(_tile_in(FAR)))
	assert_eq(_panel.parcel_label.text, "Parcel 0, 0: %s, can't buy: not next to your land" % LandPrices.money(_price(FAR)))
	_tool.hover_at(_at(_tile_in(BLOCK[0])))
	assert_eq(_panel.parcel_label.text, "Parcel 3, 3: yours")


func test_buy_waits_for_the_confirm() -> void:
	_tool.select_tool(BuildTool.Tool.BUY)
	var cost: int = _price(BUYABLE)
	_tool.press_at(_at(_tile_in(BUYABLE)))
	_tool.release()
	assert_false(_main.course.is_parcel_owned(BUYABLE), "a click alone buys nothing")
	assert_true(_panel.confirm_box.visible)
	assert_eq(_panel.pending_parcel, BUYABLE)
	assert_string_contains(_panel.confirm_label.text, "for %s?" % LandPrices.money(cost))
	_panel.confirm_button.pressed.emit()
	assert_true(_main.course.is_parcel_owned(BUYABLE))
	assert_eq(_main.course.land_budget, 5000 - cost)
	assert_eq(_panel.budget_label.text, "Land budget: %s" % LandPrices.money(5000 - cost))
	assert_false(_panel.confirm_box.visible)
	var cell: Vector2i = _tile_in(BUYABLE)
	assert_eq(_main.course_view.land_layer(2).get_cell_source_id(cell), -1, "bought land draws as owned")


func test_cancel_buys_nothing() -> void:
	_tool.select_tool(BuildTool.Tool.BUY)
	_tool.press_at(_at(_tile_in(BUYABLE)))
	_tool.release()
	_panel.cancel_button.pressed.emit()
	assert_false(_main.course.is_parcel_owned(BUYABLE))
	assert_eq(_main.course.land_budget, 5000)
	assert_false(_panel.confirm_box.visible)


# E6-S5 review: the cursor crosses other parcels on its way to the confirm, so the map and
# the parcel line must keep naming the parcel waiting to be bought, not the hovered one.
func test_pending_parcel_stays_marked_while_the_cursor_moves() -> void:
	_tool.select_tool(BuildTool.Tool.BUY)
	_tool.press_at(_at(_tile_in(BUYABLE)))
	_tool.release()
	assert_eq(_tool.pinned_parcel, BUYABLE, "the map outlines the parcel waiting on the confirm")
	var other := Vector2i(3, 2)
	_tool.hover_at(_at(_tile_in(other)))
	assert_eq(_tool.hover_parcel(), other)
	assert_eq(_tool.pinned_parcel, BUYABLE, "still, with the cursor over another parcel")
	assert_eq(_panel.parcel_label.text, "Parcel 2, 3: %s, click to buy" % LandPrices.money(_price(BUYABLE)))
	_panel.cancel_button.pressed.emit()
	assert_eq(_tool.pinned_parcel, TilePicker.NONE, "cancel unpins it")
	assert_string_contains(_panel.parcel_label.text, "Parcel 3, 2:")
	_tool.press_at(_at(_tile_in(BUYABLE)))
	_tool.release()
	_panel.confirm_button.pressed.emit()
	assert_eq(_tool.pinned_parcel, TilePicker.NONE, "buying unpins it")
	_tool.press_at(_at(_tile_in(other)))
	_tool.release()
	_tool.select_tool(BuildTool.Tool.PAINT)
	assert_eq(_tool.pinned_parcel, TilePicker.NONE, "leaving Buy land unpins it")


func test_out_of_reach_click_says_why_without_a_confirm() -> void:
	_tool.select_tool(BuildTool.Tool.BUY)
	_tool.press_at(_at(_tile_in(FAR)))
	_tool.release()
	assert_false(_panel.confirm_box.visible)
	assert_true(_panel.message_label.visible)
	assert_eq(_panel.message_label.text, "Can't: not next to your land")


func test_tool_over_unowned_land_says_so_before_the_click() -> void:
	_tool.hover_at(_at(_tile_in(BUYABLE)))
	assert_eq(_tool.hover_hint(), CourseBuilder.NOT_YOUR_LAND)
	assert_true(_panel.hint_label.visible)
	assert_eq(_panel.hint_label.text, "Paint: not your land")
	_tool.select_tool(BuildTool.Tool.CUP)
	assert_eq(_panel.hint_label.text, "Cup: not your land")
	_tool.hover_at(_at(_tile_in(BLOCK[0])))
	assert_false(_panel.hint_label.visible, "owned land: no hint")


func test_brush_straddling_the_line_is_not_refused() -> void:
	_tool.brush_size = 3
	_tool.hover_at(_at(Vector2i(47, 60)))
	assert_eq(_tool.hover_hint(), "", "one column of the brush is owned")


func test_refused_click_shows_the_reason() -> void:
	_tool.select_tool(BuildTool.Tool.RAISE)
	var cell: Vector2i = _tile_in(BUYABLE)
	var before: String = _main.course.content_hash()
	_tool.press_at(_at(cell))
	_tool.release()
	assert_eq(_main.course.content_hash(), before, "nothing changed")
	assert_true(_panel.message_label.visible)
	assert_eq(_panel.message_label.text, "Can't: not your land")
	_panel._process(BuilderTuning.load_default().refusal_show_s + 0.1)
	assert_false(_panel.message_label.visible, "the message goes after refusal_show_s")


func test_undo_gives_the_parcel_back_on_the_hud() -> void:
	_tool.select_tool(BuildTool.Tool.BUY)
	_panel.ask_buy(BUYABLE)
	assert_true(_panel.confirm_buy())
	assert_true(_tool.undo())
	assert_false(_main.course.is_parcel_owned(BUYABLE))
	assert_eq(_panel.budget_label.text, "Land budget: $5,000")
	assert_eq(_main.course_view.land_layer(2).get_cell_source_id(_tile_in(BUYABLE)), CourseView.LAND_SOURCE)


func test_palette_has_buy_land() -> void:
	_main.build_palette.buy_button.pressed.emit()
	assert_eq(_tool.tool, BuildTool.Tool.BUY)
	assert_true(_main.build_palette.buy_button.button_pressed)
