class_name GuestClubTable
extends RefCounted
## D41: a guest picks its club by "flat total on fairway", the Clubs table's last row
## (docs/design.md Swing, Clubs). That row is measured, not tuned, so it is measured here the
## same way (`scripts/sim.gd --table clubs`): each full club's perfect swing (100% power,
## accuracy at the centre) from flat fairway, run to rest by the real Ball. Measured once per
## bag a run, on a strip of its own, so it follows /balance clubs with no copy of the numbers.
## It is the guest's idea of its bag, not Ball work on the course, so no tick budget pays it.
##
## Cost: 11 predictions, about 80 to 110 ms headless, in one call. Left lazy, it lands in the
## sim step of the first guest's first plan; E3-S4 calls `warm` when Play or the day starts,
## before any guest ticks. A bag loaded from files is keyed by their resource paths, so a
## fresh `ShotModel.new()` (a new ClubSet instance from ClubSet.load_default) is not measured
## again; a bag built in code is keyed by its instances, which the cache holds.

## A flat fairway strip long enough for the driver's roll (BalanceStrips' size).
const STRIP_W: int = 120
const STRIP_H: int = 24
const START_TILE: Vector2i = Vector2i(4, 12)
const SEED: int = 1

## {key: {club id: total yards}}, and the resources behind keys built from instances.
static var _cache: Dictionary = {}
static var _held: Dictionary = {}


## Measures `model`'s table now if it is not yet measured (before guests tick, E3-S4).
static func warm(model: ShotModel) -> void:
	totals(model)


## True when `model`'s table is already measured, so `totals` costs nothing.
static func is_warm(model: ShotModel) -> bool:
	return _cache.has(_key(model))


## {club id: total yards} for every full club of `model`'s bag.
static func totals(model: ShotModel) -> Dictionary:
	var key := _key(model)
	if _cache.has(key):
		return _cache[key]
	var strip := CourseData.create(STRIP_W, STRIP_H, Surface.Type.FAIRWAY, 0)
	var field := HeightField.new(strip, model.params)
	var at := field.tile_center(START_TILE)
	var out := {}
	for c: Club in model.clubs.clubs:
		if c.is_putter():
			continue
		var shot := model.full(field, c, 1.0, at, 0.0)
		var p := ShotPrediction.run_launch(strip, SEED, shot, model.params)
		out[c.id] = Vector2(p.rest.x, p.rest.y).distance_to(at)
	_cache[key] = out
	if key.begins_with("#"):
		_held[key] = [model.clubs, model.lies, model.params]
	return out


## The totals depend on the clubs, the lie table (fairway) and the ball: their resource paths
## when all three come from files, else their instances ("#" keys).
static func _key(model: ShotModel) -> String:
	var parts: Array[Resource] = [model.clubs, model.lies, model.params]
	var paths := PackedStringArray()
	for r in parts:
		if r.resource_path.is_empty() or r.resource_path.contains("::"):
			return "#%d/%d/%d" % [model.clubs.get_instance_id(), model.lies.get_instance_id(),
					model.params.get_instance_id()]
		paths.append(r.resource_path)
	return "|".join(paths)
