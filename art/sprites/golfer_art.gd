class_name GolferArt
extends Resource
## The golfer sprite set (E3-S5, art/specs/golfer.md): one sheet per state, each a row of
## 8 directions (DIRS order) times that state's frames, frames named "<dir>_<n>". Loaded from
## res://art/sprites/golfer.tres. Code asks for a frame by state, direction and index.

const PATH: String = "res://art/sprites/golfer.tres"

enum Anim { IDLE, WALK, SWING }

## Screen directions, clockwise from straight down the screen (toward the camera).
const DIRS: PackedStringArray = ["s", "sw", "w", "nw", "n", "ne", "e", "se"]

@export var idle: TileSheet
@export var walk: TileSheet
@export var swing: TileSheet

## Shirts (E3-S28, art/specs/golfer.md "Shirts"): the sheets draw the shirt in one key colour
## (chalk) and GuestView swaps it for its group's shirt in a shader (golfer_shirt.gdshader),
## so one sheet dresses every group. Shirt i is `shirt_body[i]`, with `shirt_trim[i]` on the
## rows its `shirt_pattern[i]` picks. Every colour from art/palette.gpl.
enum Pattern {
	## All body.
	PLAIN,
	## Trim on every odd sheet row: stripes across the shirt.
	HOOPS,
	## Trim on the rows above `yoke_row`: the shoulders.
	YOKE,
}

const SHIRT_SHADER: Shader = preload("res://art/sprites/golfer_shirt.gdshader")

## The colour the sheets draw the shirt in. Only shirt pixels use it (the shader swaps it).
@export var shirt_key: Color = Color8(240, 236, 224)
@export var shirt_body: PackedColorArray = PackedColorArray()
@export var shirt_trim: PackedColorArray = PackedColorArray()
@export var shirt_pattern: PackedInt32Array = PackedInt32Array()
## Sheet rows above this one wear a YOKE shirt's trim.
@export var yoke_row: int = 12
## The rows of a frame the shirt (and so the key colour) may cover, inclusive.
@export var shirt_rows: Vector2i = Vector2i(9, 16)
## Two shirts with one pattern differ by at least this much luma (0 to 255), as does a
## patterned shirt's trim from its body, so the groups still tell apart in grayscale.
@export var shirt_min_luma_step: float = 32.0

## {"<anim>/<frame name>": AtlasTexture}, built on first use.
var _cache: Dictionary = {}
## One ShaderMaterial per shirt, shared by every figure wearing it.
var _shirt_materials: Array[ShaderMaterial] = []


static func load_default() -> GolferArt:
	return load(PATH) as GolferArt


func sheet(anim: Anim) -> TileSheet:
	match anim:
		Anim.WALK:
			return walk
		Anim.SWING:
			return swing
	return idle


## Frames per direction of `anim` (idle 2, walk 4, swing 6 in the spec).
func frames_per_dir(anim: Anim) -> int:
	return sheet(anim).frame_count() / DIRS.size()


## The frame name of direction index `dir` (DIRS) and frame `n`, wrapped into range.
func frame_name(anim: Anim, dir: int, n: int) -> StringName:
	return StringName("%s_%d" % [DIRS[posmod(dir, DIRS.size())], posmod(n, frames_per_dir(anim))])


## The texture of one frame, shared between every guest drawing it.
func frame(anim: Anim, dir: int, n: int) -> AtlasTexture:
	var fname := frame_name(anim, dir, n)
	var key := "%d/%s" % [anim, fname]
	if not _cache.has(key):
		_cache[key] = sheet(anim).atlas(fname)
	return _cache[key]


## The pixel of a frame that stands on the ground point (the feet).
func anchor() -> Vector2i:
	return idle.anchor


func shirt_count() -> int:
	return shirt_body.size()


## The shirt group `group_id` (its arrival order in the day) wears: the groups take the shirts
## in turn, so any `shirt_count()` groups in a row all differ. Groups never pass, so the groups
## on a hole and the next differ while those hold no more than `shirt_count()` (six: the most
## a backed-up day on the nine-hole fixture puts there, art/specs/golfer.md "Shirts").
func shirt_of_group(group_id: int) -> int:
	return posmod(group_id, maxi(shirt_count(), 1))


## The colour shirt `shirt` draws on sheet row `row` (the shader's rule, for tests and tools).
func shirt_color(shirt: int, row: int) -> Color:
	return shirt_trim[shirt] if _is_trim(shirt_pattern[shirt], row) else shirt_body[shirt]


func _is_trim(pattern: int, row: int) -> bool:
	match pattern:
		Pattern.HOOPS:
			return posmod(row, 2) == 1
		Pattern.YOKE:
			return row < yoke_row
	return false


## The material that dresses a figure in shirt `shirt`, shared by every figure wearing it.
func shirt_material(shirt: int) -> ShaderMaterial:
	if _shirt_materials.size() != shirt_count():
		_shirt_materials.clear()
		for i in shirt_count():
			var m := ShaderMaterial.new()
			m.shader = SHIRT_SHADER
			m.set_shader_parameter("key_color", shirt_key)
			m.set_shader_parameter("body_color", shirt_body[i])
			m.set_shader_parameter("trim_color", shirt_trim[i])
			m.set_shader_parameter("pattern", shirt_pattern[i])
			m.set_shader_parameter("yoke_row", yoke_row)
			_shirt_materials.append(m)
	return _shirt_materials[shirt]


## Rec. 601 luma of `c`, 0 to 255: how bright it reads in grayscale.
static func luma(c: Color) -> float:
	return 255.0 * (0.299 * c.r + 0.587 * c.g + 0.114 * c.b)


## The direction index (DIRS) of a screen vector `v` (x right, y down): the nearest of the
## eight, `s` straight down. A zero vector gives -1 (keep the last facing).
static func direction_of(v: Vector2) -> int:
	if v.length_squared() < 1e-9:
		return -1
	# Clockwise from down: s 0, sw 1 (down-left), w 2, ... se 7.
	var a := atan2(-v.x, v.y)
	return posmod(roundi(a / (TAU / 8.0)), 8)
