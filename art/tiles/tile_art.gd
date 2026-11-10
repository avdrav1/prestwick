class_name TileArt
extends Resource
## The terrain art set: surface textures and the unowned-land hatch. Loaded from
## res://art/tiles/surfaces.tres. Surface frames are named and ordered by the surface enum
## (fairway 0 .. cart_path 7, oob 8), so frame index == surface value; the sheet repeats every
## `macro` tiles (TileSheet.macro, E5-S2). See art/specs/surfaces.md and art/specs/land.md.
##
## Final art (E5-S2, D62): both sheets are written by scripts/art_terrain.py. Since E3-S58 (D50)
## the course view draws the ground as a smooth mesh textured from them; the riser and edge cue
## sheets went with E5-S2 (art/specs/risers.md, edge_cue.md). Play art (E3-S55): a sheet's
## play_texture, when set, is what the course view draws in Play; the final sheets have no
## labels, so it is unset and one sheet draws in both modes.

const PATH: String = "res://art/tiles/surfaces.tres"

## Surface textures, one 64x32 diamond per surface and variant.
@export var surfaces: TileSheet
## Unowned land (E6-S5, art/specs/land.md): a hatch over the top, plus a line on each edge
## that lies on a parcel edge. Frame index is the edge mask (bit 0 toward x - 1, bit 1 y - 1,
## bit 2 x + 1, bit 3 y + 1), so frame 0 "hatch" is the pattern alone.
@export var land: TileSheet
## Screen pixels per height step (Iso.STEP_PX); art-spec constant.
@export var riser_px: int = 16


static func load_default() -> TileArt:
	return load(PATH) as TileArt


func surface_texture(surface_name: StringName) -> AtlasTexture:
	return surfaces.atlas(surface_name)

