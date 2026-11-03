# Backlog

Epics map to milestones in `docs/design.md`. An epic is `planned` until `/next-epic` activates it, then `active` until every story is checked, then `done`. `/next-story` takes the first unchecked story of the active epic.

Stories under a `planned` epic are drafts. `/next-epic` re-checks them against `docs/design.md` and what earlier epics taught us, rewrites what no longer holds, then activates the epic.

## Story format

```
- [ ] E<n>-S<m> Imperative title. One-line goal.
  - Accept: what a person can see in the game, or a test can assert.
  - Test: named GUT file, or how to verify by hand.
  - Touches: folders.
  - Settles: open items the story must close first (spike stories only).
```

Stories name systems by folder. They name a file only when it is a test, or when a skill already expects that exact path. A story touching more than two folders gets split.

## E1: Ball on a tile — done

Ships as 0.1.0. Retires the biggest risk: the isometric projection and the height map fighting each other in the physics.

Done when: you can paint hills, fire a debug shot over them, and the ball lands where the math said it would.

- [x] E1-S1 Stand up the project skeleton. Get a repo, a main scene with Build and Play states, and green checks.
  - Accept: `git init` done with a first commit, since `/next-story` commits and this folder is not yet a repo. Pick the engine version and record it with `/decision`: the repo says 4.3 and `scripts/install_godot.sh` pins it, but `godot` on this machine is 4.7.2. GUT is pinned to a release that runs on that version and installed in `addons/gut`. `scenes/main.tscn` exists (`project.godot` already points at it) and a key toggles Build and Play with no scene load. `.gitignore` is reviewed: it currently ignores `*.import`, which loses per-asset import settings on a fresh clone.
  - Test: `scripts/run_tests.sh` exits 0 with one real test in `tests/test_main_states.gd`. It exits 3 without GUT, so GUT is part of this story.
  - Touches: `scenes/`, `scripts/`, `tests/`
- [x] E1-S2 Build the CourseData resource. Give every system one source of truth.
  - Accept: a 2D tile array (height 0 to 7, surface enum), a holes list, and `to_dict` / `from_dict` in course format version 1 from `/course-file`, including the base64 `tiles` packing and `oob` as surface 8. A 20x20 course round-trips through JSON with no loss. Out-of-range heights are rejected on load.
  - Test: `tests/test_course_data.gd`
  - Touches: `course/`, `tests/`
- [x] E1-S3 Build the placeholder art and screenshot tools. `/art-spec` and `/next-story` both call tools that do not exist yet.
  - Accept: `art/palette.gpl` (about 32 colors), `scripts/placeholder.py`, `scripts/screenshot.sh <scene>`, and specs plus placeholders for surfaces and risers. Each surface has its colorblind pattern from day one. `screenshot.sh` writes a real PNG: Godot's `--headless` mode has a dummy renderer and draws no pixels, so it needs a display (`xvfb-run` is not installed on this machine).
  - Test: by hand. Run the screenshot script on a test scene and open the PNG.
  - Touches: `art/`, `scripts/`
- [x] E1-S4 Render the course isometrically. Draw any CourseData with heights correct and a usable camera.
  - Accept: TileMapLayer draws surfaces, risers per height step, Y-sort on. A 20x20 course with heights 0 to 7 has no overlap artifacts at 0.5x, 1x and 2x. Pan with middle mouse or WASD. Tile-to-screen and screen-to-tile projection live in one shared helper.
  - Test: `tests/test_iso_projection.gd` round-trips tile to screen to tile at every height. Screenshot at each zoom.
  - Touches: `course/`, `scenes/`, `tests/`
- [x] E1-S5 Paint terrain. Let the player shape land through the builder, the only writer.
  - Accept: surface palette for the 8 surfaces, raise and lower, brush 1/3/5, undo stack. The tile under the cursor is picked correctly on raised ground, including a tile partly hidden by a nearer hill. 50 edits then 50 undos restore the original CourseData hash. Heights clamp at 0 and 7.
  - Test: `tests/test_builder.gd`
  - Touches: `course/`, `scenes/`, `tests/`
- [x] E1-S6 Step the ball over the height map. Custom 3D physics at 60 Hz, no scene needed, so guests can reuse it.
  - Accept: gravity, one bounce by surface, roll downhill with surface friction read from a resource, height interpolated between tiles. A flying ball that meets a hillside lands there. Randomness comes from a seeded generator owned by the ball, never the global one. The same seed and inputs give the identical landing position 100 of 100 runs, not just the same tile.
  - Test: `tests/test_ball.gd`
  - Touches: `golf/`, `tests/`
  - Settles: yards per height step, gravity and bounce values (none are in `docs/design.md` yet; add them there).
- [x] E1-S7 Fire a debug shot. See the physics on the projected map.
  - Accept: a button fires the ball at fixed power and angle. The sprite follows the projected path and a ground shadow shows its height. The ball lands on the predicted tile, within 1 tile, on flat and sloped terrain. The prediction comes from running the same step function ahead of time.
  - Test: `tests/test_shot_prediction.gd` covers flat and sloped courses. Screenshot mid-flight.
  - Touches: `golf/`, `scenes/`, `tests/`
- [x] E1-S8 Make `/ship-it` runnable. Its smoke test and export setup do not exist yet.
  - Accept: `scripts/playtest.gd` runs headless and asserts only what the current milestone has built. For E1 that is firing a shot and landing it. `/playtest` smoke is updated to say so: its full bar (holed out, guest reaction, money changed) cannot pass before E4, yet `/ship-it` requires it at every milestone. `docs/export.md` and `export_presets.cfg` exist for Linux and Windows.
  - Test: run smoke headless. Export a Linux build and launch it. Export templates must be installed first.
  - Touches: `scripts/`, `docs/`
- [x] E1-S9 Decide grid size and height model. Close the two open questions the design doc assigns to this milestone.
  - Accept: paint a 3-step green contour and a hillside, fire shots across them, take screenshots, then record two `/decision` entries. They answer whether 5 yards per tile is too coarse for green contours and whether sub-step ramps are needed. The design doc already assumes ramp tiles, so the decision states what "ramp" means. If either answer changes the data model, file a story here before closing the epic.
  - Test: screenshots attached to the decisions in `docs/DECISIONS.md`. `/godot-check` green.
  - Touches: `docs/`
  - Settles: design doc open questions "Grid size" and "Height model".
- [x] E1-S10 Show rises that face away from the camera. Make every slope visible without camera rotation.
  - Note: found by E1-S9 (D5). Risers are drawn only on faces that point at the camera. A rise along +x or +y shows no riser and identical tops, so the 3-step green contour and the 7-step hillside in `docs/decisions/e1-s9-green.png` and `e1-s9-hill.png` look flat. No data model change.
  - Accept: a tile higher than its back neighbour (x - 1 or y - 1) draws an edge cue along that back edge, because that rise faces away from the camera and has no riser. A tile whose back neighbour is higher draws no cue there, since the neighbour's riser already shows it (`CourseView.riser_frame` draws faces toward x + 1 and y + 1). The cue uses palette colors, has a pattern as well as a color, and differs by step count, or at least marks a step of one versus more. Every step of `GridHeightEvidence.green_contour()` and `hillside()` can be counted at 0.5x, 1x and 2x. The cue depends on the back neighbours, so `refresh_cell` also redraws (x + 1, y) and (x, y + 1), and editing a tile's height updates the cues in front of it. Picking and draw order are unchanged.
  - Test: cases in `tests/test_course_view.gd` check that the cue is present on a tile higher than its back neighbour, absent on a flat tile, and absent where the back neighbour is higher. A further case raises a tile and checks that `refresh_cell` adds the cue on its front neighbours. Screenshots: `EVIDENCE_CASE=green` and `EVIDENCE_CASE=hill scripts/screenshot.sh tests/fixtures/grid_height_shot.tscn`.
  - Touches: `course/`, `art/`, `tests/`
- [x] E1-S11 Make green contours putt as breaks. A one-step contour on a green should bend a putt, not wall it off.
  - Note: found by E1-S9 (D5). One step is a 40% slope. On a contoured green, 7 to 9 yd/s uphill putts finish within 0.7 yd of where they started, and a sidehill putt falls 5 yd sideways (`docs/decisions/e1-s9-probe.txt`). No data model change. This could move to E2, before E2-S5, at `/next-epic`.
  - Accept: a per-surface `slope_scale` in `course/surfaces.tres` (green about 0.075, every other surface 1.0) scales the slope pull on a rolling ball and the tilt of the ground normal at touchdown on that surface. The ball's height still follows the terrain. Scaling the pull alone breaks the rest rule: on green a scaled one-step pull is about 10.7 x 0.03 = 0.32 yd/s², below the constant friction `roll_decel` / roll = 1.5 / 1.4 = 1.07 yd/s², so a still or slow ball on a green slope would never start downhill. So the constant friction gets a per-surface value too (for example a `roll_decel` column, or the global one scaled by `slope_scale`), set so the scaled one-step pull beats it on every rolling surface, and the green's drag is retuned so a 4 yd/s putt still runs about 3.7 yd on a flat green. On `GridHeightEvidence.green_contour()`, a 9 yd/s uphill putt from the front tier ends within 1.5 yd of its flat-green distance, a 3 yd/s sidehill putt across a step breaks between 0.1 and 1 yd, a ball set down still on a step's slope rolls down to the lower shelf, and an uphill putt that stops short on a step rolls back. Shots on other surfaces are unchanged and the non-green ball tests pass as they are. The green-slope tests (`test_ball_at_rest_on_a_green_slope_rolls_down`, `test_ball_rolling_downhill_on_green_speeds_up`, `test_uphill_putt_that_stops_short_rolls_back`) keep their assertions but may change their ramp or speeds, and `test_slope_pull_beats_rest_friction` compares the scaled pull with each surface's constant friction. The `docs/design.md` Ball lines on friction, slope pull and rest speed are updated in this story, and it gets a `/balance surfaces` target. `docs/decisions/e1-s9-probe.txt` gains still-ball and slow-ball cases on the scaled green.
  - Test: cases in `tests/test_ball.gd`.
  - Touches: `golf/`, `course/`, `tests/`
- [x] E1-S12 Settle green balls in seconds, not half a minute. A putt should finish while the player still cares.
  - Note: found in E1-S11 review. Linear drag gives a slow ball on a green slope a terminal speed, about 0.16 yd/s with the E1-S11 values and only about 0.5 yd/s even if the constant friction never ramped back up (pull 0.32 less the 0.08 still-ball friction, over the green drag of 0.47 per second). So a ball set down on a contour step takes up to 28 s to reach the shelf, uphill putts that roll back take 12 to 35 s, a 3 yd/s sidehill putt runs 2.5 yd forward and then slides 2.5 yd sideways for 13 s, and on a green that rises one step per tile for several tiles a still ball hits the 60 s cap mid-slope. A sweep of `rest_decel_scale`, `decel_ramp_speed` and `drag_scale` found no setting that meets the E1-S11 putt targets and brings a multi-tile green ramp under the cap. Could move to E2, before E2-S7, at `/next-epic`.
  - Needs: a user answer, recorded with `/decision`. Is the sidehill "break" read where the putt runs out of pace (as E1-S11 measures it, 0.38 yd) or where the ball comes to rest (2.5 yd today)? And must a still ball on any green slope roll to the shelf, or may a ball rest on a felt slope below some threshold, as a real green holds a ball on 3%? Allowing rest changes the E1-S11 still-ball clause and makes most of this story a retune.
  - Accept: a `/balance surfaces` target in `docs/design.md` for the longest green settle time (for example 8 s), measured on `GridHeightEvidence.green_contour()` and on a green rising one step per tile from height 0 to 7. Every still ball and every putt from 1 to 15 yd/s on both settles under it, with steps below `max_steps`. The E1-S11 putt targets, or a widened band agreed through `/balance`, still hold.
  - Test: cases in `tests/test_ball.gd`, including a still ball on a several-tile one-step-per-tile green ramp that reaches flat ground with steps < `max_steps`, and `test_ball_at_rest_on_a_green_slope_rolls_down` back at its original x 20 start.
  - Done (D7): a green holds a slow ball on a felt slope up to about 4.5% (`rest_decel_scale` 0.45, `decel_ramp_speed` 1.5) and the break is read at rest (0.34 yd). Longest settle for a ball resting on green 5.5 s on the contour (axes and diagonals), 5.6 s on the ramp; a putt that runs off onto the rough's slope can take about 9.6 s (rough physics, known limit). On the one-step ramp the still ball and the x 20 start are held where set, and the tests say so; the roll-down (still from x 20) and roll-back tests moved to a two-steps-per-tile green. Open, before E2-S7 (D7 Inconclusive): greens steeper than the hold still trickle (still balls reach the cap mid-slope, roll-backs 8 to 28 s), and resting balls are drawn off the flat tile tops.
  - Touches: `golf/`, `course/`, `tests/`, `docs/`
- [x] E1-S13 Rest a ball that settles in a dip. A ball in a one-tile pit should stop, not rock for 60 s.
  - Note: found in E1-S11 review, and on main before it, on every rolling surface. A still ball in a one-tile pit hits the 3600-tick cap on green and on fairway: the static branch of `Ball._step_roll` adds the pull less the friction and nothing damps the swing across the gradient jump at the tile centre.
  - Accept: in the static branch, a ball whose pull reverses against its velocity (it is at a low point) rests, or the hold is applied against the velocity before the pull is added. Other ball tests pass as they are.
  - Test: a case in `tests/test_ball.gd`: a still ball set just off the centre of a one-tile pit, on green and on fairway, rests within 1 s (60 ticks) near the centre.
  - Touches: `golf/`, `tests/`

## E2: One hole — active

Ships as 0.2.0. Serves pillars 1 and 2: one click from the tee, honest shots.

Done when: you can design a single hole, stand on its tee in one click, play it to the cup, and read your score.

Planning notes:

- The user answered the four planning forks on 2026-11-03: cut wind, paint `oob` from the Build palette, fix steep greens in the physics (E2-S4), and snap the drawn rest height to the tile top (E2-S7). E2-S1 records these answers with `/decision`; it does not reopen them.
- The E1 review follow-ups (old E2-S10 to E2-S20) are folded in, and none is dropped. The settle cases and steep greens go into E2-S4. The resting-ball drawing goes into E2-S7. The D7 mirror and the E1-S12 commit note go into E2-S1. The hand checks go into E2-S9.
- Two-folder rule: some paths are listed in Touches but do not count toward a story's two folders. They are `tests/` (including `tests/fixtures/`), the smoke harness (`scripts/playtest.gd` and its fixture `data/playtest_smoke.json`), and edits to `docs/design.md` lines or `docs/decisions/` evidence that record the story's own change. They count as test and doc upkeep, not scope.
- E2-S1 settles the rules and targets that cross stories or need the user. A story that only sets its own starting numbers against those targets lists them under Settles and writes them into `docs/design.md` in the same commit, as E1-S6 did.
- New markers (tee, pin, aim line, landing marker, swing bar) are drawn in code with colours from `art/palette.gpl`. Each has a shape as well as a colour, like the E1 ball and landing marker. Their art specs come with the final art (E5-S1, E5-S3).

- [x] E2-S1 Settle the rules and targets One Hole needs. A spike: the stories below cannot be built from `docs/design.md` as it stands.
  - Done: D8 to D18 in `docs/DECISIONS.md`, the rules and targets in `docs/design.md` (Grid and terrain, Hole validation rules, Swing, Ball, Balance targets). The Claude Docs design doc mirror (D7 and D8 to D18, wind removed from Aim and the Play toolbar) is applied by the orchestrator, not from this branch. One departure from a recommendation: lie slope is read from the heights around the ball (rise 5 yd ahead, tilt across a 10 yd window), not from the gradient at the rest point (D14 says why).
  - Note: why a spike comes first. The milestone's only design-doc open question, "Swing bar feel", closes in E2-S9. Every other story depends on choices that need the user or a `/decision`: wind, out of bounds and the plot, where the Claude Docs design doc and `docs/design.md` disagree, plus steep greens and the drawn rest height, left open by D7. They also depend on rules that cross stories: the shot model is shared by E2-S5 and E2-S7, and the hazard and cup rules by E2-S6 and E2-S8. Measured starting values stay with the story that tunes them.
  - Accept: each item under Settles has a line in `docs/design.md`, and a `/decision` where it is a real choice. The planning forks are recorded as the user answered them, not reopened. Wind and OB each get a `/decision`. The Claude Docs design doc gets D7 (a green holds a ball on a gentle slope, and the break is read at rest) and every decision made here. If wind is cut, that edit removes it from the Play toolbar and the aim marker. If the user declines a design doc edit, the decision says so. DECISIONS.md is append-only, so D7 is not edited. Instead, the `/decision` that sets the settle targets ends with this line: "The E1-S12 commit body describes the rest rule from before D7's per-axis wording; `docs/design.md` Ball is current." A hand calculation in `docs/design.md` shows that the chosen bar and lie rules can reach the bunker target (SW at 50% lands 20 to 40 yd) with a plausible SW carry, before E2-S5 tunes it.
  - Test: none. Review the `docs/design.md` and DECISIONS.md diffs, including that the settle decision carries the E1-S12 line, and the Claude Docs edit.
  - Touches: `docs/`
  - Settles:
    - Wind: cut (user, 2026-11-03). The `/decision` says what this removes from the design doc; the Icebox "Weather" entry already carries the wind note.
    - Out of bounds: off the map plus `oob` tiles, painted from the Build palette (E2-S3) and read from files (user, 2026-11-03). Placed OB stakes stay in the Icebox.
    - Plot: its size, and the surface and height of a blank plot. It must fit a par 5 (more than 94 tiles long) with water on its line for E2-S9, and 9 holes for E3-S2. Its cost is left to E4-S1.
    - Hole rules. Rule 3's path: 4 or 8 neighbours, and which surfaces it may cross (recommended: 4 neighbours, every surface except water and `oob`, trees included, heights ignored). Rule 4's yardage measure (recommended: a straight line from tee centre to cup centre at 5 yd per tile) and its rounding at exactly 250 and 470 yd. Rule 5's landing zone: its shape and size from each tee. A hole's footprint: which tiles count as being under a hole, so that an edit there closes it.
    - Stroke limit: the most strokes on a hole before the ball is picked up, and what the score records. E3-S3 guests use the same limit.
    - Club legality. Where the driver is allowed (recommended: on a hole's first stroke from its tee marker, and on any tee tile, so a tee marker on fairway still allows it). Whether the putter is green only. The sand wedge is bunker only.
    - Shot model:
      - whether bar percentage maps to launch speed or to carry;
      - whether lie multipliers scale carry (recommended, to match the Distance column) or launch speed;
      - how a club's roll factor combines with the surface's Roll and bounce;
      - what hook, slice and sidehill curve are. Recommended: a heading offset at launch, with no new Ball term. A lateral acceleration in flight would be a new `golf/ball_params.tres` term with its own `/decision`;
      - how the lie slope is measured: the gradient at the rest point, projected along the aim for uphill and across it for sidehill, in steps per tile;
      - whether rough's 0.8 to 0.9 is fixed or rolled. If rolled, it comes from the ball's own seed, so the prediction matches the flight.
    - Aim marker: for a full club it shows where a perfect swing lands (100% power, accuracy at centre). For the putter it shows where the putt comes to rest. A perfect swing lands within 1 tile of the marker (E1-S7).
    - Cup and hazards:
      - the cup sits at its tile centre and captures on any surface, checked on ground ticks only, or also at touchdown;
      - the water and OB drop point: the exact "last entry point", and how far back onto playable ground the ball is dropped;
      - what a ball that rolls into a tree tile does;
      - how the 1 to 2 tile tree scatter picks a target that is not trees, water or OB.
    - Settle targets: the longest settle off the green on every rolling surface the builder can paint, on greens steeper than one step per tile (fixed in the physics by E2-S4, user 2026-11-03), and for a putt that runs off the green. The 9.6 s off-green diagonal putt either meets its target or is recorded as an accepted limit, with the reason.
    - Drawn rest height: snap the drawn ball and shadow to the top of the tile under them while on the ground (user, 2026-11-03; built in E2-S7).
    - `/balance` targets: copy all five target lines from `.claude/skills/balance/SKILL.md` into `docs/design.md`, which the skill credits. Restate three of them, and note the restatement in the decision:
      - "putter never leaves the green" becomes "the putter is selectable only on green, and a full putt rolls at most N yd on a flat green". E2-S5 sets N with the putter speed range;
      - "at 100% for a skill-10 golfer" becomes "a perfect swing, until guests have skill in E3";
      - "about one club" becomes "within one club step (10 to 12 yd)", and the sidehill curve target names its club.
      The reactions and economy lines are copied unchanged for E3 and E4.
- [x] E2-S2 Validate a hole and draw its markers. Write the five rules once, for the game and `/course-file` alike, and show the hole on the map.
  - Accept: all five rules from `docs/design.md`, using the E2-S1 path, yardage and landing zone. Each failing rule returns the tile at fault and a one-line reason. The par boundaries are tested at exactly 250 and 470 yd. Rule 5 is real, not a stub, and is tested on a two-hole fixture. `/course-file validate` and `/course-file generate 3 flat dry` work through a headless entry point in `course/` (run with `godot --headless -s`), and validate calls the game's own validator. The other `generate` variants are optional in E2. `courses/example_par3.json` is written by `generate 3 flat dry` and passes. The course view draws a tee marker and a pin for every hole in CourseData, at the height of their tile's top and Y-sorted with the terrain. Loading `courses/example_par3.json` shows the hole.
  - Test: `tests/test_validator.gd`, with at least one pass and one fail per rule, the 250 and 470 yd boundaries, the two-hole rule 5 fixture, and a case showing the generated par 3 passes all five rules, so the example cannot drift. Cases in `tests/test_course_view.gd` assert each marker's draw position and Y-sort key against `course/iso.gd`, not only that it is there. Screenshot of `courses/example_par3.json`.
  - Touches: `course/`, `courses/` (`tests/`)
  - Done: `course/validator.gd` (the five rules, one Issue per failing rule with its tile and reason), `course/validator_tuning.tres`, `course/course_generator.gd`, the headless `course/course_file.gd`, `courses/example_par3.json`, and `course/hole_marker.gd` drawn by CourseView. Rule 1's reading (unplaced tee or cup, tee on the cup, a duplicate hole number) and rule 3's fault tile are in `docs/design.md`. Screenshot fixture: `tests/fixtures/example_par3_shot.tscn`.
- [x] E2-S3 Place a hole in Build and open it. Make a hole exist on the map, and tell the builder what is wrong and where.
  - Accept: a New sandbox action starts a course on the E2-S1 blank plot, through the builder. The startup course in the main scene stays as it is until E2-S8. A tee tool and a cup tool create or move the hole in CourseData through the builder, and the player picks par 3, 4 or 5. These changes go on the same undo stack as terrain. `oob` is on the Build palette as OB ground (E2-S1). Each failing rule is highlighted on its tile with its one-line reason. Open is enabled only when every rule passes. A terrain edit inside an open hole's footprint (E2-S1) closes the hole until it passes again, and after every build edit the validator reruns for every open hole and closes any that now fails (E2-S1). Play stays available as soon as a tee and a cup exist, even when the hole fails validation: pillar 1 outranks the validator, which only decides whether guests can play the hole. `tests/test_shot_prediction.gd` and `bash scripts/playtest.sh` still pass.
  - Test: `tests/test_builder_holes.gd`: place, move, undo, par, painting `oob`, and a new sandbox having the E2-S1 size, surface and height. `tests/test_hole_open.gd`: open gating, an edit inside the footprint closes the hole and one outside does not unless it breaks a rule (water on a rule-3 path outside the footprint, or another hole's tee moved into its zone, closes it), and a failing rule's tile and reason reach the view. By hand: checklist item 1 without its cost clause (the economy is E4), plus a screenshot of a failing rule's highlight.
  - Touches: `course/`, `scenes/` (`tests/`)
  - Done: `course/builder.gd` places and moves hole 1's tee and cup, sets par, opens and closes holes on the terrain undo stack, closes an open hole on a footprint edit (`CourseValidator.in_footprint`) and reruns the validator after every edit (a drag once, when it ends); `CourseBuilder.new_sandbox` from `plot_*` in `course/builder_tuning.tres`; `oob` on the palette; Tee and Cup tools, the hole panel (`scenes/hole_panel.gd`), New sandbox, and `course/issue_marker.gd` highlights. Undo restores the holes as the step found them, open flags included. Play is never gated. 128 x 128 timings are in `docs/design.md` Plot. Screenshot: `docs/decisions/e2-s3-rule-highlight.png` (fixture `tests/fixtures/hole_issue_shot.tscn`). Checklist item 1 by hand is left to the user's E2 hand playtest.
- [x] E2-S4 Settle every ball the builder can make. No ball in play may roll for half a minute or reach the 60 s cap. This lands before E2-S7, because live play makes the player wait out every settle in real time.
  - Done: four changes in `golf/` and `course/surfaces.tres`, all in `docs/design.md` Ball. The gradient at an exact tile centre is the mean of both sides. A concave crease (where the ground turns up against the ball at a tile centre) keeps, per axis, only the velocity along the new ground, which damps valley, pit and gully swings; it never turns the ball back, a lip costs nothing, and at the foot of a steep green bank it feels only `slope_scale`, so a putt still climbs a 2- to 7-step tier (12.8 to 14.2 yd/s from 7.5 yd short). A low point is checked per axis speed, and a stopped axis sits on the low point's line. Rough and trees fade their drag below 12 yd/s (`drag_full_speed`), so slow balls run down rough slopes instead of crawling. Steep greens are fixed in the physics, as the user chose, but by the felt slope, not friction: above `steep_from` 0.6 on each axis a green feels `steep_scale` 1.5 of the extra slope, so one-step contours are unchanged. Friction alone cannot do it (the 6% felt pull is 0.64 yd/s², 6.7 s from the top of a two-steps-per-tile bank with no friction at all). Cart path `drag_scale` 1.1 brings drives down a cart path stepping 7 to 0 (every 1 to 4 tiles, 100% and 110%) under 10 s now that a lip no longer brakes the ball. Every case below meets its target, plus one-tile pits and trenches 2 to 7 steps deep on every rolling surface. The tightest is the stepped cart-path drive at 9.9 s (110%, every 4 tiles). The debug shot still lands on (7, 4) and rests on (12, 4), at x 64.7 instead of 63.1. Known limits in `docs/design.md` Ball, for `/balance surfaces` before E2-S7: fast downhill putts over a steep green bank (up to 12.7 s at 14 yd/s on two steps per tile, over the E2-S5 putter range), V valleys 5 to 7 steps deep (up to 13.5 s on rough), and still balls set on the rim of a two-step green pit, which creep at the rest speed (up to 20.7 s).
  - Note: this folds in old E2-S10 (a green pit from 1 to 2 yd out takes 7 to 13 s) and S11 (a rough gully creeps 6 to 10 yd until the cap). It also takes S12 (the gradient at an exact tile centre is one-sided) and S13 (green gully balls reach the cap at about y 8.2). S15 and S18 come in too: on greens steeper than the D7 hold, still balls reach the cap mid-slope and roll-backs take 8 to 28 s. So does the guard for S20, a diagonal putt off the contour that takes about 9.6 s on rough. Order of work:
    1. Centre the gradient first, since that may fix the pit and green gully cases.
    2. Fix the gully's moving branch: use the averaged cross gradient, or drop the stopped axis from the felt gradient.
    3. Settle steep greens the way the user chose at planning. Recommended: a change to the green friction model in `golf/`, such as less drag at low speed, with any new column values in `course/surfaces.tres`.
    If the steep-green change runs past the session, it moves out into its own story, still before E2-S7.
  - Accept:
    - `HeightField.gradient_at` at an exact tile centre averages both sides, and the pit test shows no spurious pull along y at y = 12.5.
    - Still balls, and balls 1 to 2 yd from the centre, settle under the E2-S1 targets in these cases: a one-tile pit on green and on fairway; a rough gully floor (they reach the bottom); a green gully; and `_steep_green(2, 2)` and `_steep_green(3, ...)`, for still balls and for roll-backs at 4 to 7 yd/s.
    - The off-green diagonal putt from (58.1, 34.4) at (-10.6, 10.6) settles under the E2-S1 off-green target, or a test pins it at the accepted limit that E2-S1 recorded.
    - Still balls across V valleys 2, 3 and 4 steps deep on rough, fairway and cart path, a 110% driver onto flat cart path, and a 100% driver landing at the top of a cart path stepping from height 7 to 0, one step every 4 tiles, settle under the E2-S1 off-green target (today up to 18.7 s on rough).
    - The green putt targets from E1-S11 and E1-S12 still hold.
    - The debug shot still lands at (7, 4) and rests at (12, 4), and `tests/test_shot_prediction.gd` and `bash scripts/playtest.sh` pass. If the debug shot moves, the `docs/design.md` Debug shot line and `data/playtest_smoke.json` are updated in the same commit, with the reason.
    - `docs/decisions/e1-s9-probe.txt` is regenerated, and the `docs/design.md` Ball "Known limit" lines say what is left.
  - Test: cases in `tests/test_ball.gd`, one per case above. Each asserts the settle ticks against the E2-S1 target, not just steps < `max_steps`.
  - Touches: `golf/`, `course/` (`tests/`; `docs/design.md`, `docs/decisions/` and `data/playtest_smoke.json` as upkeep)
- [x] E2-S5 Add clubs and lies. Make distance depend on club, surface and slope.
  - Done: 12 clubs in `golf/clubs.tres` (the E2-S1 draft ladder, 11 yd iron steps, driver 245 yd), putter 1 to 18 yd/s with N = 30 yd (a full putt rolls 27.5 yd), lies in `golf/lies.tres` (rough 0.85, `uphill_k` 0.037, `sidehill_deg` 2.9), `ShotModel` and `ShotLaunch` in `golf/`, `Ball.roll_factor`, and `scripts/sim.gd` over `scripts/balance_sim.gd`. `/balance clubs`, `lies` and `surfaces` hit every target; `/balance surfaces` wants no `course/surfaces.tres` change. The lie targets are read on the D18 terrain and flown on flat fairway (`docs/design.md` Balance targets says why: the 2-step riser is an 80% face no iron clears).
  - Settles: starting values for all 12 clubs (carry, launch angle and roll factor), set against the E2-S1 shot model and targets for a ball with no drag. The putter's speed range and its N yd full putt. The lie numbers: rough's value or roll, the carry lost per uphill step, and the curve a sidehill lie adds.
  - Accept: all 12 clubs live in `golf/clubs.tres`, and their legality follows E2-S1 (driver, putter, sand wedge). Lie multipliers follow `docs/design.md` and the E2-S1 shot model, and live in `golf/`, the folder CLAUDE.md gives lies. Uphill lies shorten carry and sidehill lies add curve, measured and applied as E2-S1 says. `scripts/sim.gd --table clubs`, `--table lies` and `--table surfaces` run with `--runs` and a fixed seed, and print measured values next to their targets. The measuring functions can be called without the command line. `/balance clubs` and `/balance lies` hit their targets. `/balance surfaces` is run once, against the rough distance cost, the bunker SW at 50%, and the green targets measured on `GridHeightEvidence`. Any value change it wants in `course/surfaces.tres` is filed as an E2 story instead of made here. The before and after tables go in this story's commit, not in separate `balance:` commits.
  - Test: `tests/test_clubs.gd`: the table loads, and legality is checked per lie and per stroke. `tests/test_lies.gd`: the multipliers, and the uphill and sidehill numbers. `tests/test_sim.gd` calls the sim's measuring functions directly.
  - Touches: `golf/`, `scripts/` (`tests/`)
- [ ] E2-S6 Teach the ball every surface and the cup. Hazards behave as the table says.
  - Settles: the trees row's bounce, bounce friction and roll; the height up to which trees block a flight; how the scatter is rolled; the cup's capture radius and the fastest speed it still captures at.
  - Accept: water and OB (off the map and on `oob` tiles) cost one stroke, and the ball is dropped at the E2-S1 drop point. The ball reports the penalty and the drop, so the hole score in E2-S8 can count them. Trees block flight below the block height and scatter the ball 1 to 2 tiles, deterministic by seed, to a target chosen as E2-S1 says. A ball rolling into a tree tile does what E2-S1 says. The trees row stops copying rough. A bunker stops the ball, and a cart path bounces hard and rolls at 1.6. A ball can never come to rest on water, on OB or inside trees. The cup captures a ball inside its radius and below its speed, at the moment E2-S1 chose, on any surface. The `course/surface_row.gd` comment that says lie distance joins that row is corrected, because lies live in `golf/` (E2-S5). The `docs/design.md` Hazard behaviour line and the trees row of its surface table are updated.
  - Test: `tests/test_ball_surfaces.gd`: one case per surface, the drop point for water and for OB, a scatter that never lands on trees, water or OB, and cup capture at, inside and outside its radius and its speed.
  - Touches: `golf/`, `course/` (`tests/`)
- [ ] E2-S7 Swing the club. Three clicks, and an aim line that tells the truth for every club, the putter included.
  - Note: this folds in old E2-S19. A ball the physics holds partway up a one-step slope is drawn up to about 7.5 px off the flat tile top, sometimes on the riser. It is drawn as the user chose at planning; recommended: the drawn height snaps to the top of the tile under the ball. If the session runs long, the rest-height snap (scenes/ only, independent of the swing) is the piece that moves out, and it still lands before E2-S9.
  - Settles: the accuracy zone width, what a shank does, the overswing penalty above 100%, the numbers in the bar mapping, the range of the bar speed setting, and the aim rotation step for keys. The step and the swing numbers are tuned in a `.tres` in `golf/` or `scenes/`.
  - Accept: the bar fills in 1.2 s and runs to 110%. Each 10% off centre gives 2 degrees of hook or slice, in the E2-S1 curve model. Outside the zone the shot shanks, and overswing is penalised. Bar speed is a setting (accessibility). The player picks a club from those the lie and stroke allow. A dotted aim line and a landing marker come from the same Ball step (E1-S7). For a full club they show where a perfect swing lands with the selected club and lie. They rotate with the mouse or keys. With the putter, the bar maps to putt speed across the E2-S5 range, and the marker shows the predicted rest point, with the break visible. A perfect swing lands within 1 tile of the marker. A perfect putt rests within 1 yd of it on a flat green and on a contour. The swing logic runs without a scene. A resting ball and its shadow are drawn on a tile top, never on a riser. The Play-mode debug fire button stays. The swing has its own input, and the button is hidden only while a swing is in progress. `bash scripts/playtest.sh` exits 0.
  - Test: `tests/test_swing.gd`: 0%, 100% and 110%; the zone edges and just outside them (shank); bar speed at its minimum and maximum; and the two perfect-putt cases. A case in `tests/test_shot_prediction.gd`: a perfect swing lands within 1 tile of the marker. A new `tests/test_shot_view.gd`: the drawn y of a ball resting on a one-step green slope equals the projected top of the tile under it. Screenshots: the aim line and bar, and a ball resting on a one-step green slope.
  - Touches: `golf/`, `scenes/` (`tests/`)
- [ ] E2-S8 Play the hole end to end. Connect build, swing, ball and score.
  - Settles: the play camera: centring on the ball, and the snap-back key and its tuning value in `scenes/camera_tuning.tres`. Zoom steps and pan already exist.
  - Accept:
    - One click from Build puts you on the tee of the hole you just shaped, with no scene load (D2).
    - The camera centres on the ball when a shot starts and after the ball rests. After you pan to scout, one key snaps it back.
    - Each next shot starts where the ball rests, or at the drop point.
    - A hole score in `golf/` counts strokes, penalty strokes, holed and score to par, with no scene, so E3 guests can reuse it. It picks the ball up at the E2-S1 stroke limit, and play continues until the ball is holed or that limit is reached.
    - The scorecard shows par, strokes including penalties, and the total to par, and shows a pick-up the way E2-S1 says.
    - One click returns to Build with the course unchanged (same `CourseData.content_hash()`).
    - The main scene now starts on the E2-S1 blank plot, and the debug shot moves behind a debug key. `tests/test_shot_prediction.gd` changes to match in the same commit.
    - The `/playtest` smoke's E1 stage sets `course_path` to `courses/heights_20x20.json` before `add_child` and fires through the debug key or `main.fire_debug_shot()`.
    - A new E2 stage sets `course_path` to `courses/example_par3.json` before `add_child` (no load UI is implied), plays the hole with a scripted swing, and holes out. `BUILT_MILESTONE` is raised to 2, and the stage's expectations go in `data/playtest_smoke.json`.
  - Test: `tests/test_round_flow.gd` plays a scripted hole through to a score and checks the content hash afterwards. `tests/test_hole_score.gd` covers strokes, penalties, score to par and the pick-up at the limit. A snap-back case goes in `tests/test_course_camera.gd`. `bash scripts/playtest.sh` exits 0.
  - Touches: `scenes/`, `golf/` (`tests/`; `scripts/playtest.gd` and `data/playtest_smoke.json` as smoke upkeep)
- [ ] E2-S9 Playtest the hole and settle the swing. Close the swing-bar question and the "fun to build, boring to play" risk.
  - Note: this folds in old E2-S16 (short uphill putts that stay on a contour step, a D7 side effect) and D4's open point that nobody has putted on 5 yd contours by hand. Both become questions in the session. The three-click bar is tested alone. The one-click swing waits in the Icebox, with a promotion trigger.
  - Accept: a `/playtest full` session covers checklist items 1 (without its cost clause), 2 and 5, and the build part of item 4: a par 5 with water on the direct line, on the E2-S1 plot. Notes go in `docs/playtests/`. They say:
    - whether the swing bar feels right, at its speed setting;
    - whether the ball landed where the aim line said;
    - whether a putt that stops on a contour step reads as intended;
    - whether 5 yd contours putt well;
    - whether the lay-up choice was real.
    A `/decision` closes "Swing bar feel". `docs/design.md` has no Open questions list, so the reply asks the user to remove the question from the Claude Docs design doc. Findings are filed as the playtest skill says: bugs as E2 stories with "(found in playtest <date>)", feel problems at the top of the Icebox with the pillar named, and numbers as `/balance` findings with the table named, not fixes. `/balance surfaces` can run from E2-S5 on. Item 4's cost question waits for E4. Items 3 and 6 need guests (E3), and items 7 and 8 need fees and saving (E4).
  - Test: findings in `docs/playtests/`. `/godot-check` green.
  - Touches: `docs/`
  - Settles: design doc open question "Swing bar feel".

## E3: Nine holes and guests — planned

Ships as 0.3.0. Serves pillar 3: the course tells a story through its guests. No money yet, so arrivals are a flat number until E4 connects rating.

Done when: nine holes are open, guests play them in order, and their complaints name a hole you can click and fix.

- [ ] E3-S1 Settle the numbers guests need. `docs/design.md` names the checks but not what they measure.
  - Accept: each item below has a line in `docs/design.md`, and a `/decision` where it is a real choice.
  - Test: none. Review the design.md diff.
  - Touches: `docs/`
  - Settles:
    - Round length. A day is 180 simulated seconds, so a 9-hole round must fit in about 20 seconds per hole or span days. This sets walk speed and shot time.
    - Skill to noise on power and accuracy, and expected score per skill for the challenge check.
    - Patience scale and how it fails the pace check: wait time and walk distance limits.
    - Taste list and what each taste changes.
    - How "interesting" is detected. Proposed: a hazard on the direct line plus a safe route that is longer.
    - What "could not see from the tee" means for the fair check: line of sight over the height map.
    - What one reaction is. The design doc has a reaction per guest at the last hole and also per hole; rating averages the last 50, so the unit matters.
    - Revisit rule 4 yardage along the line of play. E2-S1 measured a straight line from tee to cup; doglegs on a nine-hole course may want the line of play.
- [ ] E3-S2 Manage nine holes. Move from one hole to a course.
  - Accept: list of up to 9 holes, numbered in build order and renumberable. Open or close each, and play any one in one click. A plot of the size set in E2-S1 with 9 holes holds 60 fps at 1x on the dev machine.
  - Test: `tests/test_hole_list.gd`. Frame time checked by hand.
  - Touches: `course/`, `scenes/`, `tests/`
- [ ] E3-S3 Give guests a golf swing. Same shot model as the player, with skill as noise.
  - Accept: a guest picks a legal club, aims and plays out a hole with no scene. Skill 10 scores near par on `courses/example_par3.json`, and skill 1 clearly worse. The off-screen shortcut, which skips the flight and jumps to the landing, gives the same result as the full flight for the same seed.
  - Test: `tests/test_guest_shot.gd`
  - Touches: `guests/`, `golf/`, `tests/`
- [ ] E3-S4 Run guests on a timer. Spawn them and move them through the course once per simulated second.
  - Accept: each guest has skill, patience and taste, and holds a state: walking, waiting, playing, done. The sim advances once per simulated second, never per frame, three steps per real second at 3x. Guests play open holes in number order, walk cart paths when present and straight lines otherwise, and wait behind a slower group. The same seed gives the same day.
  - Test: `tests/test_guest_brain.gd`
  - Touches: `guests/`, `tests/`
- [ ] E3-S5 Show guests on the course. Make the simulation visible.
  - Accept: run `/art-spec golfer` and use the placeholder sheet: 24 px, 8 directions, idle, walk and swing. Guests Y-sort correctly with trees, the ball and hills. On-screen guests show their ball flight; off-screen ones do not.
  - Test: by hand with a screenshot of a guest behind a tree and on a hill.
  - Touches: `art/`, `scenes/`
- [ ] E3-S6 Score the four checks. Turn behavior into a verdict.
  - Accept: fair, interesting, pace and challenge each evaluated per hole, per the definitions from E3-S1. Fail 2 gives a complaint naming the hole; pass 4 gives praise. Taste adjusts the result as E3-S1 specified. Thresholds live in a resource.
  - Test: `tests/test_reactions.gd`, a pass and a fail case for each check, plus the blind tee shot and risk-reward par 5 from the design doc.
  - Touches: `guests/`, `tests/`
- [ ] E3-S7 Build the feed and the map tags. Close the loop back to the builder.
  - Accept: complaints and praise scroll in a HUD feed and tag the hole on the map. Clicking one jumps to the hole in Build. The feed is readable with several guests finishing at once.
  - Test: `tests/test_feed.gd` for ordering and hole links. Screenshot.
  - Touches: `scenes/`, `guests/`, `tests/`
- [ ] E3-S8 Tune reactions against a field. Close the "too few or too many checks" question.
  - Accept: `scripts/sim.gd --table reactions` plays a field of 50 guests. `/balance reactions` reaches 60 to 75% praise and under 15% complaints on a fair par 4. A blind hole clearly scores worse. A `/decision` answers whether four checks is right. `/playtest` smoke now requires one guest reaction.
  - Test: sim output recorded in the balance commit. `/playtest full` checklist item 3.
  - Touches: `guests/`, `scripts/`, `docs/`
  - Settles: design doc open question "Guest readability".

## E4: Economy — planned

Ships as 0.4.0. Gives building a budget and reactions a consequence. Serves pillar 3, and stays deliberately thin: one input, one output.

Done when: a player starts with $5,000, funds the course from green fees, and can save, quit and pick up where they left off.

- [ ] E4-S1 Reconcile the economy on paper. The stated budgets do not fit the cost table.
  - Accept: each item below has a line in `docs/design.md`, and a `/decision` where it is a real choice.
  - Test: `scripts/sim.gd --table economy` runs and prints measured values against the target.
  - Touches: `docs/`, `scripts/`
  - Settles:
    - Hole costs. The design doc says a basic par 3 is about $1,500 and a par 5 with hazards about $6,000. At the table's rates, a 5x5 green and 2x2 tee alone are $3,320. A 400-yard fairway 6 tiles wide is $19,200. Either tile costs, tile scale or hole budgets must move.
    - Whether raising and lowering terrain costs money, and what features cost.
    - Refunds when a tile is repainted or an edit undone.
    - Arrivals per day by rating.
    - Arrivals curve for fees between free and the ceiling, since only "at the ceiling" is defined.
    - Rating points per reaction type, and the starting rating before 50 reactions exist.
- [ ] E4-S2 Charge for building. Money flows out through the builder.
  - Accept: starting balance of $5,000. Painting and placing deduct at table rates, and undo follows the refund rule. Negative balance pauses building and never ends the game. The sandbox unlimited-money toggle works. Balance always visible on the HUD. Rates live in `data/`.
  - Test: `tests/test_economy_build.gd`
  - Touches: `course/`, `data/`, `tests/`
- [ ] E4-S3 Run the clock. Day clock and speed controls.
  - Accept: one day is 3 real minutes at 1x. Pause, 1x, 3x and skip to morning all work and are visible on the HUD. Skip to morning gives the same end-of-day state as running the day at the same seed.
  - Test: `tests/test_day_clock.gd`
  - Touches: `guests/`, `scenes/`, `tests/`
- [ ] E4-S4 Collect fees and pay upkeep. Money flows in.
  - Accept: a guest pays at the first tee. Upkeep is $5 per open hole per day, charged at day end. Daily income and costs are shown at morning. `/playtest` smoke now runs to its full bar: holed out, guest reaction, money changed.
  - Test: `tests/test_economy_day.gd`
  - Touches: `guests/`, `scenes/`, `tests/`
- [ ] E4-S5 Compute the rating. Reactions roll up to stars.
  - Accept: rolling average of the last 50 reactions, 1 to 5 stars, shown on the HUD. Daily arrivals scale with rating, replacing E3's flat number.
  - Test: `tests/test_rating.gd`, including fewer than 50 reactions, exactly 50, and the 51st pushing out the oldest.
  - Touches: `guests/`, `scenes/`, `tests/`
- [ ] E4-S6 Add the fee slider. The player's one pricing decision.
  - Accept: ceiling is $10 per star per round and the slider cannot exceed it. A fee at the ceiling cuts arrivals by a third. A falling rating that drops the ceiling below the current fee lowers the fee.
  - Test: `tests/test_fee.gd`. By hand: checklist item 7.
  - Touches: `guests/`, `scenes/`, `tests/`
- [ ] E4-S7 Save and load. Nothing lost across a quit.
  - Accept: the course plus money, day, rating history and guest feed serialize to JSON in `user://`. Only `course/` save code writes CourseData on load. Save, quit, load restores all of it. In-progress guests are not in the design doc's save data, so a load resumes at the morning of the saved day. A corrupt file shows an error and leaves the current game alone.
  - Test: `tests/test_save.gd`. By hand: checklist item 8.
  - Touches: `course/`, `scenes/`, `tests/`
- [ ] E4-S8 Tune the economy and run the whole checklist. Close the milestone on the pacing target.
  - Accept: `/balance economy` reaches 9 holes and 3 stars in 25 to 35 in-game days at one hole per 2 days, without going negative. A `/playtest full` session covers all 8 checklist items.
  - Test: sim output in the balance commit. Findings in `docs/playtests/`.
  - Touches: `data/`, `docs/`

## E5: Polish and share — planned

Ships as 0.5.0, the MVP. Pillar 4: finish it. Art is the largest single cost, so it gets its decision first.

Done when: 10 people outside the project have played a build with final art and sound, and swapped a course file.

- [ ] E5-S1 Choose the art pipeline. Decide before any final pixel is drawn.
  - Accept: a `/decision` on hand-drawn versus Aseprite with a generated terrain base, with a time estimate from one drawn surface and one riser. Every sheet to be produced is listed with an `/art-spec` file, including the E2 markers drawn in code: the pin, aim line, landing marker and swing bar.
  - Test: one final-quality tile in the game, screenshot beside the placeholders.
  - Touches: `art/`, `docs/`
  - Settles: design doc open question "Art pipeline".
- [ ] E5-S2 Replace terrain art. Final surfaces and risers.
  - Accept: 8 surfaces, risers and the E1-S10 edge cue (no ramp tiles, D5), all from the palette, each with its pattern. Surfaces stay distinguishable in a grayscale screenshot. No placeholder terrain remains.
  - Test: screenshots in color and grayscale at all three zooms.
  - Touches: `art/`
- [ ] E5-S3 Replace sprites and decor. Final golfer, ball, trees and decor that does nothing to the ball.
  - Accept: golfer sheet to spec (24 px, 8 directions, three animations), ball and shadow, trees, tee markers and cup. Benches, flags and signs are placeable through the builder and ignored by the ball and validator. No placeholder sprites remain.
  - Test: `tests/test_decor.gd` shows decor has no effect on a seeded shot. Screenshot.
  - Touches: `art/`, `course/`, `tests/`
- [ ] E5-S4 Add audio. Sound that serves readability.
  - Accept: one ambient bed, a shot sound per surface, short stings for praise and complaint, one music loop that drops out during a swing. All audio assets are original or have a recorded license. Volume settings exist.
  - Test: by hand with `/playtest full`. Run headless with no audio errors.
  - Touches: `audio/`, `scenes/`
- [ ] E5-S5 Export and import courses. A course is one JSON file friends can swap.
  - Accept: export and import from a main menu. Files carry name, author and thumbnail, and show par and yardage, derived from the holes because format version 1 has no fields for them. An import runs the validator, closes failing holes, and refuses a malformed file or a newer version with a clear message. An exported course imports identically on a second machine.
  - Test: `tests/test_course_export.gd`, including malformed and wrong-version files.
  - Touches: `course/`, `scenes/`, `tests/`
- [ ] E5-S6 Finish keyboard and accessibility. Every action reachable without a mouse.
  - Accept: all Build and Play actions and menus work by keyboard, with visible focus. Swing speed setting and patterns are confirmed from a full round played keyboard-only.
  - Test: by hand, one hole built and played with the mouse unplugged.
  - Touches: `scenes/`
- [ ] E5-S7 Cut the playtest build. Something strangers can run.
  - Accept: `/ship-it` produces Linux and Windows builds with an example course and a one-page how-to-play. Trademark check on "Prestwick" done by a person before any public post, as the design doc requires. Fresh-machine install works on each OS.
  - Test: launch each build on a machine without Godot.
  - Touches: `docs/`, `courses/`
- [ ] E5-S8 Run 10 playtesters. Close the MVP on outside evidence.
  - Accept: 10 people outside the project complete the checklist, with notes in `docs/playtests/`. At least two swap a course file. Bugs are filed here, pillar-level feel problems go to the icebox, balance goes to `/balance`. Recruiting them is a person's job, not an agent's.
  - Test: 10 session notes. No open crash bugs before the final `/ship-it`.
  - Touches: `docs/`

## Icebox

Things worth doing that are out of the MVP. Promote only through `/decision`, which must say what it delays to pay for them. Feel problems from playtests go at the top with the pillar named.

- Campaign plots and goals
- Unlocks by rating
- Tournament mode
- Second plot
- Weather, including wind. Wind was cut at E2 planning (user, 2026-11-03; E2-S1 records the /decision). If promoted, the smallest version is one fixed vector per hole that shifts the aim marker and shows on the Play toolbar. Pillar 4.
- Staff
- Clubhouse
- Camera rotation
- Online course sharing
- Multiplayer
- Mobile
- One-click power-then-release swing. The A/B prototype from the original E2-S9 was dropped at E2 planning. Promote it through `/decision` only if the E2-S9 playtest finds that the three-click bar, at its speed setting, fails checklist item 2. Pillar 2.
- OB stakes as placed boundary objects, beyond painted `oob` ground. Needs a new CourseData field and course format version 2 with a `save.gd` migration. Pillar 4.
