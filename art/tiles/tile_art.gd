class_name TileArt
extends Resource
## The terrain art set: surface tops and risers. Loaded from res://art/tiles/surfaces.tres.
## Surface frames are named and ordered by the surface enum (fairway 0 .. cart_path 7, oob 8),
## so frame index == surface value. See art/specs/surfaces.md, art/specs/risers.md
## and art/specs/edge_cue.md.

const PATH: String = "res://art/tiles/surfaces.tres"

## Top faces, one 64x32 diamond per surface.
@export var surfaces: TileSheet
## Side walls, one height step each: "both", "left", "right".
@export var risers: TileSheet
## Edge cues on rises that face away from the camera (E1-S10, art/specs/edge_cue.md):
## "l1", "l2", "r1", "r2" and their pairs. Anchor (32, 18), so the shadow fits above the top.
@export var edges: TileSheet
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
