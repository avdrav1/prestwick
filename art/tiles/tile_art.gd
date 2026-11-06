class_name TileArt
extends Resource
## The terrain art set: surface tops and risers. Loaded from res://art/tiles/surfaces.tres.
## Surface frames are named and ordered by the surface enum (fairway 0 .. cart_path 7, oob 8),
## so frame index == surface value. See art/specs/surfaces.md, art/specs/risers.md,
## art/specs/edge_cue.md and art/specs/land.md.
##
## Play art (E3-S55): a sheet's play_texture is what the course view draws in Play. The
## placeholder surfaces and risers name a label-free version there (the two-letter labels are
## for Build); the Build palette's icons keep the labelled `texture`. Final art leaves it unset.
##
## Since E3-S58 (D50) the course view draws the ground as a smooth mesh textured from the
## surface and land sheets only. The riser and edge cue sheets are no longer drawn on the map
## (no risers, and slope light replaced the lip); they stay in the set for the art preview
## (art/tiles/tile_preview.tscn) and their specs, and no code path needs them.

const PATH: String = "res://art/tiles/surfaces.tres"

## Top faces, one 64x32 diamond per surface.
@export var surfaces: TileSheet
## Side walls, one height step each: "both", "left", "right". Not drawn since E3-S58.
@export var risers: TileSheet
## Edge cues on rises that face away from the camera (E1-S10, art/specs/edge_cue.md):
## "l1", "l2", "r1", "r2" and their pairs. Anchor (32, 18), so the shadow fits above the top.
## Not drawn since E3-S58.
@export var edges: TileSheet
## Unowned land (E6-S5, art/specs/land.md): a hatch over the top, plus a line on each edge
## that lies on a parcel edge. Frame index is the edge mask (bit 0 toward x - 1, bit 1 y - 1,
## bit 2 x + 1, bit 3 y + 1), so frame 0 "hatch" is the pattern alone.
@export var land: TileSheet
## Screen pixels per height step. Matches the riser frames; art-spec constant.
@export var riser_px: int = 16


static func load_default() -> TileArt:
	return load(PATH) as TileArt


func surface_texture(surface_name: StringName) -> AtlasTexture:
	return surfaces.atlas(surface_name)


func riser_texture(side: StringName) -> AtlasTexture:
	return risers.atlas(side)


func edge_texture(frame: StringName) -> AtlasTexture:
	return edges.atlas(frame)
