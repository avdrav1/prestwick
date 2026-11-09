# E4-S1: the economy's options on paper (2026-11-09)

E4-S1 lists seven things to settle before E4 charges anything (`docs/BACKLOG.md` E4-S1, Settles). Each one is the user's call, so this pass does not decide them. It measures them and sets out the options, with a recommendation for each. It writes no decision and changes no `data/` value. The measurements come from `scripts/sim.gd -- --table economy` (`scripts/economy_sim.gd`, `EconomySim`). The full output from `--runs 3 --seed 1 --log` is at the end.

Sources: the design doc's cost table (Course builder, Terrain) and its Management layer (Money, Rating, Guests), read from Claude Docs on 2026-11-09; `docs/design.md` (Economy and time, Land, Balance targets); D19, D28 and D46; `data/land.json` and `data/guests.json`.

SimGolf precedents are from memory and have not been checked against the game or its manual. They give the general approach only, not numbers.

## How the sim measures

- **A hole's cost.** Each fixture is built through `CourseBuilder` and compared tile by tile with the land it started on. Each changed tile costs the price of its new surface. Each step of height moved costs the step price. Painting a surface over itself costs nothing. The fixtures are `generate 3/4/5` (the par 5 with water), the par 3 with tee and green only, ReactionHoles' fair par 4 and dogleg (the dogleg's pond belongs to the land), and PlaytestNine hole by hole. On PlaytestNine each changed tile is charged to the nearest hole line, and so is the land under it.
- **The frugal nine** is the run's course: 3 basic par 3s, 4 par 4s and 2 par 5s, built from the fixtures. Its land is the Land hand calculation's footprint, 35.1 parcels less the 4 free ones. That is 31 parcels at the median generated price of $1,050. PlaytestNine spreads over the whole map and needs 53 parcels ($58,900), so it is not a fair model of a player's first nine.
- **Guests** are real `GuestBrain` days on PlaytestNine, with holes 1 to k open for each k. Capacity days run with 16 to 32 arrivals.
- **The run.** The player builds the next hole 2 days after the last one, as soon as the balance covers the hole and its land. Guests pay in the morning and react on every open hole. Upkeep of $5 per hole is charged at dusk. The rating is the mean of the last 50 reactions, shown to the half star.
- **The fit.** For each income model, the sim searches for the cost scale, applied to the tile table and parcel prices together, that opens the ninth hole nearest day 30. The search requires 3 stars by day 35 and a balance that never goes negative. Its course rates exactly 3 stars (25% praise, 50% neutral, 25% complaints).

## The gap in one paragraph

The cost table as written fails the design doc's own hole targets. The basic par 3 costs $9,440 (target about $1,500). Its tee and green alone cost $5,160. The par 5 with water costs $25,670 (target about $6,000). A frugal nine costs $157,420 to build, plus $32,550 of land. Income is limited too. The fee ceiling is $10 per star per round, and a day holds about 24 guests: on PlaytestNine every guest of a 24-guest day finishes the nine, but at 32 guests 12 of 96 are still out at dusk. So a 3-star nine earns $285 to $390 a day. To open the ninth hole near day 30, one of two things must give. Either total spend comes down to about $11,000 to $17,000 (holes and land at 0.19 to 0.29 times T4 at today's ceiling), or the fee ceiling goes up (scale 0.61 at $25 a star, about 1.0 at about $40).

## 0. What the pacing target means (asked first, because every number below depends on it)

The target is "a player who builds one hole per 2 days reaches 9 holes and 3 stars in 25 to 35 in-game days without going negative". Building every 2 days with no stall opens the ninth hole on day 17, so the target only holds if something slows the player down.

- **(a) Money paces the builder.** The player tries to build every 2 days, but some days the balance is short. The ninth hole opens between day 25 and 35. In every fitted run the player stalls for about 13 days. *Recommended:* the design doc says the economy "exists to pace the builder". SimGolf works the same way: money, not a clock, decides when the next hole goes in.
- **(b) Building never stalls,** so the nine is done by day 17 or 18. The rating then rises slowly enough that 3 stars arrives on day 25 to 35. This needs a slow rating, for example stars that move at most half a star a day, which is a new rule.
- **(c) Restate the target** in real time or in holes, as E4-S8's Note allows.

## 1. Hole costs: tile prices (Settles 1)

Measured cost of each hole under each table, with height steps included:

| Table | Par 3 basic 160 yd | Par 3 tee and green only | Par 4 380 yd | Fair par 4 with bunker | Dogleg 450 yd | Par 5 with water 520 yd | PlaytestNine hole 5 (par 5, hazards) | Frugal nine (holes only) |
|---|---|---|---|---|---|---|---|---|
| T1 doc as written (fairway 40, rough 10, green 120, tee 80, bunker 60, water 90, trees 30, cart path 20, height free) | $9,440 | $5,160 | $18,240 | $18,680 | $22,160 | $25,670 | $32,720 | $157,420 |
| T2 doc divided by 10, plus $5 a step | $944 | $516 | $1,824 | $1,868 | $2,216 | $2,702 | $3,762 | $16,012 |
| T3 fit (fairway 6, rough 2, green 20, tee 15, bunker 15, water 20, trees 8, cart path 6, OOB 2, $5 a step) | $1,517 | $875 | $2,837 | $2,915 | $3,401 | $4,262 | $5,844 | $25,143 |
| **T4 fit-green** (fairway 5, rough 2, green 25, tee 15, bunker 20, water 30, trees 10, cart path 8, OOB 2, $10 a step) | **$1,595** | **$1,060** | $2,695 | $2,705 | $3,065 | **$4,400** | **$6,171** | **$24,755** |

- **T1** fails both targets by 4 to 6 times. A 30 yd green (37 tiles) costs $4,440 on its own.
- **T2** keeps the doc's ratios. The par 3 falls just under its band, and the par 5 comes out at about 2.8 times the par 3, against the doc's 4 times.
- **T3** puts the basic par 3 at $1,517 and the par 5 at $4,262 to $5,844. A par 3 of tee and green only costs $875.
- **T4** *(recommended)* makes greens, water and bunkers the expensive tiles and fairway cheap. Both kinds of basic par 3 ($1,060 and $1,595) fall in the $1,000 to $2,000 band. A par 5 with water and bunkers costs $4,400 on flat ground and $6,171 for PlaytestNine's hole 5. It also keeps checklist item 1 ("build a par 3 under $1,500") possible with a modest fairway.

The table's shape and the money scale are separate questions. Whatever scale question 4 settles on, T4's numbers are multiplied by it. The tile scale stays at 5 yd (D4).

## 2. Raising and lowering terrain, and features (Settles 2)

PlaytestNine moves 813 height steps in all. Hole 1 alone moves 304: its green is lifted and a pond is filled.

| Price per step | PlaytestNine shaping | Hole 1 | Holes 2 to 9 |
|---|---|---|---|
| H1 free | $0 | $0 | $0 |
| H2 $5 | $4,065 | $1,520 | $80 to $605 |
| **H3 $10** (in T4) | **$8,130** | **$3,040** | $160 to $1,210 |
| H4 $20 | $16,260 | $6,080 | $320 to $2,420 |

*Recommended: H3, $10 a step, one price for raising and lowering, scaled with the money scale.* Shaping then costs about 20% of a hilly hole. It is visible but never the main cost. From memory, terraforming cost money in SimGolf.

Features:

- **F1** *(recommended)*: tee markers and cups are free. Their tiles (tee box, green) already carry the cost, and pillar 1 wants placing a hole to cost nothing extra.
- **F2**: a flat $100 when a hole is opened.
- **F3**: the tee marker and the cup each cost money, and moving one costs again.

OOB ground costs rough's price ($2 in T4), so painting a boundary is cheap.

## 3. Refunds (Settles 3)

Here is the same edit under each rule, using T4: a 400-tile fairway ($2,000) repainted as rough ($800).

| Rule | What the repaint costs | What an undo of the fairway gives back |
|---|---|---|
| **R1** pay the new surface, no refund for the old | $800 more | n/a |
| R2 refund 50% of what the old surface cost | $800 - $1,000 = $200 back | n/a |
| R3 pay the difference (new minus paid, refunded when cheaper) | $1,200 back | n/a |
| **U1** undo refunds exactly what the step charged | n/a | $2,000 |
| U2 undo refunds only on the same day | n/a | $2,000 the same day, else $0 |
| U3 undo refunds nothing | n/a | $0 |

*Recommended: R1 plus U1.* Undo is the "I clicked wrong" button, and D27 already refunds an undone parcel purchase in full. R1 needs no ledger of what each tile cost. R2 and R3 need a price per tile, which means CourseData or format changes.

With R1 plus U1 there is no money pump. An undo returns only what its own step charged. Repainting the land's natural trees or water costs the new surface only and refunds nothing, because the player never paid for them.

## 4. Land in the one balance, and parcel prices (Settles 4)

On the frugal nine at D28's prices, land is the biggest single cost: $32,550 for 31 parcels against $24,755 for the holes (T4). So land has to move with the hole prices.

| Option | Parcel (median) | Frugal nine, land plus holes | Notes |
|---|---|---|---|
| L1 one balance, D28 prices kept | $1,050 | $57,305 | Fits a 3-star course only with a ceiling of about $40 a star (see the money scale). |
| **L2 one balance, parcel prices scaled with the money scale** | $1,050 times scale (about $640 at M3's 0.61) | $57,305 times scale | One number scales the whole economy. |
| L3 L2, plus prices that rise with each parcel bought or with the rating | n/a | n/a | D28 turned this down for E6. It adds a curve to tune. |
| L4 two pots (keep the $5,000 land-only budget, plus a separate money balance) | $1,050 | n/a | Goes against D19's "one balance". |

*Recommended: L2, a single $5,000 starting balance* (the old land budget becomes the balance, not $5,000 on top of it), and parcel prices scaled with the hole prices. Leave rising prices out of the MVP. From memory, SimGolf also expanded by buying neighbouring land from one bank balance.

On the D28 Note about trees and water: set `tree_tile_price` and `water_tile_price` to what clearing them costs. Under T4 at scale 1, clearing a tree tile is a rough repaint ($2, today $1) and filling a pond tile is a rough repaint plus one step ($12, today $2). A wet parcel then pays for its own filling. With up to 102 water tiles a parcel's discount reaches about $1,200 at scale 1, so the clamp (`min_price`) would start to bind. `/balance land` should rerun with whatever is chosen.

## 5. Arrivals per day by rating (Settles 5)

Capacity, measured on PlaytestNine's nine over 3 days:

| Arrivals a day | Finish the nine | Still out at dusk | Pace fails (share of reactions) |
|---|---|---|---|
| 16 | 48 of 48 | 0 | 0.25 |
| 20 | 60 of 60 | 0 | 0.30 |
| 24 | 72 of 72 | 0 | 0.35 |
| 32 | 84 of 96 | 12 | 0.36 |

So 24 is a safe cap, and 32 breaks D46's "every group finishes before dusk".

| Option | 1 star | 3 stars | 5 stars | 9 holes at 3 stars, $10 ceiling, fee at 80%: net a day |
|---|---|---|---|---|
| A1 flat 16, as E3 (the rating moves only the fee ceiling) | 16 | 16 | 16 | $285 (fee at the ceiling, 11 paying) |
| **A2 8 + 4 a star, capped at 24** | 12 | 20 | 24 (28 capped) | $387 (18 paying) |
| A3 2 a hole times stars/3, at least 4, capped at 24 (traffic grows with the course) | 6 | 18 | 24 | $339 |
| A4 4 + 4 a star, capped at 24 | 8 | 16 | 24 | about $300 |

*Recommended: A2.* The step from 1 to 5 stars is large enough to feel, it caps where the day still finishes, and it is simple to read. A3 is closer to how SimGolf traffic grew with the course (from memory). Its problem is that a one-hole course draws only the floor of 4 guests, which would starve the first days. Pick A3 instead if guests paying a full round fee for one hole feels wrong.

## 6. Arrivals curve between free and the ceiling (Settles 6)

Every curve gives full arrivals when the fee is free and two thirds at the ceiling (the design doc's "cuts arrivals by a third").

| Curve | 25% | 50% | 70% | 85% | 100% | Best fee | Earns, against the ceiling |
|---|---|---|---|---|---|---|---|
| C1 straight line | 0.92 | 0.83 | 0.77 | 0.72 | 0.67 | the ceiling | 0.667 (no choice) |
| C2 flat to 50%, then a straight drop | 1.00 | 1.00 | 0.87 | 0.77 | 0.67 | the ceiling | 0.667 (no choice) |
| **C3 flat to 70%, then a straight drop** | 1.00 | 1.00 | 1.00 | 0.83 | 0.67 | **80%** | **0.711** (+6.7%) |
| C4 steep near the top (1 - f⁴/3) | 1.00 | 0.98 | 0.92 | 0.83 | 0.67 | 88% | 0.704 (+5.6%) |

The finding: under C1 or C2 the ceiling always earns the most, so the fee slider is not a real decision. *Recommended: C3.* The rule reads in one line ("up to 70% of the ceiling nobody minds; above it arrivals fall to two thirds"), its best fee sits inside the range, and checklist item 7's drop at the ceiling is easy to notice.

When the day is full at the cap, a lower fee brings no more guests. From memory, SimGolf's golfers grumbled about high prices in their thought bubbles. A complaint at a high fee would be a pillar 3 alternative to a curve, but it is a new reaction rule.

## 7. Rating points per reaction, and the starting rating (Settles 7)

The measured mix on PlaytestNine over 3 days:

- Holes 1 to 8 draw no praise at all. 56% to 70% of reactions are complaints and the rest are neutral.
- With all nine open, 11% of reactions are praise, 27% neutral and 62% complaints.
- Holes 1 to 8 fail the fair (sight line) check on every reaction (384 of 384). Their tee shots are blind on the generated land.

| Points (praise, neutral, complaint) | PlaytestNine's nine | One hole open | Fair course (70/27/3) |
|---|---|---|---|
| **P1 5/3/1** (equals 3 + 2 x (praise share - complaint share)) | 1.97, **2 stars** | 1.83 | 4.34, 4.5 stars |
| P2 5/4/1 (neutral counts as good) | 2.25, 2 stars | 2.25 | 4.61, 4.5 stars |
| P3 5/3/0 (complaints weigh more, clamped to 1) | 1.35, 1.5 stars | 1.25 | 4.31, 4.5 stars |
| P4 5/1/1 (praise only) | 1.43, 1.5 stars | 1.00 | 3.80, 4 stars |

*Recommended: P1.* It is symmetric, and a neutral reaction sits at 3 stars ("fine").

**Warning for E4-S5 and E4-S8:** under every rule, E3's own playtest nine rates 1.5 to 2 stars, so the 3-star target cannot be reached on it. This is not a points problem. Its tee shots are blind on generated land. E4-S8 needs a nine whose landing zones can be seen from the tees, or a look at the fair check on hilly land, before the pacing target can be read.

Starting rating:

- **S1** *(recommended)*: 3 stars, with a short window padded to 50 by neutral reactions. The rating starts at "fine" and moves as reactions arrive. It also answers E4-S5's Note: divide by the full window.
- **S2**: 1 star, padded the same way. A new course starts at the bottom and earns its way up.
- **S3**: no padding. The rating is the mean of whatever exists (3 stars when there is none), so the first few reactions swing it hard.

With the fitted economies the starting rule barely matters, because a day brings 16 to 24 reactions for each hole open and the window fills within 3 days. On a 3-star course, S2 lowers the fitted scale by 0 to 0.04 and S3 changes it by none (see the fit rows).

## The money scale: income model against cost scale (questions 4 and 5 together)

Income model against the cost scale. The scale multiplies T4 and the parcel prices together, and is the one at which the ninth hole opens near day 30, with 3 stars by day 35 and the balance never negative. In every fitted run the player stalls about 13 days for money. Prices are at the fitted scale. The 3-star course is the target course. The 4.5-star course is the reactions target's fair hole everywhere. A day's net is for 9 holes at 3 stars.

| Income model | Net a day | 3-star course: scale | 3-star course: par 3, par 5 with water, parcel | 4.5-star course: scale | 4.5-star course: par 3, par 5 with water, parcel |
|---|---|---|---|---|---|
| I1 E3's 16 a day, fee at the $10 ceiling | $285 | 0.23 | $367, $1,012, $242 | 0.31 | $494, $1,364, $326 |
| I2 A2 arrivals (8 + 4 a star), $10 ceiling, fee 80% (C3) | $387 | 0.29 | $463, $1,276, $305 | 0.47 | $750, $2,068, $494 |
| I3 A3 arrivals (by hole), $10 ceiling, fee 80% | $339 | 0.19 | $303, $836, $200 | 0.30 | $479, $1,320, $315 |
| I4 A2 arrivals, $15 ceiling, fee 80% | $603 | 0.40 | $638, $1,760, $420 | 0.67 | $1,069, $2,948, $704 |
| **I5 A2 arrivals, $25 ceiling, fee 80%** | $1,035 | **0.61** | **$973, $2,684, $641** | 1.06 | $1,691, $4,664, $1,113 |

The design doc's own figures (par 3 about $1,500, par 5 about $6,000 at scale 1) only fit a 3-star course with a ceiling of about $40 a star. That figure is extrapolated: the scale grows roughly in line with the ceiling (0.29, 0.40 and 0.61 at $10, $15 and $25), and $40 was not run.

The choice in one line:
- **M1**: keep the $10 a star ceiling and cut every price to about 0.3 times (a par 3 near $450, a par 5 near $1,300, a parcel near $300).
- **M2**: raise the ceiling to $15 a star (scale about 0.4).
- **M3**: raise the ceiling to $25 a star (scale about 0.6, a par 3 near $1,000 and a parcel near $650).
- **M4**: raise the ceiling to about $40 a star and keep the design doc's $1,500 and $6,000 as written.

*Recommended:* M3. Under M3:
- A round at 3 stars costs $60 at the ceiling, or $48 at the 80% sweet spot. That reads as a believable green fee.
- Hole prices stay within reach of the design doc's ($1,000 par 3, $2,700 to $4,000 par 5 with hazards).
- Parcels stay near D28's prices (about $650 against $1,050), so `/balance land`'s "the budget buys a par 3 and a par 4" stays roughly true. It needs a rerun at the chosen scale.
- It is one sentence of the design doc (the fee ceiling) plus one scale on the tables.

M1 keeps the fee rule but makes a basic par 3 cost less than a day's fees on a 4-star course, which takes the weight out of building. E4-S8 then tunes the exact scale between 0.6 (a 3-star course) and 1.0 (a 4.5-star course) once question 0 and the PlaytestNine rating are settled.

## Raw output

```
== /balance economy, 3 runs, seed 1
cost doc: par 3 basic (generate 3 flat dry, 160 yd) ($)     9440.000   target 1000.000 to 2000.000 MISS fairway 107, green 37, tee 9, steps 0
cost doc: par 4 (generate 4 flat dry, 380 yd) ($)          18240.000   target -                       fairway 327, green 37, tee 9, steps 0
cost doc: par 5 with water (generate 5 flat water, 520 yd) ($) 25670.000   target 4000.000 to 8000.000 MISS fairway 452, green 37, tee 9, water 27, steps 27
cost doc: par 3 tee and green only, no fairway (160 yd) ($)  5160.000   target 1000.000 to 2000.000 MISS green 37, tee 9, steps 0
cost doc: fair par 4 with cross bunker (ReactionHoles, 380 yd) ($) 18680.000   target -                       fairway 365, green 25, tee 9, bunker 6, steps 0
cost doc: dogleg par 4 round a pond (ReactionHoles, 450 yd) ($) 22160.000   target -                       fairway 461, green 25, tee 9, steps 0
cost doc: PlaytestNine hole 1, par 4, 340 yd ($)           23860.000   target -                       fairway 318, rough 79, green 49, tee 9, bunker 21, trees 83, steps 304, trees cleared 4, water filled 112; land 12 parcels $14,000
cost doc: PlaytestNine hole 2, par 3, 130 yd ($)            4980.000   target -                       green 35, tee 9, bunker 1, steps 20, trees cleared 30; land 2 parcels $2,050
cost doc: PlaytestNine hole 3, par 4, 347 yd ($)           26040.000   target -                       fairway 315, green 47, tee 9, bunker 26, water 39, trees 67, steps 121, trees cleared 11; land 8 parcels $8,200
cost doc: PlaytestNine hole 4, par 4, 327 yd ($)           18850.000   target -                       fairway 295, green 35, tee 9, bunker 16, trees 39, steps 72, trees cleared 45; land 5 parcels $5,750
cost doc: PlaytestNine hole 5, par 5, 524 yd ($)           32720.000   target 4000.000 to 8000.000 MISS fairway 583, rough 58, green 45, tee 9, bunker 15, trees 60, steps 98, trees cleared 77, water filled 78; land 8 parcels $8,900
cost doc: PlaytestNine hole 6, par 4, 447 yd ($)           24790.000   target -                       fairway 415, green 47, tee 9, bunker 19, trees 23, steps 76, trees cleared 63; land 8 parcels $8,800
cost doc: PlaytestNine hole 7, par 3, 150 yd ($)            6360.000   target -                       green 43, tee 9, bunker 8, steps 81, trees cleared 2; land 3 parcels $3,300
cost doc: PlaytestNine hole 8, par 4, 320 yd ($)           24920.000   target -                       fairway 386, green 43, tee 9, bunker 15, trees 90, steps 25, trees cleared 33; land 5 parcels $5,850
cost doc: PlaytestNine hole 9, par 3, 230 yd ($)            5230.000   target -                       rough 19, green 33, tee 9, bunker 6, steps 16, trees cleared 26; land 2 parcels $2,050
cost doc: PlaytestNine, nine holes ($)                     167750.000   target -                       its land $58,900 more (it spreads over the whole map); fairway 2312, rough 156, green 377, tee 81, bunker 127, water 39, trees 362, steps 813, trees cleared 291, water filled 190
cost doc: frugal nine, holes ($)                           157420.000   target -                       3 par 3, 4 par 4, 2 par 5 from the fixtures; land $32,550 more (31 parcels at the median $1,050)
cost doc/10: par 3 basic (generate 3 flat dry, 160 yd) ($)   944.000   target 1000.000 to 2000.000 MISS fairway 107, green 37, tee 9, steps 0
cost doc/10: par 4 (generate 4 flat dry, 380 yd) ($)        1824.000   target -                       fairway 327, green 37, tee 9, steps 0
cost doc/10: par 5 with water (generate 5 flat water, 520 yd) ($)  2702.000   target 4000.000 to 8000.000 MISS fairway 452, green 37, tee 9, water 27, steps 27
cost doc/10: par 3 tee and green only, no fairway (160 yd) ($)   516.000   target 1000.000 to 2000.000 MISS green 37, tee 9, steps 0
cost doc/10: fair par 4 with cross bunker (ReactionHoles, 380 yd) ($)  1868.000   target -                       fairway 365, green 25, tee 9, bunker 6, steps 0
cost doc/10: dogleg par 4 round a pond (ReactionHoles, 450 yd) ($)  2216.000   target -                       fairway 461, green 25, tee 9, steps 0
cost doc/10: PlaytestNine hole 1, par 4, 340 yd ($)         3906.000   target -                       fairway 318, rough 79, green 49, tee 9, bunker 21, trees 83, steps 304, trees cleared 4, water filled 112; land 12 parcels $14,000
cost doc/10: PlaytestNine hole 2, par 3, 130 yd ($)          598.000   target -                       green 35, tee 9, bunker 1, steps 20, trees cleared 30; land 2 parcels $2,050
cost doc/10: PlaytestNine hole 3, par 4, 347 yd ($)         3209.000   target -                       fairway 315, green 47, tee 9, bunker 26, water 39, trees 67, steps 121, trees cleared 11; land 8 parcels $8,200
cost doc/10: PlaytestNine hole 4, par 4, 327 yd ($)         2245.000   target -                       fairway 295, green 35, tee 9, bunker 16, trees 39, steps 72, trees cleared 45; land 5 parcels $5,750
cost doc/10: PlaytestNine hole 5, par 5, 524 yd ($)         3762.000   target 4000.000 to 8000.000 MISS fairway 583, rough 58, green 45, tee 9, bunker 15, trees 60, steps 98, trees cleared 77, water filled 78; land 8 parcels $8,900
cost doc/10: PlaytestNine hole 6, par 4, 447 yd ($)         2859.000   target -                       fairway 415, green 47, tee 9, bunker 19, trees 23, steps 76, trees cleared 63; land 8 parcels $8,800
cost doc/10: PlaytestNine hole 7, par 3, 150 yd ($)         1041.000   target -                       green 43, tee 9, bunker 8, steps 81, trees cleared 2; land 3 parcels $3,300
cost doc/10: PlaytestNine hole 8, par 4, 320 yd ($)         2617.000   target -                       fairway 386, green 43, tee 9, bunker 15, trees 90, steps 25, trees cleared 33; land 5 parcels $5,850
cost doc/10: PlaytestNine hole 9, par 3, 230 yd ($)          603.000   target -                       rough 19, green 33, tee 9, bunker 6, steps 16, trees cleared 26; land 2 parcels $2,050
cost doc/10: PlaytestNine, nine holes ($)                  20840.000   target -                       its land $58,900 more (it spreads over the whole map); fairway 2312, rough 156, green 377, tee 81, bunker 127, water 39, trees 362, steps 813, trees cleared 291, water filled 190
cost doc/10: frugal nine, holes ($)                        16012.000   target -                       3 par 3, 4 par 4, 2 par 5 from the fixtures; land $32,550 more (31 parcels at the median $1,050)
cost fit: par 3 basic (generate 3 flat dry, 160 yd) ($)     1517.000   target 1000.000 to 2000.000 ok   fairway 107, green 37, tee 9, steps 0
cost fit: par 4 (generate 4 flat dry, 380 yd) ($)           2837.000   target -                       fairway 327, green 37, tee 9, steps 0
cost fit: par 5 with water (generate 5 flat water, 520 yd) ($)  4262.000   target 4000.000 to 8000.000 ok   fairway 452, green 37, tee 9, water 27, steps 27
cost fit: par 3 tee and green only, no fairway (160 yd) ($)   875.000   target 1000.000 to 2000.000 MISS green 37, tee 9, steps 0
cost fit: fair par 4 with cross bunker (ReactionHoles, 380 yd) ($)  2915.000   target -                       fairway 365, green 25, tee 9, bunker 6, steps 0
cost fit: dogleg par 4 round a pond (ReactionHoles, 450 yd) ($)  3401.000   target -                       fairway 461, green 25, tee 9, steps 0
cost fit: PlaytestNine hole 1, par 4, 340 yd ($)            5680.000   target -                       fairway 318, rough 79, green 49, tee 9, bunker 21, trees 83, steps 304, trees cleared 4, water filled 112; land 12 parcels $14,000
cost fit: PlaytestNine hole 2, par 3, 130 yd ($)             950.000   target -                       green 35, tee 9, bunker 1, steps 20, trees cleared 30; land 2 parcels $2,050
cost fit: PlaytestNine hole 3, par 4, 347 yd ($)            5276.000   target -                       fairway 315, green 47, tee 9, bunker 26, water 39, trees 67, steps 121, trees cleared 11; land 8 parcels $8,200
cost fit: PlaytestNine hole 4, par 4, 327 yd ($)            3517.000   target -                       fairway 295, green 35, tee 9, bunker 16, trees 39, steps 72, trees cleared 45; land 5 parcels $5,750
cost fit: PlaytestNine hole 5, par 5, 524 yd ($)            5844.000   target 4000.000 to 8000.000 ok   fairway 583, rough 58, green 45, tee 9, bunker 15, trees 60, steps 98, trees cleared 77, water filled 78; land 8 parcels $8,900
cost fit: PlaytestNine hole 6, par 4, 447 yd ($)            4414.000   target -                       fairway 415, green 47, tee 9, bunker 19, trees 23, steps 76, trees cleared 63; land 8 parcels $8,800
cost fit: PlaytestNine hole 7, par 3, 150 yd ($)            1520.000   target -                       green 43, tee 9, bunker 8, steps 81, trees cleared 2; land 3 parcels $3,300
cost fit: PlaytestNine hole 8, par 4, 320 yd ($)            4381.000   target -                       fairway 386, green 43, tee 9, bunker 15, trees 90, steps 25, trees cleared 33; land 5 parcels $5,850
cost fit: PlaytestNine hole 9, par 3, 230 yd ($)            1003.000   target -                       rough 19, green 33, tee 9, bunker 6, steps 16, trees cleared 26; land 2 parcels $2,050
cost fit: PlaytestNine, nine holes ($)                     32585.000   target -                       its land $58,900 more (it spreads over the whole map); fairway 2312, rough 156, green 377, tee 81, bunker 127, water 39, trees 362, steps 813, trees cleared 291, water filled 190
cost fit: frugal nine, holes ($)                           25143.000   target -                       3 par 3, 4 par 4, 2 par 5 from the fixtures; land $32,550 more (31 parcels at the median $1,050)
cost fit-green: par 3 basic (generate 3 flat dry, 160 yd) ($)  1595.000   target 1000.000 to 2000.000 ok   fairway 107, green 37, tee 9, steps 0
cost fit-green: par 4 (generate 4 flat dry, 380 yd) ($)     2695.000   target -                       fairway 327, green 37, tee 9, steps 0
cost fit-green: par 5 with water (generate 5 flat water, 520 yd) ($)  4400.000   target 4000.000 to 8000.000 ok   fairway 452, green 37, tee 9, water 27, steps 27
cost fit-green: par 3 tee and green only, no fairway (160 yd) ($)  1060.000   target 1000.000 to 2000.000 ok   green 37, tee 9, steps 0
cost fit-green: fair par 4 with cross bunker (ReactionHoles, 380 yd) ($)  2705.000   target -                       fairway 365, green 25, tee 9, bunker 6, steps 0
cost fit-green: dogleg par 4 round a pond (ReactionHoles, 450 yd) ($)  3065.000   target -                       fairway 461, green 25, tee 9, steps 0
cost fit-green: PlaytestNine hole 1, par 4, 340 yd ($)      7398.000   target -                       fairway 318, rough 79, green 49, tee 9, bunker 21, trees 83, steps 304, trees cleared 4, water filled 112; land 12 parcels $14,000
cost fit-green: PlaytestNine hole 2, par 3, 130 yd ($)      1230.000   target -                       green 35, tee 9, bunker 1, steps 20, trees cleared 30; land 2 parcels $2,050
cost fit-green: PlaytestNine hole 3, par 4, 347 yd ($)      6455.000   target -                       fairway 315, green 47, tee 9, bunker 26, water 39, trees 67, steps 121, trees cleared 11; land 8 parcels $8,200
cost fit-green: PlaytestNine hole 4, par 4, 327 yd ($)      3915.000   target -                       fairway 295, green 35, tee 9, bunker 16, trees 39, steps 72, trees cleared 45; land 5 parcels $5,750
cost fit-green: PlaytestNine hole 5, par 5, 524 yd ($)      6171.000   target 4000.000 to 8000.000 ok   fairway 583, rough 58, green 45, tee 9, bunker 15, trees 60, steps 98, trees cleared 77, water filled 78; land 8 parcels $8,900
cost fit-green: PlaytestNine hole 6, par 4, 447 yd ($)      4755.000   target -                       fairway 415, green 47, tee 9, bunker 19, trees 23, steps 76, trees cleared 63; land 8 parcels $8,800
cost fit-green: PlaytestNine hole 7, par 3, 150 yd ($)      2180.000   target -                       green 43, tee 9, bunker 8, steps 81, trees cleared 2; land 3 parcels $3,300
cost fit-green: PlaytestNine hole 8, par 4, 320 yd ($)      4590.000   target -                       fairway 386, green 43, tee 9, bunker 15, trees 90, steps 25, trees cleared 33; land 5 parcels $5,850
cost fit-green: PlaytestNine hole 9, par 3, 230 yd ($)      1278.000   target -                       rough 19, green 33, tee 9, bunker 6, steps 16, trees cleared 26; land 2 parcels $2,050
cost fit-green: PlaytestNine, nine holes ($)               37972.000   target -                       its land $58,900 more (it spreads over the whole map); fairway 2312, rough 156, green 377, tee 81, bunker 127, water 39, trees 362, steps 813, trees cleared 291, water filled 190
cost fit-green: frugal nine, holes ($)                     24755.000   target -                       3 par 3, 4 par 4, 2 par 5 from the fixtures; land $32,550 more (31 parcels at the median $1,050)
height at $0 a step: PlaytestNine's shaping ($)                0.000   target -                       813 steps; by hole 1: $0, 2: $0, 3: $0, 4: $0, 5: $0, 6: $0, 7: $0, 8: $0, 9: $0
height at $5 a step: PlaytestNine's shaping ($)             4065.000   target -                       813 steps; by hole 1: $1520, 2: $100, 3: $605, 4: $360, 5: $490, 6: $380, 7: $405, 8: $125, 9: $80
height at $10 a step: PlaytestNine's shaping ($)            8130.000   target -                       813 steps; by hole 1: $3040, 2: $200, 3: $1210, 4: $720, 5: $980, 6: $760, 7: $810, 8: $250, 9: $160
height at $20 a step: PlaytestNine's shaping ($)           16260.000   target -                       813 steps; by hole 1: $6080, 2: $400, 3: $2420, 4: $1440, 5: $1960, 6: $1520, 7: $1620, 8: $500, 9: $320
guests: PlaytestNine holes 1 to 1 open, complaint share        0.583   target -                       3 days, 48 guests, 48 reactions: praise 0.00, neutral 0.42; fails fair 48, interesting 0, pace 13, challenge 7
guests: PlaytestNine holes 1 to 2 open, complaint share        0.562   target -                       3 days, 48 guests, 96 reactions: praise 0.00, neutral 0.44; fails fair 96, interesting 0, pace 26, challenge 13
guests: PlaytestNine holes 1 to 3 open, complaint share        0.562   target -                       3 days, 48 guests, 144 reactions: praise 0.00, neutral 0.44; fails fair 144, interesting 0, pace 38, challenge 18
guests: PlaytestNine holes 1 to 4 open, complaint share        0.615   target -                       3 days, 48 guests, 192 reactions: praise 0.00, neutral 0.39; fails fair 192, interesting 0, pace 66, challenge 31
guests: PlaytestNine holes 1 to 5 open, complaint share        0.592   target -                       3 days, 48 guests, 240 reactions: praise 0.00, neutral 0.41; fails fair 240, interesting 0, pace 69, challenge 40
guests: PlaytestNine holes 1 to 6 open, complaint share        0.587   target -                       3 days, 48 guests, 288 reactions: praise 0.00, neutral 0.41; fails fair 288, interesting 0, pace 73, challenge 53
guests: PlaytestNine holes 1 to 7 open, complaint share        0.646   target -                       3 days, 48 guests, 336 reactions: praise 0.00, neutral 0.35; fails fair 336, interesting 48, pace 74, challenge 55
guests: PlaytestNine holes 1 to 8 open, complaint share        0.698   target -                       3 days, 48 guests, 384 reactions: praise 0.00, neutral 0.30; fails fair 384, interesting 96, pace 105, challenge 57
guests: PlaytestNine holes 1 to 9 open, complaint share        0.620   target -                       3 days, 48 guests, 432 reactions: praise 0.11, neutral 0.27; fails fair 384, interesting 96, pace 106, challenge 58
capacity: 16 arrivals on PlaytestNine's nine, share finishing nine     1.000   target -                       48 guests, 0 left at dusk; praise 0.11, complaint 0.62; pace fails 0.25 of reactions
capacity: 20 arrivals on PlaytestNine's nine, share finishing nine     1.000   target -                       60 guests, 0 left at dusk; praise 0.11, complaint 0.65; pace fails 0.30 of reactions
capacity: 24 arrivals on PlaytestNine's nine, share finishing nine     1.000   target -                       72 guests, 0 left at dusk; praise 0.10, complaint 0.69; pace fails 0.35 of reactions
capacity: 32 arrivals on PlaytestNine's nine, share finishing nine     0.875   target -                       96 guests, 12 left at dusk; praise 0.09, complaint 0.69; pace fails 0.36 of reactions
rating 5/3/1: PlaytestNine's nine (stars)                      2.000   target -                       mean 1.97; a fair course (0.70/0.27/0.03) 4.34, 4.5 stars; one hole open 1.83
rating 5/4/1: PlaytestNine's nine (stars)                      2.000   target -                       mean 2.25; a fair course (0.70/0.27/0.03) 4.61, 4.5 stars; one hole open 2.25
rating 5/3/0: PlaytestNine's nine (stars)                      1.500   target -                       mean 1.35; a fair course (0.70/0.27/0.03) 4.31, 4.5 stars; one hole open 1.25
rating 5/1/1 (praise only): PlaytestNine's nine (stars)        1.500   target -                       mean 1.43; a fair course (0.70/0.27/0.03) 3.80, 4.0 stars; one hole open 1.00
fee curve linear: best fee (share of ceiling)                  1.000   target -                       arrivals at 25% 0.92, 50% 0.83, 70% 0.77, 85% 0.72, 100% 0.67; earns 0.667 of ceiling x arrivals, the ceiling 0.667
fee curve flat_to_half: best fee (share of ceiling)            1.000   target -                       arrivals at 25% 1.00, 50% 1.00, 70% 0.87, 85% 0.77, 100% 0.67; earns 0.667 of ceiling x arrivals, the ceiling 0.667
fee curve knee_70: best fee (share of ceiling)                 0.800   target -                       arrivals at 25% 1.00, 50% 1.00, 70% 1.00, 85% 0.83, 100% 0.67; earns 0.711 of ceiling x arrivals, the ceiling 0.667
fee curve steep: best fee (share of ceiling)                   0.880   target -                       arrivals at 25% 1.00, 50% 0.98, 70% 0.92, 85% 0.83, 100% 0.67; earns 0.704 of ceiling x arrivals, the ceiling 0.667
day I1 E3 traffic, fee at the $10 ceiling: 9 holes at 1 stars, net ($)    65.000   target -                       11 guests at $10.00, upkeep $45
day I1 E3 traffic, fee at the $10 ceiling: 9 holes at 3 stars, net ($)   285.000   target -                       11 guests at $30.00, upkeep $45
day I1 E3 traffic, fee at the $10 ceiling: 9 holes at 5 stars, net ($)   505.000   target -                       11 guests at $50.00, upkeep $45
run I1 E3 traffic, fee at the $10 ceiling: 3-star course at the fit-green table, day the nine opens       inf   target 25.000 to 35.000   MISS stalled 37 days for money; 3 stars day -1; lowest $325
fit I1 E3 traffic, fee at the $10 ceiling, 3-star course: cost scale on fit-green and land     0.230   target at least 0.000     ok   nine opens day 29, 3 stars day 29, stalled 12 days, lowest $394; par 3 $367, par 5 $1012, parcel $242
fit I1 E3 traffic, fee at the $10 ceiling, 4.5-star fair course: cost scale on fit-green and land     0.310   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $472; par 3 $494, par 5 $1364, parcel $326
fit I1 E3 traffic, fee at the $10 ceiling, 3-star course, start 1 star: cost scale on fit-green and land     0.230   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $317; par 3 $367, par 5 $1012, parcel $242
fit I1 E3 traffic, fee at the $10 ceiling, 3-star course, no pad: cost scale on fit-green and land     0.230   target at least 0.000     ok   nine opens day 29, 3 stars day 29, stalled 12 days, lowest $394; par 3 $367, par 5 $1012, parcel $242
day I2 by star 8 + 4 a star, $10 ceiling, fee 80%: 9 holes at 1 stars, net ($)    43.000   target -                       11 guests at $8.00, upkeep $45
day I2 by star 8 + 4 a star, $10 ceiling, fee 80%: 9 holes at 3 stars, net ($)   387.000   target -                       18 guests at $24.00, upkeep $45
day I2 by star 8 + 4 a star, $10 ceiling, fee 80%: 9 holes at 5 stars, net ($)   915.000   target -                       24 guests at $40.00, upkeep $45
run I2 by star 8 + 4 a star, $10 ceiling, fee 80%: 3-star course at the fit-green table, day the nine opens       inf   target 25.000 to 35.000   MISS stalled 37 days for money; 3 stars day -1; lowest $534
fit I2 by star 8 + 4 a star, $10 ceiling, fee 80%, 3-star course: cost scale on fit-green and land     0.290   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $442; par 3 $463, par 5 $1276, parcel $305
fit I2 by star 8 + 4 a star, $10 ceiling, fee 80%, 4.5-star fair course: cost scale on fit-green and land     0.470   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $860; par 3 $750, par 5 $2068, parcel $494
fit I2 by star 8 + 4 a star, $10 ceiling, fee 80%, 3-star course, start 1 star: cost scale on fit-green and land     0.270   target at least 0.000     ok   nine opens day 29, 3 stars day 29, stalled 12 days, lowest $388; par 3 $431, par 5 $1188, parcel $284
fit I2 by star 8 + 4 a star, $10 ceiling, fee 80%, 3-star course, no pad: cost scale on fit-green and land     0.290   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $442; par 3 $463, par 5 $1276, parcel $305
day I3 by hole 2 a hole x stars/3, $10 ceiling, fee 80%: 9 holes at 1 stars, net ($)    -5.000   target -                       5 guests at $8.00, upkeep $45
day I3 by hole 2 a hole x stars/3, $10 ceiling, fee 80%: 9 holes at 3 stars, net ($)   339.000   target -                       16 guests at $24.00, upkeep $45
day I3 by hole 2 a hole x stars/3, $10 ceiling, fee 80%: 9 holes at 5 stars, net ($)   915.000   target -                       24 guests at $40.00, upkeep $45
run I3 by hole 2 a hole x stars/3, $10 ceiling, fee 80%: 3-star course at the fit-green table, day the nine opens       inf   target 25.000 to 35.000   MISS stalled 41 days for money; 3 stars day -1; lowest $93
fit I3 by hole 2 a hole x stars/3, $10 ceiling, fee 80%, 3-star course: cost scale on fit-green and land     0.190   target at least 0.000     ok   nine opens day 29, 3 stars day 29, stalled 12 days, lowest $351; par 3 $303, par 5 $836, parcel $200
fit I3 by hole 2 a hole x stars/3, $10 ceiling, fee 80%, 4.5-star fair course: cost scale on fit-green and land     0.300   target at least 0.000     ok   nine opens day 29, 3 stars day 29, stalled 12 days, lowest $498; par 3 $479, par 5 $1320, parcel $315
fit I3 by hole 2 a hole x stars/3, $10 ceiling, fee 80%, 3-star course, start 1 star: cost scale on fit-green and land     0.190   target at least 0.000     ok   nine opens day 31, 3 stars day 31, stalled 14 days, lowest $383; par 3 $303, par 5 $836, parcel $200
fit I3 by hole 2 a hole x stars/3, $10 ceiling, fee 80%, 3-star course, no pad: cost scale on fit-green and land     0.190   target at least 0.000     ok   nine opens day 29, 3 stars day 29, stalled 12 days, lowest $383; par 3 $303, par 5 $836, parcel $200
day I4 by star 8 + 4 a star, $15 ceiling, fee 80%: 9 holes at 1 stars, net ($)    87.000   target -                       11 guests at $12.00, upkeep $45
day I4 by star 8 + 4 a star, $15 ceiling, fee 80%: 9 holes at 3 stars, net ($)   603.000   target -                       18 guests at $36.00, upkeep $45
day I4 by star 8 + 4 a star, $15 ceiling, fee 80%: 9 holes at 5 stars, net ($)  1395.000   target -                       24 guests at $60.00, upkeep $45
run I4 by star 8 + 4 a star, $15 ceiling, fee 80%: 3-star course at the fit-green table, day the nine opens       inf   target 25.000 to 35.000   MISS stalled 33 days for money; 3 stars day -1; lowest $716
fit I4 by star 8 + 4 a star, $15 ceiling, fee 80%, 3-star course: cost scale on fit-green and land     0.400   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $650; par 3 $638, par 5 $1760, parcel $420
fit I4 by star 8 + 4 a star, $15 ceiling, fee 80%, 4.5-star fair course: cost scale on fit-green and land     0.670   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $1523; par 3 $1069, par 5 $2948, parcel $704
fit I4 by star 8 + 4 a star, $15 ceiling, fee 80%, 3-star course, start 1 star: cost scale on fit-green and land     0.370   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $859; par 3 $590, par 5 $1628, parcel $389
fit I4 by star 8 + 4 a star, $15 ceiling, fee 80%, 3-star course, no pad: cost scale on fit-green and land     0.400   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $650; par 3 $638, par 5 $1760, parcel $420
day I5 by star 8 + 4 a star, $25 ceiling, fee 80%: 9 holes at 1 stars, net ($)   175.000   target -                       11 guests at $20.00, upkeep $45
day I5 by star 8 + 4 a star, $25 ceiling, fee 80%: 9 holes at 3 stars, net ($)  1035.000   target -                       18 guests at $60.00, upkeep $45
day I5 by star 8 + 4 a star, $25 ceiling, fee 80%: 9 holes at 5 stars, net ($)  2355.000   target -                       24 guests at $100.00, upkeep $45
run I5 by star 8 + 4 a star, $25 ceiling, fee 80%: 3-star course at the fit-green table, day the nine opens       inf   target 25.000 to 35.000   MISS stalled 29 days for money; 3 stars day -1; lowest $1260
fit I5 by star 8 + 4 a star, $25 ceiling, fee 80%, 3-star course: cost scale on fit-green and land     0.610   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $1475; par 3 $973, par 5 $2684, parcel $641
fit I5 by star 8 + 4 a star, $25 ceiling, fee 80%, 4.5-star fair course: cost scale on fit-green and land     1.060   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $2357; par 3 $1691, par 5 $4664, parcel $1113
fit I5 by star 8 + 4 a star, $25 ceiling, fee 80%, 3-star course, start 1 star: cost scale on fit-green and land     0.570   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $1163; par 3 $909, par 5 $2508, parcel $599
fit I5 by star 8 + 4 a star, $25 ceiling, fee 80%, 3-star course, no pad: cost scale on fit-green and land     0.610   target at least 0.000     ok   nine opens day 30, 3 stars day 30, stalled 13 days, lowest $1475; par 3 $973, par 5 $2684, parcel $641
== economy: 14 missed

-- run I2 by star 8 + 4 a star, $10 ceiling, fee 80% at scale 0.29
day  1: 1 open, 18 guests at $24.00, +$432 -$5, balance $4964, 3.0 stars built hole 1 ($463 + land $0)
day  2: 1 open, 18 guests at $24.00, +$432 -$5, balance $5391, 3.0 stars
day  3: 2 open, 18 guests at $24.00, +$432 -$10, balance $4116, 3.0 stars built hole 2 ($784 + land $913)
day  4: 2 open, 18 guests at $24.00, +$432 -$10, balance $4538, 3.0 stars
day  5: 3 open, 18 guests at $24.00, +$432 -$15, balance $3883, 3.0 stars built hole 3 ($463 + land $609)
day  6: 3 open, 18 guests at $24.00, +$432 -$15, balance $4300, 3.0 stars
day  7: 4 open, 18 guests at $24.00, +$432 -$20, balance $2712, 3.0 stars built hole 4 ($782 + land $1218)
day  8: 4 open, 18 guests at $24.00, +$432 -$20, balance $3124, 3.0 stars
day  9: 5 open, 18 guests at $24.00, +$432 -$25, balance $732, 3.0 stars built hole 5 ($1276 + land $1523)
day 10: 5 open, 18 guests at $24.00, +$432 -$25, balance $1139, 3.0 stars
day 11: 6 open, 18 guests at $24.00, +$432 -$30, balance $469, 3.0 stars built hole 6 ($463 + land $609)
day 12: 6 open, 18 guests at $24.00, +$432 -$30, balance $871, 3.0 stars
day 13: 6 open, 18 guests at $24.00, +$432 -$30, balance $1273, 3.0 stars
day 14: 6 open, 18 guests at $24.00, +$432 -$30, balance $1675, 3.0 stars
day 15: 6 open, 18 guests at $24.00, +$432 -$30, balance $2077, 3.0 stars
day 16: 6 open, 18 guests at $24.00, +$432 -$30, balance $2479, 3.0 stars
day 17: 7 open, 18 guests at $24.00, +$432 -$35, balance $464, 3.0 stars built hole 7 ($889 + land $1523)
day 18: 7 open, 18 guests at $24.00, +$432 -$35, balance $861, 3.0 stars
day 19: 7 open, 18 guests at $24.00, +$432 -$35, balance $1258, 3.0 stars
day 20: 7 open, 18 guests at $24.00, +$432 -$35, balance $1655, 3.0 stars
day 21: 7 open, 18 guests at $24.00, +$432 -$35, balance $2052, 3.0 stars
day 22: 8 open, 18 guests at $24.00, +$432 -$40, balance $442, 3.0 stars built hole 8 ($784 + land $1218)
day 23: 8 open, 18 guests at $24.00, +$432 -$40, balance $834, 3.0 stars
day 24: 8 open, 18 guests at $24.00, +$432 -$40, balance $1226, 3.0 stars
day 25: 8 open, 18 guests at $24.00, +$432 -$40, balance $1618, 3.0 stars
day 26: 8 open, 18 guests at $24.00, +$432 -$40, balance $2010, 3.0 stars
day 27: 8 open, 18 guests at $24.00, +$432 -$40, balance $2402, 3.0 stars
day 28: 8 open, 18 guests at $24.00, +$432 -$40, balance $2794, 3.0 stars
day 29: 8 open, 18 guests at $24.00, +$432 -$40, balance $3186, 3.0 stars
day 30: 9 open, 18 guests at $24.00, +$432 -$45, balance $470, 3.0 stars built hole 9 ($1276 + land $1827)
day 31: 9 open, 18 guests at $24.00, +$432 -$45, balance $857, 3.0 stars
day 32: 9 open, 18 guests at $24.00, +$432 -$45, balance $1244, 3.0 stars
day 33: 9 open, 18 guests at $24.00, +$432 -$45, balance $1631, 3.0 stars
day 34: 9 open, 18 guests at $24.00, +$432 -$45, balance $2018, 3.0 stars
day 35: 9 open, 18 guests at $24.00, +$432 -$45, balance $2405, 3.0 stars
day 36: 9 open, 18 guests at $24.00, +$432 -$45, balance $2792, 3.0 stars
day 37: 9 open, 18 guests at $24.00, +$432 -$45, balance $3179, 3.0 stars
day 38: 9 open, 18 guests at $24.00, +$432 -$45, balance $3566, 3.0 stars
day 39: 9 open, 18 guests at $24.00, +$432 -$45, balance $3953, 3.0 stars
day 40: 9 open, 18 guests at $24.00, +$432 -$45, balance $4340, 3.0 stars
day 41: 9 open, 18 guests at $24.00, +$432 -$45, balance $4727, 3.0 stars
day 42: 9 open, 18 guests at $24.00, +$432 -$45, balance $5114, 3.0 stars
day 43: 9 open, 18 guests at $24.00, +$432 -$45, balance $5501, 3.0 stars
day 44: 9 open, 18 guests at $24.00, +$432 -$45, balance $5888, 3.0 stars
day 45: 9 open, 18 guests at $24.00, +$432 -$45, balance $6275, 3.0 stars

-- run I5 by star 8 + 4 a star, $25 ceiling, fee 80% at scale 0.61
day  1: 1 open, 18 guests at $60.00, +$1080 -$5, balance $5102, 3.0 stars built hole 1 ($973 + land $0)
day  2: 1 open, 18 guests at $60.00, +$1080 -$5, balance $6177, 3.0 stars
day  3: 2 open, 18 guests at $60.00, +$1080 -$10, balance $3675, 3.0 stars built hole 2 ($1650 + land $1922)
day  4: 2 open, 18 guests at $60.00, +$1080 -$10, balance $4745, 3.0 stars
day  5: 3 open, 18 guests at $60.00, +$1080 -$15, balance $3556, 3.0 stars built hole 3 ($973 + land $1281)
day  6: 3 open, 18 guests at $60.00, +$1080 -$15, balance $4621, 3.0 stars
day  7: 4 open, 18 guests at $60.00, +$1080 -$20, balance $1475, 3.0 stars built hole 4 ($1644 + land $2562)
day  8: 4 open, 18 guests at $60.00, +$1080 -$20, balance $2535, 3.0 stars
day  9: 4 open, 18 guests at $60.00, +$1080 -$20, balance $3595, 3.0 stars
day 10: 4 open, 18 guests at $60.00, +$1080 -$20, balance $4655, 3.0 stars
day 11: 4 open, 18 guests at $60.00, +$1080 -$20, balance $5715, 3.0 stars
day 12: 4 open, 18 guests at $60.00, +$1080 -$20, balance $6775, 3.0 stars
day 13: 5 open, 18 guests at $60.00, +$1080 -$25, balance $1943, 3.0 stars built hole 5 ($2684 + land $3203)
day 14: 5 open, 18 guests at $60.00, +$1080 -$25, balance $2998, 3.0 stars
day 15: 6 open, 18 guests at $60.00, +$1080 -$30, balance $1794, 3.0 stars built hole 6 ($973 + land $1281)
day 16: 6 open, 18 guests at $60.00, +$1080 -$30, balance $2844, 3.0 stars
day 17: 6 open, 18 guests at $60.00, +$1080 -$30, balance $3894, 3.0 stars
day 18: 6 open, 18 guests at $60.00, +$1080 -$30, balance $4944, 3.0 stars
day 19: 6 open, 18 guests at $60.00, +$1080 -$30, balance $5994, 3.0 stars
day 20: 7 open, 18 guests at $60.00, +$1080 -$35, balance $1966, 3.0 stars built hole 7 ($1870 + land $3203)
day 21: 7 open, 18 guests at $60.00, +$1080 -$35, balance $3011, 3.0 stars
day 22: 7 open, 18 guests at $60.00, +$1080 -$35, balance $4056, 3.0 stars
day 23: 7 open, 18 guests at $60.00, +$1080 -$35, balance $5101, 3.0 stars
day 24: 8 open, 18 guests at $60.00, +$1080 -$40, balance $1929, 3.0 stars built hole 8 ($1650 + land $2562)
day 25: 8 open, 18 guests at $60.00, +$1080 -$40, balance $2969, 3.0 stars
day 26: 8 open, 18 guests at $60.00, +$1080 -$40, balance $4009, 3.0 stars
day 27: 8 open, 18 guests at $60.00, +$1080 -$40, balance $5049, 3.0 stars
day 28: 8 open, 18 guests at $60.00, +$1080 -$40, balance $6089, 3.0 stars
day 29: 8 open, 18 guests at $60.00, +$1080 -$40, balance $7129, 3.0 stars
day 30: 9 open, 18 guests at $60.00, +$1080 -$45, balance $1637, 3.0 stars built hole 9 ($2684 + land $3843)
day 31: 9 open, 18 guests at $60.00, +$1080 -$45, balance $2672, 3.0 stars
day 32: 9 open, 18 guests at $60.00, +$1080 -$45, balance $3707, 3.0 stars
day 33: 9 open, 18 guests at $60.00, +$1080 -$45, balance $4742, 3.0 stars
day 34: 9 open, 18 guests at $60.00, +$1080 -$45, balance $5777, 3.0 stars
day 35: 9 open, 18 guests at $60.00, +$1080 -$45, balance $6812, 3.0 stars
day 36: 9 open, 18 guests at $60.00, +$1080 -$45, balance $7847, 3.0 stars
day 37: 9 open, 18 guests at $60.00, +$1080 -$45, balance $8882, 3.0 stars
day 38: 9 open, 18 guests at $60.00, +$1080 -$45, balance $9917, 3.0 stars
day 39: 9 open, 18 guests at $60.00, +$1080 -$45, balance $10952, 3.0 stars
day 40: 9 open, 18 guests at $60.00, +$1080 -$45, balance $11987, 3.0 stars
day 41: 9 open, 18 guests at $60.00, +$1080 -$45, balance $13022, 3.0 stars
day 42: 9 open, 18 guests at $60.00, +$1080 -$45, balance $14057, 3.0 stars
day 43: 9 open, 18 guests at $60.00, +$1080 -$45, balance $15092, 3.0 stars
day 44: 9 open, 18 guests at $60.00, +$1080 -$45, balance $16127, 3.0 stars
day 45: 9 open, 18 guests at $60.00, +$1080 -$45, balance $17162, 3.0 stars
```
