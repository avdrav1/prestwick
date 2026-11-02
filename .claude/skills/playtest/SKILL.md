---
name: playtest
description: Run a scripted playtest of Prestwick with simulated input, record what happened, and file findings as backlog stories. Use after a visual or feel story, before shipping, or when the user says "playtest".
---

# Playtest

Two modes. Pick by argument: `smoke` (default) or `full`.

## Smoke

Run `bash scripts/playtest.sh`. It drives the real main scene headless at a fixed 60 fps with `scripts/playtest.gd`, prints one `ok` or `FAIL` line per check, and exits 0 only when every check passes and Godot printed no error or warning. Expected values (the course it must load, where the debug shot lands and rests) come from `data/playtest_smoke.json`, copied from `docs/design.md`, so a fallback course or a physics change fails it. Takes a few seconds. Used by `/ship-it`.

The smoke asserts only what the milestones shipped so far have built, so it can pass at every milestone. Each stage is added by the epic that builds it, which also raises `BUILT_MILESTONE` in `scripts/playtest.gd`:

| Milestone | Stage | Pass if |
| --- | --- | --- |
| E1 Ball on a tile (built) | switch to Play, fire the debug shot | the ball lands on the course, on the ground, on the predicted tile, and comes to rest on the course on the predicted tile |
| E2 One hole | load `courses/example_par3.json`, play the hole with a scripted swing | the ball holes out |
| E3 Nine holes and guests | spawn one guest | the guest leaves a reaction |
| E4 Economy | run one in-game day | the day ends with money changed |

The full bar (holed out, guest reaction, money changed) is the E4 smoke. Before E4 a passing smoke means every stage built so far passed, not that the full bar did.

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
