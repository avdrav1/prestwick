class_name MoneyPanel
extends PanelContainer
## The balance on the HUD, in Build and Play (E4-S2, D57; docs/design.md Economy and time): one
## line, "Balance: $4,400", "Balance: unlimited" (New sandbox), or below 0 "Balance: -$120,
## building paused" in the refusal colour (CourseBuilder.money_refusal). It replaced the land
## panel's land budget line, since parcels and building come out of the one balance. A view
## onto the builder: it never writes the course. Main hands it every fresh builder (watch).

## A balance below 0: the land panel's refusal colour (a light flag_red).
@export var owing_font_color: Color = Color8(240, 160, 150)

var balance_label: Label
var builder: CourseBuilder


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	balance_label = Label.new()
	balance_label.name = "Balance"
	box.add_child(balance_label)
	refresh()


## Follows `b` (Main.show_course's fresh builder) from now on.
func watch(b: CourseBuilder) -> void:
	builder = b
	b.money_changed.connect(func(_balance: int) -> void: refresh())
	refresh()


## The balance line for `b`'s balance now.
static func balance_text(b: CourseBuilder) -> String:
	if b == null:
		return ""
	if b.has_unlimited_money():
		return "Balance: unlimited"
	var line := "Balance: %s" % LandPrices.money(b.balance())
	return line + ", building paused" if b.balance() < 0 else line


func refresh() -> void:
	if balance_label == null:
		return
	balance_label.text = balance_text(builder)
	if builder != null and not builder.has_unlimited_money() and builder.balance() < 0:
		balance_label.add_theme_color_override("font_color", owing_font_color)
	else:
		balance_label.remove_theme_color_override("font_color")
