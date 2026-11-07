extends GutTest
## E3-S7: the guests' feed and the map tags. Praise and complaints scroll in the Play HUD's
## feed, newest first, in the order guests gave them; a neutral stays quiet; a burst comes in
## one line at a time and a line several guests gave at once folds into one; each line links
## to its hole, and clicking it switches to Build, picks the hole and frames it; each hole's
## tag on the map counts its praise and complaints among the last rating_window reactions.
## E3-S19: clicking a map tag picks and frames its hole, and the click never reaches the build
## tool or the swing.
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
	assert_true(panel.in_play, "the feed is on the Play HUD")
	assert_false(panel.visible, "hidden until its first line (E3-S27)")
	var step: float = panel.tuning.reveal_interval_s
	panel.tick(step)
	# A group of three finishes hole 2 in one step.
	feed.push(_complaint(2, "Hole 2: a."), 1, 30)
	feed.push(_praise(2, "Hole 2: b."), 1, 30)
	feed.push(_complaint(2, "Hole 2: c."), 1, 30)
	panel.tick(0.0)
	assert_eq(_texts(panel.shown_entries()), PackedStringArray(["Hole 2: a."]), "the first line comes in at once")
	assert_eq(panel.waiting(), 2)
	assert_true(panel.visible, "shown with its first line")
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
	# Moving the cup moves where a tag would stand, and clears the hole's tally (E3-S17).
	m.build_tool.builder.place_cup(1, Vector2i(18, 6))
	assert_eq(tags.anchor_of(1), Iso.tile_to_screen(Vector2(18, 6), m.course.get_height(18, 6)) + Vector2(0, -tags.lift))
	assert_eq(tags.tags(), {2: Vector2i(1, 0)}, "a moved cup's old verdicts are gone, even given with no slot")
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
	var feed: ReactionFeed = m.guest_sim.feed
	feed.push(_praise(2, "Hole 2: loved it."), 1, 40)
	m.feed_panel.tick(m.feed_panel.tuning.reveal_interval_s)
	await get_tree().process_frame
	assert_true(m.feed_panel.visible)
	var empty_h: float = m._hud_rect(m.feed_panel).size.y
	var long := "Hole 7: blind from the tee, could not see the flag. I hate blind shots. Also slow (47 s wait) and too hard (6 on a par 3)."
	for i: int in 8:
		feed.push(_complaint(7, long + " %d" % i), 1, 50)
	m.feed_panel.tick(0.0)
	await get_tree().process_frame
	assert_eq(m.feed_panel.shown_entries().size(), m.feed_panel.tuning.visible_rows)
	assert_almost_eq(m._hud_rect(m.feed_panel).size.y, empty_h, 0.5,
			"the full list takes the room the one-line panel kept, so no row grows under the cursor")


## E3-S27: Play opens with no empty feed box over the map; the first line shows it, the free
## view counts it only then, Build hides it and a new course's empty feed hides it again.
func test_the_feed_hides_until_its_first_line() -> void:
	var m := _main_in_play()
	var panel: FeedPanel = m.feed_panel
	panel.tick(1.0)
	assert_false(panel.visible, "no line yet: no box")
	assert_false(panel in m.hud_controls(), "and the free view does not count it")
	var feed: ReactionFeed = m.guest_sim.feed
	feed.push(_complaint(3, "Hole 3: too hard, 6 on a par 3."), 1, 30)
	panel.tick(0.0)
	assert_true(panel.visible, "the first line shows it")
	assert_true(panel in m.hud_controls())
	m.set_mode(Main.Mode.BUILD)
	assert_false(panel.visible, "Build hides it")
	m.set_mode(Main.Mode.PLAY)
	assert_true(panel.visible, "back in Play with its lines")
	feed.clear()
	assert_false(panel.visible, "an emptied feed hides it again")


# --- E3-S17: reactions stay on the hole that earned them ---

## Hole 1 (slot 0) panned twice, hole 2 (slot 1) praised and hole 3 (slot 2) panned, as GuestSim
## gives them, then Build.
func _main_with_verdicts() -> Main:
	var m := _main_in_play()
	var feed: ReactionFeed = m.guest_sim.feed
	feed.push(_complaint(1, "Hole 1: too hard, 6 on a par 3."), 1, 20, 0)
	feed.push(_complaint(1, "Hole 1: too hard, 5 on a par 3."), 1, 21, 0)
	feed.push(_praise(2, "Hole 2: loved it, 3 on a par 3."), 1, 22, 1)
	feed.push(_complaint(3, "Hole 3: too hard, 6 on a par 3."), 1, 23, 2)
	m.set_mode(Main.Mode.BUILD)
	return m


func test_a_moved_cup_clears_its_holes_tag() -> void:
	var m := _main_with_verdicts()
	var tags: ReactionTags = m.reaction_tags
	var feed: ReactionFeed = m.guest_sim.feed
	assert_eq(tags.tag_slots(), {0: Vector2i(0, 2), 1: Vector2i(1, 0), 2: Vector2i(0, 1)})
	assert_true(m.build_tool.builder.place_cup(1, Vector2i(18, 6)))
	assert_eq(tags.tag_slots(), {1: Vector2i(1, 0), 2: Vector2i(0, 1)}, "hole 1's tag is gone, the others stay")
	assert_eq(feed.tally(1), Vector2i.ZERO, "and its tally by number")
	assert_eq(feed.recent.size(), 4, "the reactions keep their place in the rating window")
	# Undoing the move is an edit too: the old verdicts do not come back.
	assert_true(m.build_tool.builder.undo())
	assert_eq(m.course.holes[0].cup, GuestCourse.HOLES[0][2])
	assert_eq(tags.tag_slots(), {1: Vector2i(1, 0), 2: Vector2i(0, 1)})
	# The lines are history: they still read and still link to hole 1, which is still there.
	assert_eq(feed.entries.size(), 4)
	assert_eq(ReactionFeed.resolve_slot(m.course, feed.entries[0].slot, 1), 0)
	# New verdicts on the edited hole count again.
	feed.push(_praise(1, "Hole 1: loved it, 3 on a par 3."), 2, 5, 0)
	assert_eq(tags.tag_slots()[0], Vector2i(1, 0))
	# A tee moved or a par changed is an edit of the hole as well.
	assert_true(m.build_tool.builder.place_tee(2, Vector2i(25, 6)))
	assert_false(tags.tag_slots().has(1), "a moved tee clears hole 2")
	assert_true(m.build_tool.builder.set_par(3, 4))
	assert_false(tags.tag_slots().has(2), "a new par clears hole 3")


func test_terrain_on_a_holes_line_clears_it_and_terrain_elsewhere_does_not() -> void:
	var m := _main_with_verdicts()
	var tags: ReactionTags = m.reaction_tags
	var b: CourseBuilder = m.build_tool.builder
	# Far from every hole's line (D11 footprint): nothing clears.
	assert_true(b.paint(Vector2i(10, 22), Surface.Type.BUNKER, 1))
	assert_true(b.raise(Vector2i(10, 22), 1))
	assert_eq(tags.tag_slots(), {0: Vector2i(0, 2), 1: Vector2i(1, 0), 2: Vector2i(0, 1)})
	# A bunker on hole 1's line: hole 1 only.
	assert_true(b.paint(Vector2i(12, 6), Surface.Type.BUNKER, 1))
	assert_eq(tags.tag_slots(), {1: Vector2i(1, 0), 2: Vector2i(0, 1)})
	# Ground raised under hole 3 in one drag: hole 3 only.
	b.begin_stroke()
	b.raise(Vector2i(30, 15), 3)
	b.raise(Vector2i(32, 15), 3)
	b.end_stroke()
	assert_eq(tags.tag_slots(), {1: Vector2i(1, 0)})


func test_a_renumber_or_an_open_flag_keeps_the_tally() -> void:
	var m := _main_with_verdicts()
	var tags: ReactionTags = m.reaction_tags
	var b: CourseBuilder = m.build_tool.builder
	assert_true(b.renumber_hole(1, 3))
	assert_true(b.close_hole(1))  # hole 3, numbered 1 now
	assert_eq(tags.tag_slots(), {0: Vector2i(0, 2), 1: Vector2i(1, 0), 2: Vector2i(0, 1)},
			"each tally stays on the hole guests played")
	assert_eq(tags.tags(), {3: Vector2i(0, 2), 2: Vector2i(1, 0), 1: Vector2i(0, 1)})
	assert_true(b.undo())
	assert_true(b.undo())
	assert_eq(tags.tags(), {1: Vector2i(0, 2), 2: Vector2i(1, 0), 3: Vector2i(0, 1)})


func test_undo_then_place_at_the_freed_slot_starts_clean() -> void:
	var m := _main_with_verdicts()
	var tags: ReactionTags = m.reaction_tags
	var feed: ReactionFeed = m.guest_sim.feed
	var b: CourseBuilder = m.build_tool.builder
	var tee := Vector2i(4, 20)
	var cup := Vector2i(12, 20)
	assert_true(b.place_tee(4, tee, 3))
	assert_true(b.place_cup(4, cup))
	assert_eq(m.course.holes.size(), 4)
	feed.push(_complaint(4, "Hole 4: too hard, 7 on a par 3."), 2, 30, 3)
	assert_eq(tags.tag_slots()[3], Vector2i(0, 1))
	# Undo the new hole away: its tag goes with it, the others stay.
	assert_true(b.undo())
	assert_true(b.undo())
	assert_eq(m.course.holes.size(), 3)
	assert_eq(tags.tag_slots(), {0: Vector2i(0, 2), 1: Vector2i(1, 0), 2: Vector2i(0, 1)})
	# A new hole 4 at the freed slot, even on the same tiles, starts with none.
	assert_true(b.place_tee(4, tee, 3))
	assert_true(b.place_cup(4, cup))
	assert_eq(m.course.holes.size(), 4)
	assert_false(tags.tag_slots().has(3), "the new hole starts with no tag")
	assert_eq(feed.tally(4), Vector2i.ZERO)
	# The old line still reads, but no longer links to a hole.
	var old: ReactionFeed.Entry = feed.entries[feed.entries.size() - 1]
	assert_eq(old.text, "Hole 4: too hard, 7 on a par 3.")
	assert_eq(ReactionFeed.resolve_slot(m.course, old.slot, old.hole_number), -1)
	m.set_mode(Main.Mode.PLAY)
	for i: int in 5:
		m.feed_panel.tick(m.feed_panel.tuning.reveal_interval_s)
	assert_eq(m.feed_panel.row_text(old), "! Hole 4: too hard, 7 on a par 3.")
	var picked: int = m.build_tool.picked_slot()
	m.feed_panel.rows[0].pressed.emit()
	assert_eq(m.mode, Main.Mode.BUILD)
	assert_eq(m.build_tool.picked_slot(), picked, "the pick stays where Build left it")
	assert_false(m.jump_to_hole(old.hole_number, old.slot), "the gone hole's line jumps nowhere")
	# A new course still starts empty, and the next builder is watched.
	m.show_course(GuestCourse.course())
	m.guest_sim.feed.push(_complaint(1), 1, 3, 0)
	m.set_mode(Main.Mode.BUILD)
	assert_true(m.build_tool.builder.place_cup(1, Vector2i(18, 6)))
	assert_eq(m.reaction_tags.tag_slots(), {})


# --- E3-S17 review: plays under way when Build edits ---

## Main in Play with day 1 stepped until its first group has teed off hole 1 (slot 0) and,
## with `struck`, struck there (else not yet).
func _main_mid_hole_1(struck: bool = true) -> Main:
	var m := _main_in_play()
	m.guest_sim.advance(0.0)
	var b: GuestBrain = m.guest_sim.brain
	for i: int in 600:
		if b.guests.size() >= 2 and b.guests[0].hole != null and b.guests[0].hole.hole.number == 1:
			var g: GuestGroup = b.group_of(b.guests[0])
			if g.phase == GuestGroup.Phase.ON_HOLE and g.struck == struck:
				break
		b.step()
	assert_eq(b.guests[0].hole.slot, 0, "the play is stamped with its slot as it starts")
	assert_false(b.guests[0].hole_recorded)
	return m


## Steps `m`'s day until its first group gives two reactions: [[reaction, slot pushed], ...].
func _first_group_reactions(m: Main) -> Array:
	var b: GuestBrain = m.guest_sim.brain
	var feed: ReactionFeed = m.guest_sim.feed
	var group: int = b.guests[0].group_id
	var got: Array = []
	var hear := func(guest: Guest, r: GuestReaction) -> void:
		if guest.group_id == group:
			got.append([r, feed.recent_slots[feed.recent_slots.size() - 1]])
	b.reacted.connect(hear)
	for i: int in 600:
		if got.size() >= 2:
			break
		b.step()
	b.reacted.disconnect(hear)
	return got


func test_a_verdict_on_terrain_edited_mid_hole_counts_for_no_hole() -> void:
	var m := _main_mid_hole_1()
	var builder: CourseBuilder = m.build_tool.builder
	m.set_mode(Main.Mode.BUILD)
	builder.paint(Vector2i(12, 6), Surface.Type.BUNKER, 3)  # on hole 1's line
	builder.open_hole(1)
	m.set_mode(Main.Mode.PLAY)
	var got := _first_group_reactions(m)
	assert_eq(got.size(), 2, "the group finishes hole 1")
	for each: Array in got:
		assert_eq((each[0] as GuestReaction).hole_number, 1)
		assert_eq(each[1], ReactionFeed.CLEARED, "judged on the hole before the bunker: uncounted")
	assert_false(m.guest_sim.feed.slot_tallies(m.course).has(0), "hole 1's tally starts empty")
	if not m.guest_sim.feed.entries.is_empty():
		var line: ReactionFeed.Entry = m.guest_sim.feed.entries[m.guest_sim.feed.entries.size() - 1]
		assert_eq(line.slot, 0, "the line still links to the hole")
	# The next group plays the hole with its bunker, and counts.
	var b: GuestBrain = m.guest_sim.brain
	var first_group: int = b.guests[0].group_id
	var feed: ReactionFeed = m.guest_sim.feed
	var counted: Array[bool] = [false]
	var hear := func(guest: Guest, _r: GuestReaction) -> void:
		if guest.group_id != first_group and guest.hole.slot == 0:
			counted[0] = counted[0] or feed.recent_slots[feed.recent_slots.size() - 1] == 0
	b.reacted.connect(hear)
	for i: int in 900:
		if counted[0]:
			break
		b.step()
	assert_true(counted[0], "a play started after the edit counts on its hole")


func test_a_renumber_mid_hole_keeps_the_verdict_on_the_hole_played() -> void:
	# Not yet struck: the group heads for the hole numbered 1 now (slot 2) and plays it.
	var m := _main_mid_hole_1(false)
	m.set_mode(Main.Mode.BUILD)
	assert_true(m.build_tool.builder.renumber_hole(1, 3))
	m.set_mode(Main.Mode.PLAY)
	var got := _first_group_reactions(m)
	assert_eq(got.size(), 2)
	for each: Array in got:
		assert_eq((each[0] as GuestReaction).hole_number, 1)
		assert_eq(each[1], 2, "on the hole it played, now numbered 1")
	# A guest that holed out on slot 0 before the renumber, reacting after it: filed on slot 0
	# (its play's stamp), not on the hole numbered 1 now.
	var m2 := _main_mid_hole_1()
	var b: GuestBrain = m2.guest_sim.brain
	var guest: Guest = b.guests[0]
	m2.set_mode(Main.Mode.BUILD)
	assert_true(m2.build_tool.builder.renumber_hole(1, 3))
	m2.guest_sim._on_reacted(guest, _praise(1, "Hole 1: loved it, 3 on a par 3."), b)
	var feed: ReactionFeed = m2.guest_sim.feed
	assert_eq(feed.recent_slots[feed.recent_slots.size() - 1], 0)
	assert_eq(feed.slot_tallies(m2.course), {0: Vector2i(1, 0)})
	# hole_slot, given the played hole, finds it by its ground too.
	var played: HoleData = guest.hole.hole
	assert_eq(GuestSim.hole_slot(m2.course, 1, played), 0, "tee and cup beat the number")
	assert_eq(GuestSim.hole_slot(m2.course, 1), 2, "without the played hole, the number")


func test_a_moved_cup_mid_hole_leaves_no_verdict_on_the_new_hole() -> void:
	var m := _main_mid_hole_1()
	var b: GuestBrain = m.guest_sim.brain
	var guest: Guest = b.guests[0]
	m.set_mode(Main.Mode.BUILD)
	assert_true(m.build_tool.builder.place_cup(1, Vector2i(18, 6)))
	# Were it to react about the old cup (holed out before the move), it counts for none.
	m.guest_sim._on_reacted(guest, _praise(1), b)
	var feed: ReactionFeed = m.guest_sim.feed
	assert_eq(feed.recent_slots[feed.recent_slots.size() - 1], ReactionFeed.CLEARED)
	assert_false(feed.slot_tallies(m.course).has(0))
	# A new day forgets the old plays.
	assert_gt(m.guest_sim._stale.size(), 0)
	b.day_over = true
	m.guest_sim.advance(0.0)
	assert_eq(m.guest_sim.day, 2)
	assert_eq(m.guest_sim._stale.size(), 0)


func test_cleared_reactions_hold_their_window_place_but_are_not_rated() -> void:
	var feed := ReactionFeed.new(4, 10)
	var c := GuestCourse.course()
	feed.push(_complaint(1), 1, 1, 0)
	feed.push(_complaint(1), 1, 2, 0)
	feed.push(_praise(2), 1, 3, 1)
	var line := feed.push(_praise(1), 1, 4, 0, false)
	assert_eq(line.slot, 0, "an uncounted line still links to its hole")
	assert_eq(feed.rated().size(), 3, "an uncounted push is not rated")
	feed.clear_slot(c.holes, 0)
	assert_eq(feed.recent.size(), 4, "cleared reactions keep their place")
	assert_eq(feed.rated().size(), 1, "and the rating reads the rest")
	assert_eq(feed.rated()[0].hole_number, 2)
	feed.push(_praise(3), 1, 5, 2)
	assert_eq(feed.rated().size(), 2, "the oldest cleared one is pushed out")


# --- E3-S19: a map tag picks its hole ---

## A left press or release at viewport point `at`, through the real viewport, so the nodes
## take it in the order Godot hands it out (TagClicks ahead of BuildTool and SwingControl).
func _click(m: Main, at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.position = at
	ev.global_position = at
	m.get_viewport().push_input(ev, true)


## Centres the camera on slot `slot`'s tag at 1x, clear of the HUD, and returns its centre on
## the screen.
func _show_tag(m: Main, slot: int) -> Vector2:
	var tags: ReactionTags = m.reaction_tags
	m.camera.restore_zoom()
	m.camera.tracking = false
	m.camera.has_focus = false
	m.camera.position = m.camera.get_parent().to_local(tags.to_global(tags.anchor_at(slot)))
	m.camera.force_update_scroll()
	tags._process(0.0)
	var at: Vector2 = tags.tag_centre(slot)
	for ctl: Control in m.hud_controls():
		assert_false(m._hud_rect(ctl).has_point(at), "the tag is clear of %s" % ctl.name)
	return at


func _assert_framed(m: Main, slot: int) -> void:
	var h: HoleData = m.course.holes[slot]
	var free: Rect2 = m.free_view_rect_for(m.tile_world(h.tee), m.tile_world(h.cup))
	var inner: Rect2 = free.grow(-m.camera.tuning.aim_frame_margin + 0.5)
	assert_true(inner.has_point(m.camera.screen_point(m.tile_world(h.tee))), "its tee is framed")
	assert_true(inner.has_point(m.camera.screen_point(m.tile_world(h.cup))), "and its cup")


func test_a_click_on_a_tag_frames_its_hole_and_paints_nothing() -> void:
	var m := _main_with_verdicts()
	var tags: ReactionTags = m.reaction_tags
	await get_tree().process_frame
	m.build_tool.select_surface(Surface.Type.BUNKER)
	assert_eq(m.build_tool.picked_slot(), 0, "hole 1 picked to start")
	var at: Vector2 = _show_tag(m, 2)
	assert_eq(tags.slot_at(at), 2, "the hit test finds hole 3's tag")
	assert_eq(tags.slot_at(at + Vector2(0, 60)), -1, "and none below it, on the green")
	var before: String = m.course.content_hash()
	var strokes: int = m.build_tool.stroke_count
	_click(m, at, true)
	_click(m, at, false)
	assert_eq(m.build_tool.picked_slot(), 2, "the click picks hole 3")
	assert_eq(m.build_tool.hole_number, 3)
	_assert_framed(m, 2)
	assert_eq(m.course.content_hash(), before, "and paints nothing")
	assert_eq(m.build_tool.stroke_count, strokes, "the build tool never saw the click")
	assert_false(m.build_tool.builder.can_undo(), "no undo step")
	# A click off every tag still paints, as before.
	m.camera.force_update_scroll()
	var off: Vector2 = m.camera.screen_point(m.tile_world(Vector2i(10, 12)))
	assert_eq(tags.slot_at(off), -1)
	_click(m, off, true)
	_click(m, off, false)
	assert_eq(m.build_tool.stroke_count, strokes + 1, "the tool takes a click on the map")
	assert_ne(m.course.content_hash(), before)


func test_a_click_on_a_tag_in_play_goes_to_build_and_never_swings() -> void:
	var m := _main_with_verdicts()
	await get_tree().process_frame
	m.set_mode(Main.Mode.PLAY)  # hole 1: its tag is not drawn, holes 2 and 3 are
	assert_eq(m.reaction_tags.tag_slots().keys().has(0), false)
	m.set_process(false)  # Play's ball follow would move the camera off the tag
	var at: Vector2 = _show_tag(m, 1)
	var before: String = m.course.content_hash()
	_click(m, at, true)
	_click(m, at, false)
	assert_eq(m.mode, Main.Mode.BUILD, "the click goes to Build, as a feed line's does")
	assert_eq(m.build_tool.picked_slot(), 1, "picks hole 2")
	_assert_framed(m, 1)
	assert_false(m.swing_control.swing.in_progress(), "no swing started")
	assert_eq(m.course.content_hash(), before, "nothing painted")
	# Mid-swing the click is the swing's: the tag leaves it, so the shot goes on.
	m.set_mode(Main.Mode.PLAY)  # hole 2 now, so hole 3's tag
	at = _show_tag(m, 2)
	m.swing_control.press()
	var phase: int = m.swing_control.swing.phase
	_click(m, at, true)
	_click(m, at, false)
	assert_eq(m.mode, Main.Mode.PLAY, "a tag clicked mid-swing does not leave Play")
	assert_ne(m.swing_control.swing.phase, phase, "the click went to the swing")


## E3-S19 review: mid-hole, with the ball at rest, the click that starts the swing is often over
## another hole's tag (the cursor aims at the ground under it). The tag leaves it to the swing,
## so the round in progress is kept; once the hole is finished the tag takes the click again.
func test_a_click_on_a_tag_mid_hole_at_rest_is_the_swings() -> void:
	var m := _main_with_verdicts()
	await get_tree().process_frame
	m.set_mode(Main.Mode.PLAY)  # hole 1: holes 2 and 3 have tags
	m.set_process(false)
	var at: Vector2 = _show_tag(m, 1)
	var score: HoleScore = m.swing_control.score
	score.strokes = 2  # two strokes played, the ball at rest
	assert_false(m.swing_control.is_ball_moving())
	assert_false(m.swing_control.swing.in_progress())
	assert_true(m.tag_waits_for_swing())
	var phase: int = m.swing_control.swing.phase
	_click(m, at, true)
	_click(m, at, false)
	assert_eq(m.mode, Main.Mode.PLAY, "the tag click mid-hole does not leave Play")
	assert_eq(m.swing_control.score, score, "the round goes on")
	assert_eq(m.swing_control.score.strokes, 2, "with its strokes")
	assert_ne(m.swing_control.swing.phase, phase, "the click started the swing")
	# Finished, the hole is no longer under way: the tag takes the click and goes to Build.
	m.swing_control.swing.reset()  # the swing the click started is set down
	score.holed = true
	assert_false(m.tag_waits_for_swing())
	at = _show_tag(m, 1)
	_click(m, at, true)
	_click(m, at, false)
	assert_eq(m.mode, Main.Mode.BUILD, "a finished hole's tag click goes to Build")
	assert_eq(m.build_tool.picked_slot(), 1, "and picks hole 2")
	_assert_framed(m, 1)


# --- E3-S43: a tag looks clickable, and its hole-list row reaches it ---

## A mouse motion to viewport point `at`, through the real viewport.
func _move(m: Main, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	m.get_viewport().push_input(ev, true)


func test_hovering_a_tag_shows_the_pointing_hand_and_a_highlight() -> void:
	var m := _main_with_verdicts()
	var tags: ReactionTags = m.reaction_tags
	await get_tree().process_frame
	var at: Vector2 = _show_tag(m, 2)
	assert_eq(m.tag_clicks.hover_at(at), 2, "the tag under the mouse")
	assert_eq(m.tag_clicks.cursor_shape, Input.CURSOR_POINTING_HAND, "the pointing hand")
	assert_eq(tags.hovered_slot, 2, "and the tag is highlighted")
	assert_eq(m.tag_clicks.hover_at(at + Vector2(0, 60)), -1, "off the tag, on the green")
	assert_eq(m.tag_clicks.cursor_shape, Input.CURSOR_ARROW, "the arrow again")
	assert_eq(tags.hovered_slot, -1, "and no highlight")
	# Through the viewport, as the mouse moves.
	_move(m, at)
	assert_eq(tags.hovered_slot, 2, "a motion over the tag hovers it")
	assert_eq(m.tag_clicks.cursor_shape, Input.CURSOR_POINTING_HAND)
	_move(m, at + Vector2(0, 60))
	assert_eq(tags.hovered_slot, -1)
	assert_eq(m.tag_clicks.cursor_shape, Input.CURSOR_ARROW)


func test_a_tag_mid_hole_in_play_shows_no_hand() -> void:
	var m := _main_with_verdicts()
	await get_tree().process_frame
	m.set_mode(Main.Mode.PLAY)
	m.set_process(false)
	var at: Vector2 = _show_tag(m, 1)
	assert_eq(m.tag_clicks.hover_at(at), 1, "before the first stroke the tag takes a click")
	m.swing_control.score.strokes = 1  # the hole under way
	assert_eq(m.tag_clicks.hover_at(at), -1, "mid-hole the click is the swing's")
	assert_eq(m.tag_clicks.cursor_shape, Input.CURSOR_ARROW, "so no hand")
	assert_eq(m.reaction_tags.hovered_slot, -1, "and no highlight")


func test_a_hole_list_rows_tag_picks_and_frames_its_hole() -> void:
	var m := _main_with_verdicts()
	await get_tree().process_frame
	m.hole_panel.refresh()
	var rows: Array = m.hole_panel.shown_rows()
	assert_eq(rows.size(), 3)
	var texts: Array[String] = []
	for r: HolePanel.HoleRow in rows:
		texts.append(r.tag_button.text if r.tag_button.visible else "")
	assert_eq(texts, ["!2", "+1", "!1"], "each row shows its map tag's counts")
	assert_eq(m.build_tool.picked_slot(), 0)
	(rows[2] as HolePanel.HoleRow).tag_button.pressed.emit()
	assert_eq(m.build_tool.picked_slot(), 2, "the row's tag picks hole 3")
	_assert_framed(m, 2)
	# A moved cup clears the tag, and the row's with it.
	assert_true(m.build_tool.builder.place_cup(1, Vector2i(18, 6)))
	m.hole_panel.refresh()
	assert_false((m.hole_panel.shown_rows()[0] as HolePanel.HoleRow).tag_button.visible,
			"hole 1's row has no tag once its tag is cleared")
