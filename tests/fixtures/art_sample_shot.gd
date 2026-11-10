class_name ArtSampleShot
extends Node2D
## Screenshot fixture for E5-S1 (docs/playtests/2026-11-10-e5-art-options.md): the playtest nine
## shot (tests/fixtures/playtest_nine_shot.tscn, its PLAYTEST_* variables) with ART_SAMPLE=1
## drawing the procedural fairway sample (scripts/art_sample.py,
## art/tiles/surfaces_sample_procedural.png) in Play in place of the placeholder. Unset, it is the
## placeholder, for the picture beside it.
##   ART_SAMPLE=1 PLAYTEST_SHOT=play:1 PLAYTEST_ZOOM=1 scripts/screenshot.sh tests/fixtures/art_sample_shot.tscn

const SHOT_SCENE: String = "res://tests/fixtures/playtest_nine_shot.tscn"
const SAMPLE_PATH: String = "res://art/tiles/surfaces_sample_procedural.png"

## Held so the cached TileArt (and the texture swapped into it) lives until the course view loads it.
var _art: TileArt


func _ready() -> void:
	if OS.get_environment("ART_SAMPLE") == "1":
		_art = TileArt.load_default()
		_art.surfaces.play_texture = load(SAMPLE_PATH) as Texture2D
	add_child((load(SHOT_SCENE) as PackedScene).instantiate())
