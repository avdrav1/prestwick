class_name BuildPalette
extends PanelContainer
## The Build-mode HUD bar: the 9 surfaces, `oob` included (D9; each with its tile art, so the
## colorblind pattern shows on the button), raise and lower, the tee and cup tools (E2-S3),
## Buy land (E6-S5), the Clubhouse tool (E5-S10: a click moves it, a right-click turns its
## door), brush 1/3/5 and undo. E5-S10: buttons keep BUTTON_SIDE_MARGIN px each side (6 before).
## E5-S13: the surface icons draw SURFACE_ICON_WIDTH px wide (64 before), so the whole bar, Buy
## land and Clubhouse shown, fits a 1280 px window with a gutter at both ends. A view onto a BuildTool:
## buttons set the tool, and the tool's settings_changed keeps the buttons in step.
## Buttons are made in code from CourseBuilder.PALETTE and BuilderTuning.brush_sizes.

## Surface buttons in CourseBuilder.PALETTE order.
var surface_buttons: Array[Button] = []
var raise_button: Button
var lower_button: Button
var tee_button: Button
var cup_button: Button
var buy_button: Button
## E5-S10: the Clubhouse tool.
var clubhouse_button: Button
## Brush buttons in BuilderTuning.brush_sizes order.
var brush_buttons: Array[Button] = []
var undo_button: Button

## Each button's left and right content margin, px (E5-S10; the top and bottom keep 6).
const BUTTON_SIDE_MARGIN: int = 3
## E5-S13: the surface buttons' tile art width, px (the 64 x 32 tile scaled to 56 x 28).
const SURFACE_ICON_WIDTH: int = 56
## E5-S13: the least space left between the bar and either side of a 1280 px window.
const MIN_GUTTER: int = 16
## E5-S13: the bar's height, px, as it was with 64 px icons, kept so the free view the camera
## frames holes in (Main.free_view_rects) does not change with the smaller icons.
const BAR_HEIGHT: int = 90

## Selected buttons get this border so the current tool and brush read at a glance.
@export var selected_border: Color = Color(1.0, 0.97, 0.8)

var _tool: BuildTool
var _normal_style: StyleBoxFlat
var _selected_style: StyleBoxFlat
var _tools_group := ButtonGroup.new()
var _brush_group := ButtonGroup.new()
var _brush_sizes: PackedInt32Array


func _ready() -> void:
	_normal_style = StyleBoxFlat.new()
	_normal_style.bg_color = Color(0.12, 0.12, 0.14)
	_normal_style.set_content_margin_all(6)
	_normal_style.content_margin_left = BUTTON_SIDE_MARGIN
	_normal_style.content_margin_right = BUTTON_SIDE_MARGIN
	_selected_style = _normal_style.duplicate() as StyleBoxFlat
	_selected_style.bg_color = Color(0.22, 0.22, 0.26)
	_selected_style.border_color = selected_border
	_selected_style.set_border_width_all(2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	var art := TileArt.load_default()
	for s: Surface.Type in CourseBuilder.PALETTE:
		var b := _toggle(row, Surface.name_of(s).replace("_", " "), _tools_group)
		b.icon = art.surface_texture(StringName(Surface.name_of(s)))
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_constant_override("icon_max_width", SURFACE_ICON_WIDTH)
		b.custom_minimum_size = Vector2(SURFACE_ICON_WIDTH, BAR_HEIGHT)
		b.tooltip_text = "Paint %s" % Surface.name_of(s)
		b.pressed.connect(func() -> void: _tool.select_surface(s))
		surface_buttons.append(b)
	row.add_child(VSeparator.new())
	raise_button = _toggle(row, "Raise", _tools_group)
	raise_button.pressed.connect(func() -> void: _tool.select_tool(BuildTool.Tool.RAISE))
	lower_button = _toggle(row, "Lower", _tools_group)
	lower_button.pressed.connect(func() -> void: _tool.select_tool(BuildTool.Tool.LOWER))
	row.add_child(VSeparator.new())
	tee_button = _toggle(row, "Tee", _tools_group)
	tee_button.tooltip_text = "Place the hole's tee"
	tee_button.pressed.connect(func() -> void: _tool.select_tool(BuildTool.Tool.TEE))
	cup_button = _toggle(row, "Cup", _tools_group)
	cup_button.tooltip_text = "Place the hole's cup"
	cup_button.pressed.connect(func() -> void: _tool.select_tool(BuildTool.Tool.CUP))
	row.add_child(VSeparator.new())
	buy_button = _toggle(row, "Buy land", _tools_group)
	buy_button.tooltip_text = "Buy the parcel under the cursor (it must touch your land)"
	buy_button.pressed.connect(func() -> void: _tool.select_tool(BuildTool.Tool.BUY))
	row.add_child(VSeparator.new())
	clubhouse_button = _toggle(row, "Clubhouse", _tools_group)
	clubhouse_button.tooltip_text = "Click to move the clubhouse, where guests arrive and leave (free); right-click or R to turn its door"
	clubhouse_button.pressed.connect(func() -> void: _tool.select_tool(BuildTool.Tool.CLUBHOUSE))
	row.add_child(VSeparator.new())
	var brush_label := Label.new()
	brush_label.text = "Brush"
	row.add_child(brush_label)
	_brush_sizes = BuilderTuning.load_default().brush_sizes
	for size: int in _brush_sizes:
		var b := _toggle(row, str(size), _brush_group)
		b.custom_minimum_size = Vector2(32, 0)
		b.tooltip_text = "%dx%d brush ([ and ] step the brush)" % [size, size]
		b.pressed.connect(func() -> void: _tool.brush_size = size)
		brush_buttons.append(b)
	row.add_child(VSeparator.new())
	undo_button = Button.new()
	undo_button.text = "Undo"
	undo_button.tooltip_text = "Undo (Ctrl+Z)"
	undo_button.focus_mode = Control.FOCUS_NONE
	undo_button.pressed.connect(func() -> void: _tool.undo())
	row.add_child(undo_button)


## Shows or hides Buy land (E6-S6: hidden in New sandbox, where every parcel is owned). Hiding
## it while it is the selected tool steps the tool back to painting its surface.
func set_buying(on: bool) -> void:
	buy_button.visible = on
	if _tool != null:
		_tool.buying = on
	if not on and _tool != null and _tool.tool == BuildTool.Tool.BUY:
		_tool.select_surface(_tool.surface)


## E5-S6: the bar is in the keyboard's reach (HudFocus: F6, then the arrows and Space or Enter),
## and Q and E step the tool, [ and ] the brush, without it (BuildTool).

## Drives `tool` from now on and shows its current settings.
func bind(tool: BuildTool) -> void:
	_tool = tool
	_tool.settings_changed.connect(_sync)
	_sync()


## Shows the tool's settings. set_pressed_no_signal skips the ButtonGroup, so every button
## in a group is set explicitly.
func _sync() -> void:
	if _tool == null:
		return
	var on: Button = null
	match _tool.tool:
		BuildTool.Tool.PAINT:
			var i: int = CourseBuilder.PALETTE.find(_tool.surface)
			on = surface_buttons[i] if i >= 0 else null
		BuildTool.Tool.RAISE:
			on = raise_button
		BuildTool.Tool.LOWER:
			on = lower_button
		BuildTool.Tool.TEE:
			on = tee_button
		BuildTool.Tool.CUP:
			on = cup_button
		BuildTool.Tool.BUY:
			on = buy_button
		BuildTool.Tool.CLUBHOUSE:
			on = clubhouse_button
	for b: BaseButton in _tools_group.get_buttons():
		b.set_pressed_no_signal(b == on)
	var n: int = _brush_sizes.find(_tool.brush_size)
	for i: int in brush_buttons.size():
		brush_buttons[i].set_pressed_no_signal(i == n)


func _toggle(parent: Control, text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	for state: StringName in [&"normal", &"hover", &"disabled"]:
		b.add_theme_stylebox_override(state, _normal_style)
	for state: StringName in [&"pressed", &"hover_pressed"]:
		b.add_theme_stylebox_override(state, _selected_style)
	parent.add_child(b)
	return b
