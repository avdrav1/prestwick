class_name TileSheet
extends Resource
## One PNG sheet: a single row of equal frames, no padding, a transparent gutter between
## frames (art-spec constants). Code asks for a frame by name, never by pixel offset.

@export var texture: Texture2D
## The sheet the course view draws in Play, when it differs (E3-S55): the placeholder's
## label-free version, same size, frames and layout. Unset, `texture` is used in both modes,
## so final art (which has no labels, art/specs/surfaces.md) sets only `texture`.
@export var play_texture: Texture2D
@export var frame_size: Vector2i = Vector2i(64, 32)
@export var gutter: int = 1
## Frame names in sheet order, left to right.
@export var frames: PackedStringArray = PackedStringArray()
## Pixel in a frame that sits on the point the projection returns for its tile.
@export var anchor: Vector2i = Vector2i(32, 16)


## The texture to draw in Play (`play` true) or Build: play_texture in Play when it is set,
## else texture.
func texture_for(play: bool) -> Texture2D:
	return play_texture if play and play_texture != null else texture


func frame_count() -> int:
	return frames.size()


func has_frame(frame_name: StringName) -> bool:
	return frames.has(String(frame_name))


func frame_index(frame_name: StringName) -> int:
	return frames.find(String(frame_name))


func region(index: int) -> Rect2i:
	assert(index >= 0 and index < frames.size(), "frame index out of range: %d" % index)
	return Rect2i(Vector2i(index * (frame_size.x + gutter), 0), frame_size)


func region_named(frame_name: StringName) -> Rect2i:
	var index: int = frame_index(frame_name)
	assert(index >= 0, "no frame named %s" % frame_name)
	return region(index)


## A texture for one frame, for a Sprite2D or a draw_texture call.
func atlas(frame_name: StringName) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = texture
	tex.region = Rect2(region_named(frame_name))
	return tex
