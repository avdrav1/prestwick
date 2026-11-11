# Art spec: ball

> Status (E5-S3): final art, `python3 scripts/art_sprites.py ball` (D62), drawn by `BallArt`
> (`art/sprites/ball_art.gd`) for ShotView and GuestView at the radius they drew the disc at
> (never under `ball_min_screen_radius`; a guest's at `ball_scale` 0.7); the spin frame
> alternates every 0.08 s in flight. The shadow stays in code.

## Purpose

The one thing the player must always find (pillar 2): in flight, at rest on any surface, at
every zoom. A guest's ball must never be taken for the player's (E3 review: a look of its own,
not only a smaller size).

## Look

Mean 18 clarity first: a white ball with a 1 px ink outline reads on every surface including
sand and the green. The shadow is the height cue in flight and stays in code (an ellipse that
shrinks and moves away as the ball climbs).

## Sheet

- File: `art/sprites/ball.png`, loaded from `art/sprites/ball.tres`.
- One row of 4 frames, 8 x 8 px, 1 px gutter (35 x 8):

| # | Frame | Contents |
| --- | --- | --- |
| 0 | `player` | `chalk` ball, `ink` outline, a 1 px `slate_light` shade lower right |
| 1 | `player_spin` | the same with the shade moved, alternated in flight |
| 2 | `guest` | `slate_light` ball, `ink` outline, a `chalk` dot (shape and value differ from the player's) |
| 3 | `guest_spin` | its flight alternate |

## Anchor

(4, 7): the ball's contact point; ShotView draws it at the ball's projected 3D position.

## Code that reads it

`scenes/shot_view.gd` (player), `scenes/guest_view.gd` (guests), and `scenes/green_view.gd`
(the player's ball in the overhead green inset, at its `sprite_scale`, E7-S2). The minimum on-screen size (3 px radius) holds: below 1x the frame is drawn at a
scale that keeps it 8 px on screen.

## Changing it (scripts/art_sprites.py, D62)

- Keep 4 frames of 8 x 8, the order above, anchor (4, 7). Palette colours only.
