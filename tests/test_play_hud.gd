extends GutTest
## E3-S64: in Play, when the played hole's cup is outside the free view, a marker at the free
## view's edge points to it and carries the hole number; it hides once the cup is on screen,
## and in Build.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _main_in_play() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.show_course(GuestCourse.course())
	m.camera.view_size_override = Vector2(1280, 720)
	m.set_mode(Main.Mode.PLAY)
	m.guest_sim.set_process(false)
	m.set_process(false)  # the ball follow would move the camera
	m.camera.tracking = false
	m.camera.has_focus = false
	return m


func _look_at(m: Main, cell: Vector2i, zoom_index: int) -> void:
	m.camera.set_zoom_index(zoom_index)
	m.camera.position = m.tile_world(cell)
	m.camera.force_update_scroll()


func test_an_off_screen_cup_gets_an_edge_marker_that_points_at_it() -> void:
	var m := _main_in_play()
	var pointer: CupPointer = m.cup_pointer
	var h: HoleData = m.swing_control.hole
	assert_eq(h.number, 1, "hole 1 played")
	# 2x on the tee: the cup, 80 yd east, is off the screen.
	_look_at(m, h.tee, m.camera.tuning.zoom_levels.size() - 1)
	m.update_cup_pointer()
	var free: Rect2 = m.free_view_rect()
	var cup: Vector2 = m.camera.screen_point(m.tile_world(h.cup))
	assert_false(free.has_point(cup), "the cup is outside the free view")
	assert_true(pointer.visible, "so the marker shows")
	assert_eq(pointer.number, 1, "with the hole's number")
	assert_true(free.has_point(pointer.at), "inside the free view")
	assert_true(free.has_point(pointer.tip()), "its arrow too")
	var edge: float = minf(minf(pointer.at.x - free.position.x, free.end.x - pointer.at.x),
			minf(pointer.at.y - free.position.y, free.end.y - pointer.at.y))
	assert_almost_eq(edge, pointer.tuning.edge_inset, 0.5, "at the free view's edge")
	assert_gt(pointer.direction.dot((cup - pointer.at).normalized()), 0.999, "pointing at the cup")
	assert_eq(pointer.mouse_filter, Control.MOUSE_FILTER_IGNORE, "it takes no clicks")
	assert_false(m.hud_controls().has(pointer), "nor room from the free view")
	# Looking the other way, past the tee: it points back west.
	_look_at(m, h.tee - Vector2i(12, 0), m.camera.tuning.zoom_levels.size() - 1)
	m.update_cup_pointer()
	cup = m.camera.screen_point(m.tile_world(h.cup))
	assert_true(pointer.visible)
	assert_gt(pointer.direction.dot((cup - pointer.at).normalized()), 0.999, "still at the cup")
	# The cup on screen: no marker.
	_look_at(m, h.cup, 2)
	m.update_cup_pointer()
	assert_true(m.free_view_rect().has_point(m.camera.screen_point(m.tile_world(h.cup))))
	assert_false(pointer.visible, "hidden with the cup in view")
	# Off again, then Build: hidden.
	_look_at(m, h.tee, m.camera.tuning.zoom_levels.size() - 1)
	m.update_cup_pointer()
	assert_true(pointer.visible)
	m.set_mode(Main.Mode.BUILD)
	m.update_cup_pointer()
	assert_false(pointer.visible, "Build has none")


func test_the_marker_follows_the_hole_being_played() -> void:
	var m := _main_in_play()
	m.play_hole(2)
	m.set_process(false)
	m.camera.tracking = false
	m.camera.has_focus = false
	var h: HoleData = m.swing_control.hole
	assert_eq(h.number, 2)
	_look_at(m, m.course.holes[0].cup, m.camera.tuning.zoom_levels.size() - 1)
	m.update_cup_pointer()
	assert_true(m.cup_pointer.visible)
	assert_eq(m.cup_pointer.number, 2, "hole 2's number, not hole 1's on screen")
	var cup: Vector2 = m.camera.screen_point(m.tile_world(h.cup))
	assert_gt(m.cup_pointer.direction.dot((cup - m.cup_pointer.at).normalized()), 0.999)
