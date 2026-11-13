# Art spec: bridge

> Status (E14-S1, D69): final art, `python3 scripts/art_sprites.py bridge` (D62). Built by
> painting cart path on water (`CourseBuilder.paint`), stored in the course (`CourseData.set_bridge`,
> the optional `bridges` field), drawn by `course/bridge_view.gd`.

## Purpose

A wooden footbridge over one water tile: guests walk it at cart path's speed, a ball that lands
on it is still in the water. It must read as something to walk on, never as dry ground a ball
could rest on (pillar 2), so the water shows beside a railed deck and the deck is wood, not path.

## Look

`earth_light` planks with `earth` seams across the way the deck runs, `earth` and `earth_dark`
deck faces toward the camera, `earth` rails on `earth_dark` posts with an `ink` top line, an
`ink` deck outline. The deck stands 3 px over the water surface, the rails 7 px over the deck.
Colours from `art/palette.gpl` only.

## Sheet

- File: `art/sprites/bridge.png`, loaded from `art/sprites/bridge.tres`.
- One row of 32 frames, 64 x 48 px each, 1 px gutter (2079 x 48).
- Frames 0 to 15 (`bridge_x_<rails>`): planks for a deck running along x; 16 to 31
  (`bridge_y_<rails>`): along y. `rails` is a 4-bit mask of the sides with a rail, the
  neighbour there being open water (or off the map): bit 0 +x, bit 1 -x, bit 2 +y, bit 3 -y. A
  railed side's deck edge stands 0.36 of a tile from the centre (water shows beside it); an
  open side runs to the tile's edge and meets the next bridge tile or the bank.

## Anchor

(32, 28): the tile centre on the drawn water surface; sorted half a unit under
`Iso.object_sort_key` of its tile, so a guest on it draws over the deck.

## Code that reads it

`course/bridge_view.gd` (`BridgeView.frame_for`: along x when its x neighbours, bridge or dry, are
at least as many as its y neighbours; rails where the neighbour is open water),
`course/course_view.gd` (redraws on a bridge change or a height or water change).

## Changing it

Change the rule in `scripts/art_sprites.py` and rerun it; never edit the PNG. Keep 32 frames of
64 x 48, the order and the mask bits above, anchor (32, 28).
