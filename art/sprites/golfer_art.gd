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

## {"<anim>/<frame name>": AtlasTexture}, built on first use.
var _cache: Dictionary = {}


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


## The direction index (DIRS) of a screen vector `v` (x right, y down): the nearest of the
## eight, `s` straight down. A zero vector gives -1 (keep the last facing).
static func direction_of(v: Vector2) -> int:
	if v.length_squared() < 1e-9:
		return -1
	# Clockwise from down: s 0, sw 1 (down-left), w 2, ... se 7.
	var a := atan2(-v.x, v.y)
	return posmod(roundi(a / (TAU / 8.0)), 8)
