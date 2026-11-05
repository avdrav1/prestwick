class_name GuestSpawner
extends RefCounted
## The day's guests (E3-S4; docs/design.md Guests and reactions, Arrivals until E4 and Skill
## and patience draw), all drawn from the day's seed, never the clock:
##
## - group sizes, each of `group_size_min` to `group_size_max` equally likely, until
##   `arrivals_per_day` guests (the last group cut to fit);
## - group i of n arrives at i × `arrival_window_s` / n seconds from morning (D46: seconds,
##   whatever `day_s` is);
## - then, guest by guest in arrival order: skill (`skill_min` to `skill_max`), patience
##   (`patience_min` to `patience_max`), each whole value equally likely; taste by
##   `taste_weights`; and a seed of its own for its holes.
##
## E4-S5 replaces `arrivals_per_day` with arrivals by rating.


## The groups of the day of `day_seed`, in arrival order, every guest numbered.
static func day(tuning: GuestTuning, day_seed: int) -> Array[GuestGroup]:
	var rng := RandomNumberGenerator.new()
	rng.seed = day_seed
	var sizes: Array[int] = []
	var left := tuning.arrivals_per_day
	while left > 0:
		var n := mini(rng.randi_range(tuning.group_size_min, tuning.group_size_max), left)
		sizes.append(n)
		left -= n
	var groups: Array[GuestGroup] = []
	var gap := tuning.arrival_window_s / maxf(sizes.size(), 1.0)
	var id := 0
	for i in sizes.size():
		var g := GuestGroup.new()
		g.index = i
		g.arrive_s = i * gap
		for place in sizes[i]:
			var guest := draw_guest(tuning, rng)
			guest.id = id
			guest.group_id = i
			guest.place = place
			id += 1
			g.guests.append(guest)
		groups.append(g)
	return groups


## One guest drawn from `rng`: skill, patience, taste, seed, in that order.
static func draw_guest(tuning: GuestTuning, rng: RandomNumberGenerator) -> Guest:
	var guest := Guest.new()
	guest.skill = rng.randi_range(tuning.skill_min, tuning.skill_max)
	guest.patience = rng.randi_range(tuning.patience_min, tuning.patience_max)
	guest.taste = draw_taste(tuning, rng)
	guest.guest_seed = rng.randi()
	return guest


## A taste by `taste_weights`, read in Guest.TASTE_NAMES order (never the file's key order).
static func draw_taste(tuning: GuestTuning, rng: RandomNumberGenerator) -> Guest.Taste:
	var total := 0.0
	for name: String in Guest.TASTE_NAMES:
		total += maxf(float(tuning.taste_weights.get(name, 0.0)), 0.0)
	var r := rng.randf() * total
	for i in Guest.TASTE_NAMES.size():
		var w := maxf(float(tuning.taste_weights.get(Guest.TASTE_NAMES[i], 0.0)), 0.0)
		if r < w:
			return i as Guest.Taste
		r -= w
	return (Guest.TASTE_NAMES.size() - 1) as Guest.Taste


## A group built by hand (tests, scripts): `guests` is a list of [skill, patience, taste,
## seed]. Ids follow `first_id`.
static func group(index: int, arrive_s: float, specs: Array, first_id: int = 0) -> GuestGroup:
	var g := GuestGroup.new()
	g.index = index
	g.arrive_s = arrive_s
	for place in specs.size():
		var s: Array = specs[place]
		var guest := Guest.new()
		guest.skill = s[0]
		guest.patience = s[1]
		guest.taste = s[2]
		guest.guest_seed = s[3]
		guest.id = first_id + place
		guest.group_id = index
		guest.place = place
		g.guests.append(guest)
	return g
