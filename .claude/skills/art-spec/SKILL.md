---
name: art-spec
description: Write the spec for a Prestwick tile set, sprite, or UI element before art is drawn, and generate a placeholder so code can proceed. Use when a story needs art that does not exist or the user says "art spec <thing>".
---

# Art spec

Argument: what to spec. Examples: `surfaces`, `risers`, `golfer`, `ball`, `trees`, `hud-swing-bar`.

## Constants (do not restate elsewhere)

- Isometric 2:1. Tile footprint 64x32 px. Riser 16 px per height step, 7 steps max.
- Golfer 24 px tall, 8 directions, animations: idle (2 frames), walk (4), swing (6).
- Palette: `art/palette.gpl`, about 32 colors. No colors outside it.
- Sheets are PNG, no padding, 1 px transparent gutter between frames. Named `<thing>_<state>.png`.

## Steps

1. Write `art/specs/<thing>.md`: purpose, frame list with sizes, anchor point, which code reads it, and one line on the look (SimGolf warmth, Mean 18 clarity).
2. Generate a placeholder with `scripts/placeholder.py <thing>`: flat colors from the palette, a label in the corner, correct frame count and size. Save to `art/<folder>/<thing>_placeholder.png`.
3. Add the sheet to the matching `.tres` (`art/tiles/surfaces.tres`, `art/sprites/golfer.tres`) so code loads it by name.
4. Note in the spec what the final sheet must keep: file name, frame count, anchor.

## Final art (D62)

Final sheets are made by generator scripts in `scripts/` (`scripts/art_terrain.py` for the surfaces and land hatch, `scripts/art_sprites.py` for the sprites), drawn by rule as clean pixel art to the spec, from the palette only, and rerunnable. A sheet that fails review is fixed in its script and rerun, never by editing the PNG. The user reviews screenshots in colour and grayscale.

## Colorblind rule

Every surface has a pattern as well as a color (fairway plain, rough stippled, green cross-hatched, bunker dotted, water waves, cart path lined). The spec names the pattern.

## Rules

- Placeholders are never final. The spec file is the handoff, not the PNG.
- Do not pull images from the web or reference other games' sprites by file. All art is original (D62).
