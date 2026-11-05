extends GutTest
## E3-S8: /balance reactions (scripts/reaction_field.gd, ReactionField.measure). A field
## of guests drawn as the day draws them plays one hole through GuestBrain, day after day, and
## its reactions are read against docs/design.md Balance targets, reactions: a fair par 4
## gets 60 to 75% praise and under 15% complaints, and a blind one clearly worse. The fixture
## holes are tests/fixtures/reaction_holes.gd. The full field of 50 (and the nine-hole day)
## is the sim's run (`--table reactions --runs 50`); here a smaller field checks the rows.

const SEED: int = 1
## Guests in the field here; the target's field is FIELD_TARGET.
const SMALL: int = 12

var sim: ReactionField


func before_all() -> void:
	sim = ReactionField.new()


func _named(rows: Array[Dictionary], prefix: String) -> Dictionary:
	for r in rows:
		if String(r.name).begins_with(prefix):
			return r
	return {}


func test_the_fixture_holes_are_open_and_their_statics_are_as_named() -> void:
	var checks := HoleChecks.new()
	var fair := ReactionHoles.fair_par4()
	assert_eq(fair.holes.size(), 1)
	assert_true(fair.holes[0].open, "the fair par 4 passes every rule")
	assert_eq(fair.holes[0].par, 4)
	var s := checks.statics(fair, fair.holes[0])
	assert_true(s.fair(), "seen from the tee")
	assert_true(s.interesting(), "a hazard on the line and a way round")
	var blind := ReactionHoles.blind_par4()
	assert_true(blind.holes[0].open)
	var b := checks.statics(blind, blind.holes[0])
	assert_true(b.blind, "the ridge hides the landing zone")
	assert_true(b.interesting(), "and only fair changes")
	var dog := ReactionHoles.dogleg_par4()
	assert_true(dog.holes[0].open, "rule 4 makes the dogleg a par 4 by its straight line")
	assert_true(checks.statics(dog, dog.holes[0]).interesting(), "the pond in the corner is on the line")
	var corridor := ReactionHoles.corridor_par4(SEED)
	assert_not_null(corridor, "the corridor par 4 opens on land seed %d" % SEED)
	if corridor != null:
		var owned := 0
		for q: int in corridor.parcels_high:
			for p: int in corridor.parcels_wide:
				if corridor.is_parcel_owned(Vector2i(p, q)):
					owned += 1
		assert_eq(owned, corridor.parcels_wide, "one parcel row owned: an 80 yd corridor")


func test_a_field_plays_the_hole_through_the_guest_day() -> void:
	var c := ReactionHoles.fair_par4()
	var field := sim.play_field(c, SMALL, SEED)
	assert_eq(field.size(), SMALL, "the first %d hole records" % SMALL)
	var ids := {}
	for e: Dictionary in field:
		var g: Guest = e.guest
		var r: Guest.HoleRecord = e.record
		assert_eq(r.number, 1)
		assert_not_null(r.reaction, "every record has its reaction")
		ids[Vector2i(e.day, g.id)] = true
	assert_eq(ids.size(), SMALL, "one record a guest")
	var again := sim.play_field(ReactionHoles.fair_par4(), SMALL, SEED)
	for i in SMALL:
		var a: Guest.HoleRecord = field[i].record
		var b: Guest.HoleRecord = again[i].record
		assert_eq([a.score, a.wait_s, a.reaction.kind], [b.score, b.wait_s, b.reaction.kind],
				"the same seed gives the same field")


func test_reaction_rows_print_next_to_their_targets() -> void:
	var rows := sim.measure(SMALL, SEED, 1)
	for prefix: String in ["fair par 4: praise", "fair par 4: complaints",
			"blind par 4: praise", "blind par 4: complaints",
			"corridor par 4", "dogleg par 4", "nine holes"]:
		assert_false(_named(rows, prefix).is_empty(), "a row for %s" % prefix)
	var praise := _named(rows, "fair par 4: praise")
	assert_eq(praise.target, ReactionField.FAIR_PRAISE, "praise is read against 60 to 75%")
	var blind := _named(rows, "blind par 4: praise")
	assert_lte(float(blind.measured), float(praise.measured) * 0.5 + 1e-6,
			"a blind hole clearly scores worse")
	var nine := _named(rows, "nine holes, New sandbox: days reaching every hole")
	assert_true(nine.ok, "the nine-hole day reaches every hole: %s" % nine.note)


func test_the_fair_par_4_hits_its_target_with_a_field_of_50() -> void:
	var c := ReactionHoles.fair_par4()
	var field := sim.play_field(c, ReactionField.FIELD_TARGET, SEED)
	var tally := ReactionField.tally(field)
	assert_between(float(tally.praise), ReactionField.FAIR_PRAISE.x, ReactionField.FAIR_PRAISE.y,
			"praise share of %d guests" % ReactionField.FIELD_TARGET)
	assert_lt(float(tally.complaints), ReactionField.FAIR_COMPLAINTS.y + 1e-6, "complaints under 15%")
	var blind := ReactionField.tally(sim.play_field(ReactionHoles.blind_par4(), ReactionField.FIELD_TARGET, SEED))
	assert_eq(float(blind.praise), 0.0, "nobody praises a blind hole")
	assert_gt(float(blind.complaints), float(tally.complaints) + 0.25, "and many more complain")
