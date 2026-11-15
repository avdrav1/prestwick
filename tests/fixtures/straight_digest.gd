class_name StraightDigest
extends RefCounted
## E20-S1 (D74): a digest of many straight strokes on Dogleg Hollow, recorded before shot shape
## existed, so tests/test_shot_shape.gd can check that a Straight shot is byte for byte the
## flight it was: every hole's tee, four clubs, three aims, a centred, an early, a late and a
## shanked swing at several powers, and a putt beside each cup; every tick's position, the
## landing, the rest and the tick count of each, hashed in order.

## SHA-256 of `digest()` on main before E20 (commit 3e89d10).
const BEFORE_E20: String = "9d49f155be045d9089add8f4cb268ceff6d44a605c6c128309e17338916c9029"
## E20-S3: the digest's strokes are played on Dogleg Hollow as it was then (version 1, the
## file kept beside the other shipped versions), since the retouch moved its corners.
const V1_PATH: String = "res://tests/fixtures/famous_old/dogleg_hollow_v1.json"


static func digest() -> String:
	var course := CourseSave.load_file(V1_PATH)
	var model := ShotModel.new()
	var field := HeightField.new(course, model.params)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var n := 0
	for h: HoleData in course.holes:
		var at := field.tile_center(h.tee)
		var aim := rad_to_deg((field.tile_center(h.cup) - at).angle())
		for id: String in ["driver", "5i", "9i", "sw"]:
			var club := model.clubs.club(id)
			for turn: float in [-12.0, 0.0, 12.0]:
				for result: Vector2 in [Vector2(1.0, 0.0), Vector2(0.8, 0.15), Vector2(1.05, -0.08),
						Vector2(0.9, 0.25)]:
					var s := Swing.new()
					s.set_result(result.x, result.y)
					n += 1
					var shot := s.launch(model, field, club, at, aim + turn)
					var p := ShotPrediction.run_launch(course, n, shot, null, null, h.cup)
					ctx.update(var_to_bytes(p.path))
					ctx.update(var_to_bytes([p.landing, p.rest, p.ticks, p.holed, p.penalty_strokes]))
		var putt := Swing.new()
		putt.set_result(0.4, 0.05)
		n += 1
		var g := field.tile_center(h.cup) + Vector2(7.5, 2.5)
		var ps := putt.launch(model, field, model.clubs.putter(), g, 200.0)
		var pp := ShotPrediction.run_launch(course, n, ps, null, null, h.cup)
		ctx.update(var_to_bytes(pp.path))
		ctx.update(var_to_bytes([pp.rest, pp.ticks, pp.holed]))
	return ctx.finish().hex_encode()
