extends GutTest
## E1-S1: Build and Play are states on one main scene (D2), switched by a toggle, never a scene load.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _main: Main


func before_each() -> void:
	_main = MAIN_SCENE.instantiate() as Main
	# A small course: these tests are about the states, not the land (E6-S6 starts the game
	# on a generated New course, which takes longer to make and draw).
	_main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(_main)


func test_starts_in_build() -> void:
	assert_eq(_main.mode, Main.Mode.BUILD)


func test_toggle_switches_build_and_play() -> void:
	_main.toggle_mode()
	assert_eq(_main.mode, Main.Mode.PLAY)
	_main.toggle_mode()
	assert_eq(_main.mode, Main.Mode.BUILD)


func test_toggle_emits_mode_changed() -> void:
	watch_signals(_main)
	_main.toggle_mode()
	assert_signal_emitted_with_parameters(_main, "mode_changed", [Main.Mode.PLAY])


func test_setting_same_mode_emits_nothing() -> void:
	watch_signals(_main)
	_main.set_mode(Main.Mode.BUILD)
	assert_signal_not_emitted(_main, "mode_changed")


func test_toggle_action_switches_mode() -> void:
	var event := InputEventAction.new()
	event.action = "toggle_mode"
	event.pressed = true
	_main._unhandled_input(event)
	assert_eq(_main.mode, Main.Mode.PLAY)


func test_toggle_keeps_same_scene_instance() -> void:
	var before: Node = _main
	_main.toggle_mode()
	_main.toggle_mode()
	assert_true(is_instance_valid(before), "main survives toggling")
	assert_same(_main, before)
	assert_true(_main.is_inside_tree())


func test_mode_label_follows_mode() -> void:
	assert_eq(_main.mode_label.text, "BUILD")
	_main.toggle_mode()
	assert_eq(_main.mode_label.text, "PLAY")


# E3-S55: the placeholder tile labels draw in Build only; the palette buttons keep theirs.
func test_play_draws_the_label_free_tiles() -> void:
	var art := TileArt.load_default()
	assert_false(_main.course_view.play_art, "Build draws the labelled sheets")
	_main.toggle_mode()
	assert_true(_main.course_view.play_art, "Play draws the label-free sheets")
	for b: Button in _main.build_palette.surface_buttons:
		assert_eq((b.icon as AtlasTexture).atlas, art.surfaces.texture, "%s icon keeps its label" % b.text)
	_main.toggle_mode()
	assert_false(_main.course_view.play_art, "back in Build, the labels return")
