---
name: balance
description: Tune a numeric table in Prestwick (clubs, surfaces, lies, reactions, economy) against the targets in docs/design.md using the headless simulator. Use when something feels off numerically or the user says "balance <table>".
---

# Balance

Argument: the table to tune. One of `clubs`, `surfaces`, `lies`, `reactions`, `economy`.

## Targets (from docs/design.md)

- clubs: driver carries 230 to 260 yd at 100% for a skill-10 golfer; each iron steps 10 to 12 yd; putter never leaves the green.
- surfaces: rough costs 10 to 20% distance; a bunker shot with SW at 50% lands 20 to 40 yd.
- lies: a 2-step uphill lie loses about one club; a sidehill lie curves 5 to 10 yd over 150 yd.
- reactions: a fair par 4 played by a field of 50 guests, skills 1 to 10, gets 60 to 75% praise and under 15% complaints.
- economy: a player who builds one hole per 2 days reaches 9 holes and 3 stars in 25 to 35 in-game days without going negative.

## Steps

1. Read the table's resource (`golf/clubs.tres`, `course/surfaces.tres`, `guests/reactions.tres`, `data/economy.json`).
2. Run `scripts/sim.gd --table <name> --runs 200`. It prints the measured values next to the targets.
3. Propose the smallest change that moves the measured value into range. One or two numbers, not a rewrite.
4. Apply, rerun, show before and after in a short table.
5. Update the matching line in `docs/design.md` if the target itself changed, and say why.
6. Commit: `balance: <table> <what moved>`.

## Rules

- Never tune by changing logic. If the simulator cannot hit the target with numbers alone, the logic is wrong; file a story.
- Keep the seed fixed across runs so differences are real.
