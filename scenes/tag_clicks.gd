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

var tags: ReactionTags
## Called with (hole number, slot) for a tag clicked; true when it took the click.
var target: Callable
## A press this node took, so its release is taken too.
var _held: bool = false


func bind(p_tags: ReactionTags, p_target: Callable) -> void:
	tags = p_tags
	target = p_target


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
