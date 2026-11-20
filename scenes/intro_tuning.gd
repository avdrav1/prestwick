class_name IntroTuning
extends Resource
## Designer-tuned numbers for the opening flyover (E21-S1, D77; scenes/opening_flyover.gd):
## the course and the drive, the camera path and every beat's timing. Loaded from
## res://scenes/intro_tuning.tres. Times are seconds of the intro's own clock, which starts at
## 0 as the screen begins to fade in from black.

const PATH: String = "res://scenes/intro_tuning.tres"

## Where the camera path's keys look, by name: the hole's tee, turn and cup, the clubhouse door,
## the hole's middle (the mean of tee, turn and cup), and the start of the walk (between the door
## and the tee, so both show).
const ANCHORS: PackedStringArray = ["tee", "turn", "cup", "door", "hole", "walk"]

@export_group("Course and drive")
## The famous course the intro plays on (FamousCourses id), loaded into a CourseData of its own.
@export var course_id: String = "dogleg_hollow_championship"
## The hole whose tee the guest walks to and drives from.
@export var hole_number: int = 1
## The drive: club (ClubSet id), shot shape (ShotShapes id), power (1.0 = 100%) and aim, in
## degrees from the line from the tee to the hole's turn (GuestHole.turn_of), + to the right.
@export var club_id: String = "driver"
@export var shape_id: String = "hook"
@export var power: float = 0.95
@export var aim_offset_deg: float = -14.5
## The Ball's seed (ShotView.fire_launch), so the drive is the same every time.
@export var rng_seed: int = 7
## The guest's shirt (GolferArt.shirt_material).
@export var shirt: int = 2

@export_group("Dawn")
## The screen fades in from black over this long.
@export var fade_in_s: float = 1.2
## The light over the course: each colour multiplies the world at its time in dawn_times,
## eased between (smoothstep), white (day) after the last.
@export var dawn_colors: PackedColorArray = PackedColorArray([
	Color(0.42, 0.34, 0.5), Color(1.0, 0.72, 0.5), Color(1.0, 1.0, 1.0)])
@export var dawn_times: PackedFloat32Array = PackedFloat32Array([0.0, 3.5, 9.5])
## When the dawn beat hands over to the glide (the camera path runs through both).
@export var dawn_s: float = 3.5

@export_group("Camera path")
## The path's keys, each at a time, looking at an anchor (ANCHORS) plus an offset in yards,
## at a zoom. The camera passes through each key on a smooth curve (cubic Hermite, Catmull-Rom
## tangents by time), still at the first and last; the zoom eases the same way in log scale.
## The last key's time is when the guest steps out of the clubhouse. Dogleg Hollow
## (Championship)'s 1st runs to the map's north edge, so the path keeps the zoom close where it
## looks north (past the edge is the empty backdrop): a tile y of at least about 21 / zoom at the
## view's centre shows none of it.
@export var path_times: PackedFloat32Array = PackedFloat32Array([0.0, 3.5, 7.0, 9.5])
@export var path_anchors: PackedStringArray = PackedStringArray(["tee", "turn", "tee", "walk"])
@export var path_offsets: PackedVector2Array = PackedVector2Array([
	Vector2(0.0, 60.0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
@export var path_zooms: PackedFloat32Array = PackedFloat32Array([0.26, 0.85, 0.8, 0.62])

@export_group("Walk and swing")
## The guest's walk from the clubhouse door to the tee (GuestWalk.route) is played over this
## many seconds.
@export var walk_s: float = 4.5
## The camera eases toward what it follows (the guest, then the ball) with this time constant
## (about 63% of the way in this time).
@export var follow_time_s: float = 0.5
## The zoom the camera eases to while the guest walks and swings.
@export var walk_zoom: float = 0.75
## How quickly a following zoom eases to its goal, a time constant in seconds.
@export var zoom_time_s: float = 0.9
## Standing over the ball before the swing.
@export var address_s: float = 0.5
## The swing's six frames take this long; the ball leaves at GolferArt.swing_impact_frame.
@export var swing_s: float = 1.2

@export_group("Flight")
## The Ball is stepped at 60 Hz of the intro's clock times this (1.0 is as in play).
@export var ball_speed: float = 1.0
## The zoom the camera eases to while it follows the ball.
@export var flight_zoom: float = 0.6
## Once the ball rests, the camera pulls back to frame the whole drive (the tee, the start line
## and the track to the ball) inside the view less this margin on each side, screen px, never
## nearer than flight_zoom.
@export var settle_margin_px: float = 90.0
## The band at the top of the view the title takes, screen px: the pull-back frames the drive
## below it.
@export var title_band_px: float = 190.0
## The drawn track: the ball's ground track in sun_yellow and its start line in chalk dots,
## screen px at every zoom.
@export var track_width_px: float = 3.0
@export var guide_dot_px: float = 2.5
@export var guide_gap_px: float = 12.0
@export var guide_alpha: float = 0.8

@export_group("Title")
## The title fades in this long after the ball rests, over title_in_s, holds title_hold_s, and
## then the screen fades to black over fade_out_s and the menu fades in over menu_fade_s.
@export var title_delay_s: float = 0.4
@export var title_in_s: float = 1.0
@export var title_hold_s: float = 2.4
@export var fade_out_s: float = 0.8
@export var menu_fade_s: float = 0.5
@export var title: String = "Prestwick"
@export var tagline: String = "Build a golf course, then play it."
@export var title_size: int = 72
@export var tagline_size: int = 24
## A frame's step of the clock is at most this, so a slow frame (the course view is built in
## the first) never skips a beat.
@export var max_step_s: float = 0.05


static func load_default() -> IntroTuning:
	return load(PATH) as IntroTuning
