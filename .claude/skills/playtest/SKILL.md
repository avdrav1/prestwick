---
name: playtest
description: Run a scripted playtest of Prestwick with simulated input, record what happened, and file findings as backlog stories. Use after a visual or feel story, before shipping, or when the user says "playtest".
---

# Playtest

Two modes. Pick by argument: `smoke` (default) or `full`.

## Smoke

Run `bash scripts/playtest.sh`. It drives the real main scene headless at a fixed 60 fps with `scripts/playtest.gd`, prints one `ok` or `FAIL` line per check, and exits 0 only when every check passes and Godot printed no error or warning. Expected values (the course it must load, where the debug shot lands and rests) come from `data/playtest_smoke.json`, copied from `docs/design.md`, so a fallback course or a physics change fails it. Takes a few seconds. Used by `/ship-it`.

Windowed step (E3-S32): when a display is available, also run `godot --path . -s res://scripts/shirt_render_check.gd`. It opens a window, renders the idle golfer in every shirt through the real shader and exits 0 only when every pixel matches the sheet with its key swapped (the GUT tests run headless, where nothing is drawn, so `run_tests.sh` cannot check the shader's output). With no display, say it was skipped.

The smoke asserts only what the milestones shipped so far have built, so it can pass at every milestone. Each stage is added by the epic that builds it, which also raises `BUILT_MILESTONE` in `scripts/playtest.gd`:

| Milestone | Stage | Pass if |
| --- | --- | --- |
| E1 Ball on a tile (built) | switch to Play, fire the debug shot | the ball lands on the course, on the ground, on the predicted tile, and comes to rest on the course on the predicted tile |
| E2 One hole | load `courses/example_par3.json`, play the hole with a scripted swing | the ball holes out |
| E3 Nine holes and guests (built) | Play on `courses/example_par3.json` at 3x until the first guest finishes hole 1 | a guest arrives, leaves a reaction naming hole 1 within 60 simulated s, and a headless GuestBrain of the same day seed gives the same reaction at the same second |
| E4 Economy (built) | give the E3 course a $5,000 balance before Play, then Morning (skip the rest of day 1) | the day ends with money changed, by exactly its fees less its upkeep, and the morning report shows |

The full bar (holed out, guest reaction, money changed) is the E4 smoke, built in E4-S4: a passing smoke now means the full bar passed.

## Scripted sessions

A scripted session drives the real main scene through one milestone's player flow and prints what happened; Claude writes the findings to `docs/playtests/` by hand. `scripts/land_playtest.gd` (E6-S8) starts a New course, buys two parcels with Buy land, builds a par 4 across them, plays it with the scripted player and sweeps the tee for D29's OB reading: `godot --headless --path . --fixed-fps 60 -s res://scripts/land_playtest.gd -- --seed 1`. It exits 0 only when every check passes. It is not part of the smoke.

`scripts/e4_playtest.gd` (E4-S8) runs the scripted parts of the eight Full checklist items on the real main scene (a par 3 built and played on a New course, guests on it, a par 5 with water priced, two days at 3x on the playtest nine, the fee at the ceiling, save, quit and load into a fresh scene): `scripts/e4_playtest.sh --seed 1` (it gives the run a throwaway user:// folder; never run the .gd directly, its save and load would overwrite the player's own `save.json`). It exits 0 only when every check passes; what it cannot judge stays with the user (`docs/playtests/2026-11-09-e4-full.md` has the hand checklist).

## Full

A guided session with the user at the keyboard. Claude drives the checklist, the user plays.

1. Read `docs/playtests/checklist.md`.
2. Walk the user through each item: build a par 3, play it, open it, watch three guests, read the feed, build a par 5 with water, repeat.
3. After each item ask one question: what surprised you?
4. Record answers in `docs/playtests/<date>.md` under Observed, Felt, Broke.

## Findings

- A bug goes to the active epic as a story with `(found in playtest <date>)`.
- A feel problem that touches a pillar goes to the top of the icebox with the pillar named.
- A balance problem goes to `/balance` with the table named.

## Rules

- Do not fix anything during a full playtest. Record, then file.
- Smoke mode never writes to `docs/playtests/`.
