class_name TagClicks
extends Node
## Clicks on the guests' map tags (E3-S19; docs/design.md Feed and map tags). A left press on a
## tag (ReactionTags.slot_at) goes to `target` (Main._on_tag_link: number, slot -> bool), which
## picks and frames the tag's hole, in Play only while the hole is not under way, so the click
## that starts a swing mid-hole stays the swing's; when it takes the click, the press and its
## release are marked handled, so neither reaches the build tool (no paint, no stroke) nor the swing.
##
## Godot hands unhandled input to the nodes lower in the tree first, so this node sits after
## BuildTool and SwingControl among Main's children (scenes/main.tscn): the hit test runs ahead of
## the tool. A HUD control over a tag takes the click before this node sees it.
##
## Hover (E3-S43): a tag that would take a click (`can_click`, Main: not in Play mid-hole) shows
## it can be clicked: the pointing-hand cursor (`cursor_shape`, Input's default shape) and the
## tag's highlight (ReactionTags.hovered_slot). The mouse is read on every motion, before the HUD
## gets it (_input), and a HUD control under the mouse hides the hover, as it takes the click.

var tags: ReactionTags
## Called with (hole number, slot) for a tag clicked; true when it took the click.
var target: Callable
## () -> bool: whether a tag click would be taken now (Main: not in Play mid-hole); an empty
## Callable always would.
var can_click: Callable
## The cursor shape set for the hover: the pointing hand over a tag, else the arrow.
var cursor_shape: Input.CursorShape = Input.CURSOR_ARROW
## A press this node took, so its release is taken too.
var _held: bool = false


func bind(p_tags: ReactionTags, p_target: Callable, p_can_click: Callable = Callable()) -> void:
	tags = p_tags
	target = p_target
	can_click = p_can_click


## The mouse at viewport point `at` (no HUD control under it): highlights the tag there and
## shows the pointing hand when a click would be taken, else clears both. Returns the slot, or -1.
func hover_at(at: Vector2) -> int:
	var slot: int = -1
	if tags != null and target.is_valid() and (not can_click.is_valid() or bool(can_click.call())):
		slot = tags.slot_at(at)
	_show_hover(slot)
	return slot


func _show_hover(slot: int) -> void:
	if is_instance_valid(tags):
		tags.hovered_slot = slot
	var shape: Input.CursorShape = Input.CURSOR_POINTING_HAND if slot >= 0 else Input.CURSOR_ARROW
	if shape != cursor_shape:
		cursor_shape = shape
		Input.set_default_cursor_shape(shape)


func _input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm == null:
		return
	var over_hud: bool = get_viewport().gui_get_hovered_control() != null
	if over_hud:
		_show_hover(-1)
	else:
		hover_at(mm.position)


func _exit_tree() -> void:
	_show_hover(-1)


## A left press at viewport point `at`: true, after handing the tag's hole to `target`, when a
## tag is drawn there and `target` took it.
func press_at(at: Vector2) -> bool:
	if tags == null or not target.is_valid():
		return false
	var slot: int = tags.slot_at(at)
	if slot < 0:
		return false
	if not bool(target.call(tags.course.holes[slot].number, slot)):
		return false
	_held = true
	return true


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if press_at(mb.position):
			get_viewport().set_input_as_handled()
	elif _held:
		_held = false
		get_viewport().set_input_as_handled()
