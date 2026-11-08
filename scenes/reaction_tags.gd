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
## showing the hole's number now; an edit to the hole (its tee, cup, par or the terrain on its
## line) clears it (E3-S17). It sits on that hole's cup, above the pin's pennant; a hole with no
## cup on the map has none.
##
## In Play the hole being played (`played_hole`, Main sets it) has no tag: the tag stands over
## the back of the green, where the player's ball rests and the putt is read (pillar 2).
##
## A tag can be clicked (E3-S19): `slot_at` hit-tests the boxes as drawn, and TagClicks, ahead
## of the build tool and the swing, hands the click to Main, which picks and frames the hole.
## The tag under the mouse when a click would be taken (`hovered_slot`, E3-S43, set by
## TagClicks) draws a chalk outline round its box, a shape cue as well as a colour, so it reads
## as a button.
##
## A tag never hides the golfers it talks about (E3-S63): a tag whose box, as drawn, covers a
## figure GuestView draws now (`guests`, GuestView.figure_rects) draws at FeedTuning
## `tag_covered_alpha` until no figure is under it (`faded_slots`, checked every frame). The
## hovered tag draws in full, and clicks are unchanged (slot_at ignores the fade).

## Colours (art/palette.gpl): ink box, chalk number, sun_yellow praise, flag_red complaints.
@export var box_color: Color = Color8(26, 28, 34)
@export var text_color: Color = Color8(240, 236, 224)
@export var praise_color: Color = Color8(240, 200, 58)
@export var complaint_color: Color = Color8(216, 58, 58)
## Text size, screen px at every zoom, and the padding inside each segment.
@export var font_size: int = 13
@export var padding: float = 3.0
## The tag's foot sits this far above the ground at the cup's centre (its tile's height there),
## canvas units (above HoleMarker's 30 px pole), so it never covers the pennant.
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
## The slot whose tag is hovered and would take a click (TagClicks), -1 for none.
var hovered_slot: int = -1:
	set(v):
		if v != hovered_slot:
			hovered_slot = v
			queue_redraw()
## The hovered tag's outline: chalk, screen px.
@export var hover_width: float = 2.0
## Screen px per canvas unit the tags were last drawn at.
var _scale: float = 1.0
## The guests' figures (Main binds it); a tag over one fades (E3-S63). Null: none fade.
var guests: GuestView
var tuning: FeedTuning
## Slots whose tags cover a drawn figure, as last drawn.
var _faded: Dictionary = {}


func _init() -> void:
	z_index = 2  # over the course layers, as the issue boxes are
	tuning = FeedTuning.load_default()


func bind(p_feed: ReactionFeed) -> void:
	feed = p_feed
	feed.added.connect(func(_e: ReactionFeed.Entry) -> void: queue_redraw())
	feed.cleared.connect(queue_redraw)
	feed.slot_cleared.connect(func(_slot: int) -> void: queue_redraw())


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


## Where the tag of the hole in slot `slot` stands (the ground at its cup's centre, CourseView
## space, lifted), or null.
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
	var faded: Dictionary = faded_slots()
	if faded != _faded:
		_faded = faded
		queue_redraw()


## {slot: true} for every tag drawn whose box covers a figure GuestView draws now (E3-S63).
func faded_slots() -> Dictionary:
	var out := {}
	if guests == null or not is_visible_in_tree():
		return out
	var rects: Array[Rect2] = guests.figure_rects()
	if rects.is_empty():
		return out
	var all: Dictionary = tag_slots()
	var k: float = 1.0 / _view_scale()
	for slot: int in all:
		var box: Rect2 = tag_box(slot, all[slot])
		var at: Vector2 = anchor_at(slot)
		var drawn := Rect2(at + box.position * k, box.size * k)
		for r: Rect2 in rects:
			if drawn.intersects(r):
				out[slot] = true
				break
	return out


## The alpha hole `slot`'s tag draws at now: FeedTuning tag_covered_alpha while it covers a
## drawn figure, unless it is hovered; else 1.
func alpha_of(slot: int) -> float:
	return tuning.tag_covered_alpha if _faded.has(slot) and slot != hovered_slot else 1.0


func _view_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var s: float = get_global_transform_with_canvas().get_scale().x
	return s if s > 0.0 else 1.0


## Hole `slot`'s tag box in screen px, its foot at the origin (the anchor), as _draw lays it
## out: the text pieces' widths, then the whole box with its 1 px ink edge.
func tag_box(slot: int, tally: Vector2i) -> Rect2:
	var widths: Array[float] = _widths(tag_texts(course.holes[slot].number, tally))
	var total := 0.0
	for w: float in widths:
		total += w
	var h: float = _box_height()
	return Rect2(-total * 0.5 - 1.0, -h - 1.0, total + 2.0, h + 2.0)


## The slot of the tag drawn under viewport point `viewport_pos` (a mouse event's position), or
## -1 (E3-S19). Where tags overlap, the one drawn on top (the higher number) wins. Only tags
## shown now count: none while the tags are hidden, nor the played hole's in Play.
func slot_at(viewport_pos: Vector2) -> int:
	if not is_visible_in_tree():
		return -1
	var all: Dictionary = tag_slots()
	if all.is_empty():
		return -1
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * viewport_pos
	var s: float = _view_scale()
	var slots: Array = _draw_order(all)
	slots.reverse()
	for slot: int in slots:
		var at: Vector2 = anchor_at(slot)
		if tag_box(slot, all[slot]).has_point((local - at) * s):
			return slot
	return -1


## Viewport point of hole `slot`'s tag centre (tests and scripted clicks), or null with no tag.
func tag_centre(slot: int) -> Variant:
	var all: Dictionary = tag_slots()
	if not all.has(slot):
		return null
	var box: Rect2 = tag_box(slot, all[slot])
	var at: Vector2 = anchor_at(slot)
	return get_global_transform_with_canvas() * (at + box.get_center() / _view_scale())


func _box_height() -> float:
	return ThemeDB.fallback_font.get_height(font_size) + padding * 2.0


func _widths(pieces: PackedStringArray) -> Array[float]:
	var font: Font = ThemeDB.fallback_font
	var out: Array[float] = []
	for p: String in pieces:
		out.append(0.0 if p.is_empty() else font.get_string_size(p, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + padding * 2.0)
	return out


## Slots in the order their tags are drawn: by hole number, then slot (the last on top).
func _draw_order(all: Dictionary) -> Array:
	var slots: Array = all.keys()
	slots.sort_custom(func(a: int, b: int) -> bool:
		return course.holes[a].number < course.holes[b].number \
				or (course.holes[a].number == course.holes[b].number and a < b))
	return slots


func _draw() -> void:
	var all: Dictionary = tag_slots()
	if all.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var k: float = 1.0 / _scale
	var h: float = _box_height()
	for slot: int in _draw_order(all):
		var at: Vector2 = anchor_at(slot)
		var pieces: PackedStringArray = tag_texts(course.holes[slot].number, all[slot])
		var a: float = alpha_of(slot)
		var box_c: Color = Color(box_color, box_color.a * a)
		var colors: Array[Color] = [box_c, Color(praise_color, praise_color.a * a),
				Color(complaint_color, complaint_color.a * a)]
		var text_colors: Array[Color] = [Color(text_color, text_color.a * a), box_c,
				Color(text_color, text_color.a * a)]
		var widths: Array[float] = _widths(pieces)
		draw_set_transform(at, 0.0, Vector2.ONE * k)
		draw_rect(tag_box(slot, all[slot]), box_c)
		var x: float = tag_box(slot, all[slot]).position.x + 1.0
		for i: int in pieces.size():
			if widths[i] <= 0.0:
				continue
			draw_rect(Rect2(x, -h, widths[i], h), colors[i])
			draw_string(font, Vector2(x + padding, -padding - font.get_descent(font_size)), pieces[i],
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_colors[i])
			x += widths[i]
		if slot == hovered_slot:
			draw_rect(tag_box(slot, all[slot]).grow(hover_width * 0.5 + 1.0), text_color, false, hover_width)
		# A short stem down to the pin, so the tag reads as the hole's.
		draw_line(Vector2.ZERO, Vector2(0.0, stem * _scale), box_c, 2.0)
		draw_set_transform(Vector2.ZERO)
