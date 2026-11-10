# Art spec: aim and landing markers, hazard cues

> Status (E5-S1): drawn in code with `art/palette.gpl` colours, and that drawing is the
> placeholder: `scenes/aim_view.gd` (the aim line: dots on the chord, or along the putt's roll;
> the aim marker: a ring with a centre dot and four ticks), `scenes/shot_view.gd` (the struck
> ball's landing marker, a red cross) and `scenes/hazard_cue.gd` (E6-S16: OB ring and slash,
> water's two chalk splash rings, the blocked octagon with a chalk bar).

## Purpose

Tell the player before the swing where the ball goes and after it where it went and what
happened (pillar 2). Each reads by shape as well as colour (colorblind rule) and draws over the
terrain at a fixed size on screen at every zoom.

## Recommendation for the art pass

Keep these in code. They are geometry that scales with the shot (a line of any length, rings
laid 2:1 on the ground, an OB slash with a gap round the ball), they already pass the shape
rule, and a bitmap would blur or step at 0.175x and 2x. The art pass only sets their colours
and line widths to match the final art's outline weight, in the tuning resources
(`scenes/shot_view_tuning.tres`, `aim_view` constants moved to a `.tres` if they change).

## Sheet (only if a bitmap is chosen)

- File: `art/sprites/aim_markers_<state>.png`, one row, 1 px gutter, all frames 24 x 24:
  `aim_dot` (the line's dot, centred), `aim_marker`, `landing_cross`, `ob`, `water`, `blocked`.
- Anchor (12, 12) for every frame except `blocked` (12, 22, it stands upright).

## Code that reads it

`scenes/aim_view.gd`, `scenes/shot_view.gd`, `scenes/hazard_cue.gd`.

## For the artist replacing it

- If drawn, keep 24 x 24 frames, the order above, palette colours, and the shapes named in
  `scenes/hazard_cue.gd`'s header; check each at 0.175x, 0.5x and 1x in grayscale.
