# Prestwick: design summary for implementation

Source of intent: the Claude Docs design doc "Prestwick, Game Design Doc". This file holds the numbers and rules code depends on.

## Grid and terrain

- Tile = 5 yards. Isometric 2:1, 64x32 footprint. Height 0 to 7 steps, 16 px riser per step.
- Grid size (D4): 5 yards per tile everywhere, greens included. A 30 yd green is about 6x6 tiles.
- Height model (D5): heights are whole steps, drawn as terraces with risers. There are no ramp tiles and no sub-step heights. A "ramp" is the slope the ball feels between two neighbouring tile centres one step apart: 2 yd over 5 yd, 40% (21.8 degrees), from the interpolated height in `golf/height_field.gd` (see Ball). E1-S10 draws an edge cue on rises that face away from the camera, which otherwise show no riser and look flat (next line). On green the ball feels a step as a 3% break, not 40% (`slope_scale`, see Ball; E1-S11).
- Edge cue (E1-S10, `art/specs/edge_cue.md`): a tile higher than its back neighbour (x - 1 or y - 1) draws a lip line along that edge, a dark line outside the top and a bright one inside. One lip is a rise of one step, two lips are two or more, so the count reads in grayscale. Level or higher back neighbours and the map border get none. It draws over its tile's top and under objects on it. No tunables: the step classes are art frames.
- Projection (`course/iso.gd`, the only one): tile (i, j) at height h has its center at screen `x = (i - j) * 32`, `y = (i + j) * 16 - h * 16`. Draw order is back to front by i + j, then risers bottom up, then the top.
- Camera: zoom steps 0.5x, 1x, 2x; WASD pan 600 screen px/s at every zoom; middle-mouse drag; center may go 128 px past the course edge. Tuned in `scenes/camera_tuning.tres`.
- Brush sizes 1, 3, 5: an n x n square centered on the cursor tile, clipped to the map. Sizes and the undo depth (200 steps) are tuned in `course/builder_tuning.tres`.
- Plot (D10): a new sandbox (E2-S3) is 128 x 128 tiles (640 yd along an edge, 905 yd corner to corner, about 85 acres), every tile rough at height 2. A par 5 needs more than 94 tiles of straight line (470 / 5), so a 520 yd par 5 (104 tiles) fits along an edge with 24 tiles to spare, with room for water on its line. Height 2 lets the builder dig two steps for water and bunkers and raise five. The plot's cost is E4-S1's. The startup course in the main scene stays until E2-S8.
- Out of bounds (D9): OB is off the map plus every `oob` tile. From E2-S3 `oob` is on the Build palette as OB ground, and course files already carry it (surface 8). Placed OB stakes stay in the Icebox. A ball that comes to rest OB costs one stroke and is dropped (Ball, Cup and hazards).
- Builder (`course/builder.gd`, the only terrain writer with `course/save.gd`): paint any of the surfaces below (`oob` only from E2-S3, D9; until then the 8 others), raise or lower one step per click, heights clamp at 0 and 7. One click, or one drag, is one undo step; a drag raises or lowers each tile once. Edits that change nothing are not recorded. Ctrl+Z (`ui_undo`) undoes. Active in Build mode only.
- Picking (`course/tile_picker.gd`): the cursor picks the tile drawn frontmost under it. Each tile is treated as a solid column from height 0 to its top, tested front to back by depth (i + j). A top face picks its tile, a wall picks the hill it belongs to, and a tile partly behind a nearer hill is picked only where its top still shows.
- Every surface has a pattern as well as a color (colorblind rule); patterns are named in `art/specs/surfaces.md`. Art uses only `art/palette.gpl` (32 colors). Terrain sheets load by name through `art/tiles/surfaces.tres`.

| Surface | Roll | Distance | Cost/tile | Notes |
| --- | --- | --- | --- | --- |
| fairway | 1.0 | 1.0 | 40 | |
| rough | 0.6 | 0.85 (0.8 to 0.9, one fixed value, D14; `golf/lies.tres`) | 10 | |
| green | 1.4 | putter only | 120 | putter only here, and only here (D13) |
| tee | 1.0 | 1.0 | 80 | driver allowed (D13) |
| bunker | 0 | 0.5, sand wedge only | 60 | |
| water | n/a | penalty, drop at entry (D15) | 90 | |
| trees | n/a | blocks flight, 1 to 2 tile scatter (D15) | 30 | a rolling ball stops at its edge (D15) |
| cart_path | 1.6 | hard bounce | 20 | |
| oob | n/a | penalty, drop at entry (D15) | E4-S1 | on the palette from E2-S3 (D9) |

## Hole validation rules (each is a GUT test)

1. Exactly one tee and one cup.
2. Cup sits on a green tile.
3. A path of non-water, non-OB tiles connects tee to cup.
4. Tee-to-cup yardage matches par: par 3 < 250, par 4 250 to 470, par 5 > 470.
5. No tee inside another hole's landing zone.

How each rule is measured (D11). Distances are between tile centres at 5 yd per tile. `course/validator.gd` (E2-S2) is the one implementation, called by the game and by `/course-file validate` (`course/course_file.gd`). Each failing rule returns the tile at fault and a one-line reason.

- Rule 1, one tee and one cup (E2-S2): a hole fails when its tee or cup is not placed yet (off the map, `HoleData.UNPLACED`; the other rules are then not measured), when its tee and cup are the same tile, or when another hole has the same number (a second tee and cup for that hole; each reports the other's tee). A placed tee or cup is the tile at fault.

- Rule 2, cup on green: the cup's tile is the tile at fault.
- Rule 3, path: tiles connect through their 4 edge neighbours (no diagonals). Every in-map surface except water and `oob` may be crossed, trees included. Heights are ignored. The tee tile and the cup tile are part of the path. The tile at fault is the first water or `oob` tile on a 4-connected walk along the tee-to-cup line (E2-S2); a walk with none would itself be a path, so there always is one.
- Rule 4, yardage: the straight line from tee centre to cup centre, `5 * sqrt(dx² + dy²)` yd, rounded to the nearest whole yard (`roundi`). The rounded number is the one the card shows, and par is checked on it: par 3 up to 249, par 4 250 to 470 (both included), par 5 471 and up. The raw value is never exactly x.5 (`sqrt(n) = (2k + 1) / 10` has no whole n), so rounding has no tie. The cup is the tile at fault. Boundary cases for the tests: (50, 0) and (30, 40) tiles apart are 250 yd, par 4; (47, 17) is 249.90, rounds to 250, par 4; (49, 9) is 249.10, par 3; (94, 0) is 470, par 4; (94, 4) is 470.43, par 4; (94, 5) is 470.66, rounds to 471, par 5.
- Rule 5, landing zone: one disc for each par 4 and par 5. Its centre is on the tee-to-cup line, `min(240 yd, yardage - 60 yd)` from the tee centre (190 yd or more, since a par 4 is at least 250 yd). Its radius is 30 yd (6 tiles). A tee is inside when its tile centre is 30 yd or less from the centre. A par 3 has no zone: its tee shot is aimed at the green, and a next tee beside the green is ordinary routing. The 60 yd cup clearance puts the disc's far edge 30 yd short of the cup, so a tee less than 30 yd from a hole's cup is never inside that hole's zone. Test cases: a 150 yd par 3 from tile (10, 10) to (40, 10) with the next tee at (44, 13), 25 yd from its cup, passes; a 260 yd par 4 (centre 200 yd out) with another tee 25 yd beside its cup passes (65 yd from the centre). 240 yd sits inside the driver target (230 to 260, Balance targets), and 30 yd at 240 yd is a 7.1 degree cone either way, the curve of a swing 35% off centre (2 degrees per 10%). Rule 5 checks pairs: when hole B's tee is inside hole A's zone, both A and B fail it, and each reports B's tee tile. Placing or moving any tee or cup reruns it for every hole.
- Footprint (an edit there closes an open hole, design doc "Undo"): every tile whose centre is within 30 yd of the tee-to-cup segment, a capsule that holds the landing zone. A surface or height edit on any footprint tile, or moving the hole's own tee or cup, closes the hole, even if it still passes. It stays closed until the player presses Open again, which reruns the validator.
- Rerun after every edit: the footprint does not hold everything the rules read. Rule 3's path may leave it, and rule 5 reads other holes' tees. So after every build edit (a surface or height edit, or placing or moving any tee or cup) the validator also reruns for every open hole, and any open hole that now fails a rule closes, with that rule highlighted. Two cases for the tests: a lake painted across the whole capsule, with the rule-3 path going round its end outside the capsule, then water painted on that path, closes the hole; moving hole B's tee into open hole A's zone closes A (A and B both fail rule 5). The footprint check closes a hole on any edit there; the rerun closes it only when a rule fails. The rerun is one 4-neighbour search per open hole over at most 16,384 tiles (D10).
- Tunables: the landing distance (240 yd), the cup clearance (60 yd), the zone radius (30 yd) and the footprint half width (30 yd) live in `course/validator_tuning.tres` (E2-S2), with rule 4's par bands as the shortest par 4 (250 yd) and the shortest par 5 (471 yd). Change them with the driver target, not alone.
- Hole markers (E2-S2): the course view draws a tee marker (two square sun_yellow blocks either side of the tile centre) and a pin (an ink cup, a chalk pole and a flag_red pennant) for every placed tee and cup in CourseData, at the centre of their tile's top (`Iso` height = the tile's whole height), Y-sorted as objects on that tile (`Iso.object_sort_key`). Drawn in code (`course/hole_marker.gd`) until the final art.
- Generated courses (E2-S2): `/course-file generate <par> flat [water|dry]` lays out one straight hole along +x on rough at height 2 (D10): a 3x3 tee box, a 5-wide fairway from 40 yd out, a round green (radius 3.2 tiles) round the cup, at 160, 380 or 520 yd for par 3, 4 or 5; `water` adds a pond 3 tiles long across the fairway at 60% of the way, dug one step, with dry ground round its ends. `courses/example_par3.json` is `generate 3 flat dry`, and a test keeps it equal to the generator. `hilly` is not built in E2.

## Swing

- Three-click bar: start, power, accuracy. Bar fills in 1.2 s, runs to 110%.
- Accuracy: each 10% off center = 2 degrees hook or slice. Outside zone = shank.
- Clubs: driver, 3w, 3i to 9i, PW, SW, putter. Each: carry, launch angle, roll factor. Data in `golf/clubs.tres` (`golf/club.gd`, `golf/club_set.gd`). Starting values (E2-S5), set for a ball with no drag against the clubs targets; tune with `/balance clubs`. Carry is a perfect swing's flat carry from a 1.0 lie; the launch speed follows from it (Shot model).

  | Club | driver | 3w | 3i | 4i | 5i | 6i | 7i | 8i | 9i | PW | SW |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | Carry (yd) | 245 | 220 | 190 | 179 | 168 | 157 | 146 | 135 | 124 | 113 | 102 |
  | Launch (deg) | 14 | 16 | 18 | 20 | 22 | 24 | 27 | 30 | 33 | 37 | 40 |
  | Roll factor | 1.0 | 0.95 | 0.9 | 0.85 | 0.8 | 0.75 | 0.7 | 0.65 | 0.6 | 0.55 | 0.5 |
  | Launch speed (yd/s) | 74.7 | 66.6 | 58.8 | 54.6 | 50.9 | 47.5 | 43.9 | 40.8 | 38.1 | 35.5 | 33.3 |
  | Total on flat fairway (yd) | 297 | 263 | 225 | 209 | 194 | 179 | 165 | 151 | 137 | 123 | 110 |

  The last two rows are measured (`scripts/sim.gd --table clubs`), not tunables. Putter (E2-S5): starting ground speed 1.0 to 18.0 yd/s (`putt_min_speed`, `putt_max_speed`); the bar's mapping across it is E2-S7's. A full putt (18 yd/s) on a flat green rolls 27.5 yd, so N = 30 yd (`full_putt_max_yd` in `golf/clubs.tres`): a putt can cross a 6-tile green, and 30 yd leaves room for the E2-S4 green friction change.
- Lies: fairway/tee 1.0, rough 0.8 to 0.9, bunker 0.5. Uphill shortens carry; sidehill adds curve. Data in `golf/lies.tres` (`golf/lie_table.gd`, read into a `golf/lie.gd`). Starting values (E2-S5), tuned with `/balance lies`: rough 0.85; `uphill_k` 0.037 per step of rise (a 2-step lie costs the 7-iron 10.8 yd); `sidehill_deg` 2.9 degrees per step of tilt (a 1-step lie curves the 7-iron 7.4 yd at 146 yd); the windows `ahead_yd` and `side_yd` are D14's 5 yd. Water, trees and `oob` read 1.0, since a ball never rests there (E2-S6); green reads 1.0, since only the putter plays there.

Shot model (D14). E2-S5 sets the numbers, E2-S7 builds the swing on it. Code (E2-S5): `golf/shot_model.gd` (`ShotModel.full`, `ShotModel.putt`) builds a `golf/shot_launch.gd` for a stroke, with no scene; `ShotLaunch.apply` sends a Ball off, and `ShotPrediction.run_launch` predicts it with the same step.

- Power is a share of carry, not of launch speed (design doc "Power"). A full club's target carry is `carry × power × lie`, where `lie` is the surface multiplier times the uphill multiplier. The launch speed is the one whose flat-ground carry at the club's launch angle equals that target. With no drag (Ball) that is `v_full × sqrt(power × lie)`, since flat carry is `v² sin(2θ) / g`. 110% overswing is 1.1 times the carry, before E2-S7's penalty.
- Surface lie multipliers scale carry, as the Distance column says, through that one product. Rough is one fixed value from 0.8 to 0.9 (start 0.85, a 15% loss), never rolled, so the same lie always gives the same marker. Bunker is 0.5, and the sand wedge is the only club there.
- Lie slope is measured at the rest point `p`, in steps, with heights from `HeightField.height_at`. Rise (uphill) looks ahead only: `(h(p + 5 yd along the aim) - h(p)) / 2 yd per step`. Ground behind the ball never counts, so flat ground ahead reads 0 wherever the ball rests. Tilt (sidehill) is centred across the aim, a 10 yd window: `(h(p + 5 yd to the left of the aim) - h(p + 5 yd to the right)) / 2 yd per step`, whose sign names the higher side. Ground on both sides counts, since a sidehill lie is ground falling across the stance, so a ball on flat ground beside a bank reads a tilt away from the bank. A rise above 0 multiplies carry by `1 - k × rise`, and a rise of 0 or below does nothing (lower ground ahead already lengthens the flight). A tilt turns the launch heading toward the lower side by `c` degrees per step of tilt. Left is as the player sees it on screen: the projection draws +y clockwise from +x, so left is the aim heading minus 90 degrees, and a positive tilt (left higher) adds to the heading. E2-S5 sets `k` and `c` against the lies targets. Lie slope and the surface multiplier apply to full clubs only, never to the putter. Why a window and not the gradient at `p`: off the green a ball rests only where the slope's pull is under the still-ball friction, a gradient under 0.14 (fairway, 0.36 steps per tile) or 0.25 (rough, 0.62), while a one-step rise between two tile centres is 0.4 across its whole band (only where a rise fades out at a corner is it gentler). So the gradient under a resting ball is almost always near 0, and a slope lie read from it would almost never happen. The window sees the rise just ahead of the ball, so it depends on how far short of a riser the ball rests. On flat ground facing a 2-step riser, the rise is 2 at the tile centre where the riser's band begins (a 2-step uphill lie), and `2 × (5 - d) / 5` at `d` yd short of it, 0 from 5 yd back. The lies targets name the spot for that reason. Rise and tilt count steps of height, not gradient, so `k` and `c` are per step whatever the window's length (hand calculation step 6).
- Hook, slice and sidehill curve are heading offsets at launch, added to the aim: 2 degrees per 10% off centre (Accuracy), plus the sidehill turn. The ball then flies straight. Ball gets no new term.
- A club's roll factor multiplies the ground speed the ball keeps after its first touchdown, after the surface's bounce friction. It is `Ball.roll_factor`, set at launch (E2-S5). It changes nothing else: the surface's Roll, bounce, scatter and still-ball friction stay as the surface table says. Scaling Roll instead would scale the still-ball friction too. On rough a roll factor under 0.68 would then make that friction (2.5 / factor yd/s²) beat the one-step pull (3.69 yd/s²), and balls would stop rolling down slopes (the GUT slope guard). On green it would move D7's hold. The putter has no roll factor: a putt starts rolling (`Ball.start_roll`).
- Putter: the bar sets the putt's starting ground speed across the putter's range (E2-S5 sets the range, E2-S7 the mapping), not a carry.
- Aim marker: for a full club, the first touchdown of a predicted perfect swing (100% power, accuracy at centre) with the selected club and lie, including rough, rise and tilt. For the putter, the rest point of a putt at 100%. Both come from the same Ball step as the flight (E1-S7), so a perfect swing lands within 1 tile of the marker.
- Known limit, a ball at the foot of a riser (E2-S5 review, not yet decided): the flight starts at the ball's ground height and its first tick is checked against the ground, so a club whose launch is flatter than the face ahead meets it at once and its carry (the first touchdown) is about 0. A one-step riser's band is a 0.4 slope (21.8 degrees) and a two-step riser in one tile is 0.8 (38.7 degrees). Measured from the tile centre where the band begins, 100% power, lie on (`tests/test_clubs.gd`, `test_a_club_flatter_than_the_riser_ahead_meets_it_at_once`): on one step the driver, 3w, 3i, 4i and 5i carry under 2 yd and the 6i to SW fly (6i 147 yd, SW 96 yd); 1 yd further back the 4i and 5i fly and the driver, 3w and 3i still carry under 5 yd; 2 yd back only the driver and 3w are blocked. On two steps every club carries under 5 yd, the SW included (4.4 yd). A blocked ball does not always stop: the driver and 3w bounce off the face and run up and over it (about 110 and 80 yd total on one step), while the 8i, 9i and PW on two steps roll back behind the ball. So for these clubs the aim marker (first touchdown, above) sits at the ball's feet, and guests (E3) who pick a long club there meet the same face. How it should play (accept it and have the marker and club picker show a blocked club, give the first tick clearance over the start height, raise the lowest launch angle above 21.8 degrees, or leave it to the E2-S4 physics) needs a `/decision` before E2-S7 builds the marker. The lies targets avoid it by flying the lie on flat fairway (Balance targets).

Club legality (D13), checked in this order for each stroke:

1. On green: the putter only.
2. In a bunker: the sand wedge only.
3. Anywhere else: every club but the putter. The driver is allowed only on the hole's first stroke, from its tee marker, or from any tee tile. So a tee marker placed on fairway still allows the driver, and a ball that comes to rest on a tee tile later may use it too. The sand wedge is allowed on every lie except green.

Scoring (D12): stroke play. A hole's score counts strokes plus penalty strokes. The ball is picked up when that count reaches double par (6 on a par 3, 8 on a par 4, 10 on a par 5) without the ball holed, including when a penalty stroke reaches it. The score then records double par and a picked-up flag, and the card shows double par. A ball holed on the double-par stroke is holed, not picked up. E3-S3 guests use the same limit.

## Ball

- Parabola in 3D over height map, 60 Hz, deterministic by seed.
- One bounce on landing by surface, then roll down slope with surface friction.
- Water and OB: one-stroke penalty, drop at last entry point (Cup and hazards, D15).
- Code: `golf/ball.gd` (Ball, RefCounted, no scene) over `golf/height_field.gd`. Units are yards and seconds, x and y on the ground from the map corner, z up. Randomness comes only from the ball's own seeded generator.
- Height between tiles is bilinear between tile centres, so a one-step rise is a slope from one centre to the next. Past the map edge the edge height holds.
- A flight that meets the ground (including a hillside) touches down at the contact point found inside the tick. That first contact is the landing position.

Starting values from E1-S6, in `golf/ball_params.tres`. Tune with `/balance`:

- Yards per height step: 2.0 (14 yards at height 7). Matches the 16 px riser on a 64x32 tile at 5 yards per tile.
- Gravity: 10.7 yd/s² (Earth). There is no drag yet, so carry comes from launch speed and angle alone. A 75 yd/s drive at 14 degrees carries about 247 yd and finishes about 299 yd on fairway.
- Rolling friction has two parts at roll factor 1.0: a constant 1.5 yd/s² (`roll_decel`) plus grass drag of 0.6 per second times the speed (`roll_drag`). A surface's friction is that divided by its Roll column, and roll 0 stops the ball where it touches down. The drag stops fast balls; the small constant lets slow balls feel the slope. Per surface (E1-S11), `drag_scale` multiplies the drag, and `rest_decel_scale` multiplies the constant for a still ball, rising linearly back to the full constant at `decel_ramp_speed`. Both are 1.0 except on green (see the table below). On green the still-ball constant is also the hold that keeps a slow ball on a gentle slope (D7, next lines), and ramping it back to full for moving balls keeps fast putts as they were.
- Slope pull along the ground is gravity × felt gradient / (1 + felt gradient²), at most gravity / 2, where the felt gradient is the terrain's gradient times the surface's `slope_scale`. The ground normal at touchdown tilts by the same felt gradient. The ball's height always follows the real terrain. A one-step slope pulls about 3.7 yd/s² at slope_scale 1.0 and 0.32 yd/s² on green (0.075, so a 40% step putts as a 3% break). Off the green the one-step pull must stay above the still-ball friction, `roll_decel` × `rest_decel_scale` / roll, on every rolling surface (a GUT test guards it), or balls never start down a slope. On green that friction is 0.48 yd/s² by design (D7, E1-S12): it holds a ball on a felt slope up to about 4.5%, so a one-step contour (3%, or 4.2% where two meet at a corner) holds it, while a green rising two steps per tile (6%, 0.64 yd/s²) still rolls it down (a GUT test guards both sides).
- Rest speed 0.1 yd/s. A ball slower than that stays put only when the slope's pull is weaker than the still-ball friction; otherwise it starts rolling downhill, so an uphill putt that stops short on fairway, or on a green steeper than one step per tile, rolls back. On a one-step green slope the friction outweighs the pull at every speed, so a putt slows straight to rest and stays where it runs out of pace, with no slide after it, and a ball set down there stays put (D7). A 4 yd/s putt runs about 3.7 yd on a flat green. Low points (E1-S13) are checked per axis: a ball under low point speed, 0.25 yd/s (`low_point_speed`), whose next tick would carry it from ground falling along x (or y) onto ground rising against it along that axis stops on that axis. With both axes stopped (a pit) a still ball rests, so a ball in a one-tile pit settles at the centre instead of rocking across it until the cap. With one stopped (a gully sloping along its length) it goes on down the other, pulled by that axis's slope alone, and rests only if that pull is no more than the still-ball friction. Known limit: on rough the gully walls' cross slope still trims the pull along the floor while the ball moves, so a still ball in a one-step-per-tile rough gully creeps about 6 to 10 yd down before the cap instead of reaching the bottom. Known limit (D7): on a green slope steeper than the hold the net pull is small (0.64 less 0.48, 0.16 yd/s² on two steps per tile), so a slow ball trickles. On a green rising two steps per tile (a 15 yd 6% band), a still ball set down at the middle takes about 42 s to reach the foot, and one set down in the upper part of the band reaches the 60 s cap mid-slope (from 3.5 and 0.5 yd below the top it stops 0.7 and 3.7 yd above the foot): the E1-S12 symptom, moved to steeper greens. Uphill putts that stop short and roll back on it take 8 s at 4 yd/s, 14 s at 5, 21 s at 6 and 28 s at 7. Three steps per tile (9%) settles a still ball in up to about 15 s. Nothing in the builder or validator stops a player painting such a green, so E2 putting (E2-S7) will meet it. The E1-S12 settle-time target below covers one-step green slopes only; D16 (Settle targets, below) holds every green to it once E2-S4 changes the green friction model. Known limit (D7), drawn rest position: the ball and its shadow sit at the bilinear height between tile centres, but the course view draws flat tile tops at whole heights with 16 px risers. Now that a green holds a ball on a one-step slope, many balls rest visibly off the top they appear to sit on: an uphill contour putt that stops short rests 4 to 6 px above the lower top, and a 7 yd/s one rests at x 30.16 on the height-1 tile, about 7.5 px below its top, on or behind the riser. Not fixed in E1. Settled by D17 (Drawn rest height, below), built in E2-S7.
- Minimum bounce speed 1.0 yd/s. Below it the ball rolls instead of bouncing. Safety cap: 3600 ticks (60 s).

Per-surface ball numbers live in `course/surfaces.tres` (the path `/balance surfaces` reads), one row per surface. Roll is the table above. Bounce is the restitution of the speed into the ground. Bounce friction is the share of the speed along the ground lost at each touchdown. Scatter is the largest random turn of the bounce, either way.

| Surface | Bounce | Bounce friction | Scatter (deg) |
| --- | --- | --- | --- |
| fairway, tee | 0.25 | 0.5 | 2 |
| rough | 0.15 | 0.6 | 8 |
| green | 0.2 | 0.45 | 1 |
| bunker, water, oob | 0 (roll 0: stops) | 1.0 | 0 |
| trees | 0.15 (as rough, until E2-S6) | 0.6 | 8 |
| cart_path | 0.5 | 0.25 | 4 |

Green slope columns (E1-S11, D5; hold retuned in E1-S12, D7), 1.0 on every other surface: `slope_scale` 0.075, `rest_decel_scale` 0.45 (the gentle-slope hold, 0.48 yd/s²), `decel_ramp_speed` 1.5 yd/s (ignored where `rest_decel_scale` is 1.0), `drag_scale` 1.1. Starting values; `/balance surfaces` tunes them once the putter exists.

`/balance surfaces` green target, measured on `GridHeightEvidence.green_contour()` (`tests/fixtures/grid_height_evidence.gd`, output in `docs/decisions/e1-s9-probe.txt`): a 4 yd/s putt runs 3.5 to 3.9 yd on a flat green (3.7); a 9 yd/s uphill putt from the front tier ends within 1.5 yd of its flat-green distance (11.0 against 11.4); a 3 yd/s sidehill putt along the middle of a step comes to rest 0.1 to 1 yd below its line (0.34; D7 reads the break at rest); a ball set down still on a step's slope stays where it is set; an uphill putt that stops short on a step stays where it stops (at 6 yd/s from the front tier, 1.3 yd up the step's slope).

`/balance surfaces` settle target (E1-S12, D7): the longest green settle is under 8 s. Measured on `GridHeightEvidence.green_contour()` and on `GridHeightEvidence.green_ramp()` (all green, rising one step per tile from 0 to 7) (and the mirrored contour) for still balls and putts of 1 to 15 yd/s along the four axes and the four diagonals from starts across the green, all with steps below `max_steps`. The target is for balls that come to rest on green: now 5.5 s on the contour and its mirror and 5.6 s on the ramp, and every still ball rests at once. A putt that runs off the green is rough physics and is not held to it, only to settling on its own; on the test grid the worst is 7.3 s, but a denser sweep finds diagonal putts that leave the contour's y = 50 edge at about 0.3 yd/s and roll about 5 yd down the rough's tier slope, up to about 9.6 s (from (58.1, 34.4) at (-10.6, 10.6), resting at (37.3, 50.0) on rough). Known limit; rough slope settle is not tuned yet.

Settle targets (E2-S1, D16), for every ball the builder can make; E2-S4 meets them. The Measured-for column is the test set, not the limit of the claim: a shape found later that breaks a target is a finding for E2-S4, or for a later `/balance surfaces` story, not a reason to raise the target. A settle is the ticks from the ball's first touchdown, or from being set down still, or from a putt starting, to rest. Each test asserts its ticks against these numbers, not only against `max_steps`.

| Where the ball comes to rest | Target | Measured for |
| --- | --- | --- |
| green, any slope a player can paint | under 8 s (480 ticks) | the E1-S12 sweep above; a one-tile pit and a gully on green; `_steep_green(2, 2)` and `_steep_green(3, ...)` (two and three steps per tile), still balls and roll-backs at 4 to 7 yd/s. Today 42 s and the 60 s cap on two steps per tile; E2-S4 changes the green friction model in `golf/` (user, 2026-11-03) |
| fairway, tee, rough or cart path | under 10 s (600 ticks) | still balls and balls 1 to 2 yd from the centre of a one-tile pit (fairway) and of a one-step-per-tile rough gully floor, which they must reach; a 100% driver, 75 yd/s at 14 degrees, onto flat ground of each surface, and a 110% driver (1.1 times the carry, 78.7 yd/s) onto flat cart path (9.4 s today); still balls set every 0.25 yd across V valleys 2, 3 and 4 steps deep (walls rising one step per tile on both sides of a one-tile floor) on rough, fairway and cart path; a 100% driver landing at the top of a cart path that steps down from height 7 to 0, one step every 4 tiles. Today the valleys and the slope break the target: rough 10.4, 14.5 and 18.7 s, fairway 7.7, 9.1 and 10.7 s, cart path 10.0, 11.4 and 12.9 s (2, 3 and 4 steps deep), and the cart-path slope drive 10.2 s on the ground. E2-S4 brings them under it |
| off the green after a putt | under 10 s (600 ticks), the off-green target | the putt from (58.1, 34.4) at (-10.6, 10.6) on `green_contour()`: 9.6 s today, so it meets the target (0.4 s spare) and E2-S4 pins it with a test instead of recording a limit |
| bunker, water, `oob` | at touchdown | roll 0 stops the ball (water and `oob` then drop it, D15) |

Why 10 s off the green: on flat ground the slowest case is the cart path. A 100% driver onto flat ground, measured with the real Ball (E2-S1, from first touchdown): fairway 4.3 s, rough 2.2 s, green 6.0 s, cart path 9.2 s (it runs 182 yd past the 247 yd carry). Ground speed decays as `dv/dt = -(roll_decel + roll_drag × v) / roll`, about 7 s from 30 yd/s on cart path against about 2.5 s on rough. A target under 9.2 s would need a cart path change, and 10 s keeps a whole drive (3.4 s flight plus roll) inside about 13 s of waiting. Flat ground sets the floor, not the worst case: valleys a player digs and a drive down a cart-path slope settle slower today (table), and on the D10 plot, all rough, a dug valley is a common shape. They are held to 10 s anyway, because the player waits out every settle (pillar 2); E2-S4 changes the physics to meet it.

Shot prediction (E1-S7): `golf/shot_prediction.gd` runs a seeded Ball with the same `step` to rest before the live ball flies, so the prediction and the flight agree tick for tick. The live ball (`scenes/shot_view.gd`) steps in whole 1/60 s ticks from frame time, never once per frame. Its sprite sits at the projected 3D point, its shadow on the ground straight below (bilinear height), both Y-sorted as an object on the tile under the ball.

Drawn rest height (D17, user 2026-11-03, built in E2-S7): while the ball is on the ground (rolling or at rest), the ball and its shadow are drawn at the top of the tile under them, `Iso` height = that tile's whole height, never the bilinear height. In flight the ball is drawn at its true height. The shadow, which is always on the ground, follows the tile-top rule in flight too (E2-S1's default, not a user answer). The physics is unchanged: only the drawing snaps. A rolling ball that crosses a riser steps up or down by 16 px at the tile edge, as the terraces show it.

Debug shot (E1-S7, until the swing in E2-S7), in `golf/debug_shot.tres`: struck from the centre of tile (15, 4), the 7-step tee pillar of `courses/heights_20x20.json`, at 20 yd/s, 30 degrees up, heading 180 (along -x), seed 1. It lands on the pyramid's face at tile (7, 4), bounces and rolls back down to (12, 4).

Hazard behaviour (water and OB penalty, tree scatter, oob roll) comes in E2-S6. Until then the ball stops dead on water and off the map.

Cup and hazards (D15), the rules E2-S6 builds; E2-S6 sets the numbers it names:

- Cup: it sits at its tile's centre. It captures a ball on any surface, checked at the end of every rolling tick (a ball that rolls to rest inside the radius is captured too), never at touchdown. Touchdown speeds run far above any capture speed, so a check there would only add slam-dunks the speed rule rejects. A flight that touches down inside the radius bounces or rolls as usual and is checked on its next ground tick. E2-S6 sets the capture radius and the fastest speed that still captures.
- Water and OB entry point: the ball's ground track (its path in x and y, flight and roll alike) is walked back from where it stopped to the last point where it crossed from a tile outside the hazard into it. The hazard is water, or OB (an `oob` tile or off the map), whichever the ball stopped in. That crossing is the entry point.
- Drop point: the centre of the tile the track was over just before the entry point, if a ball may rest there. If not (water, `oob`, off the map or trees), keep walking back along the track to the first tile where it may. If there is none, it is the stroke's start. The ball is placed there at rest and is not stepped again until the next stroke, so a drop on a slope cannot roll back into the hazard. One penalty stroke. The ball reports the penalty and the drop point (E2-S6) for the hole score (E2-S8).
- A ball that rolls into a tree tile stops at rest where it was on the tick before, outside the trees, as if against the trunks.
- Tree scatter (a flight blocked below E2-S6's block height): from the point where the flight was blocked, draw a distance of 1 to 2 tiles (5 to 10 yd) and a direction back toward the shot's start, within 90 degrees either way of the reversed heading, from the ball's own generator. A target on trees, water, `oob` or off the map is rejected and drawn again, up to 8 draws. Then it is the nearest tile centre a ball may rest on, searched ring by ring outward from the blocked point, ties in row-major order. The ball comes down at the target with no speed and goes on as a still ball under the normal slope rules. It is deterministic by seed, so the prediction matches.
- A ball never rests on water, `oob` or inside trees: water and OB drop it, trees stop it outside or scatter it.

## Balance targets

`/balance` reads these (`.claude/skills/balance/SKILL.md` credits this file). The simulator is `godot --headless --path . -s res://scripts/sim.gd -- --table clubs|lies|surfaces --runs 200 --seed 1` (E2-S5); it prints each measured value next to its target and exits 1 on a miss. Its measuring functions are `scripts/balance_sim.gd` (`BalanceSim`), which `tests/test_sim.gd` calls directly. Its test strips are `tests/fixtures/balance_strips.gd` (`BalanceStrips`), because only `course/builder.gd`, `course/save.gd` and test fixtures write CourseData. Copied from the skill in E2-S1. Three lines are restated (D18). The reactions and economy lines are copied unchanged, for E3 and E4.

- clubs: the driver carries 230 to 260 yd with a perfect swing (100% power, accuracy at centre), until guests have skill in E3; each iron steps 10 to 12 yd; the putter is selectable only on green, and a full putt rolls at most N = 30 yd on a flat green (E2-S5; 27.5 yd at the putter's 18 yd/s top speed).
- surfaces: rough costs 10 to 20% distance; a bunker shot with SW at 50% lands 20 to 40 yd.
- lies: a 2-step uphill lie (rise 2, Shot model: struck from flat ground at the tile centre where a 2-step riser the ball faces begins) loses carry within one club step (10 to 12 yd) with the 7-iron; a 1-step sidehill lie (tilt 1: struck from flat ground at a tile centre where a 1-step band beside the aim begins, aimed along the band) curves the 7-iron 5 to 10 yd off line at its landing, about 150 yd out. How E2-S5 measures them: the lie is read on that terrain, and the shot is flown on flat fairway with that lie and with none, so only the lie rule counts (hand calculation step 6). On the uphill terrain itself no club gets away: two steps in one tile is an 80% face (38.7 degrees), the 7-iron (27 degrees) meets it at once, lie or not, and even the SW carries only 4.4 yd (Shot model, "Known limit, a ball at the foot of a riser"). The sidehill shot flown on its own terrain curves the same 7.4 yd.
- reactions: a fair par 4 played by a field of 50 guests, skills 1 to 10, gets 60 to 75% praise and under 15% complaints.
- economy: a player who builds one hole per 2 days reaches 9 holes and 3 stars in 25 to 35 in-game days without going negative.

Hand calculation: the bunker target is reachable (E2-S1, before E2-S5 tunes). No drag, so flat carry is `v² sin(2θ) / g` with g = 10.7 yd/s², and carry scales with `v²`.

1. In a bunker the target carry is `C × power × lie = C × 0.5 × 0.5 = 0.25 C`, where C is the SW's full carry (D14).
2. 20 to 40 yd needs C from 80 to 160 yd. A plausible SW carries about 80 to 110 yd, so the target holds as long as E2-S5 keeps the SW at 80 yd or more.
3. A draft ladder that meets the clubs target: driver 245, 3w 220; irons stepping 11 yd from 3i 190 through 4i 179, 5i 168, 6i 157, 7i 146, 8i 135 to 9i 124; then PW 113 and SW 102. The SW at 50% in a bunker lands 0.25 × 102 = 25.5 yd, inside the band.
4. Launch speed, with the SW at 40 degrees and C = 100 yd: `v_full = sqrt(100 × 10.7 / sin 80°) = sqrt(1086.5) = 32.96 yd/s`. In the bunker at 50%, `v = 32.96 × sqrt(0.25) = 16.48 yd/s`, and `16.48² × 0.9848 / 10.7 = 25.0 yd`. The real Ball, launched at 16.48 yd/s and 40 degrees on flat ground, carries 25.00 yd. The band's ends need 14.74 and 20.85 yd/s, which carry 20.00 and 40.00 yd.
5. The same check for the driver: 245 yd at 14 degrees needs `sqrt(245 × 10.7 / sin 28°) = 74.7 yd/s`, in line with the Ball line above (75 yd/s carries 246.8 yd).
6. On the lies targets the same ladder gives the 7-iron 146 yd. Losing 10 to 12 yd at rise 2 means `k` of 0.034 to 0.041 per step (5 to 6 yd a step). Curving 5 to 10 yd at 146 yd means `c` of 1.96 to 3.92 degrees per step of tilt (`atan(5 / 146)`, `atan(10 / 146)`). Both are measured as the same shot with the lie rule on and off, so the terrain's own effect on the flight is not counted.

## Guests and reactions

- Daily arrivals scale with rating. Guest: skill 1 to 10, patience, taste.
- Four checks per hole: fair, interesting, pace, challenge (score within 2 of par for skill).
- Fail 2 checks = complaint naming the hole. Pass 4 = praise.
- Rating = rolling average of last 50 reactions, 1 to 5 stars.
- Fee ceiling = $10 per star per round. Fee at ceiling cuts arrivals by one third.

## Economy and time

- Start $5,000. Upkeep $5 per open hole per day. Negative balance pauses building.
- Day = 3 real minutes at 1x. Speeds: pause, 1x, 3x, skip to morning.

## MVP

In: 8 surfaces above, flat and hilly terrain, 9 holes, sandbox, one golfer sprite set, course JSON export/import.

Out: campaign, unlocks, tournaments, second plot, weather (wind included: cut at E2 planning, D8), placed OB stakes (D9), staff, clubhouse, camera rotation, online sharing, multiplayer, mobile.

## Milestones

1. Ball on a tile
2. One hole
3. Nine holes and guests
4. Economy
5. Polish and share
