class_name HoleScore
extends RefCounted
## One hole's stroke-play score (D12, docs/design.md Swing, Scoring), with no scene, so the
## Play HUD and E3 guests share it. Feed it each stroke's outcome with record_stroke (the
## Ball's penalty_strokes and holed); it picks the ball up when strokes plus penalty strokes
## reach the limit (double par) without the ball holed. A picked-up score records the limit.

var par: int
var rules: ScoreRules
## Swings struck.
var strokes: int = 0
## Penalty strokes (water and OB drops, D15).
var penalty_strokes: int = 0
var holed: bool = false
## True when the limit was reached without the ball holed.
var picked_up: bool = false


func _init(p_par: int, p_rules: ScoreRules = null) -> void:
	par = p_par
	rules = p_rules if p_rules != null else ScoreRules.load_default()


## The most strokes, penalties included, before the ball is picked up.
func limit() -> int:
	return par * rules.pickup_par_multiple


## Counts one stroke, its penalty strokes, and whether it holed the ball. Ignored once the
## hole is finished.
func record_stroke(penalty: int, p_holed: bool) -> void:
	if is_finished():
		return
	strokes += 1
	penalty_strokes += penalty
	if p_holed:
		holed = true
	elif strokes + penalty_strokes >= limit():
		picked_up = true


func is_finished() -> bool:
	return holed or picked_up


## The hole's score: strokes plus penalty strokes, or the limit once picked up (D12).
func total() -> int:
	if picked_up:
		return limit()
	return strokes + penalty_strokes


## The score against par: negative under, 0 level.
func to_par() -> int:
	return total() - par


## "E" for level, "+2" over, "-1" under.
static func to_par_text(n: int) -> String:
	if n == 0:
		return "E"
	return "%+d" % n
