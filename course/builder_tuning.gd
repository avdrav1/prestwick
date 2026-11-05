class_name BuilderTuning
extends Resource
## Designer-tuned numbers for the terrain builder. Loaded from res://course/builder_tuning.tres.

const PATH: String = "res://course/builder_tuning.tres"

## Brush widths in tiles, smallest first. Each is odd so the brush centers on the cursor tile.
@export var brush_sizes: PackedInt32Array = PackedInt32Array([1, 3, 5])
## Undo steps kept; the oldest falls off past this.
@export var undo_limit: int = 200
## The blank plot a New sandbox starts on (D10): its size in tiles, and the surface and whole
## height of every tile.
@export var plot_size: Vector2i = Vector2i(128, 128)
@export var plot_surface: Surface.Type = Surface.Type.ROUGH
@export_range(0, 7) var plot_ground: int = 2
## The par the tee and cup tools give a new hole until the player picks another (3, 4 or 5).
@export_range(3, 5) var default_par: int = 3
## The most holes a course may have; holes are numbered 1 to this (E3-S2, a nine-hole course).
@export_range(1, 18) var max_holes: int = 9
## How far past its resting height an issue text box may be pushed up to clear its
## neighbours, screen px at every zoom; past that it moves sideways instead (E2-S17).
@export var issue_box_max_stack: float = 96.0
## How far sideways off centre an issue text box may move, screen px at every zoom; a box
## that fits nowhere within both limits collapses to its badge, and the hole panel lists its
## reasons (E2-S17).
@export var issue_box_max_side: float = 160.0
## Tee markers and pins (D45, E3-S9): never drawn under this times their 1x size on screen.
## At 0.5x and nearer they are drawn at their own size; at the farthest zoom step (0.175x) they
## grow to show as at 0.5x, over the terrain, so a framed hole's tee and pin still read.
@export var marker_min_screen_scale: float = 0.5

## Unowned land (E6-S5, art/specs/land.md): the modulate on every top, riser and edge cue of
## a tile on a parcel the player does not own. The hatch and parcel lines are the pattern.
@export var unowned_tint: Color = Color(0.62, 0.62, 0.68)
## Height shade (E6-S18, art/specs/surfaces.md): the value the top of each surface named in
## height_shaded is multiplied by at height 0 to 7, grey so it changes value, not hue
## (colorblind rule). Low ground is darker and high ground lighter, so a plateau reads from a
## lowland and the lighter side of any edge is the higher one. The entry at plot_ground stays
## 1, so a New sandbox draws as before. Kept narrow so shaded rough stays clear of fairway and
## tee in value at every height (tests/test_course_view.gd). Above 1 a frame's shade is capped
## where its brightest coloured pixel would reach 255 (CourseView.frame_headroom), so a channel
## never clips and the hue holds.
@export var height_shade: PackedFloat32Array = PackedFloat32Array([0.8, 0.9, 1.0, 1.025, 1.05, 1.07, 1.09, 1.1])
## The surfaces whose tops take height_shade: the natural land the player reads relief on.
## Course surfaces (fairway, green, tee, bunker, cart path) are left out so they keep their
## identity colours at every height (pillar 2: lie and target read by colour at 0.5x); their
## edge cues and risers still show their height.
@export var height_shaded: PackedStringArray = PackedStringArray(["rough", "water", "trees", "oob"])
## How long a refusal ("not your land") stays on the Build HUD after a click, seconds.
@export var refusal_show_s: float = 3.0


static func load_default() -> BuilderTuning:
	return load(PATH) as BuilderTuning
