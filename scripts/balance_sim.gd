class_name BalanceSim
extends RefCounted
## The /balance measurements (.claude/skills/balance/SKILL.md) for clubs, lies and surfaces,
## through the real ShotModel and Ball. scripts/sim.gd prints them; tests/test_sim.gd calls
## them directly. Each function returns rows: {name, measured, target, ok, note}, where
## measured is the mean over `runs` seeds counted up from `rng_seed` (the bounce scatter is
## the only random part, so carries are the same every run and totals vary a little).
##
## Targets are docs/design.md Balance targets, restated by D18. The bands are copied here as
## constants because they are design targets, not tunables; change them with that file.

const DRIVER_CARRY := Vector2(230.0, 260.0)
const IRON_STEP := Vector2(10.0, 12.0)
const IRONS: PackedStringArray = ["3i", "4i", "5i", "6i", "7i", "8i", "9i"]
const UPHILL_LOSS := Vector2(10.0, 12.0)
const SIDEHILL_CURVE := Vector2(5.0, 10.0)
const LIE_CLUB := "7i"
const ROUGH_COST := Vector2(0.10, 0.20)
const BUNKER_CARRY := Vector2(20.0, 40.0)
const BUNKER_POWER := 0.5
## docs/design.md "/balance surfaces green target" (E1-S11, D7).
const FLAT_PUTT := Vector2(3.5, 3.9)
const UPHILL_PUTT_GAP := 1.5
const SIDEHILL_BREAK := Vector2(0.1, 1.0)
## Test strip size; the strips themselves are tests/fixtures/balance_strips.gd.
const STRIP_W: int = BalanceStrips.STRIP_W
const STRIP_H: int = BalanceStrips.STRIP_H
const EPS := 0.001

var model: ShotModel
var surfaces: SurfaceTable


func _init(p_model: ShotModel = null, p_surfaces: SurfaceTable = null) -> void:
	model = p_model if p_model != null else ShotModel.new()
	surfaces = p_surfaces if p_surfaces != null else SurfaceTable.load_default()


static func row(row_name: String, measured: float, target: Vector2, note: String = "") -> Dictionary:
	return {"name": row_name, "measured": measured, "target": target,
			"ok": measured >= target.x - EPS and measured <= target.y + EPS, "note": note}


# --- clubs ---

## Every full club's carry and total from flat fairway (a perfect swing, aim +x); the driver
## carry and each iron step against their targets; the putter's legality and full putt.
func measure_clubs(runs: int, rng_seed: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var carries := {}
	for c in model.clubs.clubs:
		if c.is_putter():
			continue
		var r := _full(_strip(Surface.Type.FAIRWAY), c, 1.0, _tee(), 0.0, null, runs, rng_seed)
		carries[c.id] = r.carry
		var info := row("%s carry" % c.id, r.carry, Vector2(-INF, INF),
				"total %.1f yd, launch %.1f yd/s at %.0f deg, roll x%.2f" % [
					r.total, model.launch_speed(c, 1.0, 1.0), c.launch_deg, c.roll_factor])
		if c.kind == Club.Kind.DRIVER:
			info = row("driver carry", r.carry, DRIVER_CARRY, info.note)
		rows.append(info)
	for i in IRONS.size() - 1:
		var a: String = IRONS[i]
		var b: String = IRONS[i + 1]
		rows.append(row("%s to %s step" % [a, b], float(carries[a]) - float(carries[b]), IRON_STEP))
	var green_only := 1.0
	var putter := model.clubs.putter()
	for s in Surface.COUNT:
		if ClubSet.is_legal(putter, s as Surface.Type, true) != (s == Surface.Type.GREEN):
			green_only = 0.0
	rows.append(row("putter legal on green only (1 = yes)", green_only, Vector2(1.0, 1.0)))
	var flat := CourseData.create(STRIP_W, STRIP_H, Surface.Type.GREEN, 0)
	var putt := _putt(flat, putter.putt_max_speed, _tee(), 0.0, rng_seed)
	rows.append(row("full putt on flat green (yd)", putt.x - _tee().x,
			Vector2(0.0, model.clubs.full_putt_max_yd),
			"%.1f yd/s, range %.1f to %.1f" % [putter.putt_max_speed, putter.putt_min_speed,
				putter.putt_max_speed]))
	return rows


# --- lies ---

## The 7-iron from the D18 spots: the carry a 2-step uphill lie loses, and how far a 1-step
## sidehill lie curves it off line at landing. The lie is read on the D18 terrain; the shot is
## then flown on flat fairway with that lie and with none, so only the lie rule is counted,
## not the terrain's own effect on the flight (design.md hand calculation step 6). On the
## uphill terrain itself no iron can fly: two steps in one tile is an 80% face (38.7 deg),
## steeper than the 7-iron's launch, so the ball meets it at once, lie or not (docs/design.md
## Shot model, "Known limit, a ball at the foot of a riser").
func measure_lies(runs: int, rng_seed: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var club := model.clubs.club(LIE_CLUB)
	var at := _tee()
	var flat := _from(Surface.Type.FAIRWAY)
	var none := model.lies.flat(Surface.Type.FAIRWAY)
	var up := model.lies.measure(HeightField.new(uphill_course(), model.params), at, 0.0)
	var on := _full(flat, club, 1.0, at, 0.0, up, runs, rng_seed)
	var off := _full(flat, club, 1.0, at, 0.0, none, runs, rng_seed)
	var face := _full(uphill_course(), club, 1.0, at, 0.0, null, runs, rng_seed)
	rows.append(row("%s 2-step uphill carry lost (yd)" % LIE_CLUB, off.carry - on.carry, UPHILL_LOSS,
			"rise %.2f, k %.3f, carry %.1f against %.1f; on the riser itself %.1f" % [
				up.rise, model.lies.uphill_k, on.carry, off.carry, face.carry]))
	var side := model.lies.measure(HeightField.new(sidehill_course(), model.params), at, 0.0)
	var s_on := _full(flat, club, 1.0, at, 0.0, side, runs, rng_seed)
	var s_off := _full(flat, club, 1.0, at, 0.0, none, runs, rng_seed)
	var real := _full(sidehill_course(), club, 1.0, at, 0.0, null, runs, rng_seed)
	var curve: float = s_off.landing.y - s_on.landing.y
	rows.append(row("%s 1-step sidehill curve at landing (yd)" % LIE_CLUB, curve, SIDEHILL_CURVE,
			"tilt %.2f, c %.2f deg, toward the lower side (-y); %.1f yd out; on the band itself %.2f" % [
				side.tilt, model.lies.sidehill_deg, s_on.carry, at.y - real.landing.y]))
	return rows


## The D18 lie terrains (tests/fixtures/balance_strips.gd): a 2-step riser ahead, and a
## 1-step band beside the aim.
func uphill_course() -> CourseData:
	return BalanceStrips.uphill(2)


func sidehill_course() -> CourseData:
	return BalanceStrips.sidehill()


# --- surfaces ---

## Rough's distance cost and the bunker SW at 50% (lie tables in golf/), and the green putt
## targets on GridHeightEvidence.green_contour() (course/surfaces.tres).
func measure_surfaces(runs: int, rng_seed: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var club := model.clubs.club(LIE_CLUB)
	var fair := _full(_strip(Surface.Type.FAIRWAY), club, 1.0, _tee(), 0.0, null, runs, rng_seed)
	var rough := _full(_from(Surface.Type.ROUGH), club, 1.0, _tee(), 0.0, null, runs, rng_seed)
	rows.append(row("rough distance cost, %s carry (share)" % LIE_CLUB, 1.0 - rough.carry / fair.carry,
			ROUGH_COST, "carry %.1f against %.1f; total %.1f against %.1f onto fairway" % [
				rough.carry, fair.carry, rough.total, fair.total]))
	var sw: Club = null
	for c in model.clubs.clubs:
		if c.kind == Club.Kind.SAND_WEDGE:
			sw = c
	var bunker := _full(_from(Surface.Type.BUNKER), sw, BUNKER_POWER, _tee(), 0.0, null, runs, rng_seed)
	rows.append(row("bunker %s at 50%% carry (yd)" % sw.id, bunker.carry, BUNKER_CARRY))
	rows.append_array(_green_rows(rng_seed))
	return rows


func _green_rows(rng_seed: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var flat := CourseData.create(16, 12, Surface.Type.GREEN, 0)
	var contour := GridHeightEvidence.green_contour()
	var front := _yd(Vector2(4.5, 5.5))
	var four := _putt_ball(flat, 4.0, _yd(Vector2(1.5, 5.5)), 0.0, rng_seed)
	rows.append(row("green: 4 yd/s flat putt runs (yd)", four.position.x - _yd(Vector2(1.5, 5.5)).x, FLAT_PUTT))
	var flat9 := _putt_ball(flat, 9.0, front, 0.0, rng_seed).position.x - front.x
	var up9 := _putt_ball(contour, 9.0, front, 0.0, rng_seed).position.x - front.x
	rows.append(row("green: 9 yd/s uphill putt short of flat (yd)", flat9 - up9,
			Vector2(0.0, UPHILL_PUTT_GAP), "%.2f against %.2f flat" % [up9, flat9]))
	var side_from := _yd(Vector2(5.5, 2.5))
	var side := _putt_ball(contour, 3.0, side_from, 90.0, rng_seed)
	rows.append(row("green: 3 yd/s sidehill putt rests below its line (yd)",
			side_from.x - side.position.x, SIDEHILL_BREAK))
	var moved := 0.0
	for band: int in 3:
		var lower := 27.5 + 10.0 * band
		for into: float in [0.5, 2.5, 4.5]:
			var b := _putt_ball(contour, 0.0, Vector2(lower + into, 27.5), 0.0, rng_seed, false)
			moved = maxf(moved, absf(b.position.x - (lower + into)))
	rows.append(row("green: still ball on a step moves (yd)", moved, Vector2(0.0, EPS)))
	var short := _putt_ball(contour, 6.0, front, 0.0, rng_seed)
	var furthest := 0.0
	for p in short.path:
		furthest = maxf(furthest, p.x)
	var on_step := short.position.x >= 27.5 and short.position.x <= 32.5
	rows.append(row("green: 6 yd/s uphill putt slides back after it stops (yd)",
			furthest - short.position.x if on_step else INF, Vector2(0.0, EPS),
			"stops at x %.2f, on the step's slope: %s" % [short.position.x, on_step]))
	return rows


# --- helpers ---

func _tee_tile() -> Vector2i:
	return BalanceStrips.tee_tile()


func _tee() -> Vector2:
	return (Vector2(_tee_tile()) + Vector2(0.5, 0.5)) * model.params.yards_per_tile


func _yd(tile: Vector2) -> Vector2:
	return (tile + Vector2(0.5, 0.5)) * model.params.yards_per_tile


func _strip(surface: Surface.Type) -> CourseData:
	return BalanceStrips.strip(surface)


## Flat fairway with only the start tile on `surface`.
func _from(surface: Surface.Type) -> CourseData:
	return BalanceStrips.from(surface)


## Mean carry (ground distance to the first touchdown), mean total (to rest) and the mean
## landing point over `runs` seeds.
## `lie` null reads the lie from `course` at `at`.
func _full(course: CourseData, club: Club, power: float, at: Vector2, aim_deg: float,
		lie: Lie, runs: int, rng_seed: int) -> Dictionary:
	var field := HeightField.new(course, model.params)
	var read := lie if lie != null else model.lies.measure(field, at, aim_deg)
	var shot := model.full_with_lie(field, club, power, at, aim_deg, read)
	var carry := 0.0
	var total := 0.0
	var landing := Vector2.ZERO
	var n := maxi(runs, 1)
	for i in n:
		var p := ShotPrediction.run_launch(course, rng_seed + i, shot, model.params, surfaces)
		var land := Vector2(p.landing.x, p.landing.y)
		carry += land.distance_to(at)
		total += Vector2(p.rest.x, p.rest.y).distance_to(at)
		landing += land
	return {"carry": carry / n, "total": total / n, "landing": landing / n}


func _putt(course: CourseData, speed: float, at: Vector2, aim_deg: float, rng_seed: int) -> Vector2:
	var b := _putt_ball(course, speed, at, aim_deg, rng_seed)
	return Vector2(b.position.x, b.position.y)


## A putt through the putter, or a ball set down still when `as_putt` is false.
func _putt_ball(course: CourseData, speed: float, at: Vector2, aim_deg: float, rng_seed: int,
		as_putt: bool = true) -> Ball:
	var ball := Ball.new(course, rng_seed, model.params, surfaces)
	ball.record_path = true
	if as_putt:
		model.putt(ball.field, model.clubs.putter(), speed, at, aim_deg).apply(ball)
	else:
		ball.start_roll(at, Vector2.ZERO)
	ball.run_to_rest()
	return ball


## One line per row: name, measured, target, ok, note.
static func format(rows: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for r in rows:
		var t: Vector2 = r.target
		var target := "-"
		if is_finite(t.x) and is_finite(t.y):
			target = "%.3f to %.3f" % [t.x, t.y]
		elif is_finite(t.y):
			target = "at most %.3f" % t.y
		var verdict := "ok" if r.ok else "MISS"
		if target == "-":
			verdict = ""
		out.append("%-58s %9.3f   target %-18s %-4s %s" % [r.name, r.measured, target, verdict, r.note])
	return out


## Rows that miss their target.
static func misses(rows: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in rows:
		if not r.ok:
			out.append(r)
	return out
