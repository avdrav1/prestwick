extends SceneTree
## E14-S5 (D69): audits the example courses' footbridges. For each course (CourseExport.EXAMPLES
## in res://courses/, or `course=<file>`):
## - Round walks: clubhouse door to the first tee, each green to the next tee, the last green
##   back to the door, as GuestWalk.route walks them, against the straight line with no water
##   (its water yards timed as rough): yards, ratio, extra yards, seconds.
## - Ball spots: over `seeds=1,2,3` guest days (24 arrivals, as the example rows), where every
##   stroke's ball came to rest (StrokeRecord.rest; holed strokes left out), and the dry walk to
##   it from where it was struck and from the tee, and from it to the cup. A walk is a detour
##   when it is over DETOUR_RATIO times the straight line and over DETOUR_EXTRA_YD longer; a hole
##   is flagged when over SPOT_SHARE of its balls have one, or when SEVERE_BALLS or more balls
##   come to rest in one 4 x 4 tile cell with a detour over SEVERE_EXTRA_YD (E14-S5: few balls,
##   but a walk that long holds every group behind it). Flagged spots are grouped by 4 x 4
##   tile cells, each with the water its straight line crosses (where a bridge would go).
## - Bridges: each 4-connected run of bridge tiles, its length, its banks' surfaces, the holes'
##   lines of play it crosses, and the guests' walks over it during the days (by hole being
##   played or walked to): one no walk crosses is unused; one over BRIDGE_LONG_TILES, landing
##   in a bunker or trees, or across the line of a hole whose guests never use it is flagged.
## Reads only. Run it with a throwaway user://:
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --path . -s res://scripts/bridge_audit.gd \
##       [-- seeds=1,2,3] [course=cliffside.json] [arrivals=24] [spots] [map=x0,y0,x1,y1]
##       [dir=/some/folder (the course files read from there instead, as before a change)]

const DETOUR_RATIO: float = 1.3
const DETOUR_EXTRA_YD: float = 30.0
const SPOT_SHARE: float = 0.05
const SEVERE_BALLS: int = 3
const SEVERE_EXTRA_YD: float = 100.0
const BRIDGE_LONG_TILES: int = 15
const YPT: float = 5.0

var tuning: GuestTuning
var model: ShotModel
var validator := CourseValidator.new()
## `map=x0,y0,x1,y1`: print that window of each course's tiles instead of the audit.
var map_rect := PackedStringArray()


func _initialize() -> void:
	var seeds: Array[int] = [1, 2, 3]
	var only := ""
	var arrivals := ReactionField.EXAMPLE_ARRIVALS
	var list_spots := false
	var from_dir := CourseExport.EXAMPLES_FROM
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seeds="):
			seeds.clear()
			for s: String in arg.substr(6).split(","):
				seeds.append(int(s))
		elif arg.begins_with("course="):
			only = arg.substr(7)
		elif arg.begins_with("arrivals="):
			arrivals = int(arg.substr(9))
		elif arg.begins_with("dir="):
			from_dir = arg.substr(4)
		elif arg == "spots":
			list_spots = true
		elif arg.begins_with("map="):
			map_rect = arg.substr(4).split(",")
	tuning = GuestTuning.load_default()
	model = ShotModel.new()
	for file: String in CourseExport.EXAMPLES:
		if only != "" and file != only:
			continue
		var errors: Array[String] = []
		var c := CourseSave.load_file(from_dir.path_join(file), errors)
		if c == null:
			push_error("%s: %s" % [file, "; ".join(errors)])
			continue
		if map_rect.size() == 4:
			_map(c, int(map_rect[0]), int(map_rect[1]), int(map_rect[2]), int(map_rect[3]))
		else:
			_audit(c, seeds, arrivals, list_spots)
	quit(0)


func _audit(c: CourseData, seeds: Array[int], arrivals: int, list_spots: bool) -> void:
	print("\n=== %s: %d bridge tiles ===" % [c.course_name, c.bridge_cells().size()])
	var cache := GuestWalk.Cache.new()
	# Round walks.
	print("round walks (dry route against the straight line with no water):")
	var walks := GuestWalk.round_walks(c, YPT)
	if c.has_clubhouse() and not walks.is_empty():
		var last: Dictionary = walks[-1]
		var h: HoleData = c.holes[last.to_slot]
		walks.append({"from": _center(h.cup), "to": _center(c.clubhouse_door()),
				"from_hole": last.to_hole, "to_hole": 0})
	var flagged_walks := 0
	for w: Dictionary in walks:
		var m := _measure(c, w.from, w.to, cache)
		var name := "%s to %s" % ["clubhouse" if w.from_hole == 0 else "green %d" % w.from_hole,
				"clubhouse" if w.to_hole == 0 else "tee %d" % w.to_hole]
		var flag: bool = m.flag
		if flag:
			flagged_walks += 1
		print("  %-22s %4d yd straight, walked %4d yd (%.2fx, +%d yd), %4d s against %4d s%s%s" % [
				name, roundi(m.straight), roundi(m.walked), m.ratio, roundi(m.extra),
				roundi(m.walk_s), roundi(m.dry_s), " searched" if m.searched else "",
				"  <-- DETOUR, wet %s" % m.wet if flag else ""])
	print("  %d of %d walks with a detour" % [flagged_walks, walks.size()])
	# Guest days: ball spots and bridge use.
	var comps := _bridge_runs(c)
	var comp_of := {}
	for i: int in comps.size():
		for t: Vector2i in comps[i]:
			comp_of[t] = i
	var use: Array[Dictionary] = []
	for i: int in comps.size():
		use.append({})
	var spots: Array[Dictionary] = []
	for s: int in seeds:
		var brain := GuestBrain.new(c, s, tuning, model, [], null, arrivals)
		brain.hole_finished.connect(func(g: Guest, r: Guest.HoleRecord) -> void:
			for st: GuestHole.StrokeRecord in g.hole.strokes:
				if st.holed:
					continue
				spots.append({"hole": r.number, "start": Vector2(st.start.x, st.start.y),
						"rest": Vector2(st.rest.x, st.rest.y), "hazard": st.hazard}))
		var latest := 0
		# Each guest's walk as last seen: a new one is checked once for the bridges it crosses.
		var seen := {}
		while not brain.day_over:
			brain.serve(-1)
			brain.step()
			for g: Guest in brain.guests:
				if g.walk == null or seen.get(g.id) == g.walk:
					continue
				seen[g.id] = g.walk
				var gr := brain.group_of(g)
				var what := "?"
				if gr != null:
					what = ("to tee %d" % gr.hole_number) if gr.phase == GuestGroup.Phase.TO_TEE \
							else ("on %d" % gr.hole_number)
				for k: int in _runs_crossed(g.walk.points, comp_of):
					var u: Dictionary = use[k]
					u[what] = int(u.get(what, 0)) + 1
		var last: Guest = null
		for g: Guest in brain.guests:
			if last == null or g.left_s > last.left_s:
				last = g
			latest = maxi(latest, g.left_s)
		print("day %d: latest finish %d s" % [s, latest])
		if last != null:
			# The last guest home: when it arrived, and each hole's start, end and wait.
			var holes := PackedStringArray()
			for r: Guest.HoleRecord in last.records:
				holes.append("%d: %d-%d (%d s, wait %d)" % [r.number, r.start_s, r.end_s,
						r.end_s - r.start_s, r.wait_s])
			print("  last home: arrived %d s; %s" % [last.arrived_s, ", ".join(holes)])
	# Ball spots by hole.
	print("ball spots (%d balls at rest over %d days; detour: over %.1fx and %d yd):" % [
			spots.size(), seeds.size(), DETOUR_RATIO, DETOUR_EXTRA_YD])
	var by_hole := {}
	for sp: Dictionary in spots:
		var h := _hole(c, sp.hole)
		var to_it := _measure(c, sp.start, sp.rest, cache)
		var from_tee := _measure(c, _center(h.tee), sp.rest, cache)
		var to_cup := _measure(c, sp.rest, _center(h.cup), cache)
		sp["to_it"] = to_it
		sp["from_tee"] = from_tee
		sp["to_cup"] = to_cup
		sp["flag"] = to_it.flag or to_cup.flag or from_tee.flag
		if not by_hole.has(sp.hole):
			by_hole[sp.hole] = []
		(by_hole[sp.hole] as Array).append(sp)
	var numbers: Array = by_hole.keys()
	numbers.sort()
	for n: int in numbers:
		var list: Array = by_hole[n]
		var f: Array = list.filter(func(sp: Dictionary) -> bool: return sp.flag)
		var share := float(f.size()) / list.size()
		var worst := 0.0
		for sp: Dictionary in f:
			worst = maxf(worst, maxf(sp.to_it.extra, maxf(sp.to_cup.extra, sp.from_tee.extra)))
		if f.is_empty():
			print("  hole %d: %d balls, 0 with a detour" % [n, list.size()])
			continue
		# Group the detour spots by 4 x 4 tile cells.
		var cells := {}
		var severe := false
		for sp: Dictionary in f:
			var cell := Vector2i(floori(sp.rest.x / YPT / 4.0), floori(sp.rest.y / YPT / 4.0))
			if not cells.has(cell):
				cells[cell] = []
			(cells[cell] as Array).append(sp)
		for cell: Vector2i in cells:
			var big: Array = (cells[cell] as Array).filter(func(sp: Dictionary) -> bool:
				return maxf(sp.to_it.extra, maxf(sp.to_cup.extra, sp.from_tee.extra)) > SEVERE_EXTRA_YD)
			severe = severe or big.size() >= SEVERE_BALLS
		var why := ""
		if share > SPOT_SHARE:
			why = "  <-- FLAGGED (share)"
		elif severe:
			why = "  <-- FLAGGED (%d+ balls in one cell over %d yd)" % [SEVERE_BALLS, SEVERE_EXTRA_YD]
		print("  hole %d: %d balls, %d with a detour (%.1f%%), worst +%d yd%s" % [n, list.size(),
				f.size(), share * 100.0, roundi(worst), why])
		var keys: Array = cells.keys()
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (cells[a] as Array).size() > (cells[b] as Array).size())
		for cell: Vector2i in keys.slice(0, 6):
			var cl: Array = cells[cell]
			var sp: Dictionary = cl[0]
			var e_to := 0.0
			var e_cup := 0.0
			var e_tee := 0.0
			for x: Dictionary in cl:
				e_to = maxf(e_to, x.to_it.extra)
				e_cup = maxf(e_cup, x.to_cup.extra)
				e_tee = maxf(e_tee, x.from_tee.extra)
			var wet: String = sp.to_cup.wet if sp.to_cup.flag else (sp.to_it.wet if sp.to_it.flag else sp.from_tee.wet)
			print("    tiles (%d..%d, %d..%d): %d balls; extra yd walk to it %d, from tee %d, to cup %d; wet %s" % [
					cell.x * 4, cell.x * 4 + 3, cell.y * 4, cell.y * 4 + 3, cl.size(), roundi(e_to),
					roundi(e_tee), roundi(e_cup), wet])
		if list_spots:
			for sp: Dictionary in f:
				print("      rest tile %s from %s: to it %.2fx +%d, to cup %.2fx +%d" % [
						Vector2i(sp.rest / YPT), Vector2i(sp.start / YPT), sp.to_it.ratio,
						roundi(sp.to_it.extra), sp.to_cup.ratio, roundi(sp.to_cup.extra)])
	# Bridges.
	print("bridges:")
	for i: int in comps.size():
		var run: Array = comps[i]
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-1, -1)
		for t: Vector2i in run:
			lo = Vector2i(mini(lo.x, t.x), mini(lo.y, t.y))
			hi = Vector2i(maxi(hi.x, t.x), maxi(hi.y, t.y))
		var banks := {}
		var near := {}
		var bank_tiles: Array[Vector2i] = []
		for t: Vector2i in run:
			for d: Vector2i in GuestWalk.NEIGHBOURS.slice(0, 4):
				var q: Vector2i = t + d
				if c.in_bounds(q.x, q.y) and c.get_surface(q.x, q.y) != Surface.Type.WATER:
					banks[Surface.Type.keys()[c.get_surface(q.x, q.y)]] = true
					bank_tiles.append(q)
			for d: Vector2i in GuestWalk.NEIGHBOURS:
				var q: Vector2i = t + d
				if c.in_bounds(q.x, q.y) and c.get_surface(q.x, q.y) in [Surface.Type.BUNKER, Surface.Type.TREES]:
					near[Surface.Type.keys()[c.get_surface(q.x, q.y)]] = true
		# A bridge crosses when its banks lie farther apart than the run is long: one whose
		# banks are all at one end is a dead end over the water.
		var span := 0.0
		for a: Vector2i in bank_tiles:
			for q: Vector2i in bank_tiles:
				span = maxf(span, Vector2(a).distance_to(Vector2(q)))
		var lines: Array[int] = []
		for h: HoleData in c.holes:
			var line := validator.line_of_play(c, h)
			var crossed := false
			for t: Vector2i in run:
				for k: int in range(1, line.size()):
					var p := Vector2(t) + Vector2(0.5, 0.5)
					if p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[k - 1], line[k])) <= 1.5:
						crossed = true
			if crossed:
				lines.append(h.number)
		var u: Dictionary = use[i]
		var total := 0
		var users := {}
		for k: String in u:
			total += int(u[k])
			users[int(k.split(" ")[-1])] = true
		var notes: Array[String] = []
		if total == 0:
			notes.append("UNUSED")
		if span <= maxi(hi.x - lo.x, hi.y - lo.y) + 1:
			notes.append("DEAD END: banks on one side only")
		if run.size() > BRIDGE_LONG_TILES:
			notes.append("LONG")
		if banks.has("BUNKER") or banks.has("TREES"):
			notes.append("LANDS IN A HAZARD")
		for n: int in lines:
			if total > 0 and not users.has(n):
				notes.append("CROSSES HOLE %d'S LINE, UNUSED BY IT" % n)
		print("  bridge %d: %d tiles (%d yd), tiles %s..%s, banks %s, beside %s, on the line of holes %s; walks over it %d %s%s" % [
				i + 1, run.size(), run.size() * int(YPT), lo, hi, ",".join(banks.keys()),
				",".join(near.keys()) if not near.is_empty() else "-", lines, total, u,
				("  <-- " + "; ".join(notes)) if not notes.is_empty() else ""])


## The dry walk from `a` to `b` (yards) against the straight line with no water (its open water
## yards timed as rough): {straight, walked, ratio, extra, walk_s, dry_s, flag, wet, searched}.
func _measure(c: CourseData, a: Vector2, b: Vector2, cache: GuestWalk.Cache) -> Dictionary:
	var w := GuestWalk.route(c, a, b, tuning, YPT, cache)
	var straight := a.distance_to(b)
	var on := PackedFloat64Array([0.0, 0.0, 0.0])
	var t := GuestWalk.time_pieces(c, PackedVector2Array([a, b]), tuning, YPT,
			PackedVector2Array(), PackedFloat64Array(), on)
	var dry_s := t - on[2] / tuning.walk_speed(Surface.Type.WATER) + on[2] / tuning.walk_speed(Surface.Type.ROUGH)
	var ratio := w.length / straight if straight > 0.0 else 1.0
	var extra := w.length - straight
	return {"straight": straight, "walked": w.length, "ratio": ratio, "extra": extra,
		"walk_s": w.duration, "dry_s": dry_s, "searched": w.searched,
		"flag": ratio > DETOUR_RATIO and extra > DETOUR_EXTRA_YD, "wet": _wet(c, a, b)}


## The open water tiles the straight line from `a` to `b` crosses: their span, "-" for none.
func _wet(c: CourseData, a: Vector2, b: Vector2) -> String:
	var n := maxi(1, ceili(a.distance_to(b) / 1.0))
	var first := Vector2i(-1, -1)
	var last := Vector2i(-1, -1)
	var count := 0
	var seen := {}
	for i: int in n + 1:
		var p := a.lerp(b, float(i) / n)
		var t := Vector2i(floori(p.x / YPT), floori(p.y / YPT))
		if seen.has(t):
			continue
		seen[t] = true
		if c.in_bounds(t.x, t.y) and not GuestWalk.walkable(c, t.x, t.y):
			if first.x < 0:
				first = t
			last = t
			count += 1
	return "-" if count == 0 else "%d tiles %s..%s" % [count, first, last]


## The bridge runs (indexes into `comp_of`'s values) the polyline `pts` (yards) passes over.
func _runs_crossed(pts: PackedVector2Array, comp_of: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for i: int in range(1, pts.size()):
		var n := maxi(1, ceili(pts[i - 1].distance_to(pts[i])))
		for k: int in n + 1:
			var p := pts[i - 1].lerp(pts[i], float(k) / n)
			var t := Vector2i(floori(p.x / YPT), floori(p.y / YPT))
			if comp_of.has(t) and not out.has(comp_of[t]):
				out.append(comp_of[t])
	return out


## The bridge tiles in 4-connected runs.
func _bridge_runs(c: CourseData) -> Array:
	var left := {}
	for t: Vector2i in c.bridge_cells():
		left[t] = true
	var out: Array = []
	for t: Vector2i in c.bridge_cells():
		if not left.has(t):
			continue
		var run: Array[Vector2i] = []
		var todo: Array[Vector2i] = [t]
		left.erase(t)
		while not todo.is_empty():
			var p: Vector2i = todo.pop_back()
			run.append(p)
			for d: Vector2i in GuestWalk.NEIGHBOURS.slice(0, 4):
				var q: Vector2i = p + d
				if left.has(q):
					left.erase(q)
					todo.append(q)
		out.append(run)
	return out


## Prints tiles x0..x1, y0..y1 one character a tile: ~ water, = bridge, . rough, f fairway,
## G green, T tee, s bunker, t trees, p cart path, # clubhouse, o oob; the tee and cup of each
## hole as its number (cup) or a letter a..i (tee).
func _map(c: CourseData, x0: int, y0: int, x1: int, y1: int) -> void:
	print("\n=== %s: tiles (%d, %d) to (%d, %d) ===" % [c.course_name, x0, y0, x1, y1])
	var marks := {}
	for h: HoleData in c.holes:
		marks[h.cup] = str(h.number)
		marks[h.tee] = "abcdefghi"[h.number - 1]
	var ruler := "     "
	for x: int in range(x0, x1 + 1):
		ruler += str(x % 10)
	print(ruler)
	for y: int in range(y0, y1 + 1):
		var row := "%4d " % y
		for x: int in range(x0, x1 + 1):
			if not c.in_bounds(x, y):
				row += " "
				continue
			var t := Vector2i(x, y)
			if marks.has(t):
				row += marks[t]
				continue
			if c.is_bridge(x, y):
				row += "="
				continue
			if c.is_clubhouse(x, y):
				row += "#"
				continue
			match c.get_surface(x, y):
				Surface.Type.WATER: row += "~"
				Surface.Type.FAIRWAY: row += "f"
				Surface.Type.GREEN: row += "G"
				Surface.Type.TEE: row += "T"
				Surface.Type.BUNKER: row += "s"
				Surface.Type.TREES: row += "t"
				Surface.Type.CART_PATH: row += "p"
				Surface.Type.ROUGH: row += "."
				_: row += "o"
		print(row)


func _hole(c: CourseData, n: int) -> HoleData:
	for h: HoleData in c.holes:
		if h.number == n:
			return h
	return null


func _center(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * YPT
