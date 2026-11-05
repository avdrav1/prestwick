extends GutTest
## E3-S7: the guests' feed and the map tags. Praise and complaints scroll in the Play HUD's
## feed, newest first, in the order guests gave them; a neutral stays quiet; a burst comes in
## one line at a time and a line several guests gave at once folds into one; each line links
## to its hole, and clicking it switches to Build, picks the hole and frames it; each hole's
## tag on the map counts its praise and complaints among the last rating_window reactions.
## Checked by hand too: docs/decisions/e3-s7-feed.png, docs/decisions/e3-s7-jump.png.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var tuning: GuestTuning


func before_all() -> void:
	tuning = GuestTuning.load_default()


# --- helpers ---

func _reaction(hole: int, kind: GuestReaction.Kind, text: String = "") -> GuestReaction:
	var r := GuestReaction.new()
	r.hole_number = hole
	r.kind = kind
	r.text = text if not text.is_empty() else "Hole %d: %s." % [hole, GuestReaction.KIND_NAMES[kind]]
	return r


func _praise(hole: int, text: String = "") -> GuestReaction:
	return _reaction(hole, GuestReaction.Kind.PRAISE, text)


func _complaint(hole: int, text: String = "") -> GuestReaction:
	return _reaction(hole, GuestReaction.Kind.COMPLAINT, text)


func _texts(entries: Array[ReactionFeed.Entry]) -> PackedStringArray:
	var out := PackedStringArray()
	for e: ReactionFeed.Entry in entries:
		out.append(e.text)
	return out


func _main_in_play() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.show_course(GuestCourse.course())
	m.camera.view_size_override = Vector2(1280, 720)
	m.set_mode(Main.Mode.PLAY)
	m.guest_sim.set_process(false)
	m.feed_panel.set_process(false)
	return m


# --- ordering ---

func test_praise_and_complaints_come_in_order_and_neutrals_stay_quiet() -> void:
	var feed := ReactionFeed.new(50, 100)
	feed.push(_complaint(3, "Hole 3: first."), 1, 10)
	assert_null(feed.push(_reaction(2, GuestReaction.Kind.NEUTRAL), 1, 11), "a neutral makes no line")
	feed.push(_praise(1, "Hole 1: second."), 1, 12)
	feed.push(_complaint(2, "Hole 2: third."), 2, 4)
	assert_eq(feed.total, 4, "every reaction is counted")
	assert_eq(feed.entries.size(), 3)
	assert_eq(_texts(feed.newest(10)), PackedStringArray(["Hole 2: third.", "Hole 1: second.", "Hole 3: first."]),
			"newest first")
	assert_eq(_texts(feed.newest(2)), PackedStringArray(["Hole 2: third.", "Hole 1: second."]))
	var ids: Array[int] = []
	for e: ReactionFeed.Entry in feed.entries:
		ids.append(e.id)
	assert_eq(ids, [1, 2, 3] as Array[int], "ids in arrival order")
	assert_eq(feed.entries[2].day, 2)
	assert_eq(feed.entries[2].second, 4)
	assert_eq(feed.entries[0].hole_number, 3, "each line links to the hole it names")


func test_a_line_several_guests_give_at_once_folds_into_one() -> void:
	var feed := ReactionFeed.new()
	var same := "Hole 2: loved it, 3 on a par 3."
	feed.push(_praise(2, same), 1, 40)
	feed.push(_complaint(2, "Hole 2: too hard."), 1, 40)
	var folded := feed.push(_praise(2, same), 1, 40)
	assert_eq(feed.entries.size(), 2, "the same line in the same second folds")
	assert_eq(folded.count, 2)
	assert_eq(folded.id, 1, "it keeps its place")
	assert_eq(folded.display_text(), same + " (x2)")
	feed.push(_praise(2, same), 1, 41)
	assert_eq(feed.entries.size(), 3, "a second later it is a new line")
	feed.push(_praise(3, "Hole 3: loved it, 3 on a par 3."), 1, 41)
	assert_eq(feed.entries.size(), 4, "another hole is another line")
	assert_eq(feed.tally(2), Vector2i(3, 1), "folded lines still count every guest")


func test_the_feed_keeps_its_newest_lines_and_tags_count_the_last_window() -> void:
	var feed := ReactionFeed.new(4, 3)
	for i: int in 5:
		feed.push(_complaint(1, "Hole 1: line %d." % i), 1, i)
	assert_eq(feed.entries.size(), 3, "max_entries lines kept")
	assert_eq(feed.entries[0].text, "Hole 1: line 2.")
	assert_eq(feed.newest_id(), 5)
	assert_eq(feed.tally(1), Vector2i(0, 4), "the window holds the last 4 reactions")
	feed.push(_reaction(1, GuestReaction.Kind.NEUTRAL), 1, 9)
	feed.push(_praise(2), 1, 10)
	assert_eq(feed.tally(1), Vector2i(0, 2), "neutrals take their place in the window")
	assert_eq(feed.tallies(), {1: Vector2i(0, 2), 2: Vector2i(1, 0)})
	feed.clear()
	assert_eq(feed.entries.size(), 0)
	assert_eq(feed.tallies(), {})
	assert_eq(feed.newest_id(), 0)


func test_a_guest_day_fills_the_feed_in_the_brains_order_the_same_every_time() -> void:
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.set_process(false)
	sim.start(GuestCourse.course(), 3)
	sim.advance(0.0)  # builds day 1
	var heard: Array[GuestReaction] = []
	sim.brain.reacted.connect(func(_g: Guest, r: GuestReaction) -> void: heard.append(r))
	sim.brain.run_day()
	assert_gt(heard.size(), 0)
	assert_eq(sim.feed.total, heard.size(), "every reaction reaches the feed")
	var want := PackedStringArray()
	for r: GuestReaction in heard:
		if r.kind != GuestReaction.Kind.NEUTRAL:
			want.append(r.text)
	var got := PackedStringArray()
	var count := 0
	for e: ReactionFeed.Entry in sim.feed.entries:
		assert_string_starts_with(e.text, "Hole %d:" % e.hole_number, "the line names the hole it links to")
		assert_ne(e.kind, GuestReaction.Kind.NEUTRAL)
		assert_eq(e.day, 1)
		for k: int in e.count:
			got.append(e.text)
		count += e.count
	assert_gt(count, 0, "the day has praise or complaints")
	assert_eq(got, want, "lines in the order guests gave them, folds expanded")
	var seconds: Array[int] = []
	for e: ReactionFeed.Entry in sim.feed.entries:
		seconds.append(e.second)
	var sorted := seconds.duplicate()
	sorted.sort()
	assert_eq(seconds, sorted, "in time order")
	# The same seed gives the same feed.
	var again := GuestSim.new()
	add_child_autofree(again)
	again.set_process(false)
	again.start(GuestCourse.course(), 3)
	again.advance(0.0)
	again.brain.run_day()
	assert_eq(_texts(again.feed.entries), _texts(sim.feed.entries))
	# The next day adds to it; a new course empties it.
	var before := sim.feed.entries.size()
	sim.advance(0.0)
	assert_eq(sim.day, 2)
	assert_eq(sim.feed.entries.size(), before, "the feed runs on across days")
	sim.start(GuestCourse.course(), 3)
	assert_eq(sim.feed.entries.size(), 0, "a new course starts a new feed")


# --- the HUD feed ---

func test_a_burst_comes_in_one_line_at_a_time_newest_on_top() -> void:
	var m := _main_in_play()
	var panel: FeedPanel = m.feed_panel
	var feed: ReactionFeed = m.guest_sim.feed
	assert_true(panel.visible, "the feed is on the Play HUD")
	assert_true(panel.empty_label.visible, "says it is empty")
	var step: float = panel.tuning.reveal_interval_s
	panel.tick(step)
	# A group of three finishes hole 2 in one step.
	feed.push(_complaint(2, "Hole 2: a."), 1, 30)
	feed.push(_praise(2, "Hole 2: b."), 1, 30)
	feed.push(_complaint(2, "Hole 2: c."), 1, 30)
	panel.tick(0.0)
	assert_eq(_texts(panel.shown_entries()), PackedStringArray(["Hole 2: a."]), "the first line comes in at once")
	assert_eq(panel.waiting(), 2)
	assert_false(panel.empty_label.visible)
	panel.tick(step * 0.5)
	assert_eq(panel.shown_entries().size(), 1, "the next waits its turn")
	panel.tick(step * 0.5)
	assert_eq(_texts(panel.shown_entries()), PackedStringArray(["Hole 2: b.", "Hole 2: a."]), "newest on top")
	assert_gt(panel.highlight_left, 0.0, "the newest is highlighted")
	panel.tick(step)
	assert_eq(panel.shown_entries().size(), 3)
	assert_eq(panel.waiting(), 0)
	assert_eq(panel.rows[0].text, "! Hole 2: c.", "a complaint's mark")
	assert_eq(panel.rows[1].text, "+ Hole 2: b.", "a praise's mark")
	assert_ne(panel.rows[0].get_theme_color("font_color"), panel.rows[1].get_theme_color("font_color"),
			"and colour")
	panel.tick(panel.tuning.highlight_s)
	assert_eq(panel.highlight_left, 0.0)
	# A backlog longer than the list comes in at once.
	for i: int in panel.tuning.visible_rows + 2:
		feed.push(_complaint(1, "Hole 1: %d." % i), 1, 31)
	panel.tick(0.0)
	assert_eq(panel.waiting(), 0, "no backlog longer than the list")
	assert_eq(panel.shown_entries().size(), panel.tuning.visible_rows, "only visible_rows lines show")
	assert_eq(panel.shown_entries()[0].text, "Hole 1: %d." % (panel.tuning.visible_rows + 1))
	var shown := 0
	for b: Button in panel.rows:
		if b.visible:
			shown += 1
	assert_eq(shown, panel.tuning.visible_rows)


func test_the_feed_stays_readable_and_clear_of_the_hud_with_long_lines() -> void:
	var m := _main_in_play()
	var feed: ReactionFeed = m.guest_sim.feed
	var long := "Hole 7: blind from the tee, could not see the flag. I hate blind shots. Also slow (47 s wait) and too hard (6 on a par 3)."
	for i: int in 8:
		feed.push(_complaint(7, long + " %d" % i), 1, 50)
	m.feed_panel.tick(0.0)
	await get_tree().process_frame
	assert_true(m.feed_panel in m.hud_controls(), "framing and the free view count it")
	var r: Rect2 = m._hud_rect(m.feed_panel)
	assert_lt(r.end.y, 720.0, "the full list fits the screen at 1280 x 720")
	for ctl: Control in m.hud_controls():
		if ctl != m.feed_panel:
			assert_false(r.intersects(m._hud_rect(ctl)), "the feed clears %s" % ctl.name)
	assert_true(m.free_view_rect().has_area())
	assert_false(m.free_view_rect().intersects(r))


func test_clicking_a_line_shows_its_hole_in_build() -> void:
	var m := _main_in_play()
	var feed: ReactionFeed = m.guest_sim.feed
	feed.push(_complaint(3, "Hole 3: too hard, 6 on a par 3."), 1, 90)
	feed.push(_praise(2, "Hole 2: loved it, 3 on a par 3."), 1, 91)
	for i: int in 2:
		m.feed_panel.tick(m.feed_panel.tuning.reveal_interval_s)
	assert_eq(m.feed_panel.shown_entries().size(), 2)
	assert_eq(m.build_tool.hole_number, 1, "hole 1 picked to start")
	m.feed_panel.rows[1].pressed.emit()  # the older line, hole 3
	assert_eq(m.mode, Main.Mode.BUILD, "the click goes to Build")
	assert_eq(m.build_tool.hole_number, 3, "and picks the hole in the hole list")
	var row: HolePanel.HoleRow = null
	for each: HolePanel.HoleRow in m.hole_panel.rows:
		if each.visible and each.number == 3:
			row = each
	assert_not_null(row)
	assert_true(row.pick_button.button_pressed, "the list shows the pick")
	assert_false(m.feed_panel.visible, "the feed is Play's")
	var h: HoleData = m.course.holes[2]
	assert_eq(h.number, 3)
	var free: Rect2 = m.free_view_rect_for(m.tile_world(h.tee), m.tile_world(h.cup))
	var inner: Rect2 = free.grow(-m.camera.tuning.aim_frame_margin + 0.5)
	assert_true(inner.has_point(m.camera.screen_point(m.tile_world(h.tee))), "its tee is framed")
	assert_true(inner.has_point(m.camera.screen_point(m.tile_world(h.cup))), "and its cup")
	# A hole the guest named that is gone: Build, nothing picked anew.
	m.set_mode(Main.Mode.PLAY)
	assert_false(m.jump_to_hole(8))
	assert_eq(m.mode, Main.Mode.BUILD)
	assert_eq(m.build_tool.hole_number, 3)


# --- map tags ---

func test_each_hole_is_tagged_on_its_cup_with_its_counts() -> void:
	var m := _main_in_play()
	var feed: ReactionFeed = m.guest_sim.feed
	var tags: ReactionTags = m.reaction_tags
	assert_eq(tags.tags(), {}, "no reactions, no tags")
	feed.push(_complaint(1), 1, 20)
	feed.push(_complaint(1), 1, 21)
	feed.push(_praise(1), 1, 22)
	feed.push(_praise(2), 1, 23)
	feed.push(_reaction(3, GuestReaction.Kind.NEUTRAL), 1, 24)
	feed.push(_praise(8), 1, 25)  # no hole 8 on the course
	assert_eq(tags.tags(), {2: Vector2i(1, 0)},
			"a quiet hole and a missing one have none, nor, in Play, the hole being played")
	m.set_mode(Main.Mode.BUILD)
	assert_eq(tags.tags(), {1: Vector2i(1, 2), 2: Vector2i(1, 0)}, "Build shows the played hole's tag")
	var cup: Vector2i = GuestCourse.HOLES[0][2]
	var want: Vector2 = Iso.tile_to_screen(Vector2(cup), m.course.get_height(cup.x, cup.y)) + Vector2(0, -tags.lift)
	assert_eq(tags.anchor_of(1), want, "on its cup, over the pin")
	assert_eq(ReactionTags.tag_texts(1, Vector2i(1, 2)), PackedStringArray(["1", "+1", "!2"]))
	assert_eq(ReactionTags.tag_texts(2, Vector2i(1, 0)), PackedStringArray(["2", "+1", ""]))
	assert_true(tags.is_visible_in_tree(), "the tags stay on the map in Build")
	assert_eq(tags.tags().size(), 2)
	# Moving the cup moves the tag.
	m.build_tool.builder.place_cup(1, Vector2i(18, 6))
	assert_eq(tags.anchor_of(1), Iso.tile_to_screen(Vector2(18, 6), m.course.get_height(18, 6)) + Vector2(0, -tags.lift))
	# A new course has none.
	m.show_course(GuestCourse.course())
	assert_eq(tags.tags(), {})


# --- review fixes ---

func test_a_renumber_keeps_verdicts_and_links_on_the_hole_guests_played() -> void:
	var m := _main_in_play()
	var feed: ReactionFeed = m.guest_sim.feed
	var tags: ReactionTags = m.reaction_tags
	# Hole 2 (slot 1) praised, hole 3 (slot 2) panned, as GuestSim gives them.
	var s2: int = GuestSim.hole_slot(m.course, 2)
	var s3: int = GuestSim.hole_slot(m.course, 3)
	assert_eq([s2, s3], [1, 2])
	feed.push(_praise(2, "Hole 2: loved it, 3 on a par 3."), 1, 30, s2)
	feed.push(_praise(2, "Hole 2: loved it, 2 on a par 3."), 1, 31, s2)
	feed.push(_complaint(3, "Hole 3: too hard, 6 on a par 3."), 1, 32, s3)
	m.set_mode(Main.Mode.BUILD)
	var praised_cup: Vector2i = GuestCourse.HOLES[1][2]
	var panned_cup: Vector2i = GuestCourse.HOLES[2][2]
	# The hole list's down arrow on hole 2: holes 2 and 3 swap numbers, the cups stay.
	assert_true(m.build_tool.builder.renumber_hole(2, 3))
	assert_eq(m.course.holes[1].number, 3)
	assert_eq(tags.tags(), {3: Vector2i(2, 0), 2: Vector2i(0, 1)}, "each tag shows its hole's number now")
	var lifted := Vector2(0, -tags.lift)
	assert_eq(tags.anchor_at(1), Iso.tile_to_screen(Vector2(praised_cup), m.course.get_height(praised_cup.x, praised_cup.y)) + lifted,
			"the praise stays on the praised hole's cup")
	assert_eq(tags.tag_slots(), {1: Vector2i(2, 0), 2: Vector2i(0, 1)})
	assert_eq(tags.anchor_at(2), Iso.tile_to_screen(Vector2(panned_cup), m.course.get_height(panned_cup.x, panned_cup.y)) + lifted)
	# The feed names the hole's number now and links to it.
	m.set_mode(Main.Mode.PLAY)
	for i: int in 3:
		m.feed_panel.tick(m.feed_panel.tuning.reveal_interval_s)
	var top: ReactionFeed.Entry = m.feed_panel.shown_entries()[0]
	assert_eq(top.text, "Hole 3: too hard, 6 on a par 3.")
	assert_eq(m.feed_panel.row_text(top), "! Hole 2: too hard, 6 on a par 3.", "the panned hole is hole 2 now")
	assert_eq(m.feed_panel.rows[0].text, "! Hole 2: too hard, 6 on a par 3.")
	m.feed_panel.rows[1].pressed.emit()  # a praise line, given about the hole now numbered 3
	assert_eq(m.mode, Main.Mode.BUILD)
	assert_eq(m.build_tool.hole_number, 3)
	assert_eq(m.build_tool.picked_slot(), 1, "the click picks the praised hole")
	var free: Rect2 = m.free_view_rect_for(m.tile_world(m.course.holes[1].tee), m.tile_world(praised_cup))
	assert_true(free.grow(-m.camera.tuning.aim_frame_margin + 0.5).has_point(
			m.camera.screen_point(m.tile_world(praised_cup))), "and frames it")


func test_a_feed_line_clicked_during_a_swing_keeps_the_shot() -> void:
	var m := _main_in_play()
	m.guest_sim.feed.push(_complaint(2, "Hole 2: too hard, 6 on a par 3."), 1, 40, 1)
	m.feed_panel.tick(m.feed_panel.tuning.reveal_interval_s)
	assert_true(m.feed_panel.rows[0].visible)
	m.swing_control.press()
	assert_true(m.swing_control.swing.in_progress(), "the swing is under way")
	m.feed_panel.rows[0].pressed.emit()
	assert_eq(m.mode, Main.Mode.PLAY, "a line clicked mid-swing does not leave Play")
	assert_true(m.swing_control.swing.in_progress(), "and the swing goes on")


func test_the_feed_keeps_one_height_as_lines_come_in() -> void:
	var m := _main_in_play()
	await get_tree().process_frame
	var empty_h: float = m._hud_rect(m.feed_panel).size.y
	var feed: ReactionFeed = m.guest_sim.feed
	var long := "Hole 7: blind from the tee, could not see the flag. I hate blind shots. Also slow (47 s wait) and too hard (6 on a par 3)."
	for i: int in 8:
		feed.push(_complaint(7, long + " %d" % i), 1, 50)
	m.feed_panel.tick(0.0)
	await get_tree().process_frame
	assert_eq(m.feed_panel.shown_entries().size(), m.feed_panel.tuning.visible_rows)
	assert_almost_eq(m._hud_rect(m.feed_panel).size.y, empty_h, 0.5,
			"the full list takes the room the empty panel kept, so no row grows under the cursor")
