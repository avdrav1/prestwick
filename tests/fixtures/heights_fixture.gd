class_name HeightsFixture
extends SceneTree
## A 20x20 course that uses every height 0 to 7 and every surface, shaped to stress the
## renderer's draw order: a stepped pyramid, a 7-step pillar on flat ground, a staircase
## ridge, a walled pit and a cliff. Source of courses/heights_20x20.json.
##
## Regenerate the file (never hand-edit its tiles):
##   godot --headless --path . -s res://tests/fixtures/heights_fixture.gd

const SIZE: int = 20
const PATH: String = "res://courses/heights_20x20.json"


func _initialize() -> void:
	var err: Error = CourseSave.save_file(build(), PATH)
	print("heights fixture: %s %s" % [PATH, error_string(err)])
	quit(0 if err == OK else 1)


static func build() -> CourseData:
	var c := CourseData.create(SIZE, SIZE, Surface.Type.ROUGH, 0)
	for y: int in SIZE:
		for x: int in SIZE:
			var h: int = 0
			var s: Surface.Type = Surface.Type.ROUGH
			# Stepped pyramid, peak 7 at (5, 5), green on top, fairway skirt.
			var d: int = maxi(absi(x - 5), absi(y - 5))
			if d <= 6:
				h = 7 - d
				s = Surface.Type.GREEN if d <= 1 else Surface.Type.FAIRWAY
			# Pillar: one tile at 7 on flat ground, trees around it.
			if x == 15 and y == 4:
				h = 7
				s = Surface.Type.TEE
			elif absi(x - 15) <= 1 and absi(y - 4) <= 1:
				s = Surface.Type.TREES
			# Staircase ridge along y = 14..15, rising one step every two tiles.
			if (y == 14 or y == 15) and x >= 1 and x <= 16:
				h = mini((x - 1) / 2, CourseData.MAX_HEIGHT)
				s = Surface.Type.CART_PATH if y == 14 else Surface.Type.FAIRWAY
			# Walled pit: a 5x5 plateau at 4 with a water hole at 0 in the middle.
			if absi(x - 15) <= 2 and absi(y - 9) <= 2:
				h = 4
				s = Surface.Type.BUNKER
				if x == 15 and y == 9:
					h = 0
					s = Surface.Type.WATER
			# Cliff: the last row is a 6-step wall above the plain, oob along the far edge.
			if y == SIZE - 1:
				h = 6 if x >= 10 else 0
				s = Surface.Type.OOB if x >= 10 else Surface.Type.ROUGH
			c.set_tile(x, y, h, s)
	c.set_info("Heights 20x20", "tests", "")
	return c
