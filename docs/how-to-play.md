# How to play Prestwick

Prestwick is a golf course you build, then play. Guests play it too, pay a green fee, and tell you what they think. Build a nine-hole course that earns 3 stars without running out of money.

## Start

Run the game. The menu opens: choose **New course**, **Famous courses** to start on one of the six courses built into the game, or **Import course** to open a course a friend sent you (a course file goes in the folder the Import page's **Open folder** shows). Esc opens the menu at any time and pauses the guests' day.

**Famous courses** lists the seven courses that come with the game, modelled on famous real holes: five nines, **Harbor Links** (holes over water, an island green to finish), **Old Grey Links** (seaside links, pot bunkers and burns), **Pine Ridge** (tree-lined parkland with doglegs and creeks), **Cliffside** (clifftop holes across the sea) and **Dogleg Hollow** (nine famous doglegs, every hole bending round a lake, woods or sand), and two full eighteens, **Old Grey Links (Championship)** (the links nine plus a back nine of famous links holes) and **Dogleg Hollow (Championship)** (the dogleg nine plus a back nine of famous doglegs, every one of the eighteen bending), each with its par and yardage. Picking one starts a new game on it (it asks first if you have a game under way): Day 1, every hole open, all the land owned and the starting $5,000 to rebuild with, to play, watch the guests on, or change. They are built into the game, so each update brings their latest version. A game you saved on one keeps the course as it was when you saved it; the Load game and Famous courses pages say "A newer version of Cliffside is available." when an update changed it, and a new game from Famous courses plays the new one.

Earlier versions (rc8 to rc10) copied the four into your course folder. The game tidies those copies away once when it first starts: a copy you never changed is removed, and one you edited is kept as "Cliffside (my copy)" (`cliffside_my_copy.json`) on the Import page.

## Build (the starting mode)

- You start with **$5,000** and a 4 x 4 parcel block of land round your clubhouse. Painting, raising and lowering ground cost money; undo (Ctrl+Z) gives back what that step charged. **Buy land** adds a neighbouring parcel.
- Click **New hole**, place a **Tee** and a **Cup**, paint a green round the cup and fairway between. The hole panel (top right) says what is wrong until the hole is legal; the moment it is, the hole opens itself ("Hole 1 is open: guests will play it"). **Close** in the hole list shuts a hole to guests until you press **Open** again.
- Pick par 3, 4 or 5 to match the hole's length; a hole that bends needs room to land a ball at the corner.
- With the Cup tool in hand, a ruler runs from the tee to the cursor and says how long the hole would be and its par ("285 yd: par 3"); placing the cup sets that par unless you picked one. Rings round the tee mark a driver's carry and total and where par 4 (320 yd) and par 5 (471 yd) start. Your free starting land is 4 x 4 parcels, 320 yd a side: a good first hole is a par 3 of 120 to 300 yd (24 to 60 tiles from the tee; a tile is 5 yd) or a par 4 of 320 to 380 yd from corner to corner. A par 5 needs more land. Guests walk from the clubhouse to the first tee, so start near it.

How far each club goes with a perfect swing from flat fairway, in yards:

| Club | Carry | Total |
| --- | --- | --- |
| driver | 235 | 282 |
| 3w | 220 | 261 |
| 3i | 190 | 223 |
| 4i | 179 | 208 |
| 5i | 168 | 193 |
| 6i | 157 | 178 |
| 7i | 146 | 164 |
| 8i | 135 | 150 |
| 9i | 124 | 136 |
| pw | 113 | 123 |
| sw | 102 | 110 |
- **Clubhouse** moves the clubhouse (right-click or R turns its door); guests start and finish there. **Decor** places scenery that never touches the ball.
- **Water** finds its level: dig a hollow (Lower), then paint water in it and the whole hollow fills, flat, up to just under its lowest edge, at water's price for each tile filled. Water on a hill, on open flat ground, or in a hollow that touches the map's edge or land you don't own would run off, so nothing is painted. Water won't cover a tee, a green, a hole's tee or cup, the clubhouse or decor. Raise and Lower skip water; lowering the bank beside a pond to the water's level lets the water spread onto it, or drain away if that opens a way out.
- **Cart path** ($6 a tile) is the quick way round for guests: they walk half as fast again on a path, and slower through trees, bunkers and up hills. Guests never wade: they walk round water by the quickest dry way, or over a bridge. With the Cart path brush in hand the map shows every walk a round takes: green when a path serves it, red when it is long enough to draw complaints, with the reason ("path stops 19 yd short of the 8th tee"), and pale when it is short. A path serves a walk when it starts within 40 yd of the green (or the clubhouse door) and ends within 40 yd of the next tee, and walking it is quicker than walking across. Lay or extend one and the old walk complaints about that tee clear, so the next guests' word shows. A ball bounces and runs on a path, so keep paths off the line of play. Paint cart path over water and it builds a wooden footbridge instead ($31 a tile; the brush says so before you click): guests cross on it at path speed, but a ball that lands on a bridge is still in the water. Paint anything else over a bridge to take it away. A hole whose tee, green or landing ground guests cannot walk to closes and says so ("no way to walk to the 9th green: add a bridge"); lay the bridge and it opens.
- The **fee slider** sets the green fee. Higher fees bring fewer guests; the most you can charge is $25 per star.

## Guests, money and stars

- Each morning guests arrive at the clubhouse, pay at the first tee and play your open holes. If none is open yet they go home, and come back as soon as your first hole opens, while the day has time for a round. Each open hole costs $5 a day to keep up.
- When guests finish a hole they say what they thought: the feed on the left and the tags on the map show it. Click one to jump to that hole. Complaints name what to fix (a blind tee shot, a dull hole, a slow wait, or a long walk from one green to the next tee that no cart path serves, with why, which alone is enough for a complaint). A cart path that turns a long walk into a quick one can earn a word of praise.
- At dusk their verdicts set your stars (1 to 5). More stars bring more guests and a higher fee ceiling.
- **P** pauses, **1** and **3** run the day at 1x and 3x, **M** skips to the next morning.

## Play a hole yourself

- **Tab** switches between Build and Play.
- Aim with the mouse or Left/Right, change club with Up/Down.
- Swing with Space or a click: press once to start, again to set power, again to set accuracy (hit the mark).
- The bar shows how far your club carries from this lie at 50%, 100% and max, and while you set the power the readout says the yards and the landing marker moves with it. Stop the bar on its way back inside the green accuracy zone to hit it straight; outside it, the shot shanks.
- On the green, the green view shows the slope (G hides it for this green), and the tick on the bar is the power the aim marker's putt needs. **T** shows contour lines.

## Saving

**F5** saves, **F9** loads (a load starts that day again from its morning). Each asks first when it would replace something: "Save over your saved game from Day 4?" or "Load Day 4 and lose today's progress?". **Enter** says yes, **Esc** says no.

The game also saves itself each morning, keeping the last 3 mornings apart from your own save, which it never touches. **Load game** in the menu (Esc) lists your saved game and each of those mornings with its day, balance and the date and time it was saved; pick one to load it. Starting a new course keeps the old course's morning saves until the new course makes its first one.

**Export course** in the menu writes a course file to send to a friend; it opens with $5,000.

## Keys

**F1** shows every key. **F2** sets the volumes. With **F6** every button can be reached from the keyboard; the arrow keys move a build cursor, and Space or Enter uses the tool.

## Eighteen holes

A new course is 192 x 192 tiles (960 yards a side) and holds up to eighteen holes. Once hole 10 exists the hole list splits into Out (1 to 9) and In (10 to 18). With all eighteen open, the day runs longer (17 minutes at 1x) and about half the groups play the full eighteen, stopping at the clubhouse at the turn and paying 1.75 times the nine-hole fee; the rest play nine, on the back nine when the 1st tee is busy.
