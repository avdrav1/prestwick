# Audio license

Every `.wav` file in this folder is original. Each one is synthesized by
`scripts/gen_audio.py` (Python standard library only: oscillators, noise, filters and
envelopes, no samples, recordings or third-party sound) and belongs to the project like
its code. Nothing here is under a third-party license.

To regenerate them (the output is deterministic, so an unchanged script writes the same bytes):

```
python3 scripts/gen_audio.py          # writes audio/*.wav
python3 scripts/gen_audio.py --list   # names and lengths, writes nothing
godot --headless --path . --import    # re-imports them
```

| File | What it is | Played when |
| --- | --- | --- |
| `strike_tee.wav` | bright "tock" with a swish | a swing from the tee |
| `strike_fairway.wav` | clean click, brush of turf | a swing from the fairway |
| `strike_rough.wav` | dull click under a grassy tear | a swing from the rough |
| `strike_bunker.wav` | sand blast | a swing from a bunker |
| `strike_cart_path.wav` | metallic clack and scrape | a swing from the cart path |
| `putt.wav` | soft "tok" | any putt |
| `land_fairway.wav` | firm thud | first touchdown on fairway or tee |
| `land_rough.wav` | muffled rustle | first touchdown in the rough |
| `land_green.wav` | soft pat | first touchdown on a green |
| `land_bunker.wav` | dead "pff" | first touchdown in a bunker |
| `land_cart_path.wav` | bouncing clacks | first touchdown on the cart path |
| `splash.wav` | splash and bubbles | a ball into water |
| `trees.wav` | wooden knock, shaking leaves | trees block a flight |
| `oob.wav` | falling two-tone "no" | a ball out of bounds |
| `cup.wav` | rattle and plunk | a holed ball |
| `praise.wav` | rising major arpeggio | a guest's praise in the feed |
| `complaint.wav` | sagging "wah-wah" | a guest's complaint in the feed |
| `ambient.wav` | 12 s wind and birdsong, loops | always, Ambient bus |
| `music.wav` | 8 s loop, 120 BPM, I-vi-IV-V in C | always, Music bus; drops out during a swing |
