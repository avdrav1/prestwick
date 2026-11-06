class_name ContourTracer
extends RefCounted
## Topographic contour lines of the ground the ball rolls on (E3-S56): the lines where
## HeightField.height_at equals a level, over a window of tiles. A reader only: it reads the
## HeightField (and so CourseData) and never writes either.
##
## Marching squares on the tile-centre grid. height_at is bilinear between tile centres, so
## along a cell's edge it is linear and a crossing found by linear interpolation lies exactly
## on the level; inside a cell the level line is a hyperbola segment, which `subdiv` sub-cells a
## side approximate with straight chords (each sub-cell is still exactly bilinear, so its saddle
## is decided by its centre value, the mean of its corners).
##
## Heights are whole steps, so a whole-step level runs along a terrace of that height. A level
## is traced a hair below itself (LEVEL_EPS), so a terrace at the level counts as on or above
## it and its line hugs the terrace's falling edge, through the centres of its edge tiles, where
## the ground starts to fall: never along both sides of a flat terrace, and a flat window has no
## lines at all.
##
## Lines are polylines in yards (the HeightField's space: x, y from the map corner, +y down as
## the green view draws it), oriented so the higher ground is on the left of the direction of
## travel (left of d is (d.y, -d.x)) and the lower on the right, where downhill ticks go
## (ticks). A closed loop repeats its first point at its end. Lines are clipped to the window's
## own tiles; the grid reaches one tile past the window (clamped to the map, and out to the map's
## edge there, where the edge height holds) so the half tile between the window's edge and its
## outer tile centres is traced too.

## Steps below the level the threshold sits (see above).
const LEVEL_EPS: float = 1e-4
## A line shorter than this, yards, is dropped (the speck a lone summit tile's level leaves).
const MIN_LENGTH_YD: float = 0.05


## The lines at `level` (steps) over the tiles of `window`, as trace_levels.
static func trace(field: HeightField, level: float, window: Rect2i, subdiv: int = 1) -> Array[PackedVector2Array]:
	var by_level := trace_levels(field, PackedFloat32Array([level]), window, subdiv)
	var out: Array[PackedVector2Array] = []
	out.assign(by_level[0])
	return out


## Every whole multiple of `interval` (plus `offset`) strictly between `low` and `high` steps,
## and `high` itself when it is one (the top terrace's edge), from the lowest up: the levels a
## window spanning `low` to `high` can have lines at.
static func levels_between(low: float, high: float, interval: float, offset: float = 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if interval <= 0.0 or high <= low:
		return out
	var k := floori((low - offset) / interval) + 1
	while offset + k * interval <= high + 1e-6:
		out.append(offset + k * interval)
		k += 1
	return out


## The lowest and highest tile heights, steps, of `window` grown by one tile (clamped to the
## map): every level a trace of `window` can cross lies between them.
static func height_range(field: HeightField, window: Rect2i) -> Vector2i:
	var c := field.course
	var g := window.grow(1).intersection(Rect2i(0, 0, c.width, c.height))
	var lo := CourseData.MAX_HEIGHT
	var hi := 0
	for y: int in range(g.position.y, g.end.y):
		for x: int in range(g.position.x, g.end.x):
			var h := c.get_height(x, y)
			lo = mini(lo, h)
			hi = maxi(hi, h)
	return Vector2i(lo, hi)


## The lines at each of `levels` (steps) over the tiles of `window`: one Array of polylines
## (PackedVector2Array, yards) per level, in the order given. `subdiv` sub-cells a side per
## tile-centre cell (1 is the plain grid).
static func trace_levels(field: HeightField, levels: PackedFloat32Array, window: Rect2i, subdiv: int = 1) -> Array:
	var c := field.course
	var out: Array = []
	for _l in levels.size():
		out.append([] as Array[PackedVector2Array])
	var nodes := window.grow(1).intersection(Rect2i(0, 0, c.width, c.height))
	if levels.is_empty() or nodes.size.x <= 0 or nodes.size.y <= 0 or window.size.x <= 0 or window.size.y <= 0:
		return out
	var sub := maxi(subdiv, 1)
	var ypt := field.yards_per_tile
	var yps := field.yards_per_step
	# Node lines, yards: the tile centres, and the map's edge where the grid meets it (past the
	# outer centre the edge height holds, so that strip is flat across and still bilinear).
	var xs := _node_lines(nodes.position.x, nodes.end.x, c.width, ypt)
	var ys := _node_lines(nodes.position.y, nodes.end.y, c.height, ypt)
	var nw := xs.size()
	var nh := ys.size()
	if nw < 2 or nh < 2:
		return out
	# Node values in steps: height_at at each node (whole steps).
	var node := PackedFloat32Array()
	node.resize(nw * nh)
	for j: int in nh:
		for i: int in nw:
			node[j * nw + i] = field.height_at(xs[i], ys[j]) / yps
	var sw := (nw - 1) * sub + 1  # samples a row
	var sx := _sample_lines(xs, sub)
	var sy := _sample_lines(ys, sub)
	# Per level: segments as start, end edge id pairs (an Array, so _cell appends to it in
	# place; packed arrays pass by value), and each edge id's point.
	var segs: Array = []
	var pts: Array = []
	for _l in levels.size():
		segs.append([] as Array[int])
		pts.append({})
	var v := PackedFloat32Array()
	v.resize((sub + 1) * (sub + 1))
	for cj: int in nh - 1:
		for ci: int in nw - 1:
			var a00 := node[cj * nw + ci]
			var a10 := node[cj * nw + ci + 1]
			var a01 := node[(cj + 1) * nw + ci]
			var a11 := node[(cj + 1) * nw + ci + 1]
			var lo := minf(minf(a00, a10), minf(a01, a11))
			var hi := maxf(maxf(a00, a10), maxf(a01, a11))
			if hi == lo:
				continue
			# Sub-sample the cell (exactly bilinear).
			for sj: int in sub + 1:
				var fv := float(sj) / sub
				var left := lerpf(a00, a01, fv)
				var right := lerpf(a10, a11, fv)
				for si: int in sub + 1:
					v[sj * (sub + 1) + si] = lerpf(left, right, float(si) / sub)
			for li: int in levels.size():
				var t := levels[li] - LEVEL_EPS
				if t <= lo or t >= hi:
					continue
				for sj: int in sub:
					for si: int in sub:
						var gx := ci * sub + si
						var gy := cj * sub + sj
						_cell(v, sub + 1, si, sj, t, gx, gy, sw, sx, sy, segs[li], pts[li])
	var clip := Rect2(Vector2(window.position) * ypt, Vector2(window.size) * ypt)
	for li: int in levels.size():
		var lines: Array[PackedVector2Array] = out[li]
		for line: PackedVector2Array in _join(segs[li], pts[li]):
			for piece: PackedVector2Array in clip_polyline(line, clip):
				if polyline_length(piece) >= MIN_LENGTH_YD:
					lines.append(piece)
	return out


## One sub-cell of marching squares: corners at local (si, sj) of the cell's samples `v`
## (`vw` a row), threshold `t`; its global sample is (gx, gy) on a grid `sw` wide. Appends
## oriented segments (higher ground on the left) to `segs` and their points to `pts`.
static func _cell(v: PackedFloat32Array, vw: int, si: int, sj: int, t: float, gx: int, gy: int,
		sw: int, sx: PackedFloat32Array, sy: PackedFloat32Array, segs: Array[int], pts: Dictionary) -> void:
	var v0 := v[sj * vw + si]  # top left
	var v1 := v[sj * vw + si + 1]  # top right
	var v2 := v[(sj + 1) * vw + si + 1]  # bottom right
	var v3 := v[(sj + 1) * vw + si]  # bottom left
	var b0 := v0 >= t
	var b1 := v1 >= t
	var b2 := v2 >= t
	var b3 := v3 >= t
	var idx := int(b0) | int(b1) << 1 | int(b2) << 2 | int(b3) << 3
	if idx == 0 or idx == 15:
		return
	# Edges: 0 top (v0-v1), 1 right (v1-v2), 2 bottom (v3-v2), 3 left (v0-v3).
	var ids: Array[int] = [
		(gy * sw + gx) * 2,  # horizontal edge from sample (gx, gy)
		(gy * sw + gx + 1) * 2 + 1,  # vertical edge from (gx + 1, gy)
		((gy + 1) * sw + gx) * 2,
		(gy * sw + gx) * 2 + 1,
	]
	var corner: Array[Vector2] = [Vector2(sx[gx], sy[gy]), Vector2(sx[gx + 1], sy[gy]),
			Vector2(sx[gx + 1], sy[gy + 1]), Vector2(sx[gx], sy[gy + 1])]
	var vals: Array[float] = [v0, v1, v2, v3]
	var high: Array[bool] = [b0, b1, b2, b3]
	# Edge e runs from corner ea[e] to corner eb[e].
	var ea: Array[int] = [0, 1, 3, 0]
	var eb: Array[int] = [1, 2, 2, 3]
	var pairs: Array = []  # [edge, edge, a corner on one side, that corner is high]
	var crossing: Array[int] = []
	for e: int in 4:
		if high[ea[e]] != high[eb[e]]:
			crossing.append(e)
	if crossing.size() == 2:
		# Any corner off the segment's line will do: a corner of the first crossed edge.
		pairs.append([crossing[0], crossing[1]])
	else:
		var centre_high := (v0 + v1 + v2 + v3) * 0.25 >= t
		if centre_high == b0:
			pairs.append([0, 1])  # cuts off corner 1
			pairs.append([2, 3])  # cuts off corner 3
		else:
			pairs.append([3, 0])  # cuts off corner 0
			pairs.append([1, 2])  # cuts off corner 2
	for pair: Array in pairs:
		var e0: int = pair[0]
		var e1: int = pair[1]
		var p := _crossing(corner, vals, ea[e0], eb[e0], t)
		var q := _crossing(corner, vals, ea[e1], eb[e1], t)
		# Orient: the high corner of e0 must lie on the left of p -> q (cross < 0 in +y down).
		var hc: int = ea[e0] if high[ea[e0]] else eb[e0]
		var d := q - p
		var w := corner[hc] - p
		var cr := d.x * w.y - d.y * w.x
		var s0: int = ids[e0]
		var s1: int = ids[e1]
		if cr > 0.0:
			var tmp := s0
			s0 = s1
			s1 = tmp
			var tp := p
			p = q
			q = tp
		pts[s0] = p
		pts[s1] = q
		segs.append(s0)
		segs.append(s1)


## The grid's lines along one axis, yards: the centres of tiles `from` to `to` - 1, and the map
## edge (0 or `count` tiles) beyond the first or last when the grid reaches it.
static func _node_lines(from: int, to: int, count: int, ypt: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if from == 0:
		out.append(0.0)
	for i: int in range(from, to):
		out.append((i + 0.5) * ypt)
	if to == count:
		out.append(count * ypt)
	return out


## The sample lines: `sub` a cell between each pair of node lines.
static func _sample_lines(lines: PackedFloat32Array, sub: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i: int in range(lines.size() - 1):
		for k: int in sub:
			out.append(lerpf(lines[i], lines[i + 1], float(k) / sub))
	out.append(lines[lines.size() - 1])
	return out


static func _crossing(corner: Array[Vector2], vals: Array[float], a: int, b: int, t: float) -> Vector2:
	var f := (t - vals[a]) / (vals[b] - vals[a])
	return corner[a].lerp(corner[b], f)


## Chains oriented segments (pairs of edge ids in `segs`) into polylines; a closed one repeats
## its first point.
static func _join(segs: Array[int], pts: Dictionary) -> Array[PackedVector2Array]:
	var n := segs.size() / 2
	var by_start := {}
	var by_end := {}
	for k: int in n:
		by_start[segs[2 * k]] = k
		by_end[segs[2 * k + 1]] = k
	var used := PackedByteArray()
	used.resize(n)
	var out: Array[PackedVector2Array] = []
	for k0: int in n:
		if used[k0]:
			continue
		# Walk back to the chain's first segment (or round a loop to k0).
		var first := k0
		while true:
			var prev: Variant = by_end.get(segs[2 * first])
			if prev == null or prev == k0 or used[prev]:
				break
			first = prev
		var line := PackedVector2Array([pts[segs[2 * first]]])
		var k := first
		while true:
			used[k] = 1
			line.append(pts[segs[2 * k + 1]])
			var nxt: Variant = by_start.get(segs[2 * k + 1])
			if nxt == null:
				break
			if nxt == first:
				line[line.size() - 1] = line[0]
				break
			if used[nxt]:
				break
			k = nxt
		out.append(line)
	return out


## The parts of `line` inside `rect` (Liang-Barsky per segment, pieces joined while they run on).
static func clip_polyline(line: PackedVector2Array, rect: Rect2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var inside_all := true
	for p: Vector2 in line:
		if p.x < rect.position.x or p.y < rect.position.y or p.x > rect.end.x or p.y > rect.end.y:
			inside_all = false
			break
	if inside_all:
		out.append(line)
		return out
	var cur := PackedVector2Array()
	for i: int in range(1, line.size()):
		var seg: Variant = _clip_segment(line[i - 1], line[i], rect)
		if seg == null:
			if cur.size() >= 2:
				out.append(cur)
			cur = PackedVector2Array()
			continue
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		if cur.is_empty() or not cur[cur.size() - 1].is_equal_approx(a):
			if cur.size() >= 2:
				out.append(cur)
			cur = PackedVector2Array([a])
		cur.append(b)
	if cur.size() >= 2:
		out.append(cur)
	return out


static func _clip_segment(a: Vector2, b: Vector2, r: Rect2) -> Variant:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var ps: Array[float] = [-d.x, d.x, -d.y, d.y]
	var qs: Array[float] = [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for k: int in 4:
		if ps[k] == 0.0:
			if qs[k] < 0.0:
				return null
			continue
		var u := qs[k] / ps[k]
		if ps[k] < 0.0:
			t0 = maxf(t0, u)
		else:
			t1 = minf(t1, u)
		if t0 > t1:
			return null
	if t1 - t0 <= 0.0:
		return null
	return [a + d * t0, a + d * t1]


## Length of a polyline, in its own units.
static func polyline_length(line: PackedVector2Array) -> float:
	var s := 0.0
	for i: int in range(1, line.size()):
		s += line[i - 1].distance_to(line[i])
	return s


## Downhill ticks along `line` (oriented as trace returns it): one every `spacing` along it,
## starting half a spacing in, each a segment [foot, tip] of `length` on the line's right, the
## low side. Returned as pairs in one array (foot, tip, foot, tip, ...), in the line's units.
static func ticks(line: PackedVector2Array, spacing: float, length: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if spacing <= 0.0:
		return out
	var carry := spacing * 0.5
	for i: int in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var seg := a.distance_to(b)
		if seg <= 0.0:
			continue
		var d := (b - a) / seg
		var right := Vector2(-d.y, d.x)
		while carry <= seg:
			var foot := a + d * carry
			out.append(foot)
			out.append(foot + right * length)
			carry += spacing
		carry -= seg
	return out
