class_name TilePicker
extends RefCounted
## Screen-to-tile picking on raised ground: which tile the player sees under the cursor.
## A reader only. Uses the one projection in course/iso.gd.
##
## A tile at height h is drawn as a solid column: its top diamond at h plus the risers below
## it, which together are exactly what the diamond sweeps rising from 0 to h. Riser faces the
## renderer skips are hidden behind a nearer neighbor's column, so testing whole columns
## front to back (by depth i + j) gives the frontmost drawn piece. The pick is that piece's
## tile: a top face picks its tile, and a wall picks the hill it belongs to. A tile partly
## hidden behind a nearer hill is picked only where its top still shows.

## Returned when no tile of the course is under the point.
const NONE: Vector2i = Vector2i(-1, -1)


## The tile drawn frontmost at `screen` (CourseView local space), or NONE. `heights` overrides
## the course height of the tiles it holds (tile -> height), to pick against ground as it was.
static func pick(course: CourseData, screen: Vector2, heights: Dictionary = {}) -> Vector2i:
	# Rising one step moves a point's tile coordinates by (+0.5, +0.5), so only tiles on the
	# diagonal from the height-0 tile up to MAX_HEIGHT / 2 tiles further can hold the point.
	var t0: Vector2 = Iso.screen_to_tile(screen, 0.0)
	var reach: float = CourseData.MAX_HEIGHT * 0.5
	var best := NONE
	var best_depth: int = -1
	for y: int in range(maxi(floori(t0.y - 0.5), 0), mini(ceili(t0.y + reach + 0.5), course.height - 1) + 1):
		for x: int in range(maxi(floori(t0.x - 0.5), 0), mini(ceili(t0.x + reach + 0.5), course.width - 1) + 1):
			if x + y <= best_depth:
				continue
			var cell := Vector2i(x, y)
			var h: int = heights.get(cell, course.get_height(x, y))
			if column_contains(cell, h, screen):
				best = Vector2i(x, y)
				best_depth = x + y
	return best


## True when `screen` lies in the column of tile `cell` standing at `h`: the union of its
## diamond raised to every height from 0 to h.
static func column_contains(cell: Vector2i, h: int, screen: Vector2) -> bool:
	# At height t the point sits at tile position t0 + (t, t) / 2. It is in the cell's diamond
	# while both coordinates are within half a tile of the center; solve that for t in [0, h].
	var t0: Vector2 = Iso.screen_to_tile(screen, 0.0)
	var lo: float = maxf(0.0, maxf(2.0 * (cell.x - 0.5 - t0.x), 2.0 * (cell.y - 0.5 - t0.y)))
	var hi: float = minf(float(h), minf(2.0 * (cell.x + 0.5 - t0.x), 2.0 * (cell.y + 0.5 - t0.y)))
	return lo <= hi
