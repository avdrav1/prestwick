---
name: balance
description: Tune a numeric table in Prestwick (clubs, surfaces, lies, reactions, economy) against the targets in docs/design.md using the headless simulator. Use when something feels off numerically or the user says "balance <table>".
---

# Balance

Argument: the table to tune. One of `clubs`, `surfaces`, `lies`, `land`, `reactions`, `putting`, `economy`.

## Targets

The targets live in `docs/design.md` Balance targets, the one source of truth (D18). Read that section before tuning; do not copy its lines here. Each table's numbers live in one resource:

- clubs: `golf/clubs.tres`
- lies: `golf/lies.tres`
- surfaces: `course/surfaces.tres`
- land: `data/land.json` (parcel prices and the land budget, D28; E6-S8)
- reactions: `data/guests.json` (E3; the pace, challenge and verdict numbers, the queue's `play_clear_yd`, `play_clear_share`, `cross_clear_yd` and `cross_hold_max_s`, E3-S22)
- putting: `golf/clubs.tres` (the putter's range and `putt_bar_curve`), `golf/swing_tuning.tres` (`putt_aim_past_yd`), `golf/ball_params.tres` (`cup_radius`, `cup_capture_speed`) (E3-S51, D49). A change here also reruns `reactions` (guests putt with the same bar)
- economy: `data/economy.json` (E4)

## Steps

1. Read the table's targets in `docs/design.md` Balance targets and its resource from the list above.
2. Run `godot --headless --path . -s res://scripts/sim.gd -- --table <name> --runs 200 --seed 1` (tables built so far: clubs, lies, surfaces, land, reactions, putting; for land, `--runs` is the number of generated seeds; for reactions it is the field, read at `--runs 50`, and the run takes about five minutes: E3-S24 added the scoring-at-the-edges rows, and E3-S22 the pace-across-hole-shapes rows, read on 150 records and ten nine-hole days whatever `--runs` is). It prints the measured values next to the targets and exits 1 on a miss.
3. Propose the smallest change that moves the measured value into range. One or two numbers, not a rewrite.
4. Apply, rerun, show before and after in a short table.
5. Update the matching line in `docs/design.md` if the target itself changed, and say why.
6. Commit: `balance: <table> <what moved>`.

## Rules

- Never tune by changing logic. If the simulator cannot hit the target with numbers alone, the logic is wrong; file a story.
- Keep the seed fixed across runs so differences are real.
