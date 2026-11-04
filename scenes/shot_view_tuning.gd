class_name ShotViewTuning
extends Resource
## Designer-tuned numbers for the drawn shot (scenes/shot_view.gd). Loaded from
## res://scenes/shot_view_tuning.tres.

const PATH: String = "res://scenes/shot_view_tuning.tres"

## E2-S13: a ball that stops in water or OB stays drawn where it went in for this many
## seconds before it appears at its drop point and the shot counts as at rest.
@export var hazard_show_time: float = 0.8
## E6-S16: the OB cue's slash reaches this many times the ring's radius from its centre each
## way, so it runs past the ring and reads round the ball (HazardCue.ob_slash).
@export var ob_slash_reach: float = 1.8
## E6-S27: the ball's radius never draws smaller than this many screen px, so at 0.5x it
## does not shrink to a 2 px dot (ShotView.ball_draw_radius). Above it the ball scales with
## the map (ShotView.ball_radius at 1x).
@export var ball_min_screen_radius: float = 3.0


static func load_default() -> ShotViewTuning:
	return load(PATH) as ShotViewTuning
