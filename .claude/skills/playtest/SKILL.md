---
name: playtest
description: Run a scripted playtest of Prestwick with simulated input, record what happened, and file findings as backlog stories. Use after a visual or feel story, before shipping, or when the user says "playtest".
---

# Playtest

Two modes. Pick by argument: `smoke` (default) or `full`.

## Smoke

Headless run of `scripts/playtest.gd`: load `courses/example_par3.json`, play one hole with a scripted swing, spawn one guest, run one in-game day. Pass if the ball holes out, the guest leaves a reaction, and the day ends with money changed. Takes under a minute. Used by `/ship-it`.

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
