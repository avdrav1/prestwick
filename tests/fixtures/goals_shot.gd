class_name GoalsShot
extends Node2D
## Screenshot fixture for E10-S1: a New course (seed 7) with its goal checklist part-way: hole 1
## placed, greened and open, guests arrived, so the next goal is Buy a parcel. GOALS_SHOT picks
## the view: `mid` (the default) the expanded list, `line` folded to its one line, `buy` the Buy land tool picked (the land list
## takes the column's room), `start` the
## course as it opens.
##   GOALS_SHOT=line scripts/screenshot.sh tests/fixtures/goals_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TEE := Vector2i(51, 60)
const CUP := Vector2i(76, 60)


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.start_seed = 7
	add_child(main)
	main.guest_sim.set_process(false)
	var view: String = OS.get_environment("GOALS_SHOT")
	if view == "start":
		return
	var b: CourseBuilder = main.build_tool.builder
	for x: int in range(TEE.x - 1, CUP.x + 3):
		for y: int in range(TEE.y - 2, TEE.y + 3):
			b.paint(Vector2i(x, y), Surface.Type.FAIRWAY, 1)
	b.paint(TEE, Surface.Type.TEE, 1)
	b.paint(CUP, Surface.Type.GREEN, 3)
	b.place_tee(1, TEE, 3)
	b.place_cup(1, CUP)
	main.guest_sim.guest_arrived.emit(null)
	main.frame_first_hole()
	if view == "line":
		main.goals_panel.set_collapsed(true)
	elif view == "buy":
		main.build_tool.select_tool(BuildTool.Tool.BUY)
