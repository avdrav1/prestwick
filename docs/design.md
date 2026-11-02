# Prestwick: design summary for implementation

Source of intent: the Claude Docs design doc "Prestwick, Game Design Doc". This file holds the numbers and rules code depends on.

## Grid and terrain

- Tile = 5 yards. Isometric 2:1, 64x32 footprint. Height 0 to 7 steps, 16 px riser per step.
- Brush sizes 1, 3, 5.
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
