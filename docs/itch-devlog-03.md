# Devlog #3: Eighteen holes

Title: Prestwick 0.7.0: eighteen holes

Prestwick 0.6.0 let you build nine holes. 0.7.0 goes all the way: courses can now have eighteen.

## A bigger map

A real eighteen needs room, roughly twice the land of a nine. New courses now start on a map 960 yards on a side, about 190 acres, more than twice the old one. Before committing to it we measured the bigger map against every frame-time budget the game keeps, and found a few places where eighteen holes made things slow: checking every hole after an edit, guests working out their walk round water, and skipping to the next morning. Those got faster first. Now building, undoing, the farthest zoom and skip to morning all hold their budgets on a full eighteen, and skipping a day on a nine is quicker than it was in 0.6.0.

You still start on the same 4 x 4 block of free land and buy more as you grow. Once your course has a hole 10, the hole list splits into Out and In.

## Nine or eighteen

With all eighteen holes open, the day gets longer and your guests choose how much golf they want. About half play the full eighteen: they finish the 9th, stop at the clubhouse for a moment at the turn, and head out to the 10th. They pay 1.75 times the nine-hole fee, as at a real club. The rest play nine, and if the 1st tee is crowded they start on the back nine instead.

Money still paces you. A good (3-star) course opens its nine around day 27 and its full eighteen around day 69; a great one gets there much sooner.

## The first famous eighteen

**Old Grey Links (Championship)** is the sixth course built into the game. The front nine is the Old Grey Links you know; the new back nine runs south along the shore and comes home to the clubhouse, with holes modelled on famous links holes: a railway down the right, a long alley between twin bunkers, a burn short of the green, a blind green behind a wall of turf, a long par 3 over a chasm, a pair of bunkers cut into a ridge like spectacles, a bunker shaped like a nose, and a finish in front of the clubhouse windows. See how many you can name.

Find it under **Esc, Famous courses**.

## What's next

Playtesting carries on. If you build an eighteen, export it (Esc, Export course) and share it in the comments; I'd love to play it. Bug reports and feedback are welcome in the comments or on GitHub: https://github.com/avdrav1/prestwick/issues

See you on the 10th tee.
