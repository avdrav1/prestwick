class_name FeedPanel
extends PanelContainer
## The guests' feed on the Play HUD (E3-S7; docs/design.md Guests and reactions, Feed): their
## praise and complaints as they finish holes (GuestSim.feed, ReactionFeed), newest at the top,
## `visible_rows` at once, older lines scrolling off the bottom. Each line names its hole
## ("Hole 3: ..."), and clicking it emits hole_requested, which Main answers by switching to
## Build, picking that hole in the hole list and framing it (Main.jump_to_hole). A line links
## to the hole guests played (its slot, ReactionFeed), and names that hole's number now, so a
## renumber in Build never points it at another hole. Main ignores a click while a swing is
## under way or the ball is moving, so a line never ends a shot.
##
## The panel keeps one height in Play, the full list's (`row_lines` lines a row), so a line
## coming in never grows it over the map under a cursor that has not moved. It shows for the
## whole of Play, from before its first line (E3-S67): the free view leaves its room from the
## start, so the aim fit and hole framing never change when the first line comes in. With no
## line yet (and after a new course empties the feed) it shows its title and one quiet
## placeholder line. Main says when it is Play's (set_in_play); Build hides it.
##
## Readable when several guests finish at once: a burst comes in one line at a time, at most
## one every `reveal_interval_s` real seconds (tick), so the list moves one row at a time; a
## backlog longer than the list shows at once. The newest line is highlighted for
## `highlight_s`. A line several guests gave in the same second shows once, with its count
## (ReactionFeed). Shape and colour both tell the verdict (colourblind rule): a praise line
## starts "+" in sun_yellow, a complaint "!" in a light flag_red.
##
## The feed reads real time only to pace what it shows; the day itself never waits on it.

## A line was clicked: Main shows hole `number` in Build.
## `slot` is its slot in CourseData.holes (-1 when unknown: Main goes by the number).
signal hole_requested(number: int, slot: int)

const PRAISE_MARK: String = "+"
const COMPLAINT_MARK: String = "!"

## Line colours: sun_yellow for praise, a light flag_red for complaints (art/palette.gpl ramps).
@export var praise_color: Color = Color8(240, 200, 58)
@export var complaint_color: Color = Color8(240, 160, 150)
## The highlighted (newest) line's border: chalk.
@export var highlight_color: Color = Color8(240, 236, 224)
## The placeholder shown before the first line (E3-S67): a dim chalk, quieter than any line.
@export var placeholder_color: Color = Color8(240, 236, 224, 110)

## Null loads scenes/feed_tuning.tres.
var tuning: FeedTuning
var sim: GuestSim
var title_label: Label
## Shown in place of the rows while the feed has no line yet (E3-S67).
var placeholder_label: Label
## True while Main shows the Play HUD (set_in_play): the panel shows then.
var in_play: bool = false
## One button per visible row, top (newest) first; the first shown_entries().size() are shown.
var rows: Array[Button] = []
## The newest line shown so far (ReactionFeed.Entry.id); lines after it wait to come in.
var shown_id: int = 0
## Real seconds left of the newest line's highlight.
var highlight_left: float = 0.0

var _since_reveal: float = 0.0
## The entry each shown row stands for, by row.
var _row_entries: Array[ReactionFeed.Entry] = []
var _highlight_box: StyleBoxFlat


func _ready() -> void:
	if tuning == null:
		tuning = FeedTuning.load_default()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = "Guests say"
	box.add_child(title_label)
	placeholder_label = Label.new()
	placeholder_label.name = "Placeholder"
	placeholder_label.text = "Nothing yet: guests speak as they finish a hole."
	placeholder_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placeholder_label.custom_minimum_size = Vector2(tuning.width, 0)
	placeholder_label.add_theme_font_size_override("font_size", tuning.font_size)
	placeholder_label.add_theme_color_override("font_color", placeholder_color)
	box.add_child(placeholder_label)
	_highlight_box = StyleBoxFlat.new()
	_highlight_box.bg_color = Color(0.2, 0.2, 0.24)
	_highlight_box.border_color = highlight_color
	_highlight_box.set_border_width_all(1)
	_highlight_box.set_content_margin_all(4)
	for i: int in tuning.visible_rows:
		var b := Button.new()
		b.name = "Row%d" % i
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(tuning.width, 0)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", tuning.font_size)
		b.visible = false
		b.pressed.connect(_on_row_pressed.bind(i))
		box.add_child(b)
		rows.append(b)
	box.custom_minimum_size.y = full_height()
	_refresh()


## The list's height with every row shown at `row_lines` lines, px: the height the panel keeps.
func full_height() -> float:
	if rows.is_empty():
		return 0.0
	var b: Button = rows[0]
	var font: Font = b.get_theme_font("font")
	var line: float = font.get_height(tuning.font_size) + b.get_theme_constant("line_spacing")
	var row: float = line * tuning.row_lines + b.get_theme_stylebox("normal").get_minimum_size().y
	row = maxf(row, line * tuning.row_lines + _highlight_box.get_minimum_size().y)
	var sep: float = (get_child(0) as VBoxContainer).get_theme_constant("separation")
	# The placeholder (one line, hidden once a line is in) fits in the rows' room.
	return title_label.get_combined_minimum_size().y + (row + sep) * tuning.visible_rows


## Main shows (true, Play) or hides (false, Build) the feed. In Play it shows from the start,
## with a placeholder until its first line (E3-S67).
func set_in_play(value: bool) -> void:
	in_play = value
	_refresh()


func bind(p_sim: GuestSim) -> void:
	sim = p_sim
	sim.feed.added.connect(_on_added)
	sim.feed.cleared.connect(_on_cleared)
	shown_id = sim.feed.newest_id()
	if is_node_ready():
		_refresh()


func _process(delta: float) -> void:
	tick(delta)


## `delta` real seconds: brings in the next waiting line once `reveal_interval_s` has gone by
## since the last, or every waiting line when more wait than the list shows, and runs down the
## highlight. Out of Play (Build), every line comes in at once, so Play never replays old ones.
func tick(delta: float) -> void:
	if sim == null:
		return
	_since_reveal += delta
	var was_highlighted := highlight_left > 0.0
	highlight_left = maxf(highlight_left - delta, 0.0)
	var newest := sim.feed.newest_id()
	var changed := was_highlighted and highlight_left <= 0.0
	if newest > shown_id:
		if not in_play:
			shown_id = newest
			highlight_left = 0.0
			changed = true
		elif newest - shown_id > tuning.visible_rows:
			shown_id = newest
			_reveal()
			changed = true
		elif _since_reveal >= tuning.reveal_interval_s:
			shown_id += 1
			_reveal()
			changed = true
	if changed:
		_refresh()


## Lines waiting to come in.
func waiting() -> int:
	return 0 if sim == null else sim.feed.newest_id() - shown_id


## The lines shown now, top (newest) first.
func shown_entries() -> Array[ReactionFeed.Entry]:
	var out: Array[ReactionFeed.Entry] = []
	if sim == null:
		return out
	var entries: Array[ReactionFeed.Entry] = sim.feed.entries
	for i: int in range(entries.size() - 1, -1, -1):
		if out.size() >= tuning.visible_rows:
			break
		if entries[i].id <= shown_id:
			out.append(entries[i])
	return out


## The text row `entry` shows: its mark, then its line, naming its hole's number now.
func row_text(entry: ReactionFeed.Entry) -> String:
	return "%s %s" % [PRAISE_MARK if entry.is_praise() else COMPLAINT_MARK,
			entry.display_text(number_now(entry))]


## The hover text of `entry`'s row: where a click goes, then (E3-S44) the checks it failed in
## the player's words, the same words the hole panel's hover uses (GuestReaction.CHECK_WORDS).
func row_tip(entry: ReactionFeed.Entry, number: int) -> String:
	var tip := "Show hole %d in Build" % (number if number > 0 else entry.hole_number)
	return tip if entry.failed_text.is_empty() else tip + "\n" + entry.failed_text


## The number of the hole `entry` links to as the course has it now, or 0 when it is gone.
func number_now(entry: ReactionFeed.Entry) -> int:
	if sim == null or sim.course == null:
		return 0
	var slot: int = ReactionFeed.resolve_slot(sim.course, entry.slot, entry.hole_number)
	return sim.course.holes[slot].number if slot >= 0 else 0


func _reveal() -> void:
	_since_reveal = 0.0
	highlight_left = tuning.highlight_s


func _on_added(entry: ReactionFeed.Entry) -> void:
	# A folded line that is already shown grows its count at once.
	if entry.id <= shown_id:
		_refresh()


func _on_cleared() -> void:
	shown_id = 0
	highlight_left = 0.0
	_refresh()


func _on_row_pressed(i: int) -> void:
	if i < _row_entries.size():
		var e: ReactionFeed.Entry = _row_entries[i]
		var n: int = number_now(e)
		hole_requested.emit(n if n > 0 else e.hole_number, e.slot)


func _refresh() -> void:
	if rows.is_empty():
		return
	_row_entries = shown_entries()
	visible = in_play
	placeholder_label.visible = _row_entries.is_empty()
	for i: int in rows.size():
		var b: Button = rows[i]
		if i >= _row_entries.size():
			b.visible = false
			continue
		var e: ReactionFeed.Entry = _row_entries[i]
		b.visible = true
		b.text = row_text(e)
		var n: int = number_now(e)
		b.tooltip_text = row_tip(e, n)
		var c: Color = praise_color if e.is_praise() else complaint_color
		for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(state, c)
		if i == 0 and highlight_left > 0.0:
			b.add_theme_stylebox_override("normal", _highlight_box)
		else:
			b.remove_theme_stylebox_override("normal")
	# Shrink back when lines get shorter (a PanelContainer only grows by itself).
	reset_size()
