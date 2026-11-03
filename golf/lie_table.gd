class_name LieTable
extends Resource
## Lie numbers (docs/design.md Swing, Shot model; D14), in golf/lies.tres. Tuned with
## /balance lies (uphill_k, sidehill_deg) and /balance surfaces (the rough multiplier).

const DEFAULT_PATH := "res://golf/lies.tres"

## Carry multiplier per Surface.Type, in enum order (the Distance column). Rough is one fixed
## value from 0.8 to 0.9, never rolled. Green is 1.0 because only the putter plays there,
## which no lie touches. Water, trees and oob are 1.0: a ball never rests there (E2-S6).
@export var surface_multiplier: PackedFloat32Array = PackedFloat32Array(
		[1.0, 0.85, 1.0, 1.0, 0.5, 1.0, 1.0, 1.0, 1.0])
## Carry lost per step of rise ahead: carry × (1 - uphill_k × rise) for a rise above 0.
@export var uphill_k: float = 0.037
## Degrees the launch heading turns toward the lower side per step of tilt.
@export var sidehill_deg: float = 2.9
## How far ahead of the ball the rise is read, yards (D14: 5).
@export var ahead_yd: float = 5.0
## How far to each side of the ball the tilt is read, yards (D14: 5, a 10 yd window).
@export var side_yd: float = 5.0


static func load_default() -> LieTable:
	return load(DEFAULT_PATH) as LieTable


func multiplier_for(surface: Surface.Type) -> float:
	return surface_multiplier[surface]


## Reads the lie of a ball resting at `at` (yards), aimed at `aim_deg` (degrees from +x
## toward +y, as Ball.launch_velocity). Heights come from HeightField.height_at, in steps.
## The projection (course/iso.gd) draws +y clockwise from +x, so the player's left on screen
## is the aim minus 90 degrees, and a positive turn (toward +heading) goes to the right.
func measure(field: HeightField, at: Vector2, aim_deg: float) -> Lie:
	var lie := Lie.new()
	lie.surface = field.surface_at(at.x, at.y)
	lie.surface_multiplier = multiplier_for(lie.surface)
	var aim := Vector2.RIGHT.rotated(deg_to_rad(aim_deg))
	var left := aim.rotated(-PI / 2.0)
	var here := _steps(field, at)
	lie.rise = _steps(field, at + aim * ahead_yd) - here
	lie.tilt = _steps(field, at + left * side_yd) - _steps(field, at - left * side_yd)
	if lie.rise > 0.0:
		lie.uphill_multiplier = maxf(0.0, 1.0 - uphill_k * lie.rise)
	# Left higher (tilt > 0) turns right (+heading); right higher turns left.
	lie.turn_deg = sidehill_deg * lie.tilt
	return lie


## A flat 1.0 lie of `surface` with no slope: what the putter and the aim marker's
## "no lie" comparison use.
func flat(surface: Surface.Type) -> Lie:
	var lie := Lie.new()
	lie.surface = surface
	lie.surface_multiplier = multiplier_for(surface)
	return lie


## Problems with the table, empty when it is usable.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if surface_multiplier.size() != Surface.COUNT:
		errors.append("expected %d surface multipliers, got %d" % [Surface.COUNT, surface_multiplier.size()])
	for i in surface_multiplier.size():
		if surface_multiplier[i] <= 0.0 or surface_multiplier[i] > 1.0:
			errors.append("%s: multiplier must be in (0, 1]" % Surface.name_of(i))
	if ahead_yd <= 0.0 or side_yd <= 0.0:
		errors.append("windows must be positive")
	return errors


func _steps(field: HeightField, p: Vector2) -> float:
	return field.height_at(p.x, p.y) / field.yards_per_step
