extends Node
## Screenshot fixture for E1-S7: main in Play, the debug shot fired and frozen mid-flight
## (`flight_share` of the way to its predicted landing), so the PNG is the same every run.
##   scripts/screenshot.sh tests/fixtures/shot_preview.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## Share of the ticks to the predicted landing to play before freezing.
@export var flight_share: float = 0.5


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	add_child(main)
	main.set_mode(Main.Mode.PLAY)
	main.fire_debug_shot()
	var view := main.shot_view
	view.set_process(false)
	var to_landing := 0
	for p: Vector3 in view.prediction.path:
		to_landing += 1
		if p == view.prediction.landing:
			break
	view.advance(to_landing * flight_share / Ball.TICK_HZ)
	print("shot preview: tick %d of %d, ball %s, predicted landing tile %s, rest tile %s" % [
		view.ball.steps, view.prediction.ticks, view.ball.position,
		view.prediction.landing_tile, view.prediction.rest_tile])
