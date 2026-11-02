class_name TileArt
extends Resource
## The terrain art set: surface tops and risers. Loaded from res://art/tiles/surfaces.tres.
## Surface frames are named and ordered by the surface enum (fairway 0 .. cart_path 7, oob 8),
## so frame index == surface value. See art/specs/surfaces.md and art/specs/risers.md.

const PATH: String = "res://art/tiles/surfaces.tres"

## Top faces, one 64x32 diamond per surface.
@export var surfaces: TileSheet
## Side walls, one height step each: "both", "left", "right".
@export var risers: TileSheet
## Screen pixels per height step. Matches the riser frames; art-spec constant.
@export var riser_px: int = 16


static func load_default() -> TileArt:
	return load(PATH) as TileArt


func surface_texture(surface_name: StringName) -> AtlasTexture:
	return surfaces.atlas(surface_name)


func riser_texture(side: StringName) -> AtlasTexture:
	return risers.atlas(side)
