class_name TerrainTuning
extends Resource
## Designer-tuned numbers for the smooth ground the course view draws (E3-S58, D50,
## course/terrain_mesh.gd). Loaded from res://course/terrain_tuning.tres.

const PATH: String = "res://course/terrain_tuning.tres"

## Cuts a side on a sloped tile: the mesh's grid there is subdiv x subdiv, so its vertices lie
## on the tile centre lines (where the bilinear ground creases) and on its edges. Even, 2 or
## more. A flat tile is one fan whatever this is.
@export_range(2, 8, 2) var subdiv: int = 4
## Where the light comes from across the ground, x and y along the tile axes (the camera looks
## from +x +y, so -x -y is behind the hills from the player). Need not be unit length.
@export var light_dir: Vector2 = Vector2(-1.0, -0.8)
## How strongly a slope's facing changes its shade: shade = 1 + strength * (n.x, n.y) . L, n the
## ground's unit normal and L the unit light_dir, so flat ground is 1 (draws as before), a slope
## turned toward the light is lighter and one turned away as much darker.
@export var light_strength: float = 0.5
## The shade is held between these, so a steep face never goes black or white.
@export var light_min: float = 0.55
@export var light_max: float = 1.25
## The map's side faces (its two edges toward the camera) and the bank where land meets water
## at another height: this colour, shaded by the face's facing as the ground is.
@export var side_color: Color = Color8(122, 86, 58)
## The side faces reach down to this height, steps (0: the old risers' base).
@export var base_steps: float = 0.0
## Tiles a side of each drawn chunk along a depth row: an edit rebuilds only the chunks round it.
@export var chunk_tiles: int = 8


static func load_default() -> TerrainTuning:
	return load(PATH) as TerrainTuning
