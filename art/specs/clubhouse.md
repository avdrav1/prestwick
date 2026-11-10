# Art spec: clubhouse

## Purpose

The course's front door (D60, E5-S10; pillar 3: the course reads as a place people visit).
One building per course, a 3x3 tile footprint with a facing: guests come out of its door in
the morning, walk to the first tee, and walk back in after their last hole (E5-S11). It must
read at 0.175x as "the building where the guests are", and at 0.5x and 1x which side its door
is on, so the player can see where the walks start.

## Look

SimGolf warmth, Mean 18 clarity: a small single-storey clubhouse with a hipped red roof
(flag_red on the lit face, earth_dark on the shaded face, earth on the back faces), sand_light
and sand_dark walls (the lit and shaded side, as the ground's slope light reads: light from the
upper left), water_light windows and an earth_dark door, all on an ink outline, standing on a
paved apron of path and path_dark over the whole 3x3 footprint. Colours from `art/palette.gpl`
only. No shadow in the sheet.

Shape as well as colour (colorblind rule): the door is a tall dark rectangle with a chalk
doorstep, on the wall it faces. With the door on a wall facing away from the camera (-x or -y),
a sun_yellow pennant on a chalk pole stands on the eave on that side, so the facing still reads
in grayscale.

The ground is smooth slopes (D50): the building is drawn over its own footprint, standing at the
lowest ground of its 9 tiles, so on a slope its walls sink into the uphill side, not float.

## Sheet

`art/sprites/clubhouse.png` (final art, E5-S3, D62: `python3 scripts/art_sprites.py clubhouse`;
siding, a stone plinth, mullioned windows on sills, a door with its knob, tile courses on the
roof and a chimney): one row of 4 frames, 192 x 138 px each, 1 px gutter,
no padding, named by facing: `+x`, `+y`, `-x`, `-y` (`CourseData.FACING_NAMES`: the side the door
is on; on screen +x runs down and right, +y down and left, so only `+x` and `+y` show the door).

- Footprint: the 3x3 diamond, 192 x 96 px, its centre at the anchor.
- Anchor: (96, 88), the ground point of the footprint's centre tile.
- Walls stand 1.25 tiles from the centre (a quarter tile of apron round them), 40 px high
  (2.5 height steps, about 6 yd); the roof's eaves overhang to 1.4 tiles and rise 36 px.

Loaded as a `TileSheet` from `art/sprites/clubhouse.tres` (frames by facing name, anchor);
`course/clubhouse_view.gd` (ClubhouseView) draws it, Y-sorted with the ground, the hole markers
and the guests at the sort key of the footprint's front tile (centre + (1, 1)).

## Changing it

- Change the rule in `scripts/art_sprites.py` and rerun it (D62).
- File: `art/sprites/clubhouse.png`.
- Frames: 4, 192 x 138, in the order `+x`, `+y`, `-x`, `-y`, 1 px gutter.
- Anchor: (96, 88) for the footprint centre; keep the building inside the 3x3 diamond at the
  ground and the frame's 138 px height (or change `frame_size` and `anchor` together).
- The geometry helpers it shares with the old placeholder (`club_pt`, the wall quads) stay in
  `scripts/placeholder.py`.
