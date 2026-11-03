class_name ClubSet
extends Resource
## The bag: all 12 clubs (docs/design.md Swing), in golf/clubs.tres, longest first.
## Legality follows D13. Read-only for gameplay code; tune with /balance clubs.

const DEFAULT_PATH := "res://golf/clubs.tres"
const COUNT: int = 12

@export var clubs: Array[Club] = []
## Balance target (D18): a full putt (the putter's top speed) on a flat green rolls at most
## this many yards. /balance clubs and tests/test_clubs.gd check it.
@export var full_putt_max_yd: float = 30.0


static func load_default() -> ClubSet:
	return load(DEFAULT_PATH) as ClubSet


## The club with this id, or null.
func club(id: String) -> Club:
	for c in clubs:
		if c.id == id:
			return c
	return null


func putter() -> Club:
	for c in clubs:
		if c.is_putter():
			return c
	return null


## D13, in order: on green the putter only; in a bunker the sand wedge only; anywhere else
## every club but the putter, with the driver only when `driver_stroke` (the hole's first
## stroke, from its tee marker) or from a tee tile. The sand wedge is legal on every lie but
## green.
static func is_legal(c: Club, lie: Surface.Type, driver_stroke: bool) -> bool:
	if lie == Surface.Type.GREEN:
		return c.kind == Club.Kind.PUTTER
	if lie == Surface.Type.BUNKER:
		return c.kind == Club.Kind.SAND_WEDGE
	match c.kind:
		Club.Kind.PUTTER:
			return false
		Club.Kind.DRIVER:
			return driver_stroke or lie == Surface.Type.TEE
		_:
			return true


## D20: true when `shot` (a full club), predicted as `p` from the same Ball step, meets the
## ground or trees while still climbing (ShotPrediction.stopped_climbing): a riser face or
## trees ahead stop it before its apex, so it does not fly to its marker. Every flight that
## gets away comes down descending. The physics is unchanged, so a blocked club can still
## be struck. A putt is never blocked. Guests (E3) read the same rule.
func is_blocked(shot: ShotLaunch, p: ShotPrediction) -> bool:
	if shot == null or p == null or shot.is_putt():
		return false
	return p.stopped_climbing


## The clubs a stroke from `lie` may use, in bag order.
func legal(lie: Surface.Type, driver_stroke: bool) -> Array[Club]:
	var out: Array[Club] = []
	for c in clubs:
		if is_legal(c, lie, driver_stroke):
			out.append(c)
	return out


## Problems with the bag, empty when it is the 12 clubs D13 needs.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if clubs.size() != COUNT:
		errors.append("expected %d clubs, got %d" % [COUNT, clubs.size()])
	var kinds := {}
	var ids := {}
	for c in clubs:
		if c == null:
			errors.append("empty club slot")
			continue
		if ids.has(c.id):
			errors.append("duplicate id %s" % c.id)
		ids[c.id] = true
		kinds[c.kind] = int(kinds.get(c.kind, 0)) + 1
		if c.is_putter():
			if c.putt_min_speed <= 0.0 or c.putt_max_speed <= c.putt_min_speed:
				errors.append("%s: putt speed range must be 0 < min < max" % c.id)
		elif c.carry_yd <= 0.0 or c.launch_deg <= 0.0 or c.launch_deg >= 90.0:
			errors.append("%s: needs a carry and a launch angle between 0 and 90" % c.id)
	for k: Club.Kind in [Club.Kind.DRIVER, Club.Kind.SAND_WEDGE, Club.Kind.PUTTER]:
		if int(kinds.get(k, 0)) != 1:
			errors.append("expected one %s" % Club.Kind.keys()[k].to_lower())
	return errors
