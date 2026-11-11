class_name SwingReadoutTuning
extends Resource
## E10-S3: the numbers of the swing bar's yard labels, live readout and live landing marker,
## in scenes/swing_readout_tuning.tres. The yards themselves come from ShotModel (club, power
## and lie), never from here.

const DEFAULT_PATH := "res://scenes/swing_readout_tuning.tres"

## The bar positions (1.0 = 100%) labelled with their yards, below SwingTuning.max_power, which
## is always labelled too ("max").
@export var label_powers: PackedFloat32Array = PackedFloat32Array([0.5, 1.0])
## While the power is set, the live landing marker is predicted again once the bar has moved
## this far (a share of a full swing) from the power it shows.
@export var preview_power_step: float = 0.01
## A putt shorter than this (yards) reads in feet, longer ones in yards.
@export var putt_feet_below_yd: float = 10.0


static func load_default() -> SwingReadoutTuning:
	return load(DEFAULT_PATH) as SwingReadoutTuning
