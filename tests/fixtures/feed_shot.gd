class_name FeedShot
extends Node2D
## Screenshot fixture for E3-S7's feed and map tags (by hand): the guest course
## (tests/fixtures/guest_course.gd) with a bunker on hole 2's line and rough round it, so
## hole 2 can be praised (interesting needs a hazard on the line and a way round), in Play.
## The day runs to `run_to_s` (seed 3), every line of the feed is shown and the camera frames
## the three holes, so the picture holds the feed, its marks and colours, and the tags over
## the pins. With `jump`, the feed's top line is then clicked: Build, its hole picked in the
## hole list and framed.
##   scripts/screenshot.sh tests/fixtures/feed_shot.tscn out.png 30
##   scripts/screenshot.sh tests/fixtures/feed_jump_shot.tscn out.png 30
## With `hover` (E3-S43), the day then goes back to Build with the tags' holes framed and the
## mouse over the first tag: its highlight, and each hole-list row's tag.
##   scripts/screenshot.sh tests/fixtures/feed_hover_shot.tscn out.png 30
## With `run_to_s` 0 (E3-S67), Play before any guest has finished a hole: the feed keeps its
## room with its placeholder.
##   scripts/screenshot.sh tests/fixtures/feed_empty_shot.tscn out.png 30
## With `edit_on_s` above 0 (E3-S68), a bunker goes halfway along hole `edit_hole`'s line at
## that second (Main's builder; the hole opened again), and the day runs on to `run_to_s`: that
## hole's lines from before the edit draw dimmed, the lines after at full strength.
##   scripts/screenshot.sh tests/fixtures/feed_edited_shot.tscn out.png 30
## With `fade` (E3-S63), Play stays on at 1x over hole 2's green with a guest stood behind its
## cup, under hole 2's tag, which fades; hole 3's tag, with no guest under it, draws in full.
##   scripts/screenshot.sh tests/fixtures/feed_fade_shot.tscn out.png 30

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GuestCourse := preload("res://tests/fixtures/guest_course.gd")

@export var jump: bool = false
@export var run_to_s: int = 150
@export var hover: bool = false
@export var edit_on_s: int = 0
@export var edit_hole: int = 3
@export var fade: bool = false
## E3-S62 (D53): stays in Build, where the day now runs and shows: the guests, the speed panel
## under the land panel, the map tags and the hole panel's reaction line.
##   scripts/screenshot.sh tests/fixtures/feed_build_shot.tscn out.png 30
@export var build: bool = false
## E4-S3: with `skip_frames` above 0, Build at `run_to_s`, then a skip to morning started and
## run for that many frames: the speed panel with its Skip to morning button resting and the
## status line skipping.
##   scripts/screenshot.sh tests/fixtures/feed_skip_shot.tscn out.png 30
@export var skip_frames: int = 0
## E4-S4: with `money` 0 or more, the course has that balance (not unlimited), so a skip to the
## next morning shows the balance after the day's fees and upkeep and the day's line in Play.
##   scripts/screenshot.sh tests/fixtures/money_day_shot.tscn out.png 30
@export var money: int = -1
## E4-S5: with `extra_praise` above 0, that many praises of hole 2 go into the feed after the
## day's run, so the speed panel's Rating row shows a half star (13 on top of the day: 3.5).
##   scripts/screenshot.sh tests/fixtures/rating_shot.tscn out.png 30
@export var extra_praise: int = 0
## E4-S13 (D59): with `dusk`, the day then ends at once and the next morning starts, so the row
## shows the stars set at that dusk (the praise above moves only the mean until then).
@export var dusk: bool = false

var main: Main


func _ready() -> void:
	var b: CourseBuilder = GuestCourse.build()
	b.paint(Vector2i(32, 6), Surface.Type.BUNKER, 1)
	if money >= 0:
		b.course.set_land_budget(money)
	main = MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	main.show_course(b.course)
	if not build:
		main.set_mode(Main.Mode.PLAY)
		main.set_process(false)
		main.swing_panel.visible = false
		main.aim_view.visible = false
	main.guest_sim.set_process(false)
	main.guest_sim.advance(0.0)
	var edited: bool = edit_on_s <= 0
	while main.guest_sim.brain.second < run_to_s and not main.guest_sim.brain.day_over:
		if not edited and main.guest_sim.brain.second >= edit_on_s:
			edited = true
			var spec: Array = GuestCourse.HOLES[edit_hole - 1]
			var mid: Vector2i = (spec[1] + spec[2]) / 2
			main.build_tool.builder.paint(mid, Surface.Type.BUNKER, 1)
		main.guest_sim.brain.step()
	if skip_frames > 0:
		main.guest_sim.skip_to_morning()
		for i: int in skip_frames:
			if not main.guest_sim.skipping:
				break
			main.guest_sim.skip_frame()
	for i: int in extra_praise:
		var p := GuestReaction.new()
		p.hole_number = 2
		p.kind = GuestReaction.Kind.PRAISE
		p.text = "Hole 2: loved it."
		main.guest_sim.feed.push(p, 1, run_to_s, 1)
	if dusk:
		main.guest_sim.brain.day_over = true
		main.guest_sim.advance(0.0)
	for i: int in 64:
		main.feed_panel.tick(main.feed_panel.tuning.reveal_interval_s)
	main.camera.tracking = false
	var h1: HoleData = main.course.holes[0]
	var h2: HoleData = main.course.holes[1]
	main.camera.frame_points(main.tile_world(h1.tee), main.tile_world(h2.cup), main.free_view_rect())
	if jump:
		main.feed_panel.rows[0].pressed.emit()
	if hover:
		main.set_mode(Main.Mode.BUILD)
		main.camera.frame_points(main.tile_world(h1.tee), main.tile_world(h2.cup), main.free_view_rect())
		main.camera.force_update_scroll()
		var tags: ReactionTags = main.reaction_tags
		tags._process(0.0)
		var slots: Array = tags.tag_slots().keys()
		slots.sort()
		if not slots.is_empty():
			main.tag_clicks.hover_at(tags.tag_centre(slots[0]))
	if fade:
		_fade()


func _fade() -> void:
	var feed: ReactionFeed = main.guest_sim.feed
	var r := GuestReaction.new()
	r.hole_number = 3
	r.kind = GuestReaction.Kind.COMPLAINT
	r.text = "Hole 3: too hard."
	feed.push(r, 1, run_to_s, 2)
	var p := GuestReaction.new()
	p.hole_number = 2
	p.kind = GuestReaction.Kind.PRAISE
	p.text = "Hole 2: loved it."
	feed.push(p, 1, run_to_s, 1)
	var tags: ReactionTags = main.reaction_tags
	main.camera.set_zoom_level(1.0)
	main.camera.has_focus = false
	var cup2: Vector2i = main.course.holes[1].cup
	var cup3: Vector2i = main.course.holes[2].cup
	main.camera.position = main.camera.get_parent().to_local(tags.to_global(tags.anchor_at(1)))
	main.camera.force_update_scroll()
	main.guest_view.set_process(false)
	var guest: Guest = null
	while guest == null and not main.guest_sim.brain.day_over:
		for g: Guest in main.guest_sim.brain.guests:
			if not g.is_done():
				guest = g
				break
		if guest == null:
			main.guest_sim.brain.step()
	# The first tile behind hole 2's cup that puts the guest under its tag.
	for d: int in range(0, 6):
		guest.position = main.guest_sim.brain.field.tile_center(cup2 - Vector2i(d, d) - Vector2i(0, 0))
		main.guest_view.clear()
		main.guest_view.update_view(1.0 / 60.0, 0.0)
		tags._process(0.0)
		if tags.faded_slots().has(1):
			break
	print("feed_shot fade: faded %s, cups %s %s" % [tags.faded_slots(), cup2, cup3])
