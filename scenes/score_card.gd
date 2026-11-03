class_name ScoreCard
extends PanelContainer
## The Play-mode scorecard (E2-S8): the hole, its par, the strokes so far (penalty strokes
## included, and named), the total to par once the hole is finished, and how it ended. A
## picked-up ball shows double par (D12). A view onto a SwingControl's HoleScore; refresh()
## follows `changed`.

var title_label: Label
var par_label: Label
var strokes_label: Label
var to_par_label: Label
var status_label: Label

var _control: SwingControl


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	title_label = _label(box, 18)
	par_label = _label(box)
	strokes_label = _label(box)
	to_par_label = _label(box)
	status_label = _label(box)
	refresh()


## Follows `control` from now on.
func bind(control: SwingControl) -> void:
	_control = control
	_control.changed.connect(refresh)
	refresh()


## Shows the control's score as it is now.
func refresh() -> void:
	if title_label == null:
		return
	var score: HoleScore = _control.score if _control != null else null
	if score == null:
		title_label.text = "No hole"
		par_label.text = "Place a tee and a cup in Build."
		strokes_label.text = ""
		to_par_label.text = ""
		status_label.text = ""
		return
	title_label.text = "Hole %d" % _control.hole.number
	par_label.text = "Par %d" % score.par
	strokes_label.text = strokes_text(score)
	to_par_label.text = total_text(score)
	status_label.text = status_text(score)


## "Strokes 3", or "Strokes 4 (1 penalty)": every stroke the score counts. A picked-up
## ball shows double par (D12).
static func strokes_text(score: HoleScore) -> String:
	var text := "Strokes %d" % score.total()
	if score.penalty_strokes == 1:
		text += " (1 penalty)"
	elif score.penalty_strokes > 1:
		text += " (%d penalties)" % score.penalty_strokes
	return text


## The total to par once the hole is finished ("Total -1", "Total E"); while it is in play
## no hole is finished, so there is no total yet.
static func total_text(score: HoleScore) -> String:
	if not score.is_finished():
		return "Total: in play"
	return "Total %s" % HoleScore.to_par_text(score.to_par())


## How the hole stands: in play (and the pick-up limit), holed, or picked up.
static func status_text(score: HoleScore) -> String:
	if score.holed:
		return "Holed in %d.  Tab: back to Build" % score.total()
	if score.picked_up:
		return "Picked up at %d (double par).  Tab: back to Build" % score.limit()
	return "Pick up at %d" % score.limit()


func _label(parent: Node, size: int = 14) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l
