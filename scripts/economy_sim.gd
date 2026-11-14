class_name EconomySim
extends RefCounted
## E4-S1: the economy on paper. `scripts/sim.gd -- --table economy` prints, for each candidate
## cost table below, what the fixture holes cost to build; the guests' measured reactions and
## a day's capacity on PlaytestNine; each fee curve's best fee; each rating rule on the
## measured mixes; and for each candidate income model the cost scale at which a player who
## builds a hole every 2 days, whenever the money is there, opens the ninth hole near day 30,
## against the docs/design.md and design doc targets (basic par 3 about $1,500, par 5 with
## hazards about $6,000, 9 holes and 3 stars in 25 to 35 days without going negative, a
## $5,000 start, upkeep $5 an open hole a day).
##
## The chosen economy (D56 to D58, E4-S1's close) is read from data/economy.json
## (EconomyTuning) and data/land.json (LandPrices, its price_scale included): the "chosen:" rows
## come first and are the only ones with targets, the design doc's hole bands times the money
## scale and Balance targets, economy. Every row after them is the options pass the user chose
## from (docs/playtests/2026-11-09-e4-economy-options.md), kept so E4-S8 can see the slack: the
## candidate tables, incomes and rules are constants here, not data, their land is data/land.json's
## before the money scale, and they print with no target.
##
## What a hole costs is measured, not estimated: each fixture is built through CourseBuilder
## (tests/fixtures, course/course_generator.gd) and diffed tile by tile against the land it
## started on. A tile whose surface changed costs the new surface's price; every step a tile's
## height moved costs the step price. Painting a surface over itself costs nothing. On
## PlaytestNine each changed tile is put to the hole whose tee, centre line and cup are
## nearest, and the parcels a hole's tiles stand on (outside the free starting block, not yet
## bought for an earlier hole) are what its land costs at data/land.json's prices.
##
## The run's nine (PLAN) is a frugal one: three basic par 3s, four par 4s and two par 5s from
## the fixtures, its land the Land hand calculation's footprints (BalanceSim.footprint_parcels)
## less the free block's parcels (16 since D67, 4 before), at the median generated parcel price.

const ReactionHolesFx := preload("res://tests/fixtures/reaction_holes.gd")
const PlaytestNineFx := preload("res://tests/fixtures/playtest_nine.gd")

## Design doc, Management layer, Money: a basic par 3 costs about $1,500, a par 5 with water
## and bunkers about $6,000. "About" read as within a third either way.
const PAR3_TARGET := Vector2(1000.0, 2000.0)
const PAR5_TARGET := Vector2(4000.0, 8000.0)
## The same bands at the money scale (D56; data/land.json's price_scale), rounded to $100
## (docs/design.md Balance targets, economy): at 0.63 (E4-S8) a basic par 3 $600 to $1,300, a
## par 5 with hazards $2,500 to $5,000.
func chosen_band(band: Vector2) -> Vector2:
	var s := chosen_land.price_scale
	return Vector2(roundf(band.x * s / 100.0) * 100.0, roundf(band.y * s / 100.0) * 100.0)

## The fee the run's player sets, as a share of the ceiling: D58's curve earns most there.
const CHOSEN_FEE_SHARE: float = 0.8
## docs/design.md Balance targets, economy: 9 holes and 3 stars in 25 to 35 days at one hole
## per 2 days, never negative. Read here as money pacing the builder (design doc, Management
## layer: "it exists to pace the builder"): the player builds the next hole 2 days after the
## last whenever the balance covers it, so the ninth opens on day 17 at the soonest.
const DAYS_TARGET := Vector2(25.0, 35.0)
const DAYS_AIM: float = 30.0
const START_MONEY: int = 5000
const UPKEEP_PER_HOLE: int = 5
const BUILD_EVERY_DAYS: int = 2
const RUN_DAYS: int = 45
const STAR_TARGET: float = 3.0
const WINDOW: int = 50

## Cost tables: dollars per tile painted with each surface and per step of height moved.
## "doc" is the design doc's table as it stands (OOB "set in the economy milestone").
const SURFACES: PackedStringArray = ["fairway", "rough", "green", "tee", "bunker", "water",
		"trees", "cart_path", "oob"]
const COST_TABLES: Dictionary = {
	"doc": {"fairway": 40, "rough": 10, "green": 120, "tee": 80, "bunker": 60, "water": 90,
		"trees": 30, "cart_path": 20, "oob": 10, "step": 0},
	"doc/10": {"fairway": 4, "rough": 1, "green": 12, "tee": 8, "bunker": 6, "water": 9,
		"trees": 3, "cart_path": 2, "oob": 1, "step": 5},
	"fit": {"fairway": 6, "rough": 2, "green": 20, "tee": 15, "bunker": 15, "water": 20,
		"trees": 8, "cart_path": 6, "oob": 2, "step": 5},
	"fit-green": {"fairway": 5, "rough": 2, "green": 25, "tee": 15, "bunker": 20, "water": 30,
		"trees": 10, "cart_path": 8, "oob": 2, "step": 10},
}
## The cost table the run scales.
const RUN_TABLE: String = "fit-green"

## Fixture names, in fixtures() order, and the run's nine as [fixture index, yards].
const PLAN: Array = [[0, 160.0], [4, 380.0], [0, 160.0], [1, 380.0], [2, 520.0], [0, 160.0],
		[5, 450.0], [4, 380.0], [2, 520.0]]
## Parcels the free starting block gives (D26: 4; D67: 16, LandTuning.start_block_parcels
## squared).
static func block_parcels() -> float:
	var n: int = LandTuning.load_default().start_block_parcels
	return float(n * n)

## Arrivals curve under the ceiling (Settles): the share of the full day's arrivals at fee
## share f of the ceiling. Every curve is 1 when free and 2/3 at the ceiling (design doc: a fee
## at the ceiling cuts arrivals by a third).
const CURVES: PackedStringArray = ["linear", "flat_to_half", "knee_70", "steep"]

## Rating rules: points for praise, neutral and complaint.
const POINTS: Dictionary = {
	"5/3/1": [5.0, 3.0, 1.0],
	"5/4/1": [5.0, 4.0, 1.0],
	"5/3/0": [5.0, 3.0, 0.0],
	"5/1/1 (praise only)": [5.0, 1.0, 1.0],
}

## A fair course's mix, for the run: the reactions target's fair par 4 (docs/design.md Balance
## targets, reactions: 60 to 75% praise, under 15% complaints; E3-S60 measured 0.74 and 0.00).
const FAIR_MIX: Array[float] = [0.70, 0.27, 0.03]
## A course that rates exactly 3 stars under 5/3/1, the pacing target's course: what the
## scale search fits first. (PlaytestNine's measured nine rates 2.)
const MID_MIX: Array[float] = [0.25, 0.50, 0.25]

## Income models the scale search runs. arrivals: "flat" (`n` a day), "by_star" (`base` +
## `per_star` x stars), "by_hole" (`per_hole` per open hole x stars / 3, at least `min`);
## every model capped at `cap` (a day's capacity, measured below). ceiling: dollars per star
## per round. fee_share: the fee the player sets, as a share of the ceiling.
const INCOMES: Dictionary = {
	"I1 E3 traffic, fee at the $10 ceiling": {"arrivals": "flat", "n": 16, "cap": 16,
		"ceiling": 10.0, "fee_share": 1.0, "curve": "linear"},
	"I2 by star 8 + 4 a star, $10 ceiling, fee 80%": {"arrivals": "by_star", "base": 8,
		"per_star": 4, "cap": 24, "ceiling": 10.0, "fee_share": 0.8, "curve": "knee_70"},
	"I3 by hole 2 a hole x stars/3, $10 ceiling, fee 80%": {"arrivals": "by_hole",
		"per_hole": 2, "min": 4, "cap": 24, "ceiling": 10.0, "fee_share": 0.8, "curve": "knee_70"},
	"I4 by star 8 + 4 a star, $15 ceiling, fee 80%": {"arrivals": "by_star", "base": 8,
		"per_star": 4, "cap": 24, "ceiling": 15.0, "fee_share": 0.8, "curve": "knee_70"},
	"I5 by star 8 + 4 a star, $25 ceiling, fee 80%": {"arrivals": "by_star", "base": 8,
		"per_star": 4, "cap": 24, "ceiling": 25.0, "fee_share": 0.8, "curve": "knee_70"},
}
## Starting rating rules for the run: [start stars, prior reactions padding a short window].
const STARTS: Dictionary = {
	"3 stars, padded to 50": [3.0, 50],
	"1 star, padded to 50": [1.0, 50],
	"no pad (mean of what exists, 3 when none)": [3.0, 0],
}
const RUN_POINTS: String = "5/3/1"
const RUN_START: String = "3 stars, padded to 50"
## Arrivals per day the capacity probe plays on PlaytestNine's nine.
const CAPACITY_ARRIVALS: Array[int] = [16, 20, 24, 32]

## data/land.json before the money scale: the options' land, which each candidate scales.
var land: LandPrices = _unscaled_land()
## The chosen economy and its land, scaled.
var economy: EconomyTuning = EconomyTuning.load_default()
var chosen_land: LandPrices = LandPrices.load_default()
var rating_window: int = GuestTuning.load_default().rating_window
## Each income model's run log at its fitted scale, from the last measure().
var run_logs: Dictionary = {}


## Rows {name, measured, target, ok, note}, as BalanceSim.row.
static func row(row_name: String, measured: float, target: Vector2, note: String = "") -> Dictionary:
	return BalanceSim.row(row_name, measured, target, note)


static func _unscaled_land() -> LandPrices:
	var lp := LandPrices.load_default()
	lp.price_scale = 1.0
	return lp


## The chosen tile table in COST_TABLES' shape: dollars by surface name, and "step".
func chosen_table() -> Dictionary:
	var t := {"step": economy.height_step_price}
	for i in Surface.COUNT:
		t[Surface.NAMES[i]] = economy.tile_price[i]
	return t


## The chosen income as an INCOMES model, run at CHOSEN_FEE_SHARE.
func chosen_income() -> Dictionary:
	return {"arrivals": "chosen", "tuning": economy, "cap": economy.arrivals_max,
			"ceiling": float(economy.fee_ceiling_per_star), "fee_share": CHOSEN_FEE_SHARE,
			"curve": "chosen", "start": chosen_land.land_budget, "upkeep": economy.upkeep_per_open_hole,
			"window": rating_window}


# --- what a hole costs ---

## What changed from `before` to `after` over `cells` (every tile when empty): per surface the
## tiles painted with it, the steps of height moved, the trees cleared and the water filled.
static func diff(before: CourseData, after: CourseData, cells: Array[Vector2i] = []) -> Dictionary:
	var painted := {}
	for s in SURFACES:
		painted[s] = 0
	var out := {"painted": painted, "steps": 0, "trees_cleared": 0, "water_filled": 0, "tiles": 0}
	var list := cells
	if list.is_empty():
		for y: int in after.height:
			for x: int in after.width:
				list.append(Vector2i(x, y))
	for c: Vector2i in list:
		var s0 := before.get_surface(c.x, c.y)
		var s1 := after.get_surface(c.x, c.y)
		var dh := absi(after.get_height(c.x, c.y) - before.get_height(c.x, c.y))
		if s0 != s1:
			painted[Surface.NAMES[s1]] += 1
			if s0 == Surface.Type.TREES:
				out.trees_cleared += 1
			if s0 == Surface.Type.WATER:
				out.water_filled += 1
		out.steps += dh
		if s0 != s1 or dh != 0:
			out.tiles += 1
	return out


## Dollars for a diff under cost table `table`, times `scale`.
static func price(d: Dictionary, table: Dictionary, scale: float = 1.0) -> int:
	var total := 0
	for s in SURFACES:
		total += int(d.painted[s]) * int(table[s])
	return roundi((total + int(d.steps) * int(table.step)) * scale)


## The fixtures: [{name, diff}].
func fixtures() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec: Array in [[3, false, "par 3 basic (generate 3 flat dry, 160 yd)"],
			[4, false, "par 4 (generate 4 flat dry, 380 yd)"],
			[5, true, "par 5 with water (generate 5 flat water, 520 yd)"]]:
		var after := CourseGenerator.generate(spec[0], false, spec[1])
		var before := CourseData.create(after.width, after.height, Surface.Type.ROUGH,
				CourseGenerator.PLOT_HEIGHT)
		out.append({"name": spec[2], "diff": diff(before, after)})
	# The par 3 as tee box and green only, no fairway: the cheapest hole a player can build.
	var p3 := CourseGenerator.generate(3, false, false)
	var bare: Array[Vector2i] = []
	for y: int in p3.height:
		for x: int in p3.width:
			if p3.get_surface(x, y) != Surface.Type.FAIRWAY:
				bare.append(Vector2i(x, y))
	out.append({"name": "par 3 tee and green only, no fairway (160 yd)", "diff": diff(
			CourseData.create(p3.width, p3.height, Surface.Type.ROUGH, CourseGenerator.PLOT_HEIGHT),
			p3, bare)})
	var fair := ReactionHolesFx.fair_par4()
	out.append({"name": "fair par 4 with cross bunker (ReactionHoles, 380 yd)", "diff": diff(
			CourseData.create(fair.width, fair.height, Surface.Type.ROUGH, ReactionHolesFx.GROUND),
			fair)})
	# The dogleg's pond is the land's (the fixture sets it before building): left out.
	var dog := ReactionHolesFx.dogleg_par4()
	var dog_cells: Array[Vector2i] = []
	for y: int in dog.height:
		for x: int in dog.width:
			if not (ReactionHolesFx.DOG_POND.has_point(Vector2i(x, y))
					and dog.get_surface(x, y) == Surface.Type.WATER):
				dog_cells.append(Vector2i(x, y))
	out.append({"name": "dogleg par 4 round a pond (ReactionHoles, 450 yd)", "diff": diff(
			CourseData.create(dog.width, dog.height, Surface.Type.ROUGH, ReactionHolesFx.GROUND),
			dog, dog_cells)})
	return out


## PlaytestNine hole by hole: {holes: [{n, par, yd, diff, parcels}], after, total}, holes in
## number order; `parcels` are those its tiles need that no earlier hole bought.
func nine() -> Dictionary:
	var before := PlaytestNineFx.land()
	var after := PlaytestNineFx.course()
	var lines: Array = []
	for spec: Dictionary in PlaytestNineFx.HOLES:
		var pts: Array[Vector2] = [Vector2(spec["tee"])]
		pts.append_array(PlaytestNineFx.centre_line(spec))
		pts.append(Vector2(spec["cup"]))
		lines.append(pts)
	var per: Array = []
	for i in PlaytestNineFx.HOLES.size():
		per.append([] as Array[Vector2i])
	for y: int in after.height:
		for x: int in after.width:
			if before.get_surface(x, y) == after.get_surface(x, y) \
					and before.get_height(x, y) == after.get_height(x, y):
				continue
			var best := 0
			var best_d := INF
			for i in lines.size():
				var d := _to_line(Vector2(x, y), lines[i])
				if d < best_d:
					best_d = d
					best = i
			(per[best] as Array[Vector2i]).append(Vector2i(x, y))
	var block := LandGenerator.start_block(after.width, after.height)
	var owned := {}
	var holes: Array[Dictionary] = []
	var validator := CourseValidator.new()
	for i in PlaytestNineFx.HOLES.size():
		var spec: Dictionary = PlaytestNineFx.HOLES[i]
		var cells: Array[Vector2i] = per[i]
		var need: Array[Vector2i] = []
		for c: Vector2i in cells:
			var p := after.parcel_of(c.x, c.y)
			if block.has_point(c) or owned.has(p):
				continue
			owned[p] = true
			need.append(p)
		var h: HoleData = after.holes[i]
		holes.append({"n": spec["n"], "par": spec["par"], "yd": validator.hole_yardage(after, h),
				"diff": diff(before, after, cells), "parcels": need})
	return {"after": after, "holes": holes, "total": diff(before, after)}


static func _to_line(p: Vector2, pts: Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var t := 0.0 if ab.length_squared() == 0.0 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## What `parcels` cost on `c`'s land at data/land.json's prices.
func parcels_price(c: CourseData, parcels: Array[Vector2i], lp: LandPrices = null) -> int:
	var b := CourseBuilder.new(c, null, null, land if lp == null else lp)
	var total := 0
	for p: Vector2i in parcels:
		total += b.parcel_price(p)
	return total


## The median price of every parcel outside the starting block on New courses of `seeds`
## seeds from 1, on D67's 128 x 128 land (LandTuning.load_d67: D71 pins the economy's
## measures until E18-S4 paces the bigger map).
func median_parcel(seeds: int, lp: LandPrices = null) -> int:
	if lp == null:
		lp = land
	var prices: Array[int] = []
	for s in range(1, seeds + 1):
		var c := CourseBuilder.new_course(s, lp, LandTuning.load_d67())
		var b := CourseBuilder.new(c, null, null, lp)
		for q: int in c.parcels_high:
			for p: int in c.parcels_wide:
				if not c.is_parcel_owned(Vector2i(p, q)):
					prices.append(b.parcel_price(Vector2i(p, q)))
	prices.sort()
	return prices[prices.size() / 2]


# --- guests ---

## Real guest days on PlaytestNine with holes 1 to k open, for k = 1 to 9, `days` day seeds
## from `rng_seed` each, at data/guests.json's arrivals: per k {k, guests, reactions, praise,
## neutral, complaint, fails: [fair, interesting, pace, challenge, walk]}.
func measure_mix(days: int, rng_seed: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var model := ShotModel.new()
	var tuning := GuestTuning.load_default()
	for k in range(1, 10):
		var c := _nine_open(k)
		var tally := _tally()
		tally.k = k
		for d in days:
			var brain := GuestBrain.new(c, rng_seed + d, tuning, model)
			brain.reacted.connect(_count.bind(tally))
			brain.run_day()
			tally.guests += brain.guests.size()
		out.append(tally)
	return out


## A day's capacity: PlaytestNine's nine with `arrivals` guests a day, `days` seeds: {guests,
## finished (holed or picked up on all nine), left_at_dusk, reactions, praise, neutral,
## complaint, fails}.
func measure_capacity(arrivals: int, days: int, rng_seed: int) -> Dictionary:
	var model := ShotModel.new()
	var tuning := GuestTuning.load_default()
	tuning.arrivals_per_day = arrivals
	var c := _nine_open(9)
	var tally := _tally()
	tally.finished = 0
	tally.dusk = 0
	for d in days:
		var brain := GuestBrain.new(c, rng_seed + d, tuning, model)
		brain.reacted.connect(_count.bind(tally))
		brain.run_day()
		for g: Guest in brain.guests:
			tally.guests += 1
			if g.left_at_dusk:
				tally.dusk += 1
			elif g.records.size() >= 9:
				tally.finished += 1
	return tally


func _nine_open(k: int) -> CourseData:
	var c := PlaytestNineFx.course()
	var b := CourseBuilder.new(c)
	for n in range(k + 1, 10):
		b.close_hole(n)
	return c


static func _tally() -> Dictionary:
	return {"k": 0, "guests": 0, "reactions": 0, "praise": 0, "neutral": 0, "complaint": 0,
			"fails": [0, 0, 0, 0, 0]}


static func _count(_g: Guest, r: GuestReaction, tally: Dictionary) -> void:
	tally.reactions += 1
	if r.kind == GuestReaction.Kind.PRAISE:
		tally.praise += 1
	elif r.kind == GuestReaction.Kind.COMPLAINT:
		tally.complaint += 1
	else:
		tally.neutral += 1
	for i in GuestReaction.Check.size():
		if not r.passed[i]:
			tally.fails[i] += 1


## [praise, neutral, complaint] shares of a tally.
static func shares(t: Dictionary) -> Array[float]:
	var n := maxf(float(t.reactions), 1.0)
	return [t.praise / n, t.neutral / n, t.complaint / n]


## Mean points of a mix under rule `pts`.
static func mean_points(mix: Array[float], pts: Array) -> float:
	return mix[0] * float(pts[0]) + mix[1] * float(pts[1]) + mix[2] * float(pts[2])


# --- fees and arrivals ---

## The share of the full day's arrivals that comes at fee share `f` (0 free, 1 the ceiling).
static func curve_share(curve: String, f: float) -> float:
	var x := clampf(f, 0.0, 1.0)
	match curve:
		"flat_to_half":
			return 1.0 if x <= 0.5 else 1.0 - (x - 0.5) * 2.0 / 3.0
		"knee_70":
			# Nobody minds up to 70% of the ceiling; then a straight drop to 2/3 at it.
			return 1.0 if x <= 0.7 else 1.0 - (x - 0.7) / 0.9
		"steep":
			return 1.0 - pow(x, 4.0) / 3.0
		_:
			return 1.0 - x / 3.0


## Arrivals in a day before the fee and the cap, under income model `e`.
static func arrivals(e: Dictionary, stars: float, holes: int) -> float:
	match String(e.arrivals):
		"by_star":
			return float(e.base) + float(e.per_star) * stars
		"by_hole":
			return maxf(float(e.min), float(e.per_hole) * holes * stars / 3.0)
		_:
			return float(e.n)


## Paying guests in a day.
static func guests_for(e: Dictionary, stars: float, holes: int) -> int:
	if holes <= 0:
		return 0
	if e.has("tuning"):
		return (e.tuning as EconomyTuning).arrivals(stars, float(e.fee_share))
	var n := arrivals(e, stars, holes) * curve_share(String(e.curve), float(e.fee_share))
	return mini(roundi(n), int(e.cap))


## Stars shown for a rating: to the half star, 1 to 5 (the game's, EconomyTuning.stars_of).
static func stars_of(rating: float) -> float:
	return EconomyTuning.stars_of(rating)


## E4-S8: the fee the chosen income's player sets at `stars`, as the game holds it
## (GuestSim.fee_ceiling, set_fee): Vector2(fee, its share of the ceiling), the fee `fee_share`
## of the ceiling in whole dollars down, the ceiling `fee_ceiling_per_star` x stars in whole
## dollars down. `fee_share` < 0 is a player who leaves the slider at `start_fee`, which a
## falling ceiling lowers and a rising one leaves (GuestSim._show_stars; since E4-S13, D59, the
## ceiling moves only at dusk, as this sim's day-at-a-time stars always did).
static func chosen_fee(e: Dictionary, stars: float, held: int = -1) -> Vector2:
	var t: EconomyTuning = e.tuning
	var ceiling := floori(t.fee_ceiling(stars))
	var fee: int
	if float(e.fee_share) < 0.0:
		fee = mini(t.start_fee if held < 0 else held, ceiling)
	else:
		fee = floori(ceiling * float(e.fee_share) + 1e-9)
	return Vector2(fee, 0.0 if ceiling <= 0 else float(fee) / ceiling)


# --- the run ---

## The plan's holes priced: [{name, yd, build, land}] at `scale` (cost table and land alike).
func plan_costs(fx: Array[Dictionary], table: Dictionary, parcel: int, scale: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parcels := 0.0
	var bought := 0
	for p: Array in PLAN:
		var f: Dictionary = fx[int(p[0])]
		parcels += BalanceSim.footprint_parcels(float(p[1]))
		var need := maxi(ceili(parcels - block_parcels() - 1e-6), 0) - bought
		bought += need
		out.append({"name": f.name, "yd": p[1], "build": price(f.diff, table, scale),
				"land": roundi(need * parcel * scale), "parcels": need})
	return out


## A run under income model `e`: the plan built a hole at least BUILD_EVERY_DAYS apart, each
## when the balance covers it; guests pay at morning, react by `mix`, upkeep at dusk.
## {nine_day, star_day, min_money, money, stalled, log}.
func run(e: Dictionary, plan: Array[Dictionary], mix: Array[float], pts: Array,
		start: Array) -> Dictionary:
	var money: int = e.get("start", START_MONEY)
	var upkeep_each: int = e.get("upkeep", UPKEEP_PER_HOLE)
	var size: int = e.get("window", WINDOW)
	var open := 0
	var next_build := 1
	var window: Array[float] = []
	var min_money := money
	var stalled := 0
	var nine_day := -1
	var star_day := -1
	var log: PackedStringArray = []
	var acc := [0.0, 0.0]
	var held_fee := -1
	for day in range(1, RUN_DAYS + 1):
		var built := ""
		if open < plan.size() and day >= next_build:
			var h: Dictionary = plan[open]
			var cost: int = h.build + h.land
			if money >= cost:
				money -= cost
				open += 1
				next_build = day + BUILD_EVERY_DAYS
				built = " built hole %d ($%d + land $%d)" % [open, h.build, h.land]
				if open == plan.size():
					nine_day = day
			else:
				stalled += 1
		# The stars shown all day: the mean at the last dusk (D59, GuestSim.stars).
		var stars := stars_of(_rating(window, float(start[0]), int(start[1])))
		var fee := float(e.ceiling) * stars * float(e.fee_share)
		var guests := guests_for(e, stars, open)
		if e.has("tuning"):
			# E4-S8: the game's fee (GuestSim): whole dollars, under a ceiling of whole dollars
			# down, the morning's arrivals at the fee's share of that ceiling.
			var fp := chosen_fee(e, stars, held_fee)
			fee = fp.x
			held_fee = int(fp.x)
			guests = 0 if open <= 0 else (e.tuning as EconomyTuning).arrivals(stars, fp.y)
		var income := roundi(guests * fee)
		var upkeep := upkeep_each * open
		money += income - upkeep
		min_money = mini(min_money, money)
		for i in guests * open:
			acc[0] += mix[0]
			acc[1] += mix[2]
			if acc[0] >= 1.0:
				acc[0] -= 1.0
				window.append(float(pts[0]))
			elif acc[1] >= 1.0:
				acc[1] -= 1.0
				window.append(float(pts[2]))
			else:
				window.append(float(pts[1]))
		while window.size() > size:
			window.pop_front()
		var after := stars_of(_rating(window, float(start[0]), int(start[1])))
		if star_day < 0 and open == plan.size() and after >= STAR_TARGET:
			star_day = day
		log.append("day %2d: %d open, %2d guests at $%.2f, +$%d -$%d, balance $%d, %.1f stars%s" % [
				day, open, guests, fee, income, upkeep, money, after, built])
	return {"nine_day": nine_day, "star_day": star_day, "min_money": min_money, "money": money,
			"stalled": stalled, "log": log}


## The window's mean points, padded to WINDOW with `prior` reactions at `start` when short.
static func _rating(window: Array[float], start: float, prior: int) -> float:
	var pad := clampi(prior - window.size(), 0, prior)
	if window.is_empty() and pad == 0:
		return start
	var sum := start * pad
	for v: float in window:
		sum += v
	return sum / (window.size() + pad)


## The cost scale (on RUN_TABLE and land alike, 0.01 steps) whose ninth hole opens nearest
## DAYS_AIM, with 3 stars by the end of DAYS_TARGET and never negative. {scale, run}, or
## scale -1 when none does.
func fit_scale(e: Dictionary, fx: Array[Dictionary], parcel: int, mix: Array[float], pts: Array,
		start: Array, table: Dictionary = COST_TABLES[RUN_TABLE]) -> Dictionary:
	var best := {"scale": -1.0, "run": {}}
	var best_gap := INF
	for i in range(1, 301):
		var s := i / 100.0
		var r := run(e, plan_costs(fx, table, parcel, s), mix, pts, start)
		if int(r.nine_day) < 0 or int(r.min_money) < 0:
			continue
		if int(r.star_day) < 0 or r.star_day > DAYS_TARGET.y:
			continue
		var gap := absf(float(r.nine_day) - DAYS_AIM)
		if gap < best_gap - 1e-9:
			best_gap = gap
			best = {"scale": s, "run": r}
	return best


# --- the table ---

## Every row the economy table prints. `runs` is the guest days measured per stage of the
## nine and per capacity step.
func measure(runs: int, rng_seed: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var any := Vector2(-INF, INF)
	var fx := fixtures()
	var nn := nine()
	var parcel := median_parcel(10)
	var mix := measure_mix(maxi(runs, 1), rng_seed)
	rows.append_array(measure_chosen(fx, nn, mix))
	# The options (E4-S1's pass, no targets). Hole costs under each table.
	for t: String in COST_TABLES:
		var table: Dictionary = COST_TABLES[t]
		for f: Dictionary in fx:
			rows.append(row("cost %s: %s ($)" % [t, f.name], price(f.diff, table), any,
					_tiles_note(f.diff)))
		var nine_cost := 0
		var land_cost := 0
		for h: Dictionary in nn.holes:
			var hc := price(h.diff, table)
			var lc := parcels_price(nn.after, h.parcels)
			nine_cost += hc
			land_cost += lc
			rows.append(row("cost %s: PlaytestNine hole %d, par %d, %d yd ($)" % [t, h.n, h.par, h.yd],
					hc, any, "%s; land %d parcels %s" % [
						_tiles_note(h.diff), (h.parcels as Array).size(), LandPrices.money(lc)]))
		rows.append(row("cost %s: PlaytestNine, nine holes ($)" % t, nine_cost, any,
				"its land %s more (it spreads over the whole map); %s" % [LandPrices.money(land_cost),
					_tiles_note(nn.total)]))
		var plan := plan_costs(fx, table, parcel, 1.0)
		var build := 0
		var lnd := 0
		for h: Dictionary in plan:
			build += int(h.build)
			lnd += int(h.land)
		rows.append(row("cost %s: frugal nine, holes ($)" % t, build, any,
				"3 par 3, 4 par 4, 2 par 5 from the fixtures; land %s more (%d parcels at the median %s)" % [
					LandPrices.money(lnd), ceili(_plan_parcels() - block_parcels()), LandPrices.money(parcel)]))
	# Height: what shaping costs at each step price, on PlaytestNine.
	for step: int in [0, 5, 10, 20]:
		var per: PackedStringArray = []
		for h: Dictionary in nn.holes:
			per.append("%d: $%d" % [h.n, int(h.diff.steps) * step])
		rows.append(row("height at $%d a step: PlaytestNine's shaping ($)" % step,
				int(nn.total.steps) * step, any, "%d steps; by hole %s" % [nn.total.steps, ", ".join(per)]))
	# Guests: the measured mix as the nine opens, and a day's capacity.
	for m: Dictionary in mix:
		var sh := shares(m)
		rows.append(row("guests: PlaytestNine holes 1 to %d open, complaint share" % m.k, sh[2], any,
				"%d days, %d guests, %d reactions: praise %.2f, neutral %.2f; fails fair %d, interesting %d, pace %d, challenge %d, walk %d" % [
					runs, m.guests, m.reactions, sh[0], sh[1], m.fails[0], m.fails[1], m.fails[2], m.fails[3],
					m.fails[4]]))
	for a: int in CAPACITY_ARRIVALS:
		var cap := measure_capacity(a, maxi(runs, 1), rng_seed)
		var sh := shares(cap)
		rows.append(row("capacity: %d arrivals on PlaytestNine's nine, share finishing nine" % a,
				cap.finished / maxf(cap.guests, 1.0), any,
				"%d guests, %d left at dusk; praise %.2f, complaint %.2f; pace fails %.2f of reactions" % [
					cap.guests, cap.dusk, sh[0], sh[2], cap.fails[2] / maxf(cap.reactions, 1.0)]))
	# Rating rules on the measured nine and on a fair course.
	var nine_mix := shares(mix[8])
	for p: String in POINTS:
		var pts: Array = POINTS[p]
		rows.append(row("rating %s: PlaytestNine's nine (stars)" % p, stars_of(mean_points(nine_mix, pts)),
				any, "mean %.2f; a fair course (%.2f/%.2f/%.2f) %.2f, %.1f stars; one hole open %.2f" % [
					mean_points(nine_mix, pts), FAIR_MIX[0], FAIR_MIX[1], FAIR_MIX[2],
					mean_points(FAIR_MIX, pts), stars_of(mean_points(FAIR_MIX, pts)),
					mean_points(shares(mix[0]), pts)]))
	# Fee curves: the best fee and what it earns against the ceiling.
	for curve: String in CURVES:
		var at: PackedStringArray = []
		for f: float in [0.25, 0.5, 0.7, 0.85, 1.0]:
			at.append("%.0f%% %.2f" % [f * 100.0, curve_share(curve, f)])
		var best_f := 1.0
		var best := curve_share(curve, 1.0)
		for i: int in 101:
			var f := i / 100.0
			if f * curve_share(curve, f) > best + 1e-9:
				best = f * curve_share(curve, f)
				best_f = f
		rows.append(row("fee curve %s: best fee (share of ceiling)" % curve, best_f, any,
				"arrivals at %s; earns %.3f of ceiling x arrivals, the ceiling %.3f" % [
					", ".join(at), best, curve_share(curve, 1.0)]))
	# Income models: a day at 9 holes, and the cost scale that paces the nine near day 30.
	var table: Dictionary = COST_TABLES[RUN_TABLE]
	for name: String in INCOMES:
		var e: Dictionary = INCOMES[name]
		for stars: float in [1.0, 3.0, 5.0]:
			var g := guests_for(e, stars, 9)
			var fee := float(e.ceiling) * stars * float(e.fee_share)
			rows.append(row("day %s: 9 holes at %.0f stars, net ($)" % [name, stars],
					roundi(g * fee) - UPKEEP_PER_HOLE * 9, any,
					"%d guests at $%.2f, upkeep $%d" % [g, fee, UPKEEP_PER_HOLE * 9]))
		var at1 := run(e, plan_costs(fx, table, parcel, 1.0), MID_MIX, POINTS[RUN_POINTS], STARTS[RUN_START])
		rows.append(row("run %s: 3-star course at the %s table, day the nine opens" % [name, RUN_TABLE],
				at1.nine_day if int(at1.nine_day) > 0 else INF, any,
				"stalled %d days for money; 3 stars day %d; lowest $%d" % [at1.stalled, at1.star_day, at1.min_money]))
		for case: Array in [["3-star course", MID_MIX, RUN_START], ["4.5-star fair course", FAIR_MIX, RUN_START],
				["3-star course, start 1 star", MID_MIX, "1 star, padded to 50"],
				["3-star course, no pad", MID_MIX, "no pad (mean of what exists, 3 when none)"]]:
			var fit := fit_scale(e, fx, parcel, case[1], POINTS[RUN_POINTS], STARTS[case[2]])
			var s: float = fit.scale
			if s < 0.0:
				rows.append(row("fit %s, %s: cost scale" % [name, case[0]], INF, Vector2(0.0, INF),
						"no scale from 0.01 to 3 opens the nine with 3 stars in 25 to 35 days"))
				continue
			var r: Dictionary = fit.run
			var p3 := price(fx[0].diff, table, s)
			var p5 := price(fx[2].diff, table, s)
			rows.append(row("fit %s, %s: cost scale on %s and land" % [name, case[0], RUN_TABLE], s,
					Vector2(0.0, INF), "nine opens day %d, 3 stars day %d, stalled %d days, lowest $%d; par 3 $%d, par 5 $%d, parcel $%d" % [
						r.nine_day, r.star_day, r.stalled, r.min_money, p3, p5, roundi(parcel * s)]))
			if case[0] == "3-star course":
				run_logs["%s at scale %.2f" % [name, s]] = r.log
	return rows


## The chosen economy's rows (D56 to D58; data/economy.json, data/land.json), against the
## targets: what each fixture costs at the chosen table and land, a day's net, and the run.
func measure_chosen(fx: Array[Dictionary], nn: Dictionary, mix: Array[Dictionary]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var any := Vector2(-INF, INF)
	var table := chosen_table()
	var parts: PackedStringArray = []
	for sname in SURFACES:
		parts.append("%s %d" % [sname, table[sname]])
	parts.append("$%d a step, tee marker $%d, cup $%d" % [table.step, economy.tee_marker_price,
			economy.cup_price])
	var parcel := median_parcel(10, chosen_land)
	rows.append(row("chosen: median parcel, New courses seeds 1 to 10 ($)", parcel, any,
			"price_scale %.2f; table %s" % [chosen_land.price_scale, ", ".join(parts)]))
	for f: Dictionary in fx:
		var target := any
		if String(f.name).begins_with("par 3"):
			target = chosen_band(PAR3_TARGET)
		elif String(f.name).begins_with("par 5"):
			target = chosen_band(PAR5_TARGET)
		rows.append(row("chosen: %s ($)" % f.name, price(f.diff, table), target, _tiles_note(f.diff)))
	var nine_cost := 0
	var nine_land := 0
	for h: Dictionary in nn.holes:
		var hc := price(h.diff, table)
		var lc := parcels_price(nn.after, h.parcels, chosen_land)
		nine_cost += hc
		nine_land += lc
		rows.append(row("chosen: PlaytestNine hole %d, par %d, %d yd ($)" % [h.n, h.par, h.yd], hc,
				chosen_band(PAR5_TARGET) if int(h.par) == 5 else any, "%s; land %d parcels %s" % [
					_tiles_note(h.diff), (h.parcels as Array).size(), LandPrices.money(lc)]))
	rows.append(row("chosen: PlaytestNine, nine holes ($)", nine_cost, any,
			"its land %s more (it spreads over the whole map)" % LandPrices.money(nine_land)))
	var plan := plan_costs(fx, table, parcel, 1.0)
	var build := 0
	var lnd := 0
	for h: Dictionary in plan:
		build += int(h.build)
		lnd += int(h.land)
	rows.append(row("chosen: frugal nine, holes ($)", build, any,
			"land %s more (%d parcels at the median %s)" % [LandPrices.money(lnd),
				ceili(_plan_parcels() - block_parcels()), LandPrices.money(parcel)]))
	var e := chosen_income()
	for stars: float in [1.0, 3.0, 5.0]:
		var fp := chosen_fee(e, stars)
		var g := economy.arrivals(stars, fp.y)
		var fee := int(fp.x)
		rows.append(row("chosen: a day, 9 holes at %.0f stars, fee 80%%, net ($)" % stars,
				g * fee - economy.upkeep_per_open_hole * 9, any,
				"%d guests at $%d (ceiling $%d), upkeep $%d" % [g, fee, floori(economy.fee_ceiling(stars)),
					economy.upkeep_per_open_hole * 9]))
	var pts: Array = Array(economy.rating_points)
	# D58: 3 stars to start (the neutral points), a short window padded with neutral reactions.
	var start: Array = [float(economy.rating_points[1]), rating_window]
	var r3 := run(e, plan, MID_MIX, pts, start)
	run_logs["chosen economy, 3-star course"] = r3.log
	rows.append(row("chosen: 3-star course, day the nine opens",
			r3.nine_day if int(r3.nine_day) > 0 else INF, DAYS_TARGET,
			"stalled %d days for money; a hole every %d days at the soonest" % [r3.stalled,
				BUILD_EVERY_DAYS]))
	rows.append(row("chosen: 3-star course, day 3 stars with nine open",
			r3.star_day if int(r3.star_day) > 0 else INF, DAYS_TARGET, "mix %.2f/%.2f/%.2f" % [
				MID_MIX[0], MID_MIX[1], MID_MIX[2]]))
	rows.append(row("chosen: 3-star course, lowest balance ($)", r3.min_money, Vector2(0.0, INF),
			"balance on day %d %s" % [RUN_DAYS, LandPrices.money(r3.money)]))
	var fit := fit_scale(e, fx, parcel, MID_MIX, pts, start, table)
	rows.append(row("chosen: 3-star course, cost scale on the chosen table nearest day 30",
			fit.scale, any, "1.00 is the table as chosen; E4-S8's slack" if float(fit.scale) > 0.0
				else "none fits"))
	# E4-S8: a player who never moves the slider (start_fee, lowered by a falling ceiling).
	var passive := e.duplicate()
	passive.fee_share = -1.0
	var rp := run(passive, plan, MID_MIX, pts, start)
	run_logs["chosen economy, 3-star course, fee left at the start fee"] = rp.log
	rows.append(row("chosen: 3-star course, fee left at the start fee, day the nine opens",
			rp.nine_day if int(rp.nine_day) > 0 else INF, any,
			"3 stars day %d, stalled %d days, lowest %s; recorded, not a target" % [rp.star_day,
				rp.stalled, LandPrices.money(rp.min_money)]))
	var r45 := run(e, plan, FAIR_MIX, pts, start)
	rows.append(row("chosen: 4.5-star fair course, day the nine opens",
			r45.nine_day if int(r45.nine_day) > 0 else INF, any,
			"stalled %d days; lowest %s; recorded, not a target" % [r45.stalled,
				LandPrices.money(r45.min_money)]))
	var pmix := shares(mix[8])
	var pn := run(e, plan, pmix, pts, start)
	rows.append(row("chosen: PlaytestNine's measured mix, day the nine opens",
			pn.nine_day if int(pn.nine_day) > 0 else INF, any,
			"mix %.2f/%.2f/%.2f, %.1f stars; stalled %d days; 3 stars day %d; recorded, not a target" % [
				pmix[0], pmix[1], pmix[2], stars_of(mean_points(pmix, pts)), pn.stalled, pn.star_day]))
	var pfit := fit_scale(e, fx, parcel, pmix, pts, start, table)
	rows.append(row("chosen: PlaytestNine's measured mix, cost scale on the chosen table nearest day 30",
			pfit.scale, any, ("nine opens day %d, 3 stars day %d, stalled %d days" % [
				pfit.run.nine_day, pfit.run.star_day, pfit.run.stalled]) if float(pfit.scale) > 0.0
				else "none fits: the mix never holds 3 stars"))
	return rows


func _plan_parcels() -> float:
	var n := 0.0
	for p: Array in PLAN:
		n += BalanceSim.footprint_parcels(float(p[1]))
	return n


static func _tiles_note(d: Dictionary) -> String:
	var parts: PackedStringArray = []
	for s in SURFACES:
		if int(d.painted[s]) > 0:
			parts.append("%s %d" % [s, d.painted[s]])
	parts.append("steps %d" % d.steps)
	if int(d.trees_cleared) > 0:
		parts.append("trees cleared %d" % d.trees_cleared)
	if int(d.water_filled) > 0:
		parts.append("water filled %d" % d.water_filled)
	return ", ".join(parts)
