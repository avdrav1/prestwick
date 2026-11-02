class_name Surface
extends RefCounted
## The surface enum every system shares. Values are course format version 1:
## they are the low nibble of each tile byte, so never reorder or renumber them.
## Reference as `Surface.Type.GREEN`.

enum Type { FAIRWAY, ROUGH, GREEN, TEE, BUNKER, WATER, TREES, CART_PATH, OOB }

## Number of surfaces, including oob. Valid values are 0 to COUNT - 1.
const COUNT: int = 9

## Lowercase names as written in docs and course files, indexed by Type.
const NAMES: PackedStringArray = [
	"fairway", "rough", "green", "tee", "bunker", "water", "trees", "cart_path", "oob",
]


static func is_valid(value: int) -> bool:
	return value >= 0 and value < COUNT


## "cart_path" for Type.CART_PATH; "" for an invalid value.
static func name_of(value: int) -> String:
	return NAMES[value] if is_valid(value) else ""


## Type for a lowercase name, or -1 when unknown.
static func from_name(surface_name: String) -> int:
	return NAMES.find(surface_name)
