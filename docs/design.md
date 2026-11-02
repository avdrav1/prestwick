# Prestwick: design summary for implementation

Source of intent: the Claude Docs design doc "Prestwick, Game Design Doc". This file holds the numbers and rules code depends on.

## Grid and terrain

- Tile = 5 yards. Isometric 2:1, 64x32 footprint. Height 0 to 7 steps, 16 px riser per step.
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
- Rolling friction has two parts at roll factor 1.0: a constant 1.5 yd/s² (`roll_decel`) plus grass drag of 0.6 per second times the speed (`roll_drag`). A surface's friction is that divided by its Roll column, and roll 0 stops the ball where it touches down. The drag stops fast balls; the small constant lets slow balls feel the slope.
- Slope pull along the ground is gravity × gradient / (1 + gradient²), at most gravity / 2. A one-step slope pulls about 3.7 yd/s², so `roll_decel` / roll must stay below that on every rolling surface (a GUT test guards it), or balls never start down a slope.
- Rest speed 0.1 yd/s. A ball slower than that stays put only when the slope's pull is weaker than the constant friction; otherwise it starts rolling downhill, so an uphill putt that stops short rolls back. A 4 yd/s putt runs about 3.7 yd on a flat green.
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
