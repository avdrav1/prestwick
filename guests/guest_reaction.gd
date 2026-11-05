class_name GuestReaction
extends RefCounted
## One guest's reaction to one hole it finished (D39; E3-S6; docs/design.md Guests and
## reactions, Pace, Challenge, Fair, Interesting, Tastes, Reaction): the four checks, each
## passed or failed, weighed by the guest's taste (D42), and the verdict, praise, complaint
## or a quiet neutral, with a line that names the hole for the feed (E3-S7).
##
##   Fair: the tee shot is not blind (HoleChecks, D43). Purist: counts double.
##   Interesting: a hazard on the line and a safe way round it (HoleChecks). Adventurer: double.
##   Pace: the counted wait at most wait_base_s + wait_per_patience_s x patience, and the walk
##     from the previous cup at most walk_base_yd + walk_per_patience_yd x patience.
##   Challenge: the score within challenge_within of the expected score (D40), over or under;
##     Casual: casual_challenge_within.
##
## Praise when `praise_passes` checks pass (all four); complaint when the failed checks,
## a doubled one counting `doubled_check_weight`, reach `complaint_fails`; else neutral.
## Every number is in data/guests.json (GuestTuning).

enum Kind { PRAISE, NEUTRAL, COMPLAINT }
enum Check { FAIR, INTERESTING, PACE, CHALLENGE }

const KIND_NAMES: PackedStringArray = ["praise", "neutral", "complaint"]
const CHECK_NAMES: PackedStringArray = ["fair", "interesting", "pace", "challenge"]
## Float slack for the challenge band's ends (both included).
const EPS: float = 1e-6

## The hole it names.
var hole_number: int = 0
var guest_id: int = 0
var taste: Guest.Taste = Guest.Taste.PURIST
var kind: Kind = Kind.NEUTRAL
## Passed, per Check.
var passed: Array[bool] = [true, true, true, true]
## Weight of each Check for this guest's taste (1, or doubled_check_weight).
var weights: Array[int] = [1, 1, 1, 1]
## The failed checks' weights summed.
var fail_weight: int = 0
## The guest's score and what it expected (Challenge), its wait and walk and their limits.
var score: int = 0
var par: int = 0
var expected: float = 0.0
var wait_s: int = 0
var wait_limit_s: float = 0.0
var walk_yd: float = -1.0
var walk_limit_yd: float = 0.0
## The hole's statics as the checks read them.
var statics: HoleChecks.Statics
## One line for the feed, naming the hole ("Hole 3: blind from the tee, could not see the flag.
## I hate blind shots. Also slow (20 s wait).").
var text: String = ""


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
	r.walk_limit_yd = walk_limit(guest.patience, tuning)
	r.passed[Check.FAIR] = statics.fair()
	r.passed[Check.INTERESTING] = statics.interesting()
	r.passed[Check.PACE] = pace_passes(record, guest.patience, tuning)
	r.passed[Check.CHALLENGE] = challenge_passes(record, guest.skill, guest.taste, tuning)
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


## Pace's walk limit for `patience`, yards.
static func walk_limit(patience: int, tuning: GuestTuning) -> float:
	return tuning.walk_base_yd + tuning.walk_per_patience_yd * patience


## Pace: the counted wait and the walk from the previous cup (none on a first hole, -1) are
## each within the guest's limit (over it fails).
static func pace_passes(record: Guest.HoleRecord, patience: int, tuning: GuestTuning) -> bool:
	if record.wait_s > wait_limit(patience, tuning):
		return false
	return record.walk_yd < 0.0 or record.walk_yd <= walk_limit(patience, tuning)


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


## The feed line (E3-S7): "Hole N:", then the heaviest failed check (a taste's doubled one,
## else the first in Check order) as its own sentence with the taste's word, then the other
## failed checks in their short form after "Also", commas and one final "and", so a line of
## four fails stays short and its one reason that matters reads first. A neutral has one fail.
func _line() -> String:
	var head := "Hole %d: " % hole_number
	if kind == Kind.PRAISE:
		return head + "loved it, %d on a par %d." % [score, par]
	var lead := lead_check()
	if kind == Kind.NEUTRAL:
		return head + "fine, but %s." % _reason(lead)
	var line := head + "%s." % _reason(lead)
	if weights[lead] > 1:
		line += " " + _taste_line(lead)
	var rest := PackedStringArray()
	for c: int in Check.size():
		if c != lead and not passed[c]:
			rest.append(_short_reason(c))
	if not rest.is_empty():
		line += " Also %s." % _and_list(rest)
	return line


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
			if wait_s > wait_limit_s:
				return "slow, waited %d s" % wait_s
			return "a long walk to the tee, %d yd" % roundi(walk_yd)
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
			if wait_s > wait_limit_s:
				return "slow (%d s wait)" % wait_s
			return "a long walk (%d yd)" % roundi(walk_yd)
		_:
			if score > expected:
				return "too hard (%d on a par %d)" % [score, par]
			return "too easy (%d on a par %d)" % [score, par]


## The taste's own sentence for its doubled check.
func _taste_line(c: int) -> String:
	match c:
		Check.FAIR:
			return "I hate blind shots."
		Check.INTERESTING:
			return "I want risk and reward."
		_:
			return ""
