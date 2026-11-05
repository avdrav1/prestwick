class_name BalanceSim
extends RefCounted
## The /balance measurements (.claude/skills/balance/SKILL.md) for clubs, lies and surfaces,
## through the real ShotModel and Ball, and for land (E6-S8) through the real LandGenerator,
## CourseBuilder and LandPrices. scripts/sim.gd prints them; tests/test_sim.gd calls
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
## docs/design.md Balance targets, land (E6-S8): the shortest par 4 (rule 4) and the
## /course-file generate 3 par 3, and the nine holes of the Land hand calculation.
const LAND_PAR3_YD := 160.0
const NINE_HOLES_YD: Array[float] = [160.0, 160.0, 160.0, 380.0, 380.0, 380.0, 380.0, 520.0, 520.0]
const LAND_EVERY_SEED := Vector2(1.0, 1.0)
## docs/design.md Balance targets, clubs (E6-S19, D33): a perfect drive stops short of the
## green of the shortest par 4 (rule 4's par4_min_yd). The green is D4's 30 yd green round
## the cup, so its front is GREEN_FRONT_YD short of the cup.
const GREEN_FRONT_YD := 15.0
const SHORT_OF_GREEN := Vector2(0.0, INF)
## The generated-land sample for the drive (D33): lanes off the starting block on this many
## seeds at most (fewer when --runs is smaller), LANE_OFFSETS tiles across the block on each
## of its four sides, the tee LANE_TEE_IN tiles in from the block's back edge, the fairway
## LANE_TILES long and 5 wide.
const DRIVE_LAND_SEEDS: int = 20
const LANE_OFFSETS: Array[int] = [4, 12, 20, 28]
const LANE_TEE_IN: int = 2
const LANE_TILES: int = 90
const LANE_SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const LAND_NO_SEED := Vector2(0.0, 0.0)
## E6-S34: yards between full-club starts that come down on the one-step rise.
const RISE_STRIDE := 1.0
## Test strip size; the strips themselves are tests/fixtures/balance_strips.gd.
const STRIP_W: int = BalanceStrips.STRIP_W
const STRIP_H: int = BalanceStrips.STRIP_H
const EPS := 0.001

var model: ShotModel
var surfaces: SurfaceTable
## Parcel prices and the land budget measure_land reads (data/land.json unless set).
var land: LandPrices


func _init(p_model: ShotModel = null, p_surfaces: SurfaceTable = null) -> void:
	model = p_model if p_model != null else ShotModel.new()
	surfaces = p_surfaces if p_surfaces != null else SurfaceTable.load_default()
	land = LandPrices.load_default()


static func row(row_name: String, measured: float, target: Vector2, note: String = "") -> Dictionary:
	return {"name": row_name, "measured": measured, "target": target,
			"ok": measured >= target.x - EPS and measured <= target.y + EPS, "note": note}


# --- clubs ---

## Every full club's carry and total from flat fairway (a perfect swing, aim +x); the driver
## carry and each iron step against their targets; the putter's legality and full putt.
func measure_clubs(runs: int, rng_seed: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var carries := {}
	var drive_total := 0.0
	for c in model.clubs.clubs:
		if c.is_putter():
			continue
		var r := _full(_strip(Surface.Type.FAIRWAY), c, 1.0, _tee(), 0.0, null, runs, rng_seed)
		carries[c.id] = r.carry
		if c.kind == Club.Kind.DRIVER:
			drive_total = r.total
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
	rows.append_array(_drive_rows(drive_total, runs, rng_seed))
	rows.append(row("putter legal on green only (1 = yes)", green_only, Vector2(1.0, 1.0)))
	var flat := CourseData.create(STRIP_W, STRIP_H, Surface.Type.GREEN, 0)
	var putt := _putt(flat, putter.putt_max_speed, _tee(), 0.0, rng_seed)
	rows.append(row("full putt on flat green (yd)", putt.x - _tee().x,
			Vector2(0.0, model.clubs.full_putt_max_yd),
			"%.1f yd/s, range %.1f to %.1f" % [putter.putt_max_speed, putter.putt_min_speed,
				putter.putt_max_speed]))
	return rows


## The shortest par 4 against a perfect drive (E6-S19, D33): on flat fairway the drive's
## total stops short of the green's front (the target), and on generated land the share of
## drives that reach it (measured, no target: D33 accepts the downhill tail).
func _drive_rows(flat_total: float, runs: int, rng_seed: int) -> Array[Dictionary]:
	var vt := ValidatorTuning.load_default()
	var front := par4_green_front_yd(vt)
	var rows: Array[Dictionary] = []
	rows.append(row("driver: perfect drive short of the shortest par 4's green (yd)", front - flat_total,
			SHORT_OF_GREEN, "total %.1f yd on flat fairway; par 4 from %d yd, green front %.0f yd" % [
				flat_total, vt.par4_min_yd, front]))
	var land := drives_on_land(rng_seed, mini(runs, DRIVE_LAND_SEEDS))
	var totals: Array[float] = land.totals
	var past := totals.filter(func(t: float) -> bool: return t >= front).size()
	rows.append(row("driver: perfect drives on generated land onto that green (share)",
			past / float(maxi(totals.size(), 1)), Vector2(-INF, INF),
			"%d of %d lanes, seeds %d to %d; total median %.1f, 90th percentile %.1f, max %.1f yd (D33)" % [
				past, totals.size(), rng_seed, rng_seed + int(land.seeds) - 1, totals[totals.size() / 2],
				totals[totals.size() * 9 / 10], totals[-1]]))
	return rows


## How far from the tee the green of the shortest par 4 begins: rule 4's par4_min_yd less
## GREEN_FRONT_YD.
static func par4_green_front_yd(vt: ValidatorTuning = null) -> float:
	var t: ValidatorTuning = vt if vt != null else ValidatorTuning.load_default()
	return t.par4_min_yd - GREEN_FRONT_YD


## A perfect driver (100%, accuracy at centre, the lie read on the ground) from the tee of
## each lane (lane_tees) on `seeds` generated seeds from `from_seed`, over a painted fairway
## (BalanceStrips.fairway_lane): {totals: rest distances from the tee in yards, sorted;
## seeds}. Generated land is fully owned, so no drive is OB.
func drives_on_land(from_seed: int, seeds: int) -> Dictionary:
	var driver: Club = null
	for c in model.clubs.clubs:
		if c.kind == Club.Kind.DRIVER:
			driver = c
	var totals: Array[float] = []
	var drives: Array[Dictionary] = []
	var n := maxi(seeds, 1)
	for i in n:
		var land := LandGenerator.generate(from_seed + i)
		for lane: Dictionary in lane_tees(land):
			var tee: Vector2i = lane.tee
			var dir: Vector2i = lane.dir
			var c := BalanceStrips.fairway_lane(land, tee, dir, LANE_TILES)
			var field := HeightField.new(c, model.params)
			var at := field.tile_center(tee)
			var shot := model.full(field, driver, 1.0, at, rad_to_deg(Vector2(dir).angle()))
			var p := ShotPrediction.run_launch(c, from_seed + i, shot, model.params, surfaces)
			var total := Vector2(p.rest.x, p.rest.y).distance_to(at)
			totals.append(total)
			drives.append({"total": total, "drop": shot.start.z - p.rest.z})
	totals.sort()
	return {"totals": totals, "drives": drives, "seeds": n}


## The sample's lanes on `c`: {tee, dir} for each side of the starting block and each of
## LANE_OFFSETS, the tee LANE_TEE_IN tiles in from the block's edge opposite `dir`.
static func lane_tees(c: CourseData) -> Array[Dictionary]:
	var block := LandGenerator.start_block(c.width, c.height)
	var out: Array[Dictionary] = []
	for dir: Vector2i in LANE_SIDES:
		for off: int in LANE_OFFSETS:
			var tee: Vector2i
			if dir.x != 0:
				tee = Vector2i(block.position.x + LANE_TEE_IN if dir.x > 0 else block.end.x - 1 - LANE_TEE_IN,
						block.position.y + off)
			else:
				tee = Vector2i(block.position.x + off,
						block.position.y + LANE_TEE_IN if dir.y > 0 else block.end.y - 1 - LANE_TEE_IN)
			out.append({"tee": tee, "dir": dir})
	return out


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
	rows.append_array(_rise_rows())
	return rows


## E6-S34: every full club at 100% and max_power coming down on a one-step rise
## (BalanceStrips.one_step_rise), from starts every RISE_STRIDE yd that land on it: the longest
## bounce against the bounce budget (golf/ball_params.tres max_bounce_s, one tick of rounding)
## and the longest settle against D16, per rolling surface.
func _rise_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var top := SwingTuning.load_default().max_power
	var budget := model.params.max_bounce_s + 1.0 / Ball.TICK_HZ
	var size := model.params.yards_per_tile
	var foot := (BalanceStrips.RISE_TILE - 0.5) * size
	var crest := (BalanceStrips.RISE_TILE + 0.5) * size
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.CART_PATH,
			Surface.Type.GREEN]:
		var rise := BalanceStrips.one_step_rise(s)
		var flat := CourseData.create(STRIP_W, STRIP_H, s, 0)
		var air := [0, ""]
		var settle := [0, ""]
		for c in model.clubs.clubs:
			if c.is_putter():
				continue
			for power: float in [1.0, top]:
				var carry: float = _rise_strike(flat, c, power, _tee().x)[2] - _tee().x
				var x := foot - carry - 1.0
				while x <= crest - carry + 1.0:
					var r := _rise_strike(rise, c, power, x)
					x += RISE_STRIDE
					if r[2] < foot or r[2] > crest:
						continue
					var label := "%s at %.0f%%, landing x %.1f" % [c.id, power * 100.0, r[2]]
					if r[0] > air[0]:
						air = [r[0], label]
					if r[1] > settle[0]:
						settle = [r[1], label]
		var target := 480.0 if s == Surface.Type.GREEN else 600.0
		rows.append(row("one-step rise, %s: longest bounce (s)" % Surface.NAMES[s], air[0] / float(Ball.TICK_HZ),
				Vector2(0.0, budget), "%s; budget max_bounce_s %.2f s" % [air[1], model.params.max_bounce_s]))
		rows.append(row("one-step rise, %s: longest settle (ticks)" % Surface.NAMES[s], settle[0],
				Vector2(0.0, target - 1.0), "%s (D16)" % settle[1]))
	return rows


## [ticks in the air after the first touchdown, ticks from it to rest, landing x] for `club`
## at `power` from (x, the strip's middle), aim +x, seed 1.
func _rise_strike(course: CourseData, club: Club, power: float, x: float) -> Array:
	var ball := Ball.new(course, 1, model.params, surfaces)
	model.full(ball.field, club, power, Vector2(x, _tee().y), 0.0).apply(ball)
	while not ball.has_landed and not ball.is_at_rest():
		ball.step()
	var landed := ball.steps
	var air := 0
	while ball.state == Ball.State.FLYING or ball.state == Ball.State.ROLLING:
		ball.step()
		if ball.state == Ball.State.FLYING:
			air += 1
	return [air, ball.steps - landed, ball.landing_position.x]


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


# --- land (E6-S8) ---

## The land budget against the land on seeds `rng_seed` to `rng_seed + runs - 1`: each New
## course (CourseBuilder.new_course) spends its whole budget, cheapest buyable parcel first
## (spend_budget, a frugal player), and the land it then owns is checked for room. A par 3
## and a par 4 fit when the owned parcels hold both footprints (footprint_parcels) and two
## owned tiles are a shortest par 4 apart (owned_span_yd); nine holes fit when they hold the
## nine footprints. Also the price spread, what trees and water take off, and the clamp.
## Prices and the budget come from `land`.
func measure_land(runs: int, rng_seed: int) -> Array[Dictionary]:
	var lp: LandPrices = land
	var vt := ValidatorTuning.load_default()
	var par4_yd := float(vt.par4_min_yd)
	var two := footprint_parcels(LAND_PAR3_YD, vt) + footprint_parcels(par4_yd, vt)
	var nine := 0.0
	for yd: float in NINE_HOLES_YD:
		nine += footprint_parcels(yd, vt)
	var n := maxi(runs, 1)
	var fit_two := 0
	var fit_nine := 0
	var bought := 0
	var bought_min := 1 << 30
	var bought_max := 0
	var left := 0
	var span := 0.0
	var clamped := 0
	var prices: Array[int] = []
	var cut_sum := 0.0
	var cut_max := 0
	var spread := 0.0
	for i in n:
		var c := CourseBuilder.new_course(rng_seed + i, lp)
		var b := CourseBuilder.new(c, null, null, lp)
		var lo := 1 << 30
		var hi := 0
		for q: int in c.parcels_high:
			for p: int in c.parcels_wide:
				var parcel := Vector2i(p, q)
				if c.is_parcel_owned(parcel):
					continue
				var tally := parcel_tally(c, parcel)
				var raw: int = lp.base_price + lp.relief_step_price * tally.relief \
						+ lp.tree_tile_price * tally.trees + lp.water_tile_price * tally.water
				if raw < lp.min_price or raw > lp.max_price:
					clamped += 1
				var cut: int = -(lp.tree_tile_price * tally.trees + lp.water_tile_price * tally.water)
				cut_sum += cut
				cut_max = maxi(cut_max, cut)
				var price := b.parcel_price(parcel)
				prices.append(price)
				if b.buy_refusal(parcel).is_empty() or b.buy_refusal(parcel).begins_with("costs"):
					lo = mini(lo, price)
					hi = maxi(hi, price)
		spread += hi - lo
		var spent := spend_budget(b)
		var got: int = (spent.bought as Array).size()
		bought += got
		bought_min = mini(bought_min, got)
		bought_max = maxi(bought_max, got)
		left += int(spent.left)
		var owned := 0
		for q: int in c.parcels_high:
			for p: int in c.parcels_wide:
				if c.is_parcel_owned(Vector2i(p, q)):
					owned += 1
		var s := owned_span_yd(c)
		span += s
		if owned >= two and s >= par4_yd:
			fit_two += 1
		if owned >= nine:
			fit_nine += 1
	prices.sort()
	var rows: Array[Dictionary] = []
	rows.append(row("land: seeds with room for a par 3 and a par 4", fit_two / float(n), LAND_EVERY_SEED,
			"%.0f + %.0f yd need %.2f parcels and %.0f yd of owned span; mean span %.1f yd" % [
				LAND_PAR3_YD, par4_yd, two, par4_yd, span / n]))
	rows.append(row("land: seeds with room for nine holes", fit_nine / float(n), LAND_NO_SEED,
			"nine holes need %.1f parcels; the block is 4" % nine))
	rows.append(row("land: parcels the budget buys, cheapest first", bought / float(n), Vector2(-INF, INF),
			"%d to %d; %s left on average, of %s" % [bought_min, bought_max,
				LandPrices.money(roundi(left / float(n))), LandPrices.money(lp.land_budget)]))
	rows.append(row("land: parcels at the price clamp (share)", clamped / float(maxi(prices.size(), 1)),
			LAND_NO_SEED, "%s to %s guards tuned values only" % [
				LandPrices.money(lp.min_price), LandPrices.money(lp.max_price)]))
	if not prices.is_empty():
		rows.append(row("land: median parcel price ($)", prices[prices.size() / 2], Vector2(-INF, INF),
				"%s to %s; 10th to 90th percentile %s to %s" % [LandPrices.money(prices[0]),
					LandPrices.money(prices[-1]), LandPrices.money(prices[prices.size() / 10]),
					LandPrices.money(prices[prices.size() * 9 / 10])]))
	rows.append(row("land: trees and water take off a parcel ($, mean)", cut_sum / maxf(prices.size(), 1.0),
			Vector2(-INF, INF), "at most %s" % LandPrices.money(cut_max)))
	rows.append(row("land: dearest minus cheapest neighbour of the block ($)", spread / n,
			Vector2(-INF, INF), "mean over seeds"))
	return rows


## Spends `b`'s whole land budget on the cheapest parcel it may buy, again and again (ties
## by parcel row, then column). {bought: Array[Vector2i], prices: Array[int], left: int,
## cheapest_left: int, the cheapest parcel next to the land when it stopped (1 << 30 when
## none)}. Buys through the builder, so the course is the builder's to change.
static func spend_budget(b: CourseBuilder) -> Dictionary:
	var c: CourseData = b.course
	var out := {"bought": [] as Array[Vector2i], "prices": [] as Array[int], "left": c.land_budget,
			"cheapest_left": 1 << 30}
	if c.has_unlimited_budget():
		return out
	while true:
		var best := Vector2i(-1, -1)
		var best_price := 1 << 30
		var next_price := 1 << 30
		for q: int in c.parcels_high:
			for p: int in c.parcels_wide:
				var parcel := Vector2i(p, q)
				var why := b.buy_refusal(parcel)
				if why.is_empty() or why.begins_with("costs"):
					var price := b.parcel_price(parcel)
					next_price = mini(next_price, price)
					if why.is_empty() and price < best_price:
						best_price = price
						best = parcel
		out.cheapest_left = next_price
		if best.x < 0:
			break
		b.buy_parcel(best)
		(out.bought as Array[Vector2i]).append(best)
		(out.prices as Array[int]).append(best_price)
	out.left = c.land_budget
	return out


## Parcels of land a hole's footprint covers (docs/design.md Land, hand calculation): a
## capsule of about (L + 2w) x 2w sq yd, w the footprint half width (30 yd), so
## (L + 60) x 60 for a hole of L yd. A parcel is 80 x 80 yd.
static func footprint_parcels(yd: float, vt: ValidatorTuning = null) -> float:
	var t: ValidatorTuning = vt if vt != null else ValidatorTuning.load_default()
	var w: float = t.footprint_half_width_yd
	var parcel_yd: float = CourseData.PARCEL_TILES * CourseValidator.YARDS_PER_TILE
	return (yd + 2.0 * w) * 2.0 * w / (parcel_yd * parcel_yd)


## The longest tee-to-cup line between two owned tile centres of `c`, in yards (5 yd a tile,
## rule 4's measure): the corners of the owned parcels, pair by pair.
static func owned_span_yd(c: CourseData) -> float:
	var corners: Array[Vector2i] = []
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			var parcel := Vector2i(p, q)
			if not c.is_parcel_owned(parcel):
				continue
			var r := c.parcel_rect(parcel)
			var e := r.end - Vector2i.ONE
			corners.append_array([r.position, Vector2i(e.x, r.position.y), Vector2i(r.position.x, e.y), e])
	var best := 0
	for i in corners.size():
		for j in range(i + 1, corners.size()):
			best = maxi(best, (corners[i] - corners[j]).length_squared())
	return CourseValidator.YARDS_PER_TILE * sqrt(best)


## What is on parcel `parcel` of `c`, as LandPrices reads it: {relief, trees, water}.
static func parcel_tally(c: CourseData, parcel: Vector2i) -> Dictionary:
	var r := c.parcel_rect(parcel)
	var lo := CourseData.MAX_HEIGHT
	var hi := 0
	var trees := 0
	var water := 0
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			lo = mini(lo, c.get_height(x, y))
			hi = maxi(hi, c.get_height(x, y))
			match c.get_surface(x, y):
				Surface.Type.TREES:
					trees += 1
				Surface.Type.WATER:
					water += 1
	return {"relief": hi - lo, "trees": trees, "water": water}


# --- reactions (E3-S8) ---

## /balance reactions: ReactionField.measure (scripts/reaction_field.gd), with this sim's bag.
func measure_reactions(runs: int, rng_seed: int, nine_days: int = ReactionField.NINE_DAYS) -> Array[Dictionary]:
	return ReactionField.new(model).measure(runs, rng_seed, nine_days)


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
		elif is_finite(t.x):
			target = "at least %.3f" % t.x
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
