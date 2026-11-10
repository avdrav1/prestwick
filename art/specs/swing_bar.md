# Art spec: swing bar

> Status (E5-S1): drawn in code, `scenes/swing_bar.gd` (E2-S7, E3-S73): a bar from
> `SwingTuning.bar_min` to max power, the accuracy band with bracket ends round a tall centre
> line, a chalk 100% line, the overswing hatched `flag_red`, a `sun_yellow` triangle for the
> bar's position above, an ink-outlined chalk triangle (power) and diamond (accuracy) below, and
> the putter's pace tick and ring. That drawing is the placeholder.

## Purpose

The three-click swing (Mean 18's meter): the player must read power, the 100% mark and the
accuracy window at a glance while the pointer moves (pillar 2).

## Recommendation for the art pass

Keep the bar's geometry in code (its length, zones and pointer positions come from
`SwingTuning` and change with the club). The art pass may add a 9-slice frame round it from the
HUD theme (`art/specs/hud.md`) and match its outline weight to the final art.

## Sheet (only the frame)

- File: `art/ui/swing_bar_frame.png`, one 9-slice image 48 x 24 with 8 px margins, palette
  colours only (`slate_dark` fill, `ink` outline, a `slate` bevel on the upper left).

## Code that reads it

`scenes/swing_bar.gd`, `scenes/swing_panel.gd` (the panel it sits in).

## For the artist replacing it

- Keep the pointer shapes (triangle above, triangle and diamond below, hatch past 100%): they
  are the colorblind rule for the bar.
