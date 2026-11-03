class_name Lie
extends RefCounted
## What the ground under a resting ball does to a full shot (D14), as LieTable.measure reads
## it. The putter ignores all of it.

var surface: Surface.Type = Surface.Type.FAIRWAY
## Steps of rise from the ball to the ground ahead along the aim (uphill above 0).
var rise: float = 0.0
## Steps of tilt across the aim: ground on the left minus ground on the right, so its sign
## names the higher side (left as the player sees it on screen, LieTable.measure).
var tilt: float = 0.0
## The surface's Distance column (rough 0.85, bunker 0.5).
var surface_multiplier: float = 1.0
## `1 - k × rise` for a rise above 0, else 1.
var uphill_multiplier: float = 1.0
## Degrees added to the launch heading, toward the lower side.
var turn_deg: float = 0.0


## The one product that scales a full club's carry (D14).
func carry_multiplier() -> float:
	return surface_multiplier * uphill_multiplier
