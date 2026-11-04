# Decisions

Appended by `/decision`. Never edited in place.

## D1: Ball physics is custom, not Godot physics bodies (2026-11-01)
Options: RigidBody2D with faked height; RigidBody3D in a 3D world projected to 2D; custom 3D step over the height map.
Choice: custom step.
Why: deterministic by seed, cheap enough to run for off-screen guests, and the height map is the only collider that matters. Serves pillar 2 (readable shots).
Affects: golf/ball.gd, docs/design.md Ball

## D2: One main scene with Build and Play as states (2026-11-01)
Options: separate scenes with a loader; one scene with a state machine.
Choice: one scene.
Why: pillar 1 needs a one-click switch from placing a hole to standing on its tee. A scene load breaks that.
Affects: scenes/main.tscn, CLAUDE.md Architecture

## D3: Which Godot and GUT versions the project pins (2026-11-02)
Options: Godot 4.3 with GUT 9.4.0, as the repo first said (costs a ~50 MB download to `.bin/`, and 4.3 is four minors behind the installed editor); Godot 4.7.x with GUT 9.7.1 (no download, and GUT's own compatibility table pairs 9.7.1 with 4.7.x, but 4.7-only APIs can creep in).
Choice: Godot 4.7.x with GUT 9.7.1.
Why: the machine already runs 4.7.2 and CLAUDE.md asks only for 4.3+, so pinning 4.7 removes a mismatch between the editor and the checks instead of adding one. Serves pillar 4 (small, finishable scope): one engine, one toolchain.
Affects: project.godot (config/features), scripts/install_godot.sh, addons/gut, README.md, CLAUDE.md, .claude/skills/godot-check/SKILL.md

## D4: Is 5 yards per tile too coarse for green contours? (2026-11-02)
Question: the design doc's open question "Grid size". Settled by E1-S9.
Evidence: `docs/decisions/e1-s9-probe.txt` is the output of `tests/fixtures/grid_height_evidence.gd`, which runs the real Ball over an 8x8 green with a 3-step contour (tiers 2 tiles deep) and over a 0-to-7 hillside. The screenshots are `tests/fixtures/grid_height_shot.tscn` through `scripts/screenshot.sh`, with predicted paths drawn on top: `docs/decisions/e1-s9-green.png`, `docs/decisions/e1-s9-green-mirrored.png`. Across the ground the grid holds up. A 30 yd green is 6x6 tiles. Tiers 10 yd deep read as separate shelves when their risers face the camera, and each putt path crosses 2 to 3 tiles. The coarse part is height, not the grid: one step between neighbouring tiles is a 40% slope (2 yd rise over 5 yd), about 10 times a steep real green. D5 handles that.
Options:
- Keep 5 yd per tile. Cost: a contour can turn only every 5 yd. Benefit: a par 5 stays about 100 tiles, and the art, course format, plot size and every distance in docs/design.md stay as they are.
- 2.5 yd per tile, or a finer sub-grid on greens only. Cost: 4 times the tiles per plot, or a second grid with its own rendering, picking and file packing, and every yardage and test changes. Benefit: contours could turn every 2.5 yd and a green would be about 12x12 tiles.
Choice: keep 5 yd per tile, greens included.
Why: on the ground, 5 yd tiles already resolve green tiers at a readable size. The finer grid's cost buys nothing the evidence asked for, because the problem it shows is vertical. Serves pillar 4 (small, finishable scope).
Inconclusive: nobody has putted by hand yet, since the swing and putter arrive in E2-S5 and E2-S7. That 5 yd contours feel good is an inference from paths and numbers. E2-S9's playtest should look at greens again.
Affects: docs/design.md Grid and terrain

## D5: Height model: are sub-step ramps needed, and what is a "ramp"? (2026-11-02)
Question: the design doc's open question "Height model". The design doc also says "slopes are rendered as ramp tiles between heights". Settled by E1-S9, from the same evidence as D4 plus `docs/decisions/e1-s9-hill.png`, `docs/decisions/e1-s9-hill-mirrored.png` and `docs/decisions/e1-s9-riser.png`.
Findings:
1. The physics already has ramps. `golf/height_field.gd` interpolates height between tile centres, so a one-step rise is a 40% (21.8 degree) slope 5 yd long that straddles the riser. Hillside shots behave sensibly on it. Up a hill that rises one step every 2 tiles, a shot carries 41 yd against 50.6 yd on flat ground and stays on the next shelf. Up a hill that rises one step per tile, the ball rolls back to the foot.
2. As a green contour, 40% cannot be played. Uphill putts at 7 and 9 yd/s, which roll 8.5 and 12 yd on a flat green, finish 0.3 yd past the start and 0.7 yd short of it. At 11 yd/s the ball jumps a whole tier. A 3 yd/s sidehill putt across the slope band is pulled 5 yd downhill for 3 yd forward. All 34 still balls dropped on the green came to rest on a flat shelf. The same green with 0.15 yd per step (3%) putts like a real one: a 9 yd/s uphill putt goes 11.5 yd (12 yd flat), and a sidehill putt breaks 0.3 to 0.5 yd.
3. Half of all slopes cannot be seen. Risers are drawn only on faces that point at the camera. A rise along +x or +y draws no riser, and its tops look identical. The 3-step green contour (`e1-s9-green.png`) and the 7-step hillside (`e1-s9-hill.png`) look flat. Mirrored, they read as clear terraces. Camera rotation is out of the MVP.
4. Where risers are visible, the ball and the picture agree to within half a step. At touchdown on a slope band, the ball sits at 2.7 steps on a tread drawn at 3, which is 5 px at 1x. At 2x it shows no float or clipping (`e1-s9-riser.png`).
Options:
- a. Change nothing: whole steps, terrace art, interpolated physics. Cost: greens play as shelves and away-facing slopes stay invisible. Benefit: no work.
- b. Sub-step heights in CourseData, such as quarter steps, in course format version 2. Cost: data model, file format, builder and partial-riser art, and a quarter step is still 10% on a green. Benefit: gentler hills everywhere.
- c. Sloped ramp tiles in the renderer, derived from neighbouring heights, with no data change. Cost: about 12 sloped frames per surface (about 100 in all), rework of the renderer and picker, and the loss of the Mean 18 terraces. Greens are still 40%. Benefit: the picture matches the physics everywhere.
- d. Keep whole steps and terraces. "Ramp" names the slope the physics already uses. Add two small fixes: a per-surface slope scale on the ball, about 0.075 on green so a step plays as a 3% break, and a drawn edge on rises that face away from the camera. Cost: two stories, plus an abstraction on greens: the ball climbs a 2 yd tier while feeling only a 3% pull. A 3% pull (about 0.32 yd/s²) is weaker than the green's constant rolling friction (1.07 yd/s²), so the green also needs its own lower constant friction and retuned drag, or still balls never start down a contour and short uphill putts never roll back. Benefit: no data model change, contoured greens putt as breaks, and every slope is visible.
Choice: d. Heights stay whole steps 0 to 7, drawn as terraces. A "ramp" is not a tile type and not stored data. It is the slope the ball feels between two neighbouring tile centres one step apart, as `golf/height_field.gd` computes it. Sub-step heights and ramp tiles are not needed.
Why: pillar 2 (shots are readable) needs every slope to be visible and putts that respond to a contour by degree. Option d does both without changing CourseData or the course format (pillar 4). The evidence puts the fault in the green's pull and in hidden faces, not in how many height levels exist.
Pays for it: drops ramp tiles, option c, from the art backlog and from `art/specs/risers.md`.
Inconclusive: 0.075 is a starting number from one what-if run (0.15 yd per step on a green), not a tuned value. That run fired only moving putts. It did not set balls down still or check that short putts roll back, which is how the friction conflict in option d's cost was missed at first. `/balance` sets it once the putter exists. Whether the edge cue reads at 0.5x is unverified until E1-S10 takes its screenshot.
Affects: docs/design.md Grid and terrain, art/specs/risers.md, docs/BACKLOG.md (E1-S10, E1-S11, filed and not built here), golf/ball.gd, course/surfaces.tres and course/course_view.gd once those stories land

## D6: Does the edge cue read at 0.5x? (2026-11-02)
Question: D5's open point, "whether the edge cue reads at 0.5x is unverified until E1-S10 takes its screenshot". Settled by E1-S10.
Evidence: `docs/decisions/e1-s10-green-{0.5x,1x,2x}.png` and `e1-s10-hill-{0.5x,1x,2x}.png` (the D4/D5 courses, which looked flat in `e1-s9-green.png` and `e1-s9-hill.png`), `e1-s10-steps-{0.5x,1x}.png` (rises of 1, 2, 3 and 1 steps on green, fairway, sand and rough), and grayscale copies `e1-s10-steps-1x-gray.png` and `e1-s10-hill-1x-gray.png`. The 3 steps of the green contour and the 7 steps of each half of the hillside can be counted at all three zooms. At 0.5x the cue lines are about 1 px thick, and on the hillside's one-step-per-tile half they sit about 8 px apart: countable, but tight, and the placeholder label specks compete with them.
Options:
- a. One color line per edge (bright on dark ground). Cost: it vanished on sand and green in grayscale, and the doubled line for 2+ steps vanished with it (first attempt in E1-S10). Benefit: the lightest look.
- b. A lip of a dark line plus a bright line, doubled for two or more steps, 2 px bands. Cost: a heavier edge. Benefit: the count reads on light and dark ground, in grayscale, and survives nearest sampling at 0.5x.
Choice: b.
Why: pillar 2 (shots are readable) and the colorblind rule; the count of lines is the pattern, not the hue.
Inconclusive: the final art (E5-S2) must keep the count readable at 0.5x once the placeholder labels are gone; a 1 vs 2+ cue does not tell 2 steps from 7, which risers still do only on faces toward the camera.
Affects: art/specs/edge_cue.md, art/tiles/edges_placeholder.png, course/course_view.gd, docs/design.md Grid and terrain

## D7: Where is a green break read, and may a ball rest on a green slope? (2026-11-02)
Question: E1-S12's two "Needs" questions, answered by the user. After E1-S11 a slow ball on a green contour trickled at about 0.16 yd/s: a ball set down on a step took up to 28 s to reach the shelf, uphill putts that stopped short rolled back for 12 to 35 s, a 3 yd/s sidehill putt ran 2.5 yd and then slid 2.5 yd sideways for 13 s, and on a green rising one step per tile a still ball hit the 60 s cap mid-slope. Is the sidehill break read where the putt runs out of pace (0.38 yd) or where the ball comes to rest (2.5 yd)? Must a still ball on any green slope roll to the shelf, or may it rest on a felt slope below a threshold?
Options:
- a. Keep E1-S11's rule (every still ball rolls to the shelf) and read the break where the putt runs out of pace. Cost: a sweep of the three green columns found no setting that settles a multi-tile green ramp under the cap, so this needs a new friction model, and the ball still slides on after the reported break. Benefit: every contour visibly moves a resting ball.
- b. A green holds a slow ball on a gentle felt slope, as a real green holds a ball on about 3%, and the break is read where the ball comes to rest. Cost: the E1-S11 clause "a ball set down still on a step's slope rolls down to the lower shelf" goes, and short uphill putts on a one-step contour stay where they stop instead of rolling back. Benefit: a pure retune of the existing per-surface hold (`rest_decel_scale`), no new code, every green ball settles in seconds, and the number the player reads is where the ball is.
Choice: b, the user's answer. A ball under rest speed on green rests where the felt slope pulls it less than the green's still-ball friction, `roll_decel` x `rest_decel_scale` / roll; at `rest_decel_scale` 0.45 that is 0.48 yd/s², a felt slope of about 4.5%. A one-step green contour (felt 3%, or 4.2% where two one-step slopes meet at a corner) holds; a green rising two steps per tile (felt 6%) still rolls a still ball down and rolls short putts back. The sidehill break is the lateral offset at rest; the `/balance surfaces` band of 0.1 to 1 yd for a 3 yd/s putt across a step applies to it unchanged (0.34 yd).
Why: pillar 2 (shots are readable): a putt that finishes in about 3 s, where the break you read is where the ball sits, reads better than one that keeps creeping for half a minute. Real greens hold a ball on a gentle slope, so this also matches what players expect.
Inconclusive: greens steeper than one step per tile still trickle slowly, since the net pull there is only 0.16 yd/s² (two steps per tile). On a two-steps-per-tile green a still ball set down at the middle of the 15 yd band takes about 42 s to reach the foot, one set down in the upper part reaches the 60 s cap mid-slope, and short uphill putts that roll back take 8 to 28 s (4 to 7 yd/s); three steps per tile takes up to about 15 s. Players can paint such greens, so this needs its own fix before E2-S7 (a builder or validator limit on green steps, or a faster trickle once the pull clearly beats the hold). The 8 s settle target covers balls that rest on one-step green slopes only, which is what the contour and ramp evidence measure; a putt that runs off the green and down the rough's slope can take about 9.6 s. Balls now rest partway up one-step slopes, at the bilinear height between tile centres, while the course view draws flat tops and 16 px risers, so a resting ball is drawn up to about 7.5 px above or below the top it appears to sit on, sometimes on the riser. The drawing fix (snap the drawn rest height to the tile top, sloped green art, or keep a slow ball out of the riser band) is open and needs the user's choice. Nobody has putted by hand yet (E2-S7).
Affects: course/surfaces.tres, course/surface_row.gd, docs/design.md Ball, tests/test_ball.gd, tests/fixtures/grid_height_evidence.gd, docs/decisions/e1-s9-probe.txt, scenes/shot_view.gd (drawn rest height, open)

## D8: Is wind in the MVP? (2026-11-03)
Question: E2 planning fork. The design doc's Aim paragraph says "Wind shifts the marker" and its Play toolbar lists wind, but the MVP's Out list already cuts weather.
Options:
- Keep wind: one vector per hole that shifts the aim marker, shown on the Play toolbar. Cost: a new Ball term (a drift in flight) with its own tuning, a toolbar widget, and a guest skill factor in E3. Benefit: one more input for the player to read.
- Cut wind. Cost: shots lose a variable that real golf has. Benefit: no new Ball term, and the aim marker shows the whole shot from club, lie and slope alone.
Choice: cut wind from the MVP (user, 2026-11-03).
Why: pillar 4 (small, finishable scope), and pillar 2 is better served by a marker that already tells the whole truth. It removes from the design doc the sentence "Wind shifts the marker." (Golf play, Aim) and "wind" from the Play toolbar (Presentation, UI). The ambient sound bed's "wind" (Presentation, Audio) is a sound, not weather, and stays. The Icebox "Weather" entry already holds the smallest version if it is ever promoted.
Affects: docs/design.md MVP (Out), the Claude Docs design doc (Golf play: Aim; Presentation: UI), docs/BACKLOG.md Icebox (already says so)

## D9: What is out of bounds? (2026-11-03)
Question: E2 planning fork. The design doc lists "out-of-bounds stakes" as a feature, while the course format already has an `oob` surface (8) that the palette hides.
Options:
- Off the map only. Cost: a player cannot mark OB inside the plot. Benefit: nothing to build.
- Off the map plus `oob` tiles painted from the Build palette. Cost: one palette entry (E2-S3) and the drop rule (E2-S6). Benefit: the format, the art (`oob` frames) and the ball's surface lookup already have it.
- Placed OB stakes as boundary objects. Cost: a new CourseData field, course format version 2 and a `save.gd` migration. Benefit: thin lines instead of whole tiles.
Choice: off the map plus `oob` tiles, painted from the Build palette (E2-S3) and read from files (user, 2026-11-03). Placed OB stakes stay in the Icebox.
Why: pillar 4: it costs one palette entry, since everything under it exists. Rule 3's path cannot cross `oob` (D11), and a ball that stops OB takes one penalty stroke and a drop (D15).
Pays for it: the stakes are delayed to the Icebox, with their format version 2.
Affects: docs/design.md Grid and terrain (Out of bounds, Builder, surface table), course/builder.gd and scenes/ palette (E2-S3), golf/ (E2-S6), art/specs/surfaces.md (its "still open (E2-S1)" line), the Claude Docs design doc (Course builder: Features)

## D10: What is a blank sandbox plot? (2026-11-03)
Question: the plot's size and the surface and height of a new sandbox. It must fit a par 5 over 94 tiles long with water on its line (E2-S9) and 9 holes (E3-S2).
Options:
- 64 x 64. Cost: no par 5 fits, even corner to corner (64 x 1.41 x 5 = 452 yd). Benefit: small files and quick redraws.
- 128 x 128, all rough at height 2. Cost: 16,384 tiles to draw and a 16 KB tile array (about 22 KB in base64). Benefit: 640 yd along an edge, so a 520 yd par 5 fits straight with 24 tiles to spare, and about 85 acres hold 9 holes (a real 9-hole course takes roughly 50 to 80).
- 256 x 256. Cost: 4 times the tiles, and most of the plot stays empty for a 9-hole MVP. Benefit: room for 18 holes.
Choice: 128 x 128 tiles, every tile rough, height 2 (user, 2026-11-03).
Why: pillar 4: the smallest square that fits the E2-S9 par 5 and E3's 9 holes. Rough is the unbuilt ground a player paints over. Height 2 lets them dig two steps for water and bunkers without hitting the clamp at 0.
Inconclusive: drawing 16,384 tiles has not been timed; E2-S3 should check the frame time. The plot's cost is E4-S1's. Timed since (E2-S3, RTX 3080, Godot 4.7.2 debug; `docs/design.md` Plot): drawing the whole 128 x 128 plot takes about 190 ms once, idle frames 1.0 ms at 0.5x and 0.7 ms at 1x, an edit outside a drag with its validator rerun about 8.5 ms, so the size stands.
Affects: docs/design.md Grid and terrain (Plot), course/builder.gd (E2-S3), the Claude Docs design doc (Progression and content: Sandbox)

## D11: How are hole rules 3, 4 and 5 measured, and what is a hole's footprint? (2026-11-03)
Question: the five validation rules name a path, a yardage and a landing zone without saying how to measure them, and "terrain edits under an open hole close it" names no tiles.
Options:
- Rule 3: 4 neighbours, or 8. Cost of 8: a diagonal gap between two water corners lets a path through that no ball rolls along. Benefit of 4: it matches how tiles share edges. Which surfaces: every in-map surface except water and `oob`, trees included, heights ignored (a ball can be chipped out of trees and up a hill), or also no trees (cost: a forest hole could never validate even when playable).
- Rule 4: straight line tee centre to cup centre, or the path length from rule 3. Cost of the path: a dogleg's yardage changes when the player paints rough at the corner. Benefit of the line: one formula the card, the validator and `/course-file inspect` share.
- Rule 5: a disc at a driving distance on the tee-to-cup line, or a corridor along the whole line. Cost of the corridor: two parallel holes 50 yd apart would fail. Benefit of the disc: it is where tee shots come down. Where the disc sits on short holes: at `min(240 yd, yardage)`, or kept clear of the green. Cost of `min(240 yd, yardage)`: a par 3's zone sits on its cup, and a par 4 under about 270 yd has its zone within 30 yd of the cup, so a next tee beside the green (a 150 yd par 3 from tile (10, 10) to (40, 10), next tee at (44, 13), 25 yd from the cup) fails both holes, and ordinary routing cannot open.
- Footprint: the tiles of the hole's own green and tee only, or a capsule around the tee-to-cup segment. Cost of the capsule: edits beside the fairway close the hole too. Benefit: edits to the landing area, which guests feel most, cannot slip past. Neither holds everything the rules read: rule 3's path can run outside the capsule (round the end of a lake across it), and rule 5 reads other holes' tees, so a footprint alone leaves an open hole open while it fails a rule.
Choice: 4 neighbours across every in-map surface except water and `oob`, heights ignored. Yardage is `5 × sqrt(dx² + dy²)` rounded to the nearest yard, with par checked on the rounded number: par 3 up to 249, par 4 250 to 470 inclusive, par 5 from 471. The landing zone is a 30 yd disc centred `min(240 yd, yardage - 60 yd)` along the line, for par 4s and par 5s only, checked both ways for each pair of holes; a par 3 has none, and a tee less than 30 yd from a hole's cup is never in that hole's zone. The footprint is every tile whose centre is within 30 yd of the tee-to-cup segment, and an edit there, or moving the hole's own tee or cup, closes the hole until the player presses Open again. After every build edit the validator also reruns for every open hole, and any that now fails a rule closes, so a broken rule-3 path outside the footprint, or another hole's tee moved into its zone, closes it too.
Why: pillar 1: each rule is one formula the builder can predict and see highlighted. The card shows the rounded yardage, so par follows the number on the card, and the raw value is never exactly x.5, so rounding has no tie. 240 yd sits in the driver target, and 30 yd there is about 7 degrees either way, a swing 35% off centre. The 60 yd cup clearance keeps tees beside a green legal, which 9-hole routing (E3-S2) needs, and a par 3's tee shot is aimed at the green, where no tee belongs anyway. An open hole never stays open while it fails a rule; the rerun costs one search per open hole over at most 16,384 tiles.
Inconclusive: one zone per hole; a par 5's second-shot zone is not checked. Doglegs are measured on the straight line.
Affects: docs/design.md Hole validation rules, course/ validator and its tuning `.tres` (E2-S2), course/builder.gd and scenes/ (E2-S3), the Claude Docs design doc (Course builder: Hole rules, Undo)

## D12: How many strokes before the ball is picked up? (2026-11-03)
Question: the most strokes a hole allows, and what the score records. E3-S3 guests use the same limit.
Options:
- No limit. Cost: a player stuck in a bunker, or a weak guest, can play forever and stall the course. Benefit: nothing to explain.
- A fixed limit, such as 10 on every hole. Cost: it is 7 over on a par 3 and 5 over on a par 5. Benefit: one number.
- Double par. Cost: the card shows a score that was not played out. Benefit: the same share of par on every hole, a familiar casual rule.
Choice: double par (6 on a par 3, 8 on a par 4, 10 on a par 5), counting penalty strokes. The ball is picked up when that count is reached without the ball holed, and the card shows double par (user, 2026-11-03). The score keeps a picked-up flag; a ball holed on the double-par stroke is holed.
Why: pillar 3: guest pace stays bounded, so a bad hole shows up as complaints, not as a jam. Pillar 1 holds as well, since every placed hole can be finished.
Affects: docs/design.md Swing (Scoring), golf/ hole score (E2-S8), guests/ (E3-S3), the Claude Docs design doc (Golf play: Scoring)

## D13: Which clubs may a stroke use? (2026-11-03)
Question: the design doc says "Driver is allowed only on tee boxes", "Putter is the only club on the green" and "Bunker: sand wedge only". Where exactly is the driver allowed, is the putter green only, and is the sand wedge a bunker-only club?
Options:
- Driver on tee tiles only. Cost: a tee marker placed on fairway or rough forbids the driver on its own tee shot. Benefit: one surface check.
- Driver on the hole's first stroke from its tee marker, and on any tee tile. Cost: two checks. Benefit: the tee shot always allows it, whatever the builder painted under the marker.
- Sand wedge only in bunkers. Cost: the shortest full club disappears from every pitch. Benefit: none the design doc asks for; "sand wedge only" there restricts the bunker, not the club.
Choice: checked in order: on green the putter only; in a bunker the sand wedge only; anywhere else every club but the putter, with the driver only on the hole's first stroke from its tee marker or from any tee tile. The sand wedge is legal on every lie but green.
Why: pillar 2: the club list the player sees follows from the lie alone, and the restated putter target ("selectable only on green", D18) needs the putter green only. The order also settles a tee marker on green: the putter wins.
Affects: docs/design.md Swing (Club legality), docs/design.md surface table, golf/ clubs (E2-S5), scenes/ club picker (E2-S7), the Claude Docs design doc (Golf play: Clubs)

## D14: What is the shot model? (2026-11-03)
Question: how the bar, the club, the lie and the slope become a launch, shared by E2-S5 and E2-S7.
Options:
- Bar to launch speed. Cost: carry goes as speed squared, so 50% on the bar carries 25%, against the design doc's "power is the fraction of full club distance". Benefit: one multiply.
- Bar to carry. Cost: a square root (exact with no drag; with drag later, a solve for the speed). Benefit: 50% carries half, as the design doc says.
- Lie multipliers on launch speed, or on carry. Carry matches the Distance column.
- Hook, slice and sidehill as a heading offset at launch, or as a lateral acceleration in flight. Cost of the acceleration: a new `golf/ball_params.tres` term, its own tuning, and a curve the aim line must draw. Benefit of the offset: no new Ball term, and the ball flies straight where the marker says.
- Lie slope from the gradient at the rest point, or from a window of heights around it. The gradient is almost always near 0 under a resting ball off the green, since a ball rests only where the pull is under the still-ball friction (a gradient under 0.14 on fairway against 0.4 for a one-step band). The window sees the rise beside the ball. A rise window centred on the ball (`h(p + 5) - h(p - 5)` along the aim) counts ground falling away behind as uphill: a ball on flat ground at the top of a 2-step riser, aimed away from it, reads almost rise 2. A window ahead only (`h(p + 5) - h(p)`) reads 0 on flat ground ahead wherever the ball rests.
- Rough 0.8 to 0.9 fixed, or rolled from the ball's seed. Rolled, the marker moves between identical lies and the generator stream changes; fixed, the same lie always reads the same.
- Club roll factor on the surface's Roll, or on the ground speed kept after the first touchdown. On Roll it also scales the still-ball friction: on rough a factor under 0.68 would beat the one-step pull (2.5 / factor against 3.69 yd/s²) and break the slope guard, and on green it would move D7's hold.
Choice: the bar sets a share of carry; target carry is `carry × power × surface lie × uphill`; launch speed is the one whose flat carry at the club's launch angle hits that target. Rough is one fixed value (start 0.85). Lie slope is read at the rest point in steps: rise from the ground 5 yd ahead along the aim, with ground behind never counting; tilt across a centred 10 yd window, both sides counting; rise shortens carry by `k` per step, tilt turns the heading toward the lower side by `c` degrees per step, full clubs only. Hook, slice and sidehill are heading offsets at launch (2 degrees per 10% off centre for accuracy, user 2026-11-03), and the ball flies straight. The club's roll factor multiplies the ground speed kept after the first touchdown. The putter's bar sets ground speed. The aim marker shows the first touchdown of a perfect swing with the selected club and lie, or the putt's rest point at 100%. The recommended options are taken except the lie slope measure, which departs from the story's recommendation for the reasons above.
Why: pillar 2 (shots are readable): every part of the shot is decided at launch from numbers the player can see, so the marker tells the whole truth and a perfect swing lands within 1 tile of it. The hand calculation in docs/design.md (Balance targets) shows the bunker target is reachable with a SW carrying 80 yd or more.
Affects: docs/design.md Swing (Shot model), docs/design.md Balance targets, golf/ (E2-S5, E2-S7), scenes/ (E2-S7), the Claude Docs design doc (Golf play: Aim, Power, Clubs, Lies)

## D15: How do the cup, water, OB and trees treat the ball? (2026-11-03)
Question: the rules E2-S6 and E2-S8 share: where and when the cup captures, the exact water and OB drop, a ball that rolls into trees, and how the tree scatter finds open ground.
Options:
- Cup checked on ground ticks only, or also at touchdown. Touchdown speeds are far above any capture speed, so the extra check only adds slam-dunks the speed rule would refuse.
- Drop at the entry point itself, or on the last restable tile the track crossed before it. The entry point sits on the hazard's edge, half the time on a slope or beside trees.
- A ball rolling into trees: stops outside, bounces back, or scatters as a flight does. Bounce and scatter need speeds and angles to tune; stopping is one rule and reads as hitting the trunks.
- Scatter target: any direction, or back toward the shot's start. Forward scatter usually lands deeper in the trees it just hit.
Choice: the cup sits at its tile centre and captures on any surface at the end of a rolling tick, including a ball rolling to rest inside the radius. The entry point is the last place the ground track crossed into the hazard the ball stopped in (water, or OB: `oob` or off the map). The drop is the centre of the tile the track was over just before it, walking further back past water, OB and trees, else the stroke's start, and the ball is placed there at rest. A ball rolling into a tree tile rests where it was the tick before. A blocked flight scatters 1 to 2 tiles back toward the start (within 90 degrees of the reversed heading), redrawn up to 8 times off trees, water and OB, then the nearest open tile centre, and goes on as a still ball. All draws come from the ball's own generator.
Why: pillar 2: each hazard has one visible outcome a player can predict, and the scatter stays deterministic by seed so the prediction matches the flight. A dropped ball placed at rest cannot roll back into the water it came out of.
Affects: docs/design.md Ball (Cup and hazards), docs/design.md surface table, golf/ (E2-S6), golf/ hole score (E2-S8), the Claude Docs design doc (Golf play: Flight and roll, Scoring)

## D16: How long may a ball take to settle, and how do steep greens get there? (2026-11-03)
Question: the settle targets off the green on every rolling surface, on greens steeper than one step per tile, and for a putt that runs off the green; and how steep greens are fixed, left open by D7.
Options for steep greens:
- A builder or validator limit on green steps. Cost: a player who paints a steep green cannot open it, and pillar 1 suffers. Benefit: no physics change.
- Change the green friction model in the physics, such as less drag at low speed once the pull clearly beats the hold. Cost: E2-S4 work in `golf/`, and possibly new columns in `course/surfaces.tres`. Benefit: any green a player paints plays.
Options for the off-green target: 8 s, as the green; 10 s; or a bound set by the slowest shape a player can paint. A 100% driver onto a flat cart path, measured with the real Ball, takes 9.2 s from first touchdown (fairway 4.3, rough 2.2, green 6.0), and a 110% one 9.4 s, so 8 s would force a cart path change that `/balance` has not asked for. Shapes are slower today: still balls in V valleys 2 to 4 steps deep take up to 10.4 to 18.7 s on rough, 7.7 to 10.7 s on fairway and 10.0 to 12.9 s on cart path, and a drive down a cart path stepping from 7 to 0 takes 10.2 s, so a bound set by them would be about 20 s.
Choice: fix steep greens in the physics (user, 2026-11-03), in E2-S4. Targets: a ball that rests on green, on any slope a player can paint, settles under 8 s (480 ticks), the E1-S12 target extended to `_steep_green(2, 2)` and `_steep_green(3, ...)` for still balls and roll-backs at 4 to 7 yd/s. A ball that rests on fairway, tee, rough or cart path settles under 10 s (600 ticks), from its first touchdown, its set-down or its putt start, measured on flat drives (100% on each surface, 110% on cart path), the one-tile pit and rough gully, V valleys 2 to 4 steps deep on rough, fairway and cart path, and a drive down a stepped cart path. E2-S4 brings the valleys and the slope under it. A putt that runs off the green is held to the off-green 10 s, and the 9.6 s diagonal putt from (58.1, 34.4) at (-10.6, 10.6) meets it, so it is pinned by a test, not recorded as an accepted limit.
Why: pillar 2: with live play the player waits out every settle, so no ball may creep for half a minute, and pillar 1 rules out forbidding steep greens. 10 s off the green is the smallest round bound above the slowest flat case; flat ground is the floor, not the worst case. Valleys are held to it rather than setting it, since a dug valley is a common shape on the all-rough D10 plot and a 20 s wait there is the creep pillar 2 rules out.
Inconclusive: the 9.6 s putt has 0.4 s to spare. If E2-S4 moves it over 10 s, that is a new finding, not a reason to raise the target. Whether E2-S4 can bring a 4-step rough valley from 18.7 s to under 10 s without breaking the green putt targets is not known; if it cannot, the case moves to its own story with this target, as E2-S4 says for steep greens.
Affects: docs/design.md Ball (Settle targets, Known limit lines), golf/ and course/surfaces.tres (E2-S4: the new columns `steep_from`, `steep_scale` and `drag_full_speed` in `course/surface_row.gd`, and the crease rule; see D22), tests/test_ball.gd (E2-S4), the Claude Docs design doc (Golf play: Flight and roll)
The E1-S12 commit body describes the rest rule from before D7's per-axis wording; `docs/design.md` Ball is current.

## D17: Where is a resting ball drawn? (2026-11-03)
Question: D7's open point. Balls now rest partway up one-step slopes at the bilinear height, up to about 7.5 px off the flat tile top they appear to sit on, sometimes on the riser.
Options:
- Snap the drawn ball and shadow to the top of the tile under them while on the ground. Cost: a rolling ball steps 16 px at each riser it crosses. Benefit: scenes/ only, a ball always sits on a top.
- Sloped green art. Cost: new frames per slope class, against D5. Benefit: the picture matches the physics on greens.
- Keep a slow ball out of the riser band. Cost: a physics change for a drawing problem. Benefit: no drawing change.
Choice: snap the drawn ball and its shadow to the top of the tile under them while on the ground (user, 2026-11-03), built in E2-S7. In flight the ball is drawn at its true height. The shadow follows the tile-top rule in flight too; that part is E2-S1's default, since the shadow is always on the ground.
Why: pillar 2: a resting ball is always on the top you read its lie from, and the physics stays as it is.
Affects: docs/design.md Ball (Drawn rest height), scenes/shot_view.gd (E2-S7), tests/test_shot_view.gd (E2-S7)

## D18: Which `/balance` targets change for E2? (2026-11-03)
Question: three of the five target lines in `.claude/skills/balance/SKILL.md` cannot be measured as written in E2: "putter never leaves the green", "at 100% for a skill-10 golfer" (no guest skill until E3) and "about one club".
Options:
- Keep the lines and measure by judgment. Cost: `/balance` cannot pass or fail them. Benefit: no edit.
- Restate the three as measurable lines and copy all five into docs/design.md, which the skill credits.
Choice: restate and copy. "Putter never leaves the green" becomes "the putter is selectable only on green, and a full putt rolls at most N yd on a flat green", with N set by E2-S5 alongside the putter's speed range. "At 100% for a skill-10 golfer" becomes "a perfect swing, until guests have skill in E3". "About one club" becomes "within one club step (10 to 12 yd)" for a 2-step uphill lie with the 7-iron, and the sidehill line names the 7-iron and a 1-step tilt. Each lie line names the spot it is struck from (the tile centre where a 2-step riser ahead begins, reading rise 2; the tile centre where a 1-step band beside the aim begins, reading tilt 1), because D14's windows read less a little further away. The surfaces, reactions and economy lines are copied unchanged.
Why: pillar 2: a target that `/balance` can measure is one a player can feel. The putter line follows D13, and the lie lines use D14's rise and tilt.
Affects: docs/design.md Balance targets, .claude/skills/balance/SKILL.md (its Targets list should point at docs/design.md; not edited here)

## D19: Does a course start on blank land, or on land the player buys? (2026-11-03)
Question: every course starts on the blank D10 plot, 128 x 128 tiles of rough at height 2, all of it free to build on. The user does not want to build on blank land: land should be bought, then turned into a course.
Options:
- Parcels on one map. The map is split into parcels; the player starts owning a small block and buys neighbouring parcels. Cost: an ownership layer in CourseData and course format version 2. Benefit: one map, so "second plot" stays out of the MVP, and the course grows as money allows.
- Pick one plot to buy from a few offers, then never buy again. Cost: a plot chooser and several generated plots. Benefit: no ownership layer. The course cannot grow.
- Both. Cost: everything above. Benefit: the most choice, against pillar 4.
For the land itself: natural generated terrain (hills, tree stands, ponds, rough), or flat rough as today.
For timing: a new epic before E3, inside E4 with money, or terrain before E3 and buying in E4.
Choice: parcels on one map, with natural generated terrain, built in a new Land epic (E6) that runs before E3 (user, 2026-11-03). New sandbox stays as a separate mode: every parcel owned, unlimited budget. Until E4 makes money real, a land budget is spent on parcels only; E4-S1 folds it into the one balance.
Why: pillar 3: the land you buy and shape is the start of the course's story, and buying a parcel to fit the next hole is a decision the player makes. Pillar 1 holds, because the builder only lets a hole go where the player owns land, so a placed hole is still playable at once. Pillar 4: one map, no plot chooser.
Pays for it: E3, E4 and E5 each move back one epic, and their releases move up one version (E6 ships 0.3.0, E3 0.4.0, E4 0.5.0, E5 0.6.0, the MVP). The land generator delivers the MVP's "hilly terrain", so `/course-file generate hilly` (E2-S18) reuses it instead of a generator of its own.
Open, for E6-S1: parcel size, the starting block, parcel prices, the land budget, what a ball does on land the player does not own, and whether land can be sold.
Affects: docs/design.md (Grid and terrain: Plot; Economy and time; MVP; Milestones), docs/BACKLOG.md (E6, E2-S18, E3 to E5 versions), course/ (CourseData, builder, save format v2), scenes/ (Build HUD), the Claude Docs design doc (Course building, Economy)

## D20: How does a ball at the foot of a riser play? (2026-11-03)
Question: a full club launched flatter than the face ahead meets it on the first flight tick: on a one-step riser (0.4, 21.8 degrees) the driver, 3w, 3i, 4i and 5i carry under 2 yd, and on a two-step riser (0.8, 38.7 degrees) every club does, the SW included. The aim marker sat at the ball's feet with no word why, the club picker did not flag it, and for the driver and 3w the marker did not match where the ball ended up (they bounce off the face and run over it).
Options:
- (a) Keep the physics; the marker and the club picker show the club as blocked. Cost: a blocked rule and a second marker shape. Benefit: no Ball or club table change, so every E2-S4 and E2-S5 target stands, and the player reads why the shot will not fly.
- (b) Give the first flight tick clearance over the start height. Cost: a new Ball term, and a ball that flies through the face it sits against. Benefit: every club flies.
- (c) Raise the lowest launch angle above 21.8 degrees. Cost: the driver to 5i ladder changes and `/balance clubs` runs again, and a two-step riser still blocks every club. Benefit: one-step risers stop blocking.
- (d) Leave it to the physics and look at the bounce off a near-vertical face. Cost: the marker still sits at the ball's feet. Benefit: no new rule.
Choice: (a) (user, 2026-11-03). A full club is blocked when its predicted perfect swing, from the same Ball step as the aim marker, meets the ground or trees while still climbing (`ShotPrediction.stopped_climbing`, from `Ball.stop_velocity` at the first touchdown or at the point trees stop it before one); a putt never is. Every flight that gets away comes down descending, so the rule needs no distance and does not depend on the stroke's seed (the tree scatter does, the flight before it does not). A 5 yd carry cutoff was tried first and dropped in review: it missed the driver carrying 5 to 14 yd into a riser face from 2 to 10 yd back, and trees right ahead, whose scatter lands behind the ball. A blocked club stays legal and can be struck. Its marker sits where the flight is stopped (`ShotPrediction.stop_point`: the first touchdown on a face, the tree edge for trees), drawn as a flag_red ring struck through by a slash with no dots, and the club picker reads "(blocked)" in flag_red. E3 guests read the same rule (`ClubSet.is_blocked`) and skip a blocked club.
Why: pillar 2: a shot that will not fly says so before it is struck, and the marker no longer claims a flight it will not make. Pillar 4: no physics or balance change, and the E2-S5 tables stand.
Affects: golf/club_set.gd, golf/ball.gd (`stop_point`, `stop_velocity`, bookkeeping only), golf/shot_prediction.gd (`carry_yd`, `stop_point`, `stopped_climbing`), scenes/swing_control.gd, scenes/aim_view.gd, scenes/swing_panel.gd, docs/design.md Shot model ("A ball at the foot of a riser") and Swing (Aim line and marker), tests/test_clubs.gd, tests/test_shot_prediction.gd, the Claude Docs design doc (Aim: a blocked club; to be mirrored by the orchestrator)

## D21: Which putt does the putter's aim marker show? (2026-11-03)
Question: the putter's marker showed a putt at 100% (D14's perfect swing), which rolls 27.5 yd on a flat green, so it sat 17 to 23 yd past the cup on `courses/example_par3.json`, and its dots showed the break of a roll nobody plays (E2-S7 review).
Options:
- (a) Show the putt at the power whose putt comes to rest nearest the cup. Cost: a solve of several predicted putts on each aim update. Benefit: the dots show the line and break of the putt the player needs.
- (b) Keep the 100% marker and add a distance scale to the bar for the putter. Cost: a second, non-linear scale on the bar, and the dots still show the wrong roll. Benefit: no solve.
- (c) Show the putt at the power the bar is at, live while it fills. Cost: a prediction every frame of the swing. Benefit: the player sees the pace before locking it, which gives the putt away.
Choice: (a) (user, 2026-11-03). With the putter and a cup on the map, the marker and dots show the predicted roll (accuracy at the centre, the stroke's seed) at the power whose putt rests nearest the cup, solved from the same Ball step as the live putt (E1-S7) by `PuttAim` (`golf/putt_aim.gd`): a safeguarded secant on the signed miss along the ball-to-cup line, warm-started from the last solve while the ball stays put, stopped by `putt_aim_tolerance_yd` and `putt_aim_max_runs` (`golf/swing_tuning.tres`). With no cup, the marker is the 100% putt as before. The power the bar locks still decides the putt; nothing about the shown power is put on the bar. Measured cost: about 9 ms and 1.2 predicted putts per aim update while sweeping the aim on a contour, about 22 ms (3 putts) for a new ball position.
Why: pillar 2: the aim view now shows the break of the putt the player will actually play, and the marker no longer sits 20 yd past the cup. The player still judges the pace, so the putt is not played for them.
Affects: golf/putt_aim.gd (new), golf/swing_tuning.gd and .tres (`putt_aim_tolerance_yd`, `putt_aim_max_runs`), golf/swing.gd (validate), scenes/swing_control.gd (`aim_power`, `aim_putt`), docs/design.md Swing (Aim line and marker) and Shot model (Aim marker), tests/test_shot_prediction.gd, tests/fixtures/putt_marker_shot.tscn, the Claude Docs design doc (Aim: the putter's marker; to be mirrored by the orchestrator)
Note (E2-S20 review, 2026-11-03): the miss is measured along the aim, not the ball-to-cup line, so an aim turned off the cup still shows the putt resting nearest it (a cup square to the aim or behind it shows 0%). The measured cost above is the gentle contour's typical case; the worst cases are higher: 2 to 3 putts and up to 21.5 ms per update sweeping the aim on the contour, up to 36 ms cold on the contour, and up to the 8-putt cap and 173 ms cold on a green rising two steps per tile, where the solve can also stop up to about 4 yd off the nearest putt (a miss that does not grow with power). See docs/design.md Shot model, Aim marker.

## D22: How does the physics settle a steep green? (2026-11-03)
Question: D16 chose to fix steep greens in the physics and named two candidate changes (less low-speed green friction, new surface columns). E2-S4 built the fix; this records which change it is and why, which until now lived only in `docs/design.md` Ball and a commit body.
Options:
- Lower the green's friction (its still-ball hold or its drag) so a slow ball runs down a steep bank faster. Cost: it cannot reach the target: on a bank of two steps per tile the felt slope is 6% (`slope_scale` 0.075), a pull of 0.64 yd/s², so even with no friction at all a still ball at the top needs 6.7 s to reach the foot and over 2 s more to stop, over the 8 s target. It also loosens every one-step contour, against D7's hold. Benefit: no new columns.
- Raise `slope_scale` on green. Cost: every one-step contour putts harder than D7's 3% break. Benefit: one number.
- Feel steep banks more steeply, per axis: the part of the terrain's slope above `steep_from` (0.6, one and a half steps per tile) is felt at `steep_scale` (1.5) on top of `slope_scale`, never more than the terrain's own slope. Cost: two new surface columns, 0 on every surface but green. Benefit: every one-step contour, corners included (0.4 on each axis), putts exactly as before, while two steps per tile is felt as 36% instead of 6% and three as 99% instead of 9%, so a steep bank settles under 8 s.
Choice: the felt-slope change (E2-S4), with its two companions from the same story: a drag fade, `drag_full_speed` (12 yd/s on rough, 0 elsewhere), so a slow ball running down a rough slope is not held to a crawl, and the crease rule, which takes a rolling ball's speed along the new ground's normal where the ground turns up against it on an axis, so a ball swinging across a valley or pit floor is damped instead of rocking until the cap. Green friction is unchanged.
Why: pillar 1: any green a player paints still plays and settles, and pillar 2: a one-step contour reads exactly as D7 set it, while a steep bank looks steep and plays steep. Friction alone was ruled out by the arithmetic above, not by taste.
Affects: docs/design.md Ball (Slope pull, Creases, Rolling friction) and the surface table's green and drag-fade lines, course/surface_row.gd and course/surfaces.tres (`steep_from`, `steep_scale`, `drag_full_speed`), golf/ball.gd (E2-S4), tests/test_ball.gd (E2-S4), D16, the Claude Docs design doc (Golf play: Flight and roll)

## D24: Does the three-click swing bar feel right? (2026-11-03)
Question: the design doc's open question "Swing bar feel", closed by the E2-S9 hand playtest.
Options:
- Keep the three-click bar at its E2-S7 numbers. Cost: none. Benefit: tested by hand and liked.
- Retune its speed. Cost: a `/balance` pass. Benefit: only if it felt too fast or slow; it did not.
- Promote the one-click swing from the Icebox. Cost: a new swing and its tests. Benefit: only if the three-click bar failed checklist item 2; it did not.
Choice: keep the three-click bar with zone 20%, shank 30 degrees and half power, bar speed 0.5 to 1.5 (user, E2-S9 hand playtest, 2026-11-03). The one-click swing stays in the Icebox; its promotion trigger was not met.
Why: pillar 2: the user found shots landed where the marker said and the bar felt right at its speed setting.
Affects: docs/design.md Swing, docs/playtests/2026-11-03-e2-hand.md, the Claude Docs design doc (Open questions: "Swing bar feel")

## D25: Where does the last-resort drop go when the stroke's start is beside the cup? (2026-11-03)
Question: D15 makes the stroke's start the drop of last resort. E2-S13 found that a start within `cup_radius` of the cup leaves a free tap-in.
Options:
- Keep D15. Cost: a rare free tap-in. Benefit: no change.
- Move the drop off the start in that case. Cost: one more search. Benefit: a hazard always costs a stroke.
Choice: when the start is within `cup_radius` of the cup, the drop is the nearest tile centre the game may place a ball on (`Ball.may_place_on`); with none on the whole map, the cup's own tile, `cup_clear_drop_yd` 2.4 yd from its centre toward the start (E2-S13). This supersedes the last-resort clause of D15; the rest of D15 stands.
Why: pillar 2: a penalty stroke always reads as a penalty.
Affects: docs/design.md Cup and hazards (Drop point), golf/ball.gd, golf/ball_params.tres, the Claude Docs design doc (Flight and roll, rev 36)

## D26: How big is a parcel, and which land does a new course start with? (2026-11-03)
Question: D19 split the map into parcels and left their size and the starting block to E6-S1.
Options:
- 8 x 8 tile parcels (40 yd). Cost: 256 parcels on the 128 x 128 map to draw, price and click, and a purchase barely changes what fits. Benefit: fine-grained growth.
- 16 x 16 tile parcels (80 yd), 8 x 8 on the map. Cost: a purchase is a big step. Benefit: 64 parcels a player can read at a glance, D10's map and frame times unchanged, and one purchase is about one hole's worth of land.
- 32 x 32 tile parcels (160 yd). Cost: 16 parcels, so a few purchases own the map and E4's money has little to buy. Benefit: almost no ownership UI.
- Starting block: 1 x 1 parcel (no hole over 110 yd), 2 x 2 (160 yd on a side), or 3 x 3 (240 yd, a short par 4 nearly fits).
Choice: 16 x 16 tile parcels, 8 x 8 on the 128 x 128 map, and a free starting block of 2 x 2 parcels at the map's centre (user, 2026-11-03). Ownership is one flag per parcel in CourseData, written only by `course/builder.gd` and `course/save.gd`, saved in course format version 2 with the land budget left (unlimited for New sandbox); a version 1 file loads with every parcel owned and an unlimited budget. The parcel size is a format constant (`CourseData.PARCEL_TILES`), not a tunable, since the saved flags are indexed by it.
Why: pillar 3: the block holds a par 3 but not a par 4 (219 yd corner to corner, under 250), so the course's second hole is the reason for its first purchase (hand calculation in `docs/design.md` Land). Pillar 4: 64 parcels, and the map, draw and frame times D10 measured stay as they are.
Affects: docs/design.md Land, course/ (CourseData, save format v2, E6-S3), scenes/ (E6-S5, E6-S6), the Claude Docs design doc (Course building: Land)

## D27: Which parcels may be bought, and can land be sold back? (2026-11-03)
Question: D19 says the player buys parcels that border owned land; E6-S1 settles what "border" means and whether a purchase can be reversed.
Options:
- Any parcel on the map. Cost: a course in scattered pieces, with unowned land between tee and green. Benefit: the most freedom.
- A parcel sharing an edge with an owned one. Cost: one check. Benefit: owned land stays one connected piece, so a course grows outward like a real one.
- A parcel sharing an edge or a corner. Cost: two parcels joined only at a corner, which no 4-neighbour rule-3 path crosses without unowned land. Benefit: little.
- Selling back at the price paid or less, or never. Cost of selling: a sell action, a price rule, and holes on sold land to close. Benefit: a player can undo a bad purchase late.
Choice: a parcel may be bought when it shares an edge with an owned parcel and its price fits the land budget; a refusal names the rule that failed. No selling back (user, 2026-11-03, the story's proposal). A purchase is one undo step, which gives the price back (E6-S3), and that is the only way a parcel is given up.
Why: pillar 4: one adjacency check, and no sell action or sell price to tune. Undo already covers a misclick, the case selling would mostly serve. Pillar 3: the course's land is a record of what the player chose to buy.
Affects: docs/design.md Land, course/builder.gd (E6-S3), scenes/ (E6-S5), the Claude Docs design doc (Course building: Land)

## D28: What does land cost, and what is the land budget until E4? (2026-11-03)
Question: D19 left parcel prices and the budget open; E4 has no money yet.
Options:
- One flat price per parcel. Cost: no reason to prefer one parcel over another. Benefit: nothing to tune.
- A base price plus or minus what is on the parcel: hills (its height relief) up, trees and water down. Cost: a formula and its numbers. Benefit: a hilly parcel is worth more and a wooded or wet one is a bargain with work in it, a choice the player reads from the land.
- A price that rises with every parcel bought. Cost: a curve to tune before E4 has an economy. Benefit: it limits sprawl, which the budget already does.
- Budget: $5,000 spent on parcels only, or no limit until E4.
Choice: `price = $1,000 + $100 per step of relief - $1 per tree tile - $2 per water tile`, clamped to $500 to $2,000 and rounded to $50, every number in `data/land.json`; provisional, for E6-S8's `/balance land`. A New course starts with a $5,000 land budget, spent on parcels only until E4-S1 folds it into the one balance; the starting block is free (user, 2026-11-03, the story's proposal). New sandbox has no limit. Under the generator's 60% rough floor every generated parcel prices $800 to $1,700, so the clamp never binds on generated land and trees and water take at most about $200 off; E6-S8 decides whether the discounts must rise for a wooded or wet parcel to be a real bargain.
Why: pillar 3: what is on the land changes its cost, so where to grow is a decision. The budget buys about 4 typical parcels ($1,150 each), enough for a par 3 and a par 4 and far short of the roughly 34 parcels nine holes need, so E4's money has work to do (E6-S8's target).
Affects: docs/design.md Land and Economy and time, data/land.json (E6-S3), course/builder.gd (E6-S3), docs/BACKLOG.md E6-S8 and E4-S1, the Claude Docs design doc (Economy)

## D29: What does a ball do on land the player does not own? (2026-11-03)
Question: D19 left it open. A shot can leave owned land wherever the course runs near its edge.
Options:
- It plays on as on any land. Cost: holes play over ground the player has not bought, so buying land never gives a hole room. Benefit: nothing new.
- Out of bounds only if it comes to rest there, playing the real ground until then. Cost: a ball can kick off an unowned hill back into play, and the drop must also handle unowned water and trees. Benefit: closest to a real OB line.
- Out of bounds as an `oob` tile is: a ball that touches down on or rolls onto unowned land stops there and is OB. Cost: a ball cannot kick back in off unowned ground. Benefit: D9 and D15's rule, its entry point and its drop walk already exist and are tested; one ownership check in the ball's surface lookup.
Choice: out of bounds (user, 2026-11-03: a ball that comes to rest on unowned land is OB, one stroke and a drop, D9 and D15, drawn as a boundary). Measuring it as an `oob` tile is the implementer's reading of that answer, not the user's, chosen because existing `oob` tiles stop the ball that way: touching down on or rolling onto unowned land stops the ball there, so it rests OB, and the drop walk passes over unowned tiles. A flight over unowned land that comes down on owned land plays on. ShotPrediction reads the same ownership. Unowned heights stay in the height field. New sandbox owns every parcel, so its play is unchanged.
Why: pillar 2: one OB rule with one visible line, which the aim marker already predicts. Pillar 1: a hole's ball never plays on land the player does not have, and buying the parcel beside a hole is how it gets room.
Inconclusive: the user said "comes to rest"; the stricter reading also makes OB a ball that rolls onto unowned land and would have rolled back. E6-S8's hand playtest checks whether that feels fair beside the boundary; if not, the second option replaces it in a new decision before E6-S7 is built on it, or after with E6-S7 reworked.
Affects: docs/design.md Land and Grid and terrain (Out of bounds), golf/ball.gd and golf/shot_prediction.gd (E6-S7), scenes/ aim view (E6-S7), the Claude Docs design doc (Course building: Land; Golf play: Flight and roll)

## D30: Which tiles of a hole must be on owned land? (2026-11-03)
Question: E6-S4's draft asks for a hole's whole D11 footprint (30 yd round the tee-to-cup line) on owned land. E6-S1's hand calculation shows that the 2 x 2 starting block (D26) then holds no hole over 134 yd, and a par 4 needs 4 purchases.
Options:
- The whole footprint. Cost: the tee and the cup must sit 6 tiles inside owned land, so the block's longest hole is 134 yd, the 160 yd par 3 does not fit, and a par 4 needs 2 x 4 parcels (272 yd), most of the $5,000. Benefit: no OB within 30 yd of a hole's line.
- The tee tile, the cup tile and a rule-3 path, with unowned land counted as OB in rule 3. Cost: a hole may run beside the boundary, where a wide shot is OB. Benefit: the block holds a par 3 up to 219 yd, one purchase (2 x 3 parcels, 281 yd) holds a par 4, and OB beside a hole is ordinary golf. The footprint keeps its D11 job, closing a hole on an edit near it; unowned land cannot be edited anyway.
- A narrower owned margin round the line, such as 10 yd. Cost: another tunable and a capsule test. Benefit: some room guaranteed. Little gained over the second option, since the OB line is drawn and the aim marker shows it.
Choice: a hole needs its tee tile and its cup tile on owned land (a new validator rule 6, "Tee and cup on owned land", built in E6-S4) and a rule-3 path, which counts unowned land as OB. Its footprint need not be owned.
Why: pillar 1 and D26's intent: the starting block fits the first par 3 and one purchase the second hole. Pillar 2: the boundary is drawn and predicted (D29), so a hole beside it reads as a tight hole, not a broken one.
Inconclusive: the user chose the 2 x 2 block expecting room for a par 3; this decision is what lets a 160 yd par 3 fit in it. If the whole footprint should be owned after all, the block or the parcel size has to grow to hold it, and that reopens D26.
Affects: docs/design.md Land and Hole validation rules (rules 3 and 6), course/validator.gd and course/builder.gd (E6-S4), docs/BACKLOG.md E6-S4, the Claude Docs design doc (Course builder: Hole rules)

## D31: What happens to the settle cases that tuning cannot bring inside D16? (2026-11-04)
Question: E6-S9, E6-S10 and E6-S11 each ran out of knobs. Left over: fast downhill putts over a steep green bank (715 ticks, 11.9 s, on two steps per tile), long one-step cart path slopes (845 ticks, 14.1 s, stepping every tile; up to 16.6 s through ShotModel), fairway clubs down a slope stepping every tile (684 ticks), random greens of heights 0 to 4 and 0 to 7 (up to 589 ticks) and the two mixed green banks (up to 548 ticks).
Options:
- Accept them as known limits beside D16, with guard tests at their measured worsts. Cost: on these rare shapes a ball can roll for up to about 16 s. Benefit: no physics change, every other D16 case stays met.
- A settle clock: extra friction on any ball still moving near the target. Cost: a ball visibly brakes on those shapes, against pillar 2. Benefit: every case is met.
- More physics work on the untried logic changes. Cost: another round with no promise. Benefit: maybe a real fix.
Choice: accept them as known limits (user, 2026-11-04). D16's targets do not move; these shapes are named exceptions, each guarded in `tests/test_ball.gd` a little above its measured worst, so a regression still fails. E6-S9, E6-S10 and E6-S11 close on this decision.
Why: pillar 2: a ball that rolls a little long on a rare shape still reads true, and a ball that brakes for no reason does not. Pillar 4: no more tuning rounds for rare shapes.
Affects: docs/design.md Ball (Known limits, Settle targets), tests/test_ball.gd (guards for the bank putts and the cart path slopes; the green guards from E6-S11)

## D32: Do D29's strict reading and D30 stand? (2026-11-04)
Question: E6-S23 put two implementer's calls to the user: D29 measures unowned land as an `oob` tile (a ball that touches down on or rolls onto it is OB, even if it would have come back), and D30 asks a hole to own only its tee, its cup and a rule-3 path, not its whole 30 yd footprint.
Options: keep both; judge OB only where the ball comes to rest (the drop walk then handles unowned water and trees); require the whole footprint (the starting block then holds no 160 yd par 3, which reopens D26).
Choice: keep D29's strict reading and keep D30 (user, 2026-11-04). D29's and D30's Inconclusive lines are answered by this entry. The last-resort drop is D25's rule, and E6-S13 extends the cup rule to tree scatter: a scatter target within `cup_radius` of the cup is rejected like one on trees or water (docs/design.md Ball, Tree scatter).
Why: pillar 2: one OB rule with one visible line, already predicted by the aim marker. Pillar 1: the starting block holds a playable par 3 at once.
Affects: docs/design.md Land, the Claude Docs design doc (Course building: Land)

## D33: How far is the shortest par 4, against a perfect drive? (2026-11-04)
Question: E6-S8's playtest found a perfect driver reaching the green of a 280 yd par 4 on 3 of 4 seeds. Rule 4's shortest par 4 was 250 yd, and a perfect drive (245 yd carry, 294 yd total on flat fairway) went past it, so a validator-legal par 4 played as a par 3 (E6-S19). On generated land a perfect drive's total spreads from about 230 to 364 yd with the ground, so no flat yardage keeps every one short.
Options:
- Shorten the driver alone (`/balance clubs`). Cost: the carry target is 230 to 260 yd, so even a 230 yd carry rolls past a 250 yd par 4's green; and the roll ladder (no club rolls more than the one above it) keeps the driver's roll factor at the 3w's 0.95 or more. Benefit: no rule changes.
- Raise rule 4's shortest par 4 alone, to 320 yd. Cost: par 3s run up to 319 yd; the flat drive stops 11 yd short of a 30 yd green, and on generated land 23% of perfect drives still reach it. Benefit: one number.
- Both: the shortest par 4 320 yd and the driver's carry 235 yd (inside 230 to 260). Cost: two numbers and the docs that quote them; par 3s up to 319 yd, and from about 298 yd a par 3's green front (15 yd short of its cup) is past the flat perfect drive's 282 yd, so a par 3 of 298 to 319 yd cannot be reached in one on level ground; 14% of perfect drives on generated land, those down falling ground, still reach the green; the second hole takes two purchases, not one. Benefit: the flat drive (282 yd) stops 23 yd short of the green's front, every other clubs, lies, surfaces and land target holds, and two purchases in a line off the block hold a 320 yd par 4 across the corners.
- Keep 250 yd and accept drivable par 4s. Cost: the hole the scripted player eagles on most seeds counts as a par 4 when E3 rates par. Benefit: nothing changes.
Choice: both: `par4_min_yd` 320 (`course/validator_tuning.tres`) and the driver's `carry_yd` 235 (`golf/clubs.tres`). A perfect drive on flat fairway stops short of the green of the shortest par 4, as a clubs target in docs/design.md Balance targets (`scripts/sim.gd --table clubs`). The drives that still reach it on generated land are accepted: rule 4 measures flat yardage (D11), so a short par 4 down a hill plays short, as a real one does, and that ground is the player's choice. `/balance clubs` prints their share (14% on seeds 1 to 20) so a change shows. This revises D26's Why and D30's Benefit and Why: one purchase (5 parcels, a 32 x 48 tile bounding box, 281 yd corner to corner) no longer holds a par 4, so the course's second hole comes with its second purchase (two parcels in a line off the block, a 6-parcel shape whose bounding box is 32 x 64 tiles, 351 yd corner to corner), about $2,100 of the $5,000 at the median parcel price. Courses saved before D33 (0.2.0's version 1 files, and version 2 files saved before this story) are not migrated: an open par 4 of 250 to 319 yd loads as saved, the builder closes it with a rule-4 issue ("280 yd is a par 3, not par 4") and the player sets it to par 3 and opens it again (`tests/test_hole_open.gd`). A version-keyed migration could not re-par version 2 files saved under the old band, and re-parring would change the player's hole without asking. Par 3s of about 298 to 319 yd that no club reaches in one on level ground are left for E3-S1, when par is rated (a cap on the par 3 band, or a landing zone for long par 3s).
Why: pillar 2: par says how the hole plays, so a par 4 is not reached in one by a perfect swing on level ground. Pillar 4: two numbers, no new rule; an elevation-adjusted yardage would be a new rule 4 and is left to a later story if E3's ratings need it.
Affects: D26 and D30 (one purchase no longer holds the second hole), saved courses with an open par 4 of 250 to 319 yd (they load closed), docs/design.md Hole validation rules (rules 4 and 5), Land (hand calculation), Swing (clubs table), Balance targets (clubs, land), course/validator_tuning.tres, golf/clubs.tres, scripts/balance_sim.gd, scripts/land_playtest.gd, tests/test_validator.gd, tests/test_hole_open.gd, tests/test_sim.gd, the Claude Docs design doc (Hole rules; Golf play: Clubs)

## D34: What do E6-S16's blocked marker and D33's two-purchase par 4 change in D20, D26 and D30? (2026-11-04)
Question: this file is append-only, so three entries still say what later work changed. D20's Choice draws the blocked marker as "a flag_red ring struck through by a slash", but E6-S16 made it an upright filled octagon with a chalk bar, because the slashed ring was the OB cue's shape told apart only by the slash's direction. D26's Why and D30's Benefit and Why say one purchase (2 x 3 parcels, 281 yd corner to corner) holds the course's second hole, a par 4, but D33 raised the shortest par 4 to 320 yd, so it takes two.
Options:
- Leave the old entries and let docs/design.md carry the change. Cost: the log contradicts the code, and a reader of D20, D26 or D30 alone is misled. Benefit: no entry.
- Edit D20, D26 and D30 in place. Cost: breaks the append-only rule and loses why each was chosen as it was. Benefit: each entry reads true on its own.
- One new entry that supersedes the named clauses and leaves the rest of each entry standing. Cost: a reader follows a pointer. Benefit: history intact, one place to look.
Choice: the new entry (E6-S24). Blocked marker: D20's rule, its marker position (`ShotPrediction.stop_point`, no dots), the club picker's "(blocked)" and the guests' `ClubSet.is_blocked` all stand; only the shape changes. A blocked club's marker is a filled flag_red octagon standing upright on an ink outline, with a level chalk bar across it (a "no entry" sign; `scenes/hazard_cue.gd`, `HazardCue.draw_blocked`), at a fixed size on screen like the hazard cues (E6-S16). The three outcome marks then differ by shape, not by hue or slash direction (colourblind rule): water is chalk splash rings, OB a flag_red ring with a slash running past it and drawn over the ball (`ob_slash_reach` 1.8, kept at least its 1x length on screen at 2x since E6-S27), blocked the octagon and bar. Par 4 land: D26's 16 x 16 parcels and free 2 x 2 starting block and D30's rule (tee, cup and a rule-3 path on owned land) stand, and the block still holds a par 3 up to 219 yd. What changes is the purchase count in their Why and Benefit lines: one purchase (5 parcels, a 32 x 48 tile bounding box, 281 yd corner to corner) holds no par 4 since D33, and two purchases in a line off the block (6 parcels, a 32 x 64 tile bounding box, 351 yd corner to corner) hold the shortest par 4 of 320 yd, about $2,100 of the $5,000 at the median parcel price ($1,050, E6-S8). The land balance target (room for a 160 yd par 3 and the shortest par 4 on every seed spending the budget cheapest first) holds on every seed at 320 yd (E6-S19), and the budget still buys 4 to 5 parcels, so 2 or 3 are left after the second hole.
Why: pillar 2: a blocked shot, a ball in water and a ball OB each read by shape, at every zoom and in grayscale. Pillar 3: the course's second hole is still the reason for its first purchases, now two of them, and the budget still runs out far short of nine holes, so E4's money has work to do. Pillar 4: no rule or number changes here; it only records what E6-S16 and D33 already built.
Affects: D20 (Choice: the marker's shape), D26 (Why: one purchase holds a par 4), D30 (Options and Benefit: "one purchase (2 x 3 parcels, 281 yd) holds a par 4"; Why), docs/design.md Swing (Aim line and marker), Shot model ("A ball at the foot of a riser"), Land (hand calculation), the Claude Docs design doc (Golf play: Aim; Course builder: Land and Hole rules; to be mirrored by the orchestrator)

## D35: What do par 5s, long par 3s, elevation and old short par 4s do after D33? (2026-11-04)
Question: E6-S19 (D33) set the shortest par 4 at 320 yd and the driver's carry at 235, and left four par questions for E6-S25's spike: can a par 5 be reached in two, what a 298 to 319 yd par 3 needs, whether rule 4 allows for the height between tee and cup, and what a player is told when an old course's short par 4 loads closed. Measured in the spike (`scripts/sim.gd --table clubs`, seed 1, and generated land seeds 1 to 20).
Options:
- Par 5 in two: accept it (a docs line), raise `par5_min_yd` to about 559 (550 yd holes become par 4s, par 5s need more land), or cut the 3-wood (breaks the club ladder, below the 6-iron).
- Long par 3s: give every hole of 300 yd or more rule 5's landing zone whatever its par (one condition and a tunable), cap par 3 at 297 yd (298 to 319 yd holes fit no par and cannot open), or accept them as hard holes (a next tee may sit where their tee shots land).
- Elevation: keep flat yardage, show the tee-to-cup height on the hole card, or a plays-like yardage in rule 4 (the card's yardage stops deciding par, and the 14% of downhill drives reaching a 320 yd green falls only to about 11%).
- Old short par 4s: one notice on load and import listing every closed hole with its reason, the same plus a "Set to par 3 and open" button, or the per-hole highlight only.
Choice (the user, 2026-11-04): accept par 5 in two (driver plus 3-wood 543 yd on flat ground); give every hole of 300 yd or more a landing zone by length, a new story E6-S37 with its tunable in `course/validator_tuning.tres`; keep flat yardage (D11, D33), no rule change; one notice on load (E4-S7) and import (E5-S5) listing every hole the validator closed with its one-line reason.
Why: pillar 1: every length from tee to cup still has a par, so a hole opens wherever its cup goes. Pillar 2: par stays the yardage on the card, and the zone protects the ground where a long par 3's tee shots really land; a returning player is told why a hole closed. Pillar 4: three of the four answers are docs and Accept lines, and the one rule change is one condition in rule 5.
Affects: docs/design.md Hole validation rules (rules 4 and 5) and Balance targets (clubs); docs/BACKLOG.md E6-S37, E4-S7 and E5-S5; the Claude Docs design doc (Course builder: Hole rules; Open questions)
