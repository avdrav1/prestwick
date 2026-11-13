# Example courses

The example courses of E13 (Famous holes): each hole is modelled on a famous real hole at its
real par and yardage, with its signature feature, scaled only where the 128 x 128 map (640 yd)
forces it. The names in the game and in the course files are our own; this file, which does not
ship, credits the real holes. A number marked "approximate" is from memory and may be off by a
few yards or a tee.

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
