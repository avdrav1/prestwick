class_name HazardCue
extends RefCounted
## The shot's end cues, drawn by ShotView (the struck ball) and AimView (the aim marker), so
## both draw the same shapes (E6-S16). Each reads by shape, not hue or slash direction alone
## (colourblind rule), and each sits on an ink outline:
## - OB: a flag_red ring laid on the ground (2:1) and a slash through it that runs past the
##   ring both ways (ShotViewTuning.ob_slash_reach times its radius). ShotView draws the
##   ring under the ball and the slash over it, so the ball never covers the slash; the
##   slash leaves a gap round the ball (ob_slash_pieces), so the slash never covers the ball
##   either (E2-S13: the player sees where it stopped).
## - Water: two chalk splash rings, no slash.
## - Blocked (D20): a filled flag_red octagon standing upright (not laid 2:1 on the ground
##   as the rings are) with a level chalk bar across it, a "no entry" sign; no ring and no
##   slash.
## Sizes are screen px at 1x times `k`. ShotView passes screen_k(view scale), a fixed size
## on screen at every zoom; AimView passes its own marker k.

## The 2:1 ground ellipse: screen y is half the circle's.
const SQUASH: Vector2 = Vector2(1.0, 0.5)
## The water cue's inner ring, as a share of the outer.
const WATER_INNER: float = 0.6
## The blocked bar's half length, as a share of the octagon's radius.
const BAR_HALF: float = 0.55


## The `k` that keeps a shape a fixed size on screen at canvas scale `view_scale`.
static func screen_k(view_scale: float) -> float:
	return 1.0 / maxf(view_scale, 0.01)


## The OB slash's two screen ends: from lower left to upper right through `at`, reaching
## `reach` times the ring's radius `r` along the ring's own (2:1) diagonal.
static func ob_slash(at: Vector2, r: float, reach: float) -> PackedVector2Array:
	var d := Vector2(r, -r) * 0.7071 * reach * SQUASH
	return PackedVector2Array([at - d, at + d])


## The OB slash in two pieces with a gap of `gap` round `at`: [lower start, lower end,
## upper start, upper end]. The outer ends are ob_slash's; each inner end stops `gap` from
## `at`. With `gap` 0 or less the two pieces meet at `at`, one unbroken slash.
static func ob_slash_pieces(at: Vector2, r: float, reach: float, gap: float) -> PackedVector2Array:
	var s := ob_slash(at, r, reach)
	var dir := (s[1] - s[0]).normalized()
	var g := clampf(gap, 0.0, (s[1] - at).length())
	return PackedVector2Array([s[0], at - dir * g, at + dir * g, s[1]])


## The water cue's ring radii.
static func water_rings(r: float) -> PackedFloat32Array:
	return PackedFloat32Array([r, r * WATER_INNER])


## The blocked marker's octagon, screen points round `at`, upright.
static func blocked_outline(at: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		pts.append(at + Vector2(cos(a), sin(a)) * r)
	return pts


## The blocked marker's level bar, screen ends.
static func blocked_bar(at: Vector2, r: float) -> PackedVector2Array:
	var h := Vector2(r * BAR_HALF, 0.0)
	return PackedVector2Array([at - h, at + h])


## The OB ring (2:1) at `at` on `ci`.
static func draw_ob_ring(ci: CanvasItem, at: Vector2, r: float, k: float, red: Color,
		ink: Color) -> void:
	ci.draw_set_transform(at, 0.0, SQUASH)
	ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, ink, 6.0 * k)
	ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, red, 3.5 * k)
	ci.draw_set_transform(Vector2.ZERO)


## The OB slash at `at` on `ci`, drawn in screen space so its width is even. `gap` (in
## `ci` units) leaves the ball clear: the ink stops `gap` from `at` and the red 1.5 k short
## of the ink, so each inner end has its ink outline too. With `gap` 0 the slash is unbroken.
static func draw_ob_slash(ci: CanvasItem, at: Vector2, r: float, k: float, reach: float,
		red: Color, ink: Color, gap: float = 0.0) -> void:
	var cap := 1.5 * k
	var ink_s := ob_slash_pieces(at, r, reach, gap)
	var red_s := ob_slash_pieces(at, r, reach, gap + cap if gap > 0.0 else 0.0)
	var dir := (ink_s[3] - ink_s[0]).normalized() * cap
	if gap > 0.0:
		ci.draw_line(ink_s[0] - dir, ink_s[1], ink, 6.0 * k)
		ci.draw_line(ink_s[2], ink_s[3] + dir, ink, 6.0 * k)
		ci.draw_line(red_s[0], red_s[1], red, 3.0 * k)
		ci.draw_line(red_s[2], red_s[3], red, 3.0 * k)
	else:
		ci.draw_line(ink_s[0] - dir, ink_s[3] + dir, ink, 6.0 * k)
		ci.draw_line(red_s[0], red_s[3], red, 3.0 * k)


## The whole OB cue, ring then slash.
static func draw_ob(ci: CanvasItem, at: Vector2, r: float, k: float, reach: float,
		red: Color, ink: Color) -> void:
	draw_ob_ring(ci, at, r, k, red, ink)
	draw_ob_slash(ci, at, r, k, reach, red, ink)


## The water cue: two chalk rings (2:1) on ink.
static func draw_water(ci: CanvasItem, at: Vector2, r: float, k: float, chalk: Color,
		ink: Color) -> void:
	var rings := water_rings(r)
	ci.draw_set_transform(at, 0.0, SQUASH)
	ci.draw_arc(Vector2.ZERO, rings[0], 0.0, TAU, 32, ink, 4.0 * k)
	ci.draw_arc(Vector2.ZERO, rings[1], 0.0, TAU, 24, ink, 3.5 * k)
	ci.draw_arc(Vector2.ZERO, rings[0], 0.0, TAU, 32, chalk, 2.0 * k)
	ci.draw_arc(Vector2.ZERO, rings[1], 0.0, TAU, 24, chalk, 1.5 * k)
	ci.draw_set_transform(Vector2.ZERO)


## The blocked marker: a filled flag_red octagon on an ink outline with a chalk bar.
static func draw_blocked(ci: CanvasItem, at: Vector2, r: float, k: float, red: Color,
		ink: Color, chalk: Color) -> void:
	var oct := blocked_outline(at, r)
	ci.draw_colored_polygon(oct, red)
	var loop := oct.duplicate()
	loop.append(oct[0])
	ci.draw_polyline(loop, ink, 2.0 * k)
	var bar := blocked_bar(at, r)
	ci.draw_line(bar[0], bar[1], ink, 5.0 * k)
	ci.draw_line(bar[0], bar[1], chalk, 3.0 * k)
