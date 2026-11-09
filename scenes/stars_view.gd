class_name StarsView
extends Control
## E4-S5: the course rating as five stars on the HUD (SimSpeedPanel), filled to `stars` in half
## stars (EconomyTuning.stars_of): gold where earned, a dim outline-coloured star where not.

const COUNT: int = 5
## One star's height and width, px, and the gap between stars.
const STAR_PX: float = 16.0
const GAP_PX: float = 3.0
## A star's inner radius over its outer.
const INNER_SHARE: float = 0.45
const FILL: Color = Color(0.98, 0.78, 0.25)
const EMPTY: Color = Color(1.0, 1.0, 1.0, 0.18)

## The stars shown, 0 to 5 by halves.
var stars: float = 0.0:
	set(v):
		if is_equal_approx(v, stars):
			return
		stars = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(COUNT * STAR_PX + (COUNT - 1) * GAP_PX, STAR_PX)
	mouse_filter = Control.MOUSE_FILTER_PASS


## The five-pointed star of outer radius `r` round `centre`, point up.
static func star_points(centre: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * INNER_SHARE
		pts.append(centre + Vector2(cos(a), sin(a)) * rr)
	return pts


## How much of star `i` (from 0) is filled at `p_stars`: 0, 0.5 or 1.
static func fill_of(i: int, p_stars: float) -> float:
	return clampf(p_stars - i, 0.0, 1.0)


func _draw() -> void:
	var top := (size.y - STAR_PX) / 2.0
	for i in COUNT:
		var x := i * (STAR_PX + GAP_PX)
		var pts := star_points(Vector2(x + STAR_PX / 2.0, top + STAR_PX / 2.0 + 1.0), STAR_PX / 2.0)
		draw_colored_polygon(pts, EMPTY)
		var f := fill_of(i, stars)
		if f >= 1.0:
			draw_colored_polygon(pts, FILL)
		elif f > 0.0:
			var half := PackedVector2Array([Vector2(x, top - 1.0), Vector2(x + STAR_PX * f, top - 1.0),
					Vector2(x + STAR_PX * f, top + STAR_PX + 2.0), Vector2(x, top + STAR_PX + 2.0)])
			for poly: PackedVector2Array in Geometry2D.intersect_polygons(pts, half):
				draw_colored_polygon(poly, FILL)
