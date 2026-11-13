# Example courses

The example courses of E13 (Famous holes): each hole is modelled on a famous real hole at its
real par and yardage, with its signature feature, scaled only where the 128 x 128 map (640 yd)
forces it. The names in the game and in the course files are our own; this file, which does not
ship, credits the real holes. A number marked "approximate" is from memory and may be off by a
few yards or a tee.

E13-S5: the four ship in the exported pack (`courses/*.json`), beside the build and in each itch
channel's `courses/`, and the game copies them into the player's course folder at start
(`CourseExport.install_examples`, never over a file of the same name), so Import course lists
them by Prestwick with their par and yardage. `/balance reactions` and `scripts/guest_day.gd --
examples` print a row per course (five days at 24 arrivals: the reaction mix, its rating, the
latest finish), reported, not targets (`docs/decisions/e13-s5-balance-reactions.txt`). At 24
arrivals: Harbor Links 4.32, Old Grey Links 4.46, Pine Ridge 4.44, Cliffside 4.25 (4.0 stars;
4.49 at data/guests.json's 16), every group finishing nine, the latest at 474, 436, 421 and 524 s
of the 540 s day.

E14-S3 (D69): guests never wade, so each course carries footbridges where its lines cross water
(cart path painted on water, laid by `tests/fixtures/fixture_bridges.gd` on the water tiles of a
line): Harbor Links over the 1st's, 2nd's and 6th's creeks and from the 9th tee's shore over the
west lake to the island green (the walkway at its back stays); Old Grey Links over the 1st's burn
and both of the 3rd's (beside the 9th's, which it had); Pine Ridge over the 5th's creek before its
green and the 7th's, the Footbridge; Cliffside straight over the cove on the 7th, The Crossing.
Every hole passes rule 7. At 24 arrivals, five days: Harbor Links 4.37, Old Grey Links 4.47, Pine
Ridge 4.42, Cliffside 4.26 (4.5 stars), every group finishing nine, the latest at 468, 431, 437 and
530 s (`docs/decisions/e14-s3-balance-reactions.txt`).

## Old Grey Links (E13-S2)

`courses/old_grey_links.json`, built by `tests/fixtures/old_grey_links.gd` (OldGreyLinks) and
saved by `scripts/save_old_grey_links.gd`. Nine holes of seaside links, par 34, 3,023 yd: the
holes play along valleys between rolling dunes, with wide fairways running into the greens,
gorse in the dunes and no trees, pot bunkers sunk a step, two burns, and the sea and a strip of
beach along the north edge. The nine goes out round the edge of the map and comes home through
the middle to a clubhouse beside the 1st tee and the 18th-style home green, as at the Old
Course.

| Hole | Name | Par | Yards | Modelled on | Signature here |
| --- | --- | --- | --- | --- | --- |
| 1 | Swilken Water | 4 | 375 | St Andrews (Old Course) 1st, "Burn", par 4, 376 yd | A burn across the front of a wide green on a wide opening fairway. |
| 2 | The Bishop | 5 | 483 | Prestwick 3rd, "Cardinal", par 5, about 482 yd (approximate) | A long cross bunker, sunk a step, right across the fairway on the second shot, along the shore. |
| 3 | Island Burn | 4 | 460 | Carnoustie (Championship) 17th, "Island", par 4, 461 yd (approximate) | The burn snakes across the fairway twice, leaving an island of fairway between. |
| 4 | The Road | 4 | 455 | St Andrews (Old Course) 17th, "Road", par 4, about 455 yd (the members' tee; 495 yd for the Open) | A deep pot bunker in front of the long, angled green; a cart path runs off past its back right to the 5th tee. |
| 5 | Heather Pots | 4 | 347 | St Andrews (Old Course) 12th, "Heathery", par 4, 348 yd (approximate) | A short par 4 a long hitter can drive, small pot bunkers scattered across the fairway short of a raised green. |
| 6 | The Table | 3 | 250 | Carnoustie (Championship) 16th, "Barry Burn", par 3, 248 yd | A long par 3 to a green on a plateau two steps up, bunkers at the foot of its slopes. |
| 7 | Estuary | 3 | 173 | St Andrews (Old Course) 11th, "High (In)", par 3, 174 yd | A green sloping hard to the front over a deep pot ("Strath") short and the hill bunker left. |
| 8 | Penny Stamp | 3 | 122 | Royal Troon 8th, "Postage Stamp", par 3, 123 yd | A tiny green below a raised tee, ringed by bunkers, the deepest ("Coffin") in front. |
| 9 | Grey Hollow | 4 | 358 | St Andrews (Old Course) 18th, "Tom Morris", par 4, 357 yd | A burn and a bridge just off the tee, the widest fairway on the course, and a swale (the "Valley of Sin") across the front of the green. |

Yards are the line of play the validator measures (rule 4); each is within 2 yd of the real
hole's. Not modelled: the Road hole's hotel and the out-of-bounds wall, the Old Course's
double greens and shared fairways, Carnoustie 17th's out of bounds, and the Heathery's hidden
bunkers (raised to be seen: a blind landing area fails Fair, D43).

## Pine Ridge (E13-S3)

`courses/pine_ridge.json`, built by `tests/fixtures/pine_ridge.gd` (PineRidge) and saved by
`tests/fixtures/pine_ridge_save.gd`. Nine holes of tree-lined parkland, par 34, 2,935 yd, on
flat New sandbox land raised into a ridge: a long rise in the west holds the clubhouse, the 1st
tee and the home green, and a plateau in the east centre is what the 8th drops off. Every hole
plays down its own corridor of rough walled by a belt of pines, with stands in the ground
between; three doglegs (1, 5, 9), two creeks, contoured greens and one crowned green.

| Hole | Name | Par | Yards | Modelled on | Signature here |
| --- | --- | --- | --- | --- | --- |
| 1 | Sentry Pines | 4 | 352 | Merion (East) 1st, par 4, about 350 yd, dogleg right (approximate) | Down off the ridge, turning right round a stand of pines at the corner. |
| 2 | Long Meadow | 4 | 350 | Augusta National 3rd, "Flowering Peach", par 4, 350 yd | A short par 4: bunkers left of the landing and one in front of the green. |
| 3 | Thimble | 3 | 125 | Merion (East) 13th, par 3, about 127 yd (approximate) | A small green from a raised tee, ringed with sand. |
| 4 | Turtle Back | 4 | 372 | Pinehurst No. 2, 3rd, par 4, about 387 yd (approximate), scaled to the map | A crowned green raised a step, whose edges shed a ball. |
| 5 | Creekside Bend | 5 | 513 | Augusta National 13th, "Azalea", par 5, 510 yd (before its 2023 lengthening) | A sweeping dogleg left round the pines, a creek down the inside of the bend and across the front of the green. |
| 6 | Chapel Rows | 4 | 427 | Oakmont 3rd, par 4, 428 yd | Rows of narrow bunkers (the "church pews") left of the landing area. |
| 7 | Footbridge | 3 | 155 | Augusta National 12th, "Golden Bell", par 3, 155 yd | Over a creek to a wide, shallow green, sand in front and behind. |
| 8 | Ridge Drop | 3 | 181 | Augusta National 6th, "Juniper", par 3, 180 yd | Downhill four steps off the plateau to a green framed by pines. |
| 9 | Homeward Climb | 4 | 460 | Augusta National 18th, "Holly", par 4, 465 yd | Out through a chute of pines, turning right and climbing five steps to the green beside the clubhouse. |

Yards are the line of play the validator measures (rule 4). Hole 4 is 15 yd short of the real
hole: the east edge holds no more. Not modelled: Pinehurst's sandy waste areas, Augusta 13th's
azaleas, the 18th's pair of fairway bunkers (one here, at the corner), Merion's wicker baskets, and the pews' grass
strips between rows at their real scale (here a row every 3 tiles, 15 yd).

## Harbor Links (E13-S1)

`courses/harbor_links.json`, built by `tests/fixtures/harbor_links.gd` (HarborLinks) and saved
by `scripts/save_harbor_links.gd`. Nine holes over water, par 35, 3,200 yd, on flat lowland
with every pond dug into a hollow (D66). The front four run anticlockwise round the edge of the
map; the back five play round the two big waters in the middle, the harbour (the 5th's left,
the 7th's "water left all the way") and the west lake (the 1st's right, the 8th's green, the
9th's island). The clubhouse stands beside the 1st tee; one cart path joins the only long walk,
the 4th green round its pond to the 5th tee.

| Hole | Name | Par | Yards | Modelled on | Signature here |
| --- | --- | --- | --- | --- | --- |
| 1 | Heron's Reach | 4 | 435 | PGA National (Champion) 16th, the first of the "Bear Trap", par 4, about 434 yd (approximate) | Water down the right (the west lake) and a creek across the approach. The real hole doglegs right round its lake; here it runs straight up the edge. |
| 2 | Creek Bend | 5 | 516 | Augusta National 13th, par 5, 510 yd (before its 2023 lengthening) | A fairway that bows away and turns back left to a green behind a creek, reachable in two. A gentle bend, not the real sharp dogleg, along the map's edge. |
| 3 | Long Wharf | 5 | 517 | TPC Sawgrass (Stadium) 16th, par 5, 523 yd | Water right of the green and a bunker in front; reachable in two. |
| 4 | Lantern Pond | 3 | 185 | Muirfield Village 12th, par 3, about 184 yd (approximate) | A pond the whole way to a shallow green set across the line, bunkers behind. |
| 5 | Breakwater | 4 | 460 | Bay Hill 18th, par 4, about 458 yd (approximate) | Water short and right of the green; here the harbour also runs down the left. |
| 6 | Ferry Crossing | 3 | 156 | Augusta National 12th, par 3, 155 yd | A creek in front of a wide, shallow green, bunkers behind. |
| 7 | Long Shore | 4 | 461 | TPC Sawgrass (Stadium) 18th, par 4, 462 yd | Water left the whole way, curling in short and left of the green. Straight here; the real hole bends gently left. |
| 8 | Short Tack | 4 | 332 | TPC Scottsdale (Stadium) 17th, par 4, about 332 yd (approximate) | A short par 4 a long hitter can drive, water left of the green. |
| 9 | Lighthouse Isle | 3 | 138 | TPC Sawgrass (Stadium) 17th, par 3, 137 yd | An island green with a walkway at its back. |

Yards are the line of play the validator measures (rule 4); each is within 6 yd of the real
hole's (the 2nd and 3rd are set where the 640 yd map and their neighbours fit them). Not
modelled: the real holes' elevation (the course is flat), PGA National's and Augusta's doglegs,
and the island green's single pot bunker. Measured on the file (10 guest days at
data/guests.json's arrivals): praise 0.83, neutral 0.16, complaint 0.01, 4.5 stars; at 24
arrivals every group finished nine, the latest at 474 s of the 540 s day (seeds 1 to 5).

## Cliffside (E13-S4)

`courses/cliffside.json`, built by `tests/fixtures/cliffside.gd` (Cliffside) and saved by
`scripts/save_cliffside.gd`. Nine holes round an island of clifftops, par 36, 3,353 yd. The sea
is water at height 0 round every edge of the map and in three coves (a chasm across the 3rd, a
narrow inlet between the 5th and 6th, and a bay the 6th, 7th and 1st play round); a headland
stands out under the 4th green. The plateau rolls from about 6 steps in the north to 4 in the
south and drops to the sea a step a tile (smooth bluffs, D50), so a ball that runs off a
fairway's seaward edge rolls into the sea. The clubhouse stands on the south-east headland by
the 1st tee and the 9th green; cart paths serve the five climbing walks (1-2, 3-4, 4-5, 5-6,
8-9).

| Hole | Name | Par | Yards | Modelled on | Signature here |
| --- | --- | --- | --- | --- | --- |
| 1 | Bay Bluff | 4 | 395 | Cypress Point 17th, par 4, 393 yd (approximate) | North up the bay's bluff, the water all down the left; a bunker in the middle of the fairway stands in for the real hole's cypresses (trees there slowed the guest day too much). |
| 2 | North Ledge | 4 | 363 | Bandon Dunes 16th, par 4, 363 yd (approximate) | West along the northern cliff top from a raised tee, a cross bunker in the fairway, the green on the cliff's edge. |
| 3 | The Chasm | 4 | 430 | Pebble Beach 8th, par 4, 428 yd | A drive along the western cliffs, then the approach over a sea chasm to a green on the far side. |
| 4 | Little Point | 3 | 107 | Pebble Beach 7th, par 3, 106 yd | A short drop from a raised tee to a small green on a headland in the sea, a bunker in front. |
| 5 | Long Bluff | 4 | 445 | Pebble Beach 10th, par 4, 446 yd (approximate; longer from the Open tees) | North along the inlet's bluff, the water all down the right. |
| 6 | Cliff Edge | 4 | 332 | Pebble Beach 4th, par 4, 331 yd (approximate) | A short par 4 down the inlet's far side, a bunker in the fairway, to a green on the clifftop above the water. |
| 7 | The Crossing | 3 | 231 | Cypress Point 16th, par 3, 231 yd (approximate; 219 to 233 by tee) | The long carry over the bay's mouth to a green on the far headland. |
| 8 | Headland | 5 | 525 | Pebble Beach 6th, par 5, 523 yd | Uphill all the way north to a green on the northern cliff. |
| 9 | Homeward | 5 | 525 | Pebble Beach 18th, par 5, 543 yd | Down the eastern shore, the sea all down the left, home to a green above the southern cliff; scaled to 525 yd, since the map's north and south seas leave no more room. |

Yards are the line of play the validator measures (rule 4); each is within 2 yd of the real
hole's but the 9th. Measured on the saved file (data/guests.json's arrivals, day seeds 1 to 10,
1,440 reactions): praise 0.76, neutral 0.23, complaint 0.01, a rating of 4.49, 4.5 stars
(fair and interesting never fail; the 3rd plays 1.9 over par, the hardest). The 2nd fails pace
on two thirds of its reactions, the groups backing up behind the slow 3rd. At 24 arrivals (day
seeds 1 to 10) every group finishes nine, the latest at 524 s (dusk 540). Not modelled: Cypress
Point's cypresses in the 17th fairway and Pebble Beach 18th's tree, the 7th's ring of bunkers,
and the real holes' beaches and sea walls.
