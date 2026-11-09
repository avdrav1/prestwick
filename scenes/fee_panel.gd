class_name FeePanel
extends PanelContainer
## E4-S6: the fee slider, the player's one pricing decision (docs/design.md Economy and time; D56,
## D58), in Build under the speed panel. "Fee $60" over a slider from $0 to the ceiling ($25 a
## star at the stars shown, GuestSim.fee_ceiling), so it cannot pass it, and "of $75". The
## slider sets GuestSim.fee; a falling rating that lowers the ceiling under the fee moves the
## slider's end and the fee with it (GuestSim.fee_changed, rating_changed). Its tooltip says how
## guests take the price (D58's curve).

var sim: GuestSim
var fee_label: Label
var ceiling_label: Label
var slider: HSlider


func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	fee_label = Label.new()
	fee_label.name = "Fee"
	fee_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fee_label)
	ceiling_label = Label.new()
	ceiling_label.name = "Ceiling"
	row.add_child(ceiling_label)
	slider = HSlider.new()
	slider.name = "Slider"
	slider.min_value = 0.0
	slider.step = 1.0
	slider.rounded = true
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size = Vector2(0, 20)
	slider.value_changed.connect(_on_slider)
	box.add_child(slider)
	if sim != null:
		refresh()


func bind(p_sim: GuestSim) -> void:
	sim = p_sim
	sim.fee_changed.connect(func(_f: int) -> void: refresh())
	sim.rating_changed.connect(func(_r: float) -> void: refresh())
	if is_node_ready():
		refresh()


func _on_slider(v: float) -> void:
	if sim != null:
		sim.set_fee(roundi(v))
		refresh()


## The slider's end, its knob and the two labels from the sim's fee and ceiling now.
func refresh() -> void:
	if sim == null or slider == null or sim.fee < 0:
		return
	var ceiling := sim.fee_ceiling()
	slider.set_block_signals(true)
	slider.max_value = ceiling
	slider.value = sim.fee
	slider.set_block_signals(false)
	fee_label.text = "Fee %s" % LandPrices.money(sim.fee)
	ceiling_label.text = "of %s" % LandPrices.money(ceiling)
	var e := sim.economy
	var full := floori(ceiling * e.fee_full_arrivals_share)
	var tip := ("Green fee a round. Up to %s every guest comes; above it fewer, %d%% of them at the " +
			"%s ceiling (%s a star). %d guests tomorrow at this fee.") % [LandPrices.money(full),
			roundi(e.ceiling_arrivals_share * 100.0), LandPrices.money(ceiling),
			LandPrices.money(e.fee_ceiling_per_star), sim.arrivals_today()]
	for c: Control in [fee_label, ceiling_label, slider]:
		c.tooltip_text = tip
