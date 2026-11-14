extends GutTest
## E14-S1 (D69): bridges. Cart path painted on water builds a footbridge (the tile stays water at
## its level), one undo step at bridge_tile_price a tile; painting anything over a bridge removes
## it; water levelling keeps bridges on re-levelled water and drops them where it drains. A
## bridge saves, loads and exports (the optional "bridges" field); the ball treats it as water;
## BridgeView draws it at every zoom; the Cart path hover says it would build one, and its price.

const W := Surface.Type.WATER
const R := Surface.Type.ROUGH
const P := Surface.Type.CART_PATH

var _refusals: Array[String] = []
var _econ: EconomyTuning


func before_all() -> void:
	_econ = EconomyTuning.load_default()


func before_each() -> void:
	_refusals.clear()


## A 32 x 32 map of rough at 2 with $5,000 and a pond, 3 x 6 at x 10 to 12, y 8 to 13, at 1.
func _pond(money: int = 5000) -> CourseData:
	var c := CourseData.create(32, 32, R, 2)
	c.set_land_budget(money)
	for y: int in range(8, 14):
		for x: int in range(10, 13):
			c.set_tile(x, y, 1, W)
	return c


func _builder(c: CourseData) -> CourseBuilder:
	var b := CourseBuilder.new(c)
	b.refused.connect(func(reason: String) -> void: _refusals.append(reason))
	return b


func _row(c: CourseData, y: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x: int in range(10, 13):
		out.append(Vector2i(x, y))
	return out


# --- building ---

func test_cart_path_on_water_builds_a_bridge_as_one_undo_step() -> void:
	var c := _pond()
	var b := _builder(c)
	var before: String = c.content_hash()
	var money: int = b.balance()
	assert_eq(b.paint_cost(Vector2i(11, 10), P, 1), _econ.bridge_tile_price, "the hover's price")
	assert_gt(_econ.bridge_tile_price, _econ.price_of(P), "a bridge is dearer than path")
	b.begin_stroke()
	for x: int in range(9, 14):
		b.paint(Vector2i(x, 10), P, 1)
	b.end_stroke()
	for cell: Vector2i in _row(c, 10):
		assert_true(c.is_bridge(cell.x, cell.y), "a bridge on %s" % cell)
		assert_eq(c.get_surface(cell.x, cell.y), W, "the tile stays water")
		assert_eq(c.get_height(cell.x, cell.y), 1, "at its level")
	assert_eq(c.get_surface(9, 10), P, "path on the bank")
	assert_eq(c.get_surface(13, 10), P)
	assert_false(c.is_bridge(9, 10))
	assert_eq(b.balance(), money - 3 * _econ.bridge_tile_price - 2 * _econ.price_of(P))
	assert_eq(b.undo_depth(), 1, "the drag is one step")
	assert_true(b.undo())
	assert_false(c.has_bridges(), "undo takes the bridge away")
	assert_eq(c.content_hash(), before)
	assert_eq(b.balance(), money, "and gives back what it charged")


func test_a_bridge_costs_nothing_twice_and_a_short_balance_refuses_it() -> void:
	var c := _pond(40)
	var b := _builder(c)
	assert_true(b.paint(Vector2i(11, 9), P, 1))
	assert_false(b.paint(Vector2i(11, 9), P, 1), "a bridge over a bridge changes nothing")
	assert_false(b.paint(Vector2i(11, 10), P, 1), "$12 left buys no bridge tile")
	assert_eq(_refusals.size(), 1)
	assert_string_contains(_refusals[0], "costs $28")


func test_painting_over_a_bridge_removes_it_and_undo_puts_it_back() -> void:
	var c := _pond()
	var b := _builder(c)
	assert_true(b.paint(Vector2i(11, 10), P, 3))
	assert_eq(c.bridge_cells().size(), 9)
	var with_bridges: String = c.content_hash()
	assert_true(b.paint(Vector2i(10, 10), Surface.Type.FAIRWAY, 1))
	assert_false(c.is_bridge(10, 10), "fairway over a bridge: no bridge, no water")
	assert_eq(c.get_surface(10, 10), Surface.Type.FAIRWAY)
	var money: int = b.balance()
	assert_true(b.paint(Vector2i(12, 10), W, 1), "water on a bridge takes the bridge away")
	assert_false(c.is_bridge(12, 10))
	assert_eq(c.get_surface(12, 10), W)
	assert_eq(b.balance(), money - _econ.price_of(W), "at water's price")
	assert_true(b.undo())
	assert_true(b.undo())
	assert_eq(c.content_hash(), with_bridges, "both undone: the bridges stand again")


func test_levelling_keeps_bridges_and_draining_drops_them() -> void:
	var c := _pond()
	var b := _builder(c)
	assert_true(b.paint(Vector2i(11, 10), P, 1))
	# Lowering the bank beside the pond to its level spreads the water over the new ground and
	# keeps the bridge (re-levelled water at the same level).
	assert_true(b.lower(Vector2i(13, 10), 1))
	assert_true(c.is_bridge(11, 10), "the bridge stands on re-levelled water")
	assert_eq(c.get_surface(13, 10), W)
	# Lowering a rim tile on the map's edge side opens a drain: cut a channel to the edge.
	b.begin_stroke()
	for x: int in range(13, 32):
		b.lower(Vector2i(x, 10), 1)
	b.end_stroke()
	assert_eq(c.get_surface(11, 10), R, "the pond drained to rough")
	assert_false(c.has_bridges(), "and its bridge went with it")
	assert_true(b.undo())
	assert_true(c.is_bridge(11, 10), "undo puts water and bridge back")


# --- save, load, export ---

func test_a_bridge_saves_loads_and_exports() -> void:
	var c := _pond()
	var b := _builder(c)
	b.paint(Vector2i(11, 10), P, 1)
	b.paint(Vector2i(12, 12), P, 1)
	var data: Dictionary = c.to_dict()
	assert_eq(data["bridges"], [[11, 10], [12, 12]], "a list of [x, y], by row")
	var back := CourseSave.from_json(CourseSave.to_json(c))
	assert_not_null(back)
	assert_eq(back.bridge_cells(), [Vector2i(11, 10), Vector2i(12, 12)] as Array[Vector2i])
	assert_eq(back.content_hash(), c.content_hash())
	var exported := CourseExport.read_text(CourseExport.export_json(c))
	assert_not_null(exported)
	assert_true(exported.is_bridge(12, 12), "an export carries its bridges")
	assert_true(c.copy().is_bridge(11, 10), "and a copy")


func test_a_course_without_bridges_writes_no_field() -> void:
	var c := _pond()
	assert_false(c.to_dict().has("bridges"), "the same file and hash as before E14")


func test_a_bridge_off_water_or_off_the_map_is_refused_on_load() -> void:
	var c := _pond()
	var data: Dictionary = c.to_dict()
	data["bridges"] = [[2, 2]]
	var errors: Array[String] = []
	assert_null(CourseData.from_dict(data, errors))
	assert_string_contains(errors[0], "not water")
	data["bridges"] = [[40, 2]]
	errors.clear()
	assert_null(CourseData.from_dict(data, errors))
	assert_string_contains(errors[0], "off the")
	data["bridges"] = [[11, 10], [11, 10]]
	errors.clear()
	assert_null(CourseData.from_dict(data, errors))
	assert_string_contains(errors[0], "two on")


func test_set_tile_off_water_drops_the_bridge() -> void:
	var c := _pond()
	c.set_bridge(Vector2i(11, 10), true)
	var rev: int = c.bridge_revision
	c.set_tile(11, 10, 1, W)
	assert_true(c.is_bridge(11, 10), "water to water keeps it")
	c.set_tile(11, 10, 2, R)
	assert_false(c.is_bridge(11, 10))
	assert_gt(c.bridge_revision, rev)


# --- the ball ---

func test_a_ball_that_lands_on_a_bridge_is_in_the_water() -> void:
	var c := CourseData.create(40, 11, Surface.Type.FAIRWAY, 0)
	for y: int in c.height:
		for x: int in range(20, 25):
			c.set_tile(x, y, 0, W)
			c.set_bridge(Vector2i(x, y), true)
	var params := BallParams.load_default()
	var speed := sqrt(100.0 * params.gravity / sin(deg_to_rad(60.0)))
	var ball := Ball.new(c, 7)
	ball.launch(Vector3(10, 27.5, 0), Ball.launch_velocity(speed, 30.0, 0.0))
	ball.run_to_rest()
	assert_eq(ball.penalty_strokes, 1, "a penalty, as in water")
	assert_eq(ball.hazard, Ball.Hazard.WATER)
	assert_eq(ball.drop_point, Vector3(97.5, 27.5, 0.0), "dropped before the water's entry")


# --- rule 3 ---

func test_a_bridge_crosses_rule_3s_water() -> void:
	var c := CourseData.create(40, 9, R, 2)
	for y: int in c.height:
		for x: int in range(18, 21):
			c.set_tile(x, y, 1, W)
	c.set_tile(30, 4, 2, Surface.Type.GREEN)
	c.set_holes([HoleData.new(1, 3, Vector2i(5, 4), Vector2i(30, 4))])
	var v := CourseValidator.new()
	var rules: Array[int] = []
	for i: CourseValidator.Issue in v.check_hole(c, c.holes[0]):
		rules.append(i.rule)
	assert_has(rules, 3, "a lake across the hole: no dry path")
	var b := _builder(c)
	b.paint(Vector2i(19, 4), P, 1)
	b.paint(Vector2i(18, 4), P, 1)
	b.paint(Vector2i(20, 4), P, 1)
	rules.clear()
	for i: CourseValidator.Issue in b.issues_for(1):
		rules.append(i.rule)
	assert_does_not_have(rules, 3, "a bridge across it is the path")


# --- the view and the hover ---

func test_bridge_view_draws_each_bridge_with_its_rails() -> void:
	var c := _pond()
	var b := _builder(c)
	b.begin_stroke()
	for y: int in range(8, 14):
		b.paint(Vector2i(11, y), P, 1)
	b.end_stroke()
	var view := BridgeView.new()
	add_child_autofree(view)
	view.show_course(c)
	assert_eq(view.pieces().size(), 6, "one piece a bridge tile")
	# A deck from bank to bank along y, with open water at +x and -x: rails on both x sides.
	var f: int = BridgeView.frame_for(c, Vector2i(11, 10))
	assert_eq(f, 16 + 1 + 2, "along y, rails at +x and -x")
	for p: Node in view.pieces():
		assert_true(view.sheet.has_frame(view.sheet.frames[(p as BridgeView.Piece).frame]))


func test_course_view_draws_bridges_at_every_zoom_and_follows_undo() -> void:
	var c := _pond()
	var b := _builder(c)
	var view := CourseView.new()
	add_child_autofree(view)
	view.show_course(c)
	b.tiles_changed.connect(view.refresh_cells)
	assert_true(b.paint(Vector2i(11, 10), P, 3))
	assert_eq(view.bridges.pieces().size(), 9)
	for z: float in [0.175, 0.5, 1.0, 2.0]:
		view.scale = Vector2(z, z)
		assert_true(view.bridges.is_visible_in_tree(), "drawn at %.3fx" % z)
	assert_true(b.undo())
	assert_eq(view.bridges.pieces().size(), 0, "undo takes the pieces away")


func test_the_cart_path_hover_says_it_builds_a_bridge_and_its_price() -> void:
	var c := _pond()
	var tool := BuildTool.new()
	add_child_autofree(tool)
	tool.builder = _builder(c)
	tool.tool = BuildTool.Tool.PAINT
	tool.surface = P
	tool.brush_size = 1
	tool.hover_at(Iso.tile_to_screen(Vector2(11, 10), 1))
	assert_eq(tool.hover, Vector2i(11, 10))
	assert_eq(tool.hover_note(), "builds a bridge, $28 a tile")
	tool.hover_at(Iso.tile_to_screen(Vector2(4, 4), 2))
	assert_eq(tool.hover_note(), "", "on dry ground it is path")
	tool.surface = Surface.Type.FAIRWAY
	tool.hover_at(Iso.tile_to_screen(Vector2(11, 10), 1))
	assert_eq(tool.hover_note(), "")
