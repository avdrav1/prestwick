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

## E1: Ball on a tile — active

Ships as 0.1.0. Retires the biggest risk: the isometric projection and the height map fighting each other in the physics.

Done when: you can paint hills, fire a debug shot over them, and the ball lands where the math said it would.

- [x] E1-S1 Stand up the project skeleton. Get a repo, a main scene with Build and Play states, and green checks.
  - Accept: `git init` done with a first commit, since `/next-story` commits and this folder is not yet a repo. Pick the engine version and record it with `/decision`: the repo says 4.3 and `scripts/install_godot.sh` pins it, but `godot` on this machine is 4.7.2. GUT is pinned to a release that runs on that version and installed in `addons/gut`. `scenes/main.tscn` exists (`project.godot` already points at it) and a key toggles Build and Play with no scene load. `.gitignore` is reviewed: it currently ignores `*.import`, which loses per-asset import settings on a fresh clone.
  - Test: `scripts/run_tests.sh` exits 0 with one real test in `tests/test_main_states.gd`. It exits 3 without GUT, so GUT is part of this story.
  - Touches: `scenes/`, `scripts/`, `tests/`
- [ ] E1-S2 Build the CourseData resource. Give every system one source of truth.
  - Accept: a 2D tile array (height 0 to 7, surface enum), a holes list, and `to_dict` / `from_dict` in course format version 1 from `/course-file`, including the base64 `tiles` packing and `oob` as surface 8. A 20x20 course round-trips through JSON with no loss. Out-of-range heights are rejected on load.
  - Test: `tests/test_course_data.gd`
  - Touches: `course/`, `tests/`
- [ ] E1-S3 Build the placeholder art and screenshot tools. `/art-spec` and `/next-story` both call tools that do not exist yet.
  - Accept: `art/palette.gpl` (about 32 colors), `scripts/placeholder.py`, `scripts/screenshot.sh <scene>`, and specs plus placeholders for surfaces and risers. Each surface has its colorblind pattern from day one. `screenshot.sh` writes a real PNG: Godot's `--headless` mode has a dummy renderer and draws no pixels, so it needs a display (`xvfb-run` is not installed on this machine).
  - Test: by hand. Run the screenshot script on a test scene and open the PNG.
  - Touches: `art/`, `scripts/`
- [ ] E1-S4 Render the course isometrically. Draw any CourseData with heights correct and a usable camera.
  - Accept: TileMapLayer draws surfaces, risers per height step, Y-sort on. A 20x20 course with heights 0 to 7 has no overlap artifacts at 0.5x, 1x and 2x. Pan with middle mouse or WASD. Tile-to-screen and screen-to-tile projection live in one shared helper.
  - Test: `tests/test_iso_projection.gd` round-trips tile to screen to tile at every height. Screenshot at each zoom.
  - Touches: `course/`, `scenes/`, `tests/`
- [ ] E1-S5 Paint terrain. Let the player shape land through the builder, the only writer.
  - Accept: surface palette for the 8 surfaces, raise and lower, brush 1/3/5, undo stack. The tile under the cursor is picked correctly on raised ground, including a tile partly hidden by a nearer hill. 50 edits then 50 undos restore the original CourseData hash. Heights clamp at 0 and 7.
  - Test: `tests/test_builder.gd`
  - Touches: `course/`, `scenes/`, `tests/`
- [ ] E1-S6 Step the ball over the height map. Custom 3D physics at 60 Hz, no scene needed, so guests can reuse it.
  - Accept: gravity, one bounce by surface, roll downhill with surface friction read from a resource, height interpolated between tiles. A flying ball that meets a hillside lands there. Randomness comes from a seeded generator owned by the ball, never the global one. The same seed and inputs give the identical landing position 100 of 100 runs, not just the same tile.
  - Test: `tests/test_ball.gd`
  - Touches: `golf/`, `tests/`
  - Settles: yards per height step, gravity and bounce values (none are in `docs/design.md` yet; add them there).
- [ ] E1-S7 Fire a debug shot. See the physics on the projected map.
  - Accept: a button fires the ball at fixed power and angle. The sprite follows the projected path and a ground shadow shows its height. The ball lands on the predicted tile, within 1 tile, on flat and sloped terrain. The prediction comes from running the same step function ahead of time.
  - Test: `tests/test_shot_prediction.gd` covers flat and sloped courses. Screenshot mid-flight.
  - Touches: `golf/`, `scenes/`, `tests/`
- [ ] E1-S8 Make `/ship-it` runnable. Its smoke test and export setup do not exist yet.
  - Accept: `scripts/playtest.gd` runs headless and asserts only what the current milestone has built. For E1 that is firing a shot and landing it. `/playtest` smoke is updated to say so: its full bar (holed out, guest reaction, money changed) cannot pass before E4, yet `/ship-it` requires it at every milestone. `docs/export.md` and `export_presets.cfg` exist for Linux and Windows.
  - Test: run smoke headless. Export a Linux build and launch it. Export templates must be installed first.
  - Touches: `scripts/`, `docs/`
- [ ] E1-S9 Decide grid size and height model. Close the two open questions the design doc assigns to this milestone.
  - Accept: paint a 3-step green contour and a hillside, fire shots across them, take screenshots, then record two `/decision` entries. They answer whether 5 yards per tile is too coarse for green contours and whether sub-step ramps are needed. The design doc already assumes ramp tiles, so the decision states what "ramp" means. If either answer changes the data model, file a story here before closing the epic.
  - Test: screenshots attached to the decisions in `docs/DECISIONS.md`. `/godot-check` green.
  - Touches: `docs/`
  - Settles: design doc open questions "Grid size" and "Height model".

## E2: One hole — planned

Ships as 0.2.0. Serves pillars 1 and 2: one click from the tee, honest shots.

Done when: you can design a single hole, stand on its tee in one click, play it to the cup, and read your score.

- [ ] E2-S1 Settle the numbers One Hole needs. Stories below cannot be built from `docs/design.md` as it stands.
  - Accept: each item below has a `/decision` where it is a real choice and a line in `docs/design.md`.
  - Test: none. Review the design.md diff.
  - Touches: `docs/`
  - Settles:
    - Wind. The design doc has it shifting the aim marker and on the Play toolbar, `docs/design.md` has no wind, and weather is out of the MVP. Keep or cut, and if kept, how it is rolled and how strong. Recommended: keep the smallest version, one fixed vector per hole, so the marker shift stays readable.
    - Out of bounds. `/course-file` has an `oob` surface, the design doc has stakes as a feature, and `docs/design.md` says 8 surfaces. Pick one, with a cost.
    - Plot size. Examples use 20x20 and 40x40, but a par 5 is over 94 tiles long and 9 holes must fit.
    - Landing zone, which validator rule 5 uses and nothing defines.
    - Yardage measure for rule 4. A straight line penalizes doglegs; decide whether to measure along the line of play.
    - Starting surface of a blank plot, and whether it costs anything.
    - Accuracy zone width, shank result, overswing penalty above 100%.
    - Cup capture radius and speed.
    - Club table, plus the `/balance` targets. The skill credits them to `docs/design.md`, but they are not there.
- [ ] E2-S2 Place a tee and a cup. Make a hole exist on the map.
  - Accept: tee marker and cup tools create a hole in CourseData through the builder, with par chosen by the player. Markers render at height and undo with the rest of the stack.
  - Test: `tests/test_builder_holes.gd`
  - Touches: `course/`, `scenes/`, `tests/`
- [ ] E2-S3 Validate a hole. Write the five rules once, for the game and `/course-file` alike.
  - Accept: all five rules from `docs/design.md`, each returning the offending tile. Par boundaries tested at exactly 250 and 470 yards. `/course-file validate` and `generate` work, and `courses/example_par3.json` passes.
  - Test: `tests/test_validator.gd`, at least one pass and one fail per rule.
  - Touches: `course/`, `courses/`, `tests/`
- [ ] E2-S4 Show validation on the map and open the hole. Tell the builder what is wrong, where.
  - Accept: the failing rule is highlighted on its tile with a one-line reason. Open is only enabled when all rules pass. A terrain edit under an open hole closes it until it revalidates. Play stays available as soon as a tee and cup exist, even when the hole fails validation: pillar 1 outranks the validator, which only gates opening to guests.
  - Test: `tests/test_hole_open.gd`. By hand: checklist item 1.
  - Touches: `course/`, `scenes/`, `tests/`
- [ ] E2-S5 Add clubs and lies. Make distance depend on club, surface and slope.
  - Accept: all 12 clubs in a resource with carry, launch angle and roll factor. Driver only from tee, putter only on green, sand wedge only from bunker. Lie multipliers per `docs/design.md`. Uphill shortens carry, sidehill adds curve. A minimal `scripts/sim.gd --table clubs` works and `/balance clubs` and `/balance lies` hit their targets.
  - Test: `tests/test_clubs.gd`, `tests/test_lies.gd`
  - Touches: `golf/`, `scripts/`, `tests/`
- [ ] E2-S6 Teach the ball every surface. Hazards behave as the table says.
  - Accept: water and OB cost one stroke and drop at the last entry point. Trees stop flight and scatter 1 to 2 tiles, deterministic by seed. Bunker stops the ball. Cart path bounces hard and rolls at 1.6. Wind applies if E2-S1 kept it. A ball can never come to rest on water, OB or inside trees.
  - Test: `tests/test_ball_surfaces.gd`, one case per surface.
  - Touches: `golf/`, `tests/`
- [ ] E2-S7 Swing the club. Three clicks and an aim line that tells the truth.
  - Accept: bar fills in 1.2 s and runs to 110%. Each 10% off center gives 2 degrees of hook or slice. Outside the zone shanks. Bar speed is adjustable (accessibility). A dotted line and landing marker show the carry for the selected club, rotated by mouse or keys. The swing logic runs without a scene.
  - Test: `tests/test_swing.gd`. Screenshot of aim line and bar.
  - Touches: `golf/`, `scenes/`, `tests/`
- [ ] E2-S8 Play the hole end to end. Connect build, swing, ball and score.
  - Accept: one click from Build puts you on the tee of the hole you just shaped, with no scene load. Camera centers on the ball, zooms in three steps, pans to scout and snaps back with one key. Play continues until the ball is holed. Scorecard shows par, strokes including penalties, and total to par. One click returns to Build with the course unchanged.
  - Test: `tests/test_round_flow.gd` plays a scripted hole through to a score. `/playtest` smoke now requires holing out on `courses/example_par3.json`.
  - Touches: `golf/`, `scenes/`, `tests/`
- [ ] E2-S9 Test the swing and the loop. Close the swing question and the "fun to build, boring to play" risk.
  - Accept: a one-click power-then-release swing prototyped behind a setting. A `/playtest full` session on checklist items 1 and 2 compares both. A `/decision` keeps one and removes the other's code. Checklist items 4 and 5 need the economy, so they wait for E4.
  - Test: findings in `docs/playtests/`. `/godot-check` green with the survivor.
  - Touches: `golf/`, `docs/`
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
  - Accept: a `/decision` on hand-drawn versus Aseprite with a generated terrain base, with a time estimate from one drawn surface and one riser. Every sheet to be produced is listed with an `/art-spec` file.
  - Test: one final-quality tile in the game, screenshot beside the placeholders.
  - Touches: `art/`, `docs/`
  - Settles: design doc open question "Art pipeline".
- [ ] E5-S2 Replace terrain art. Final surfaces and risers.
  - Accept: 8 surfaces, risers and whatever ramps E1-S9 kept, all from the palette, each with its pattern. Surfaces stay distinguishable in a grayscale screenshot. No placeholder terrain remains.
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
- Weather
- Staff
- Clubhouse
- Camera rotation
- Online course sharing
- Multiplayer
- Mobile
