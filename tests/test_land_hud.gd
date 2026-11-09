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


## E4-S2: the land budget line became the balance, shown in Build and Play (MoneyPanel).
func test_budget_is_always_on_the_hud() -> void:
	assert_true(_panel.visible)
	assert_eq(_main.money_panel.balance_label.text, "Balance: $5,000")
	_main.toggle_mode()
	assert_false(_panel.visible, "the land panel is Build's")
	assert_true(_main.money_panel.visible, "the balance shows in Play too")
	_main.toggle_mode()
	_main.new_sandbox()
	assert_eq(_main.money_panel.balance_label.text, "Balance: unlimited")


func test_hover_shows_price_and_whether_it_can_be_bought() -> void:
	_tool.hover_at(_at(_tile_in(BUYABLE)))
	assert_eq(_panel.parcel_label.text, "NW parcel, 130 yd out: %s, for sale (Buy land)" % LandPrices.money(_price(BUYABLE)))
	_tool.select_tool(BuildTool.Tool.BUY)
	assert_eq(_panel.parcel_label.text, "NW parcel, 130 yd out: %s, click to buy" % LandPrices.money(_price(BUYABLE)))
	_tool.hover_at(_at(_tile_in(FAR)))
	assert_eq(_panel.parcel_label.text, "N parcel, 400 yd out: %s, can't buy: not next to your land" % LandPrices.money(_price(FAR)))
	_tool.hover_at(_at(_tile_in(BLOCK[0])))
	assert_eq(_panel.parcel_label.text, "N parcel, 60 yd out: yours")


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
	assert_eq(_main.money_panel.balance_label.text, "Balance: %s" % LandPrices.money(5000 - cost))
	assert_false(_panel.confirm_box.visible)
	var cell: Vector2i = _tile_in(BUYABLE)
	assert_true((_main.course_view.chunk_at(cell).parts[cell][4] as PackedVector2Array).is_empty(),
			"bought land draws as owned: no hatch")


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
	assert_eq(_panel.parcel_label.text, "NW parcel, 130 yd out: %s, click to buy" % LandPrices.money(_price(BUYABLE)))
	_panel.cancel_button.pressed.emit()
	assert_eq(_tool.pinned_parcel, TilePicker.NONE, "cancel unpins it")
	assert_string_contains(_panel.parcel_label.text, "NE parcel, 130 yd out:")
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
	assert_eq(_main.money_panel.balance_label.text, "Balance: $5,000")
	var cell: Vector2i = _tile_in(BUYABLE)
	assert_false((_main.course_view.chunk_at(cell).parts[cell][4] as PackedVector2Array).is_empty(), "hatched again")


func test_palette_has_buy_land() -> void:
	_main.build_palette.buy_button.pressed.emit()
	assert_eq(_tool.tool, BuildTool.Tool.BUY)
	assert_true(_main.build_palette.buy_button.button_pressed)


# E6-S17: a drag across the land line makes the builder refuse every unowned dab; the HUD
# says so once per drag, and again on the next drag.
func test_one_message_per_drag() -> void:
	_tool.select_tool(BuildTool.Tool.RAISE)
	var shown: int = _panel.messages_shown
	var start: Vector2i = _tile_in(BUYABLE)
	_tool.press_at(_at(start))
	for i: int in range(1, 6):
		_tool.drag_to(_at(start + Vector2i(0, i)))
	_tool.release()
	assert_eq(_panel.messages_shown, shown + 1, "one message for the whole drag")
	assert_eq(_panel.message_label.text, "Can't: not your land")
	_tool.press_at(_at(start))
	_tool.drag_to(_at(start + Vector2i(1, 0)))
	_tool.release()
	assert_eq(_panel.messages_shown, shown + 2, "the next drag says it again")


func _key(physical: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = physical
	e.keycode = physical
	e.pressed = true
	return e


func _click_buyable() -> void:
	_tool.select_tool(BuildTool.Tool.BUY)
	_tool.press_at(_at(_tile_in(BUYABLE)))
	_tool.release()


func test_enter_confirms_a_pending_purchase() -> void:
	_click_buyable()
	var cost: int = _price(BUYABLE)
	_panel._unhandled_input(_key(KEY_ENTER))
	assert_true(_main.course.is_parcel_owned(BUYABLE))
	assert_eq(_main.course.land_budget, 5000 - cost)
	assert_false(_panel.confirm_box.visible)
	_tool.press_at(_at(_tile_in(Vector2i(3, 2))))
	_tool.release()
	_panel._unhandled_input(_key(KEY_KP_ENTER))
	assert_true(_main.course.is_parcel_owned(Vector2i(3, 2)), "keypad Enter too")


func test_esc_cancels_a_pending_purchase() -> void:
	_click_buyable()
	_panel._unhandled_input(_key(KEY_ESCAPE))
	assert_false(_main.course.is_parcel_owned(BUYABLE))
	assert_eq(_main.course.land_budget, 5000)
	assert_false(_panel.confirm_box.visible)
	assert_eq(_tool.pinned_parcel, TilePicker.NONE)
	_panel._unhandled_input(_key(KEY_ENTER))
	assert_false(_main.course.is_parcel_owned(BUYABLE), "Enter with nothing pending buys nothing")


func test_owned_parcel_under_buy_land_draws_neutral() -> void:
	_tool.select_tool(BuildTool.Tool.BUY)
	_tool.hover_at(_at(_tile_in(BLOCK[0])))
	assert_eq(_tool.parcel_outline_color(), _tool.outline_color, "the starting block")
	_tool.hover_at(_at(_tile_in(FAR)))
	assert_eq(_tool.parcel_outline_color(), _tool.refuse_color, "out of reach")
	_tool.hover_at(_at(_tile_in(BUYABLE)))
	assert_eq(_tool.parcel_outline_color(), _tool.buy_color, "buyable")
	_tool.press_at(_at(_tile_in(BUYABLE)))
	_tool.release()
	_panel.confirm_buy()
	assert_eq(_tool.parcel_outline_color(), _tool.outline_color, "just bought, still hovered: not red")


func test_parcels_are_named_by_compass_not_grid() -> void:
	var c: CourseData = _main.course
	assert_eq(LandPanel.parcel_name(c, BUYABLE), "NW parcel, 130 yd out")
	assert_eq(LandPanel.parcel_name(c, Vector2i(3, 3)), "N parcel, 60 yd out")
	var names: Dictionary = {}
	for p: Vector2i in [Vector2i(2, 3), Vector2i(2, 4), Vector2i(5, 3), Vector2i(5, 4),
			Vector2i(3, 2), Vector2i(4, 2), Vector2i(3, 5), Vector2i(4, 5)]:
		names[LandPanel.parcel_name(c, p)] = p
	assert_eq(names.size(), 8, "every parcel the block can buy has its own name: %s" % [names.keys()])
	_tool.select_tool(BuildTool.Tool.BUY)
	_tool.hover_at(_at(_tile_in(BUYABLE)))
	assert_eq(_panel.parcel_label.text, "NW parcel, 130 yd out: %s, click to buy" % LandPrices.money(_price(BUYABLE)))


func test_confirm_sits_by_the_clicked_parcel() -> void:
	var clicked: Vector2i = _tile_in(BUYABLE)
	_main.camera.tracking = false
	_main.camera.position = _at(clicked)
	_main.camera.force_update_scroll()
	_click_buyable()
	var text: String = _panel.confirm_label.text
	assert_string_contains(text, "Buy the NW parcel, 130 yd out, for %s?" % LandPrices.money(_price(BUYABLE)))
	assert_false(text.contains("2, 3"), "no grid coordinates")
	assert_eq(_panel.pending_tile, clicked)
	var anchor: Vector2 = _panel.confirm_anchor(clicked)
	var view: Rect2 = _panel.get_viewport_rect()
	assert_true(view.has_point(anchor), "the parcel is on screen: %s" % anchor)
	var box: Rect2 = _panel.confirm_box.get_global_rect()
	assert_true(box.grow(_panel.confirm_gap + 1.0).has_point(anchor),
			"the confirm touches the clicked tile: box %s, tile %s" % [box, anchor])
	assert_true(view.encloses(box), "and stays on screen")
	var far_from_panel: bool = box.position.distance_to(_panel.get_global_rect().position) > 100.0
	assert_true(far_from_panel, "not up in the land panel")


# E6-S17 review: names stay unique beyond the block. Mirror parcels a few out share a point and
# a distance; they are told apart by the point each leans toward.
func test_every_parcel_on_the_map_has_its_own_name() -> void:
	var c: CourseData = _main.course
	assert_eq(LandPanel.parcel_name(c, Vector2i(3, 0)), "ENE parcel, 280 yd out, toward NE")
	assert_eq(LandPanel.parcel_name(c, Vector2i(4, 0)), "ENE parcel, 280 yd out, toward E")
	assert_eq(LandPanel.parcel_name(c, BUYABLE), "NW parcel, 130 yd out", "no suffix when alone")
	for size: Vector2i in [Vector2i(128, 128), Vector2i(96, 96), Vector2i(160, 160),
			Vector2i(256, 256), Vector2i(200, 120), Vector2i(100, 100)]:
		var m := CourseData.create(size.x, size.y, Surface.Type.ROUGH, 2)
		var names: Dictionary = {}
		for q: int in m.parcels_high:
			for p: int in m.parcels_wide:
				var name: String = LandPanel.parcel_name(m, Vector2i(p, q))
				assert_false(names.has(name), "%s: %s and %s are both \"%s\"" % [size,
						names.get(name), Vector2i(p, q), name])
				names[name] = Vector2i(p, q)


# E6-S17 review: a click on a tile under the HUD puts the confirm clear of it, and opaque.
func test_confirm_keeps_clear_of_the_hud() -> void:
	_main.camera.set_zoom_index(_main.camera.tuning.zoom_levels.find(1.0))
	_main.camera.tracking = false
	var clicked: Vector2i = _tile_in(BUYABLE)
	var view_centre: Vector2 = _panel.get_viewport_rect().get_center()
	_click_buyable()
	# Pan so the clicked tile sits under the land panel, then let the confirm follow.
	var under: Vector2 = _panel.get_global_rect().get_center()
	_main.camera.position = _at(clicked) + (view_centre - under) / _main.camera.zoom
	_main.camera.force_update_scroll()
	_panel._process(0.0)
	assert_true(_panel.get_global_rect().grow(4.0).has_point(_panel.confirm_anchor(clicked)),
			"the clicked tile is under the land panel")
	var box: Rect2 = _panel.confirm_box.get_global_rect()
	assert_eq(_panel.hud_rects().size(), 1 + 8,
			"the land panel and the eight HUD controls (E3-S62: the guests' speed panel in Build; E4-S2: the balance)")
	for r: Rect2 in _panel.hud_rects():
		assert_false(box.intersects(r), "the confirm %s clears the HUD %s" % [box, r])
	assert_true(_panel.get_viewport_rect().encloses(box), "and stays on screen")
	var style := _panel.confirm_box.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(style.bg_color.a, 1.0, "opaque")


# E6-S26: no two parcels share a name on any square map from 16 x 16 to 256 x 256, in parcel
# steps (E6-S17 checked six sizes; groups with numbered middles show only on large maps).
func test_every_square_map_size_names_each_parcel_once() -> void:
	var size: int = CourseData.PARCEL_TILES
	while size <= 256:
		var m := CourseData.create(size, size, Surface.Type.ROUGH, 2)
		var names: Dictionary = {}
		var clashes: Array[String] = []
		for q: int in m.parcels_high:
			for p: int in m.parcels_wide:
				var name: String = LandPanel.parcel_name(m, Vector2i(p, q))
				if names.has(name):
					clashes.append("%s and %s are both \"%s\"" % [names[name], Vector2i(p, q), name])
				names[name] = Vector2i(p, q)
		assert_eq(clashes.size(), 0, "%d x %d: %s" % [size, size, clashes.slice(0, 4)])
		size += CourseData.PARCEL_TILES


# E6-S32: no two parcels share a name on any non-square map either, each side 16 to 256 in
# parcel steps (E6-S26 swept the squares). This covers the widest (256 x 16) and tallest
# (16 x 256) ratios, and maps with an odd number of parcels one way and even the other, where
# the centre sits on a parcel's middle one way and on a parcel line the other.
func test_every_non_square_map_size_names_each_parcel_once() -> void:
	var step: int = CourseData.PARCEL_TILES
	var maps: int = 0
	var clashes: Array[String] = []
	for w: int in range(step, 256 + 1, step):
		for h: int in range(step, 256 + 1, step):
			if w == h:
				continue
			var m := CourseData.create(w, h, Surface.Type.ROUGH, 2)
			var names: Dictionary = {}
			for q: int in m.parcels_high:
				for p: int in m.parcels_wide:
					var name: String = LandPanel.parcel_name(m, Vector2i(p, q))
					if names.has(name):
						clashes.append("%d x %d: %s and %s are both \"%s\"" % [w, h, names[name],
								Vector2i(p, q), name])
					names[name] = Vector2i(p, q)
			maps += 1
	assert_eq(maps, 16 * 16 - 16, "every non-square size in parcel steps")
	assert_eq(clashes.size(), 0, "%d clashes: %s" % [clashes.size(), clashes.slice(0, 6)])


# E6-S26: the confirm keeps clear of every visible Build HUD control, found from the HUD
# itself rather than a hand list, so a control added later is avoided too.
func test_confirm_avoids_every_visible_build_hud_control() -> void:
	var hud: Node = _panel.get_parent()
	var expected: Array[Rect2] = []
	for child: Node in hud.get_children():
		var control := child as Control
		if control != null and control.is_visible_in_tree():
			expected.append(control.get_global_rect().grow(_panel.confirm_margin))
	assert_gt(expected.size(), 1, "the Build HUD has controls besides the land panel")
	var rects: Array[Rect2] = _panel.hud_rects()
	for r: Rect2 in expected:
		assert_true(r in rects, "the confirm avoids the HUD control at %s" % r)
	# A control added to the HUD after the panel was ready, right where the confirm would go.
	_main.camera.set_zoom_index(_main.camera.tuning.zoom_levels.find(1.0))
	_main.camera.tracking = false
	var clicked: Vector2i = _tile_in(BUYABLE)
	_main.camera.position = _at(clicked)
	_main.camera.force_update_scroll()
	_click_buyable()
	var before: Rect2 = _panel.confirm_box.get_global_rect()
	var late := Button.new()
	late.text = "Added later"
	hud.add_child(late)
	late.global_position = before.position
	late.size = before.size
	_panel._process(0.0)
	var box: Rect2 = _panel.confirm_box.get_global_rect()
	assert_false(box.intersects(late.get_global_rect()), "the confirm %s clears the new control %s" % [box, late.get_global_rect()])
	late.visible = false
	assert_false(late.get_global_rect().grow(_panel.confirm_margin) in _panel.hud_rects(), "a hidden control is not avoided")
	late.queue_free()
