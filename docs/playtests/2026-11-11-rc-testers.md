# Playtester notes on the 0.6.0 release candidates (2026-11-11)

Relayed by the user. Findings and what was decided.

## Tester 1 (rc2): hole length

"Out the gate it was not clear how far a driver would go; I didn't know how long to make my first hole." Filed as E8-S5 (ruler, rings, club table, first-hole hint); shipped in rc3.

## Tester 2 (rc4): first impressions

> Overall, I'm not sure what I should be doing. The first thing I tried was going into "play hole" but I hadn't put in a cup or tee yet, so I spent a lot of time looking for where I was supposed to hit the ball. Then I tried buying land and deforming the terrain. It was a few minutes later that I noticed you could place cup and tee. I also noticed you could place clubhouse, but that just moves the clubhouse and I'm not sure what that does.
>
> Okay, so first time swinging at a hole that actually exists -- I overswing massively but five strokes later, I have a ball in the hole. I'm not really sure how my swing relates to the distance traveled in the little bar, but I think I'm supposed to stop it so that my swing is in the green part? This does not guarantee success so I don't really know what I am doing when I swing the club.
>
> Also I found the aiming controls really jumpy, especially if you're zoomed in. Small mouse movements translate to big camera movements, and they're not consistent, because some parts of the aimer will stay in the sides of your screen, and some will move it. Every mouse movement moves the whole screen around, so it's hard to steady it and actually aim where you want. There should probably be a dead zone in the middle of the screen that does not move the camera.
>
> Can I place a second hole? How do I make money?
>
> I like the terrain deformation and want to point out one decision I can't say is wrong, but is really quirky: You can paint water on the land at any height? Usually there's a water level that water automatically fills in below, or you place water and it flows. I thought it was funny I could make really tall, towering pools, so I made a bunch of them.

| Finding | Pillar | User's choice (2026-11-11) | Filed |
|---|---|---|---|
| Not sure what to do; Play with no hole; Tee/Cup found late; clubhouse purpose; second hole; making money | 1, 3 | A goal checklist on a new course, SimGolf-style early goals | E10-S1 |
| Aim camera jumpy, moves on every mouse move | 2 | Camera holds still while aiming; glides only when the marker leaves a large safe box | E10-S2 |
| Swing bar: how power maps to distance, what the green zone means | 2 | Label the bar with yards, a live distance readout, and a one-time practice hint | E10-S3 |
| Water paints at any height (towering pools) | 4 | Water finds its level: painting water floods the connected low ground to its rim | E10-S4 |

## Tester (rc6, 2026-11-12): cart path

A tester laid a cart path and still got "long walk" complaints. The rule was invisible: a walk counts as on a path only if the path starts within 25 yd of the cup, ends within 25 yd of the next tee, covers half the walk and is quicker; and complaints from before the path stayed in the tags. The user chose all four fixes (E12-S1).
