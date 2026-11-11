class_name GuestReaction
extends RefCounted
## One guest's reaction to one hole it finished (D39; E3-S6; docs/design.md Guests and
## reactions, Pace, Challenge, Fair, Interesting, Walk, Tastes, Reaction): the five checks, each
## passed or failed, weighed by the guest's taste (D42), and the verdict, praise, complaint
## or a quiet neutral, with a line that names the hole for the feed (E3-S7).
##
##   Fair: the tee shot is not blind (HoleChecks, D43). Purist: counts double.
##   Interesting: a hazard on the line and a safe way round it (HoleChecks). Adventurer: double.
##   Pace: the counted wait at most wait_base_s + wait_per_patience_s x patience (E9-S2: the
##     waits alone; the walk to the tee was part of it until then).
##   Challenge: the score within challenge_within of the expected score (D40), over or under;
##     Casual: casual_challenge_within.
##   Walk (E9-S2, D65): the walk to this tee, from the previous hole's green or on the round's
##     first hole from the clubhouse door, fails when it took over walk_base_s +
##     walk_per_patience_s x patience simulated seconds and did not follow a cart path (at
##     least walk_path_share of its yards on path). It weighs walk_check_weight (2), so a long
##     walk alone makes the hole a complaint naming it. One E5-S11's clubhouse walk and the walk
##     between holes share. A walk that followed a path and passed, where with no path laid it
##     would have failed (GuestWalk.bare_s), is named in the hole's praise: the path made it
##     quick.
##
## Praise when `praise_passes` checks pass (all five); complaint when the failed checks,
## a doubled one counting `doubled_check_weight` (the walk `walk_check_weight`), reach
## `complaint_fails`; else neutral. Every number is in data/guests.json (GuestTuning).

enum Kind { PRAISE, NEUTRAL, COMPLAINT }
enum Check { FAIR, INTERESTING, PACE, CHALLENGE, WALK }

const KIND_NAMES: PackedStringArray = ["praise", "neutral", "complaint"]
const CHECK_NAMES: PackedStringArray = ["fair", "interesting", "pace", "challenge", "walk"]
## E3-S44: the checks as the player reads them, in Check order: the one set of
## player-facing words the hole panel's hover, the feed's hover and docs/design.md use (the
## code names above stay internal).
const CHECK_WORDS: PackedStringArray = ["sight line", "risk and reward", "pace", "difficulty",
		"walk"]
## Float slack for the challenge band's ends (both included).
const EPS: float = 1e-6

## The hole it names.
var hole_number: int = 0
var guest_id: int = 0
var taste: Guest.Taste = Guest.Taste.PURIST
var kind: Kind = Kind.NEUTRAL
## Passed, per Check.
var passed: Array[bool] = [true, true, true, true, true]
## Weight of each Check for this guest's taste (1, or doubled_check_weight; the walk
## walk_check_weight).
var weights: Array[int] = [1, 1, 1, 1, 1]
## The failed checks' weights summed.
var fail_weight: int = 0
## The guest's score and what it expected (Challenge), its wait and walk and their limits.
var score: int = 0
var par: int = 0
var expected: float = 0.0
var wait_s: int = 0
var wait_limit_s: float = 0.0
var walk_yd: float = -1.0
## E9-S1: the walk's time and its limit, simulated seconds (walk_limit_yd before).
var walk_s: float = -1.0
var walk_limit_s: float = 0.0
## E5-S11: the walk was from the clubhouse door (the round's first hole), not a previous cup.
var from_clubhouse: bool = false
## E9-S2: the hole whose green the walk left (0 from the clubhouse), whether it followed a cart
## path (walk_path_share of its yards), and whether that path made it quick (with no path laid
## the walk would have taken over the limit).
var walk_from_hole: int = 0
var walk_on_path: bool = false
var path_made_quick: bool = false
## The hole's statics as the checks read them.
var statics: HoleChecks.Statics
## One line for the feed, naming the hole ("Hole 3: blind from the tee, could not see the flag.
## I hate blind shots. Also slow (20 s wait).").
var text: String = ""
## E3-S44: the line's lead sentence, without "Hole N: " (the reason that matters, with its
## full stop), and what follows it (the taste's sentence and "Also ...", or ""). `text` is
## "Hole N: " + lead + " " + rest, but the parts are kept, never found again by splitting.
var _lead: String = ""
var _rest: String = ""


## `guest`'s reaction to `record` (a hole it finished), with the hole's `statics`.
static func judge(guest: Guest, record: Guest.HoleRecord, statics: HoleChecks.Statics,
		tuning: GuestTuning) -> GuestReaction:
	var r := GuestReaction.new()
	r.hole_number = record.number
	r.guest_id = guest.id
	r.taste = guest.taste
	r.statics = statics
	r.score = record.score
	r.par = record.par
	r.expected = tuning.expected_score(record.par, guest.skill)
	r.wait_s = record.wait_s
	r.wait_limit_s = wait_limit(guest.patience, tuning)
	r.walk_yd = record.walk_yd
	r.walk_s = record.walk_s
	r.from_clubhouse = record.walk_from_clubhouse
	r.walk_from_hole = record.walk_from_hole
	r.walk_limit_s = walk_limit(guest.patience, tuning)
	r.walk_on_path = record.walk_s >= 0.0 and record.walk_path_share >= tuning.walk_path_share
	r.path_made_quick = r.walk_on_path and record.walk_s <= r.walk_limit_s + EPS \
			and record.walk_bare_s > r.walk_limit_s + EPS
	r.passed[Check.FAIR] = statics.fair()
	r.passed[Check.INTERESTING] = statics.interesting()
	r.passed[Check.PACE] = pace_passes(record, guest.patience, tuning)
	r.passed[Check.CHALLENGE] = challenge_passes(record, guest.skill, guest.taste, tuning)
	r.passed[Check.WALK] = walk_passes(record, guest.patience, tuning)
	r.weights[Check.WALK] = tuning.walk_check_weight
	if guest.taste == Guest.Taste.PURIST:
		r.weights[Check.FAIR] = tuning.doubled_check_weight
	elif guest.taste == Guest.Taste.ADVENTURER:
		r.weights[Check.INTERESTING] = tuning.doubled_check_weight
	var passes := 0
	for c: int in Check.size():
		if r.passed[c]:
			passes += 1
		else:
			r.fail_weight += r.weights[c]
	if passes >= tuning.praise_passes:
		r.kind = Kind.PRAISE
	elif r.fail_weight >= tuning.complaint_fails:
		r.kind = Kind.COMPLAINT
	else:
		r.kind = Kind.NEUTRAL
	r.text = r._line()
	return r


## Pace's wait limit for `patience`, seconds.
static func wait_limit(patience: int, tuning: GuestTuning) -> float:
	return tuning.wait_base_s + tuning.wait_per_patience_s * patience


## The Walk check's limit for `patience`, simulated seconds (E9-S2; pace's walk limit in E9-S1,
## yards before).
static func walk_limit(patience: int, tuning: GuestTuning) -> float:
	return tuning.walk_base_s + tuning.walk_per_patience_s * patience


## Pace: the counted wait is within the guest's limit (over it fails). E9-S2: the waits alone;
## the walk to the tee is the Walk check's (pace judged it, by yards until E9-S1, by time in it).
static func pace_passes(record: Guest.HoleRecord, patience: int, tuning: GuestTuning) -> bool:
	return record.wait_s <= wait_limit(patience, tuning)


## E9-S2 (D65): the walk to the tee (from the previous green, or the clubhouse door on the round's
## first hole; -1 for none) passes when it took at most the guest's walk_limit, or followed a
## cart path (at least walk_path_share of its yards on path): a long walk without a path fails.
static func walk_passes(record: Guest.HoleRecord, patience: int, tuning: GuestTuning) -> bool:
	if record.walk_s < 0.0 or record.walk_s <= walk_limit(patience, tuning) + EPS:
		return true
	return record.walk_path_share >= tuning.walk_path_share


## Challenge: the score is within the band of the expected score, both ends included.
static func challenge_passes(record: Guest.HoleRecord, skill: int, taste: Guest.Taste,
		tuning: GuestTuning) -> bool:
	var within := tuning.casual_challenge_within if taste == Guest.Taste.CASUAL \
			else tuning.challenge_within
	return absf(record.score - tuning.expected_score(record.par, skill)) <= within + EPS


func kind_name() -> String:
	return KIND_NAMES[kind]


func is_praise() -> bool:
	return kind == Kind.PRAISE


func is_complaint() -> bool:
	return kind == Kind.COMPLAINT


## The failed checks' names, in Check order.
func failed() -> PackedStringArray:
	var out := PackedStringArray()
	for c: int in Check.size():
		if not passed[c]:
			out.append(CHECK_NAMES[c])
	return out


## E3-S44: the lead sentence, without "Hole N: ": a praise's whole line, a neutral's, or a
## complaint's heaviest failed check in the guest's words, with its full stop. A reason may hold
## ". " itself: the lead is kept as built, not split out of `text`.
## A reaction given only a `text` (a test's or a tool's, never judged) leads with its whole body.
func lead_line() -> String:
	return _lead if not _lead.is_empty() else body_line()


## The line without its "Hole N: " (the hole panel names the hole).
func body_line() -> String:
	if _lead.is_empty():
		var head := "Hole %d: " % hole_number
		return text.substr(head.length()) if text.begins_with(head) else text
	return _lead if _rest.is_empty() else _lead + " " + _rest


## E3-S44: the checks this reaction failed in the player's words (CHECK_WORDS), in Check order.
func failed_words() -> PackedStringArray:
	var out := PackedStringArray()
	for c: int in Check.size():
		if not passed[c]:
			out.append(CHECK_WORDS[c])
	return out


## "Failed: sight line, pace and difficulty." for the hover texts, or "" with no fail.
func failed_line() -> String:
	var words := failed_words()
	return "" if words.is_empty() else "Failed: %s." % _and_list(words)


## The feed line (E3-S7): "Hole N:", then the heaviest failed check (a taste's doubled one,
## else the first in Check order) as its own sentence with the taste's word, then the other
## failed checks in their short form after "Also", commas and one final "and", so a line of
## four fails stays short and its one reason that matters reads first. A neutral has one fail.
## Sets the lead sentence and the rest (lead_line, body_line) as it builds the line.
func _line() -> String:
	_rest = ""
	if kind == Kind.PRAISE:
		if path_made_quick:
			# E9-S2: the path turned what would have been a long walk into a quick one.
			_lead = "loved it, %d on a par %d, and the cart path %s made the walk quick." % [
					score, par, _walk_from()]
		else:
			_lead = "loved it, %d on a par %d." % [score, par]
	elif kind == Kind.NEUTRAL:
		_lead = "fine, but %s." % _reason(lead_check())
	else:
		var lead := lead_check()
		_lead = "%s." % _reason(lead)
		var after := PackedStringArray()
		if weights[lead] > 1 and not _taste_line(lead).is_empty():
			after.append(_taste_line(lead))
		var rest := PackedStringArray()
		for c: int in Check.size():
			if c != lead and not passed[c]:
				rest.append(_short_reason(c))
		if not rest.is_empty():
			after.append("Also %s." % _and_list(rest))
		_rest = " ".join(after)
	return "Hole %d: " % hole_number + body_line()


## The failed check the line leads with: the heaviest, ties in Check order; -1 with no fail.
func lead_check() -> int:
	var lead := -1
	for c: int in Check.size():
		if not passed[c] and (lead < 0 or weights[c] > weights[lead]):
			lead = c
	return lead


## "a", "a and b", "a, b and c".
static func _and_list(items: PackedStringArray) -> String:
	if items.size() <= 1:
		return "".join(items)
	return ", ".join(items.slice(0, items.size() - 1)) + " and " + items[items.size() - 1]


func _reason(c: int) -> String:
	match c:
		Check.FAIR:
			return "blind from the tee, could not see the %s" % ("landing area" if statics.target_is_zone else "flag")
		Check.INTERESTING:
			if not statics.hazard_on_line:
				return "nothing in the way, nothing to think about"
			return "no way round the trouble"
		Check.PACE:
			return "slow, waited %d s" % wait_s
		Check.WALK:
			return "a long walk %s to the %s tee, %d yd and no cart path" % [_walk_from(),
					ordinal(hole_number), roundi(walk_yd)]
		_:
			if score > expected:
				return "too hard, %d on a par %d" % [score, par]
			return "too easy, %d on a par %d" % [score, par]


## A failed check after the lead, in a few words.
func _short_reason(c: int) -> String:
	match c:
		Check.FAIR:
			return "blind"
		Check.INTERESTING:
			if not statics.hazard_on_line:
				return "dull"
			return "no way round the trouble"
		Check.PACE:
			return "slow (%d s wait)" % wait_s
		Check.WALK:
			return "a long walk %s (%d yd, no cart path)" % [_walk_from(), roundi(walk_yd)]
		_:
			if score > expected:
				return "too hard (%d on a par %d)" % [score, par]
			return "too easy (%d on a par %d)" % [score, par]


## E9-S2: where the walk to this tee began, as a guest says it: "from the clubhouse" or "from
## the 4th green".
func _walk_from() -> String:
	if from_clubhouse or walk_from_hole <= 0:
		return "from the clubhouse"
	return "from the %s green" % ordinal(walk_from_hole)


## "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st".
static func ordinal(n: int) -> String:
	var tail := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				tail = "st"
			2:
				tail = "nd"
			3:
				tail = "rd"
	return "%d%s" % [n, tail]


## The taste's own sentence for its doubled check.
func _taste_line(c: int) -> String:
	match c:
		Check.FAIR:
			return "I hate blind shots."
		Check.INTERESTING:
			return "I want risk and reward."
		_:
			return ""


## E4-S7: this reaction as the game save keeps it (GameSave, the feed's window): what the tags,
## the hole panel's line and E4-S5's rating read. The hole's statics are not kept: they only
## build the line, which is kept whole (`text` and its lead and rest).
func to_save() -> Dictionary:
	return {
		"hole": hole_number, "guest": guest_id, "taste": int(taste), "kind": int(kind),
		"passed": passed.duplicate(), "weights": weights.duplicate(), "fail_weight": fail_weight,
		"score": score, "par": par, "expected": expected, "wait_s": wait_s,
		"wait_limit_s": wait_limit_s, "walk_yd": walk_yd, "walk_s": walk_s,
		"walk_limit_s": walk_limit_s,
		"from_clubhouse": from_clubhouse, "walk_from_hole": walk_from_hole,
		"walk_on_path": walk_on_path, "path_made_quick": path_made_quick,
		"text": text, "lead": _lead, "rest": _rest,
	}


## The reaction `d` (to_save) holds, or null with the reasons appended to `errors`.
static func from_save(d: Variant, errors: Array[String], context: String = "reaction") -> GuestReaction:
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("%s must be an object" % context)
		return null
	var data: Dictionary = d
	var start := errors.size()
	var r := GuestReaction.new()
	r.hole_number = CourseData.read_int(data, "hole", errors, context)
	r.guest_id = CourseData.read_int(data, "guest", errors, context)
	var t := CourseData.read_int(data, "taste", errors, context)
	var k := CourseData.read_int(data, "kind", errors, context)
	if t < 0 or t >= Guest.Taste.size():
		errors.append("%s: taste %d is not a taste" % [context, t])
	if k < 0 or k >= Kind.size():
		errors.append("%s: kind %d is not a kind" % [context, k])
	r.taste = t as Guest.Taste
	r.kind = k as Kind
	var p: Variant = data.get("passed")
	var w: Variant = data.get("weights")
	# E9-S2: a save from before the Walk check lists four checks; its walk passed (the walk was
	# part of pace then) and weighs 1.
	var listed := (p as Array).size() if typeof(p) == TYPE_ARRAY else -1
	if listed < Check.WALK or listed > Check.size() or typeof(w) != TYPE_ARRAY \
			or (w as Array).size() != listed:
		errors.append("%s: passed and weights must list %d checks" % [context, Check.size()])
	else:
		for c: int in listed:
			r.passed[c] = bool(p[c])
			r.weights[c] = int(w[c])
	r.fail_weight = CourseData.read_int(data, "fail_weight", errors, context)
	r.score = CourseData.read_int(data, "score", errors, context)
	r.par = CourseData.read_int(data, "par", errors, context)
	r.wait_s = CourseData.read_int(data, "wait_s", errors, context)
	r.expected = float(data.get("expected", 0.0))
	r.wait_limit_s = float(data.get("wait_limit_s", 0.0))
	r.walk_yd = float(data.get("walk_yd", -1.0))
	r.walk_s = float(data.get("walk_s", -1.0))  # E9-S1; -1 in older saves
	r.walk_limit_s = float(data.get("walk_limit_s", 0.0))
	r.from_clubhouse = bool(data.get("from_clubhouse", false))  # E5-S11; false in older saves
	r.walk_from_hole = int(data.get("walk_from_hole", 0))  # E9-S2; 0 in older saves
	r.walk_on_path = bool(data.get("walk_on_path", false))
	r.path_made_quick = bool(data.get("path_made_quick", false))
	r.text = str(data.get("text", ""))
	r._lead = str(data.get("lead", ""))
	r._rest = str(data.get("rest", ""))
	return null if errors.size() > start else r
