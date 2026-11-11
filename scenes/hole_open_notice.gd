class_name HoleOpenNotice
extends PanelContainer
## E8-S1 (D64): the short notice a hole gives as it opens itself, "Hole 1 is open: guests will
## play it" (CourseBuilder.opened_line), lighter than the save notice: no button, it takes no
## clicks or keys, and it goes by itself after HolePanelTuning.open_notice_s real seconds (a new
## opening restarts it with the new line). Centred near the bottom of the screen, over the map
## and above the Build palette, so it never covers the save notice at the top.

## Its bottom edge, px above the bottom of the screen (the Build palette is about 100 px tall).
const BOTTOM_MARGIN: float = 112.0

@export var tuning: HolePanelTuning

var label: Label
## Real seconds left until it hides (0 when hidden).
var time_left: float = 0.0


func _ready() -> void:
	if tuning == null:
		tuning = HolePanelTuning.load_default()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.name = "Text"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	hide()
	set_process(false)


## Shows `line` for open_notice_s seconds.
func show_line(line: String) -> void:
	label.text = line
	show()
	reset_size()
	size = get_combined_minimum_size()
	var view: Vector2 = get_viewport_rect().size
	position = Vector2((view.x - size.x) * 0.5, view.y - BOTTOM_MARGIN - size.y)
	time_left = tuning.open_notice_s
	set_process(true)


## The holes numbered `numbers` opened themselves (CourseBuilder.holes_opened).
func show_holes(numbers: Array[int]) -> void:
	if not numbers.is_empty():
		show_line(CourseBuilder.opened_line(numbers))


func _process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		hide()
		set_process(false)
