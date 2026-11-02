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
