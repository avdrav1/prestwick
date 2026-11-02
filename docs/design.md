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
- Builder (`course/builder.gd`, the only terrain writer with `course/save.gd`): paint any of the 8 surfaces below (oob is not on the palette), raise or lower one step per click, heights clamp at 0 and 7. One click, or one drag, is one undo step; a drag raises or lowers each tile once. Edits that change nothing are not recorded. Ctrl+Z (`ui_undo`) undoes. Active in Build mode only.
- Picking (`course/tile_picker.gd`): the cursor picks the tile drawn frontmost under it. Each tile is treated as a solid column from height 0 to its top, tested front to back by depth (i + j). A top face picks its tile, a wall picks the hill it belongs to, and a tile partly behind a nearer hill is picked only where its top still shows.
- Every surface has a pattern as well as a color (colorblind rule); patterns are named in `art/specs/surfaces.md`. Art uses only `art/palette.gpl` (32 colors). Terrain sheets load by name through `art/tiles/surfaces.tres`.

| Surface | Roll | Distance | Cost/tile | Notes |
| --- | --- | --- | --- | --- |
| fairway | 1.0 | 1.0 | 40 | |
| rough | 0.6 | 0.8 to 0.9 | 10 | |
| green | 1.4 | putter only | 120 | |
| tee | 1.0 | 1.0 | 80 | driver allowed |
| bunker | 0 | 0.5, sand wedge only | 60 | |
| water | n/a | penalty, drop at entry | 90 | |
| trees | n/a | blocks flight, 1 to 2 tile scatter | 30 | |
| cart_path | 1.6 | hard bounce | 20 | |

## Hole validation rules (each is a GUT test)

1. Exactly one tee and one cup.
2. Cup sits on a green tile.
3. A path of non-water, non-OB tiles connects tee to cup.
4. Tee-to-cup yardage matches par: par 3 < 250, par 4 250 to 470, par 5 > 470.
5. No tee inside another hole's landing zone.

## Swing

- Three-click bar: start, power, accuracy. Bar fills in 1.2 s, runs to 110%.
- Accuracy: each 10% off center = 2 degrees hook or slice. Outside zone = shank.
- Clubs: driver, 3w, 3i to 9i, PW, SW, putter. Each: carry, launch angle, roll factor. Data in `golf/clubs.tres`.
- Lies: fairway/tee 1.0, rough 0.8 to 0.9, bunker 0.5. Uphill shortens carry; sidehill adds curve.

## Ball

- Parabola in 3D over height map, 60 Hz, deterministic by seed.
- One bounce on landing by surface, then roll down slope with surface friction.
- Water and OB: one-stroke penalty, drop at last entry point.
- Code: `golf/ball.gd` (Ball, RefCounted, no scene) over `golf/height_field.gd`. Units are yards and seconds, x and y on the ground from the map corner, z up. Randomness comes only from the ball's own seeded generator.
- Height between tiles is bilinear between tile centres, so a one-step rise is a slope from one centre to the next. Past the map edge the edge height holds.
- A flight that meets the ground (including a hillside) touches down at the contact point found inside the tick. That first contact is the landing position.

Starting values from E1-S6, in `golf/ball_params.tres`. Tune with `/balance`:

- Yards per height step: 2.0 (14 yards at height 7). Matches the 16 px riser on a 64x32 tile at 5 yards per tile.
- Gravity: 10.7 yd/s² (Earth). There is no drag yet, so carry comes from launch speed and angle alone. A 75 yd/s drive at 14 degrees carries about 247 yd and finishes about 299 yd on fairway.
- Rolling friction has two parts at roll factor 1.0: a constant 1.5 yd/s² (`roll_decel`) plus grass drag of 0.6 per second times the speed (`roll_drag`). A surface's friction is that divided by its Roll column, and roll 0 stops the ball where it touches down. The drag stops fast balls; the small constant lets slow balls feel the slope. Per surface (E1-S11), `drag_scale` multiplies the drag, and `rest_decel_scale` multiplies the constant for a still ball, rising linearly back to the full constant at `decel_ramp_speed`. Both are 1.0 except on green (see the table below). On green the still-ball constant is also the hold that keeps a slow ball on a gentle slope (D7, next lines), and ramping it back to full for moving balls keeps fast putts as they were.
- Slope pull along the ground is gravity × felt gradient / (1 + felt gradient²), at most gravity / 2, where the felt gradient is the terrain's gradient times the surface's `slope_scale`. The ground normal at touchdown tilts by the same felt gradient. The ball's height always follows the real terrain. A one-step slope pulls about 3.7 yd/s² at slope_scale 1.0 and 0.32 yd/s² on green (0.075, so a 40% step putts as a 3% break). Off the green the one-step pull must stay above the still-ball friction, `roll_decel` × `rest_decel_scale` / roll, on every rolling surface (a GUT test guards it), or balls never start down a slope. On green that friction is 0.48 yd/s² by design (D7, E1-S12): it holds a ball on a felt slope up to about 4.5%, so a one-step contour (3%, or 4.2% where two meet at a corner) holds it, while a green rising two steps per tile (6%, 0.64 yd/s²) still rolls it down (a GUT test guards both sides).
- Rest speed 0.1 yd/s. A ball slower than that stays put only when the slope's pull is weaker than the still-ball friction; otherwise it starts rolling downhill, so an uphill putt that stops short on fairway, or on a green steeper than one step per tile, rolls back. On a one-step green slope the friction outweighs the pull at every speed, so a putt slows straight to rest and stays where it runs out of pace, with no slide after it, and a ball set down there stays put (D7). A 4 yd/s putt runs about 3.7 yd on a flat green. Low points (E1-S13) are checked per axis: a ball under low point speed, 0.25 yd/s (`low_point_speed`), whose next tick would carry it from ground falling along x (or y) onto ground rising against it along that axis stops on that axis. With both axes stopped (a pit) a still ball rests, so a ball in a one-tile pit settles at the centre instead of rocking across it until the cap. With one stopped (a gully sloping along its length) it goes on down the other, pulled by that axis's slope alone, and rests only if that pull is no more than the still-ball friction. Known limit: on rough the gully walls' cross slope still trims the pull along the floor while the ball moves, so a still ball in a one-step-per-tile rough gully creeps about 6 to 10 yd down before the cap instead of reaching the bottom. Known limit (D7): on a green slope steeper than the hold the net pull is small (0.64 less 0.48, 0.16 yd/s² on two steps per tile), so a slow ball trickles. On a green rising two steps per tile (a 15 yd 6% band), a still ball set down at the middle takes about 42 s to reach the foot, and one set down in the upper part of the band reaches the 60 s cap mid-slope (from 3.5 and 0.5 yd below the top it stops 0.7 and 3.7 yd above the foot): the E1-S12 symptom, moved to steeper greens. Uphill putts that stop short and roll back on it take 8 s at 4 yd/s, 14 s at 5, 21 s at 6 and 28 s at 7. Three steps per tile (9%) settles a still ball in up to about 15 s. Nothing in the builder or validator stops a player painting such a green, so E2 putting (E2-S7) will meet it. The settle-time target below covers one-step green slopes only. Known limit (D7), drawn rest position: the ball and its shadow sit at the bilinear height between tile centres, but the course view draws flat tile tops at whole heights with 16 px risers. Now that a green holds a ball on a one-step slope, many balls rest visibly off the top they appear to sit on: an uphill contour putt that stops short rests 4 to 6 px above the lower top, and a 7 yd/s one rests at x 30.16 on the height-1 tile, about 7.5 px below its top, on or behind the riser. Not fixed in E1; it needs a drawing or art choice before E2-S7.
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

Shot prediction (E1-S7): `golf/shot_prediction.gd` runs a seeded Ball with the same `step` to rest before the live ball flies, so the prediction and the flight agree tick for tick. The live ball (`scenes/shot_view.gd`) steps in whole 1/60 s ticks from frame time, never once per frame. Its sprite sits at the projected 3D point, its shadow on the ground straight below (bilinear height), both Y-sorted as an object on the tile under the ball.

Debug shot (E1-S7, until the swing in E2-S7), in `golf/debug_shot.tres`: struck from the centre of tile (15, 4), the 7-step tee pillar of `courses/heights_20x20.json`, at 20 yd/s, 30 degrees up, heading 180 (along -x), seed 1. It lands on the pyramid's face at tile (7, 4), bounces and rolls back down to (12, 4).

Hazard behaviour (water and OB penalty, tree scatter, oob roll) comes in E2-S6. Until then the ball stops dead on water and off the map.

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

Out: campaign, unlocks, tournaments, second plot, weather, staff, clubhouse, camera rotation, online sharing, multiplayer, mobile.

## Milestones

1. Ball on a tile
2. One hole
3. Nine holes and guests
4. Economy
5. Polish and share
