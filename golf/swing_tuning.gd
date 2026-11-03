class_name SwingTuning
extends Resource
## The three-click swing's numbers (docs/design.md Swing, E2-S7), in golf/swing_tuning.tres.
## Bar positions are shares of a full swing: 1.0 is 100%, 0 is the accuracy centre.
## E2-S9's playtest tunes them by hand.

const DEFAULT_PATH := "res://golf/swing_tuning.tres"

## Seconds the bar takes from 0 to 100% at bar speed 1.0. It runs on to `max_power`.
@export var fill_time: float = 1.2
## Where the power bar stops and locks if the player never clicks (110%, overswing).
@export var max_power: float = 1.1
## The bar's left end, past the accuracy centre: the return stops here and the swing is a
## late shank if the third click never comes.
@export var bar_min: float = -0.3
## Half the accuracy zone's width at 100% power or less: a third click within this of the
## centre curves the shot, outside it shanks.
@export var zone_half: float = 0.2
## Hook or slice per 10% off centre, degrees (design doc: 2 per 10%).
@export var deg_per_10pct: float = 2.0
## Overswing penalty: above 100% the zone narrows linearly, to this share of `zone_half` at
## `max_power`.
@export var overswing_zone_scale: float = 0.5
## A shank leaves this many degrees off the aim, toward the side of the miss.
@export var shank_deg: float = 30.0
## A shank's power (a share of carry, or of the putt mapping) is multiplied by this.
@export var shank_power: float = 0.5
## Bar speed setting (accessibility): the fill rate is `bar_speed / fill_time`.
@export var bar_speed_default: float = 1.0
@export var bar_speed_min: float = 0.5
@export var bar_speed_max: float = 1.5
## Degrees the aim turns per press of an aim key.
@export var aim_key_step_deg: float = 1.0
## After an aim key turns the aim, the mouse takes the aim back only once it has moved this
## many screen pixels (viewport space) from where it was, so a small nudge of the mouse does
## not throw away a key fine-tune.
@export var mouse_reaim_px: float = 24.0
## The putter's aim marker (D21, PuttAim): the solve for the power whose putt rests nearest
## the cup stops once a putt's rest is this close to the cup along the line (yards), or after
## this many predicted putts.
@export var putt_aim_tolerance_yd: float = 0.1
@export var putt_aim_max_runs: int = 8


static func load_default() -> SwingTuning:
	return load(DEFAULT_PATH) as SwingTuning
