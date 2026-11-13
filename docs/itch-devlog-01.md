# Devlog #1: Prestwick is playable

Title: Prestwick is playable: build a golf course, then play it

Hi! This is the first devlog for **Prestwick**, a golf course builder where you also play every hole you build, and the guests who pay to play it tell you exactly what they think.

## The idea

Prestwick is inspired by two kinds of game: *Sid Meier's SimGolf*, where you shape a course and watch golfers react to it, and the classic overhead golf games, where you actually swing the club. Prestwick puts those together. You sculpt the land, paint fairways and greens, drop a tee and a cup, and the hole is open. Guests walk out of your clubhouse, play it, and leave a comment: "blind from the tee, could not see the flag", "a long walk from the 4th green to the 5th tee, and no cart path", "loved it, 3 on a par 3". At dusk their verdicts become your star rating, and your rating decides how many people come back tomorrow and what you can charge them.

Three rules guided every decision:

1. **Every hole is playable the moment you place it.** No separate editor and game. Build, Tab, swing.
2. **Shots are readable.** You should be able to see why the ball went where it went: slopes, lies, the swing bar.
3. **The course tells a story through its guests.** The best feedback isn't a number, it's a guest grumbling about your 9th hole.

## What's in the playtest build

- Smooth, rolling terrain you can raise, lower and paint with nine surfaces. Water finds its own level, so no more towering pools (a tester made a lot of those).
- Up to nine holes, par 3 to par 5, doglegs included, with a ruler that shows each hole's length and par as you place the cup.
- Guests who wait their turn, walk your cart paths, and react to every hole.
- An economy: $5,000 to start, green fees, upkeep, land to buy, and stars set each evening.
- A three-click swing bar marked in yards, a landing marker, and a top-down green view for putts.
- A goal checklist for your first course, morning autosaves, and course files you can send to a friend.
- Original music (by me): "Scaffold" while you build, "Progress" while you play.

## What playtesters have already changed

The first outside players have been brilliant, and blunt. Some of the things that changed because of them:

- **"I'm not sure what I should be doing."** New courses now open with a goal checklist that walks you from your first tee to three stars, and Play is greyed out until there's a hole to play.
- **"It was not clear how far a driver would go."** Building now shows a ruler from the tee ("285 yd: par 3") and rings for a driver's carry and where par 4 and par 5 start.
- **"The aiming controls are really jumpy."** The camera now holds still while you aim and only glides when your aim would leave the screen.
- **"I don't really know what I am doing when I swing."** The swing bar is labelled in yards, shows the carry as you set power, and the landing marker moves with it.
- **"I can't build a nice long hole without buying land."** New courses now start on a much bigger block, so your first hole can be a real par 3 or par 4.
- And a near-miss of my own: F5 and F9 now ask before they overwrite a save, and the game autosaves every morning.

## What's next

The goal for version 0.6.0 is simple: ten people who aren't me play a full session, build a course, and send one to a friend. Everything they find gets fixed before it ships. After that, I want to look at Mac builds, smoother updates, and whatever the playtest tells me matters most.

## Play it and tell me what happened

Download the build on this page (Windows and Linux; the itch app keeps it updated). Play for half an hour, build a hole or two, and then tell me what confused you, what broke, and what you liked, either in the comments here or as a report on GitHub: https://github.com/avdrav1/prestwick/issues

If you build a course you're proud of, export it (Esc, Export course) and share the file. I'd love to play it.

Thanks for reading, and see you on the first tee.
