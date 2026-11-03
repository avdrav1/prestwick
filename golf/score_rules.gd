class_name ScoreRules
extends Resource
## Scoring numbers (D12, docs/design.md Swing, Scoring), in golf/score_rules.tres.

const DEFAULT_PATH := "res://golf/score_rules.tres"

## The ball is picked up when strokes plus penalty strokes reach par times this, without
## the ball holed (D12: double par).
@export var pickup_par_multiple: int = 2


static func load_default() -> ScoreRules:
	return load(DEFAULT_PATH) as ScoreRules
