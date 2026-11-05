class_name ReactionTags
extends Node2D
## The guests' map tags (E3-S7; docs/design.md Guests and reactions, Feed): over each hole's
## pin, a tag with the hole's number and its praise and complaint counts among the last
## `rating_window` hole reactions (ReactionFeed.tally), so the map says which holes guests talk
## about, in Play and in Build. A reader only: a child of CourseView, drawn in its space over
## the terrain (z_index), at a fixed size on screen at every zoom, as the tee numbers are.
##
## A tag: an ink box with the hole number in chalk, then a sun_yellow segment "+n" for praise
## and a flag_red segment "!n" for complaints (a mark as well as a colour), each only when its
## count is above 0. A hole with neither has no tag. A tag belongs to the hole guests played,
## by its slot (ReactionFeed.slot_tallies), so a renumber or a swap in Build keeps it there,
## showing the hole's number now. It sits on that hole's cup, above the pin's pennant; a hole
## with no cup on the map has none.
##
## In Play the hole being played (`played_hole`, Main sets it) has no tag: the tag stands over
## the back of the green, where the player's ball rests and the putt is read (pillar 2).

## Colours (art/palette.gpl): ink box, chalk number, sun_yellow praise, flag_red complaints.
@export var box_color: Color = Color8(26, 28, 34)
@export var text_color: Color = Color8(240, 236, 224)
@export var praise_color: Color = Color8(240, 200, 58)
@export var complaint_color: Color = Color8(216, 58, 58)
## Text size, screen px at every zoom, and the padding inside each segment.
@export var font_size: int = 13
@export var padding: float = 3.0
## The tag's foot sits this far above the cup's tile top, canvas units (above HoleMarker's
## 30 px pole), so it never covers the pennant.
@export var lift: float = 40.0
## A stem from the tag's foot down toward the pole's top, canvas units.
@export var stem: float = 10.0

var course: CourseData
var feed: ReactionFeed
## The hole the player is playing (Play), whose tag is not drawn, or null (Build).
var played_hole: HoleData = null:
	set(h):
		played_hole = h
		queue_redraw()
## Screen px per canvas unit the tags were last drawn at.
var _scale: float = 1.0


func _init() -> void:
	z_index = 2  # over the course layers, as the issue boxes are


func bind(p_feed: ReactionFeed) -> void:
	feed = p_feed
	feed.added.connect(func(_e: ReactionFeed.Entry) -> void: queue_redraw())
	feed.cleared.connect(queue_redraw)


## The course whose holes the tags stand on (Main.show_course).
func show_course(c: CourseData) -> void:
	course = c
	queue_redraw()


## {hole number now: Vector2i(praise, complaints)} for every tag drawn (tag_slots, keyed by
## the number each hole has now).
func tags() -> Dictionary:
	var out := {}
	var by_slot: Dictionary = tag_slots()
	for slot: int in by_slot:
		var n: int = course.holes[slot].number
		out[n] = out.get(n, Vector2i.ZERO) + by_slot[slot]
	return out


## {slot of course.holes: Vector2i(praise, complaints)} for every tag drawn: holes with a cup
## on the map and a praise or a complaint in the window, less the hole being played.
func tag_slots() -> Dictionary:
	var out := {}
	if course == null or feed == null:
		return out
	var t: Dictionary = feed.slot_tallies(course)
	for slot: int in t:
		if played_hole != null and course.holes[slot] == played_hole:
			continue
		if anchor_at(slot) != null:
			out[slot] = t[slot]
	return out


## Where hole `number`'s tag stands (the first hole with that number), or null.
func anchor_of(number: int) -> Variant:
	return anchor_at(ReactionFeed.resolve_slot(course, -1, number))


## Where the tag of the hole in slot `slot` stands (its cup's tile top, CourseView space,
## lifted), or null.
func anchor_at(slot: int) -> Variant:
	if course == null or slot < 0 or slot >= course.holes.size():
		return null
	var h: HoleData = course.holes[slot]
	if not course.in_bounds(h.cup.x, h.cup.y):
		return null
	return Iso.tile_to_screen(Vector2(h.cup), course.get_height(h.cup.x, h.cup.y)) \
			+ Vector2(0.0, -lift)


## Tag text pieces for `tally`: [number, praise or "", complaints or ""].
static func tag_texts(number: int, tally: Vector2i) -> PackedStringArray:
	return [str(number), "+%d" % tally.x if tally.x > 0 else "", "!%d" % tally.y if tally.y > 0 else ""]


func _process(_delta: float) -> void:
	var s := _view_scale()
	if not is_equal_approx(s, _scale):
		_scale = s
		queue_redraw()


func _view_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var s: float = get_global_transform_with_canvas().get_scale().x
	return s if s > 0.0 else 1.0


func _draw() -> void:
	var all: Dictionary = tag_slots()
	if all.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var k: float = 1.0 / _scale
	var h: float = font.get_height(font_size) + padding * 2.0
	var slots: Array = all.keys()
	slots.sort_custom(func(a: int, b: int) -> bool:
		return course.holes[a].number < course.holes[b].number \
				or (course.holes[a].number == course.holes[b].number and a < b))
	for slot: int in slots:
		var at: Vector2 = anchor_at(slot)
		var pieces: PackedStringArray = tag_texts(course.holes[slot].number, all[slot])
		var colors: Array[Color] = [box_color, praise_color, complaint_color]
		var text_colors: Array[Color] = [text_color, box_color, text_color]
		var widths: Array[float] = []
		var total := 0.0
		for p: String in pieces:
			var w := 0.0 if p.is_empty() else font.get_string_size(p, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + padding * 2.0
			widths.append(w)
			total += w
		draw_set_transform(at, 0.0, Vector2.ONE * k)
		var x := -total * 0.5
		draw_rect(Rect2(x - 1.0, -h - 1.0, total + 2.0, h + 2.0), box_color)
		for i: int in pieces.size():
			if widths[i] <= 0.0:
				continue
			draw_rect(Rect2(x, -h, widths[i], h), colors[i])
			draw_string(font, Vector2(x + padding, -padding - font.get_descent(font_size)), pieces[i],
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_colors[i])
			x += widths[i]
		# A short stem down to the pin, so the tag reads as the hole's.
		draw_line(Vector2.ZERO, Vector2(0.0, stem * _scale), box_color, 2.0)
		draw_set_transform(Vector2.ZERO)
