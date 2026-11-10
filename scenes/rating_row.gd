class_name RatingRow
extends HBoxContainer
## E4-S5: the course rating on the HUD, in Build and Play, on the mode label's line (so it adds no
## height to the left column and the Play feed stays put): five stars to the half star
## (StarsView) and "3.5 stars", the stars shown (GuestSim.stars, set at dusk since E4-S13, D59),
## and in its tooltip the mean now over the window and the points (GuestSim.rating, D58), which
## moves with every reaction.

var sim: GuestSim
var stars_view: StarsView
var rating_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	stars_view = StarsView.new()
	stars_view.name = "Stars"
	stars_view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(stars_view)
	rating_label = Label.new()
	rating_label.name = "RatingText"
	rating_label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(rating_label)
	if sim != null:
		refresh()


func bind(p_sim: GuestSim) -> void:
	sim = p_sim
	sim.rating_changed.connect(func(_r: float) -> void: refresh())
	sim.stars_changed.connect(func(_s: float) -> void: refresh())
	if is_node_ready():
		refresh()


## The stars shown and their line, and the mean now in the tooltip.
func refresh() -> void:
	if sim == null or stars_view == null:
		return
	var st := sim.stars()
	stars_view.stars = st
	rating_label.text = rating_text(st)
	var p := sim.economy.rating_points
	var tip := ("Rating %.2f now: the mean of the last %d guests' reactions (praise %d, neutral %d, " +
			"complaint %d). The stars move to it at dusk.") % [
			sim.rating(), sim.feed.window, int(p[0]), int(p[1]), int(p[2])]
	for c: Control in [stars_view, rating_label]:
		c.tooltip_text = tip


## "3 stars", "3.5 stars", "1 star".
static func rating_text(st: float) -> String:
	var n := ("%d" % int(st)) if is_equal_approx(st, roundf(st)) else ("%.1f" % st)
	return "%s star%s" % [n, "" if is_equal_approx(st, 1.0) else "s"]
