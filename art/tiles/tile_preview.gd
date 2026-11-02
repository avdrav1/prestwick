class_name TilePreview
extends Node2D
## Test scene for the terrain placeholders (E1-S3), for scripts/screenshot.sh.
## STRIP draws each surface frame at 2x with its name. MAP draws a 9x9 patch, one strip per
## surface, on a stepped hill, so seams and risers show. Not the course renderer (E1-S4).

enum Show { STRIP, MAP }

const GRAYSCALE_SHADER: String = """
shader_type canvas_item;
void fragment() {
	float l = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = vec3(l);
}
"""
const MAP_SIZE: int = 9
const STRIP_SCALE: int = 2
const STRIP_STEP: int = 136

@export var show_what: Show = Show.STRIP
## Draws everything in luminance only, to check the colorblind patterns.
@export var grayscale: bool = false

var _art: TileArt


func _ready() -> void:
	_art = TileArt.load_default()
	if grayscale:
		var shader := Shader.new()
		shader.code = GRAYSCALE_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = shader
		material = mat
	queue_redraw()


func _draw() -> void:
	if _art == null:
		return
	if show_what == Show.STRIP:
		_draw_strip()
	else:
		_draw_map()


func _draw_strip() -> void:
	var sheet: TileSheet = _art.surfaces
	var font: Font = ThemeDB.fallback_font
	var size: Vector2 = Vector2(sheet.frame_size * STRIP_SCALE)
	for i: int in sheet.frame_count():
		var pos := Vector2(i * STRIP_STEP, 0)
		draw_texture_rect_region(sheet.texture, Rect2(pos, size), Rect2(sheet.region(i)))
		draw_string(font, pos + Vector2(0, size.y + 16), sheet.frames[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var risers: TileSheet = _art.risers
	for i: int in risers.frame_count():
		var pos := Vector2(i * STRIP_STEP, size.y + 32)
		draw_texture_rect_region(risers.texture, Rect2(pos, size), Rect2(risers.region(i)))
		draw_string(font, pos + Vector2(0, size.y + 16), "riser " + risers.frames[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14)


func _height(i: int, j: int) -> int:
	return maxi(0, 3 - maxi(absi(i - 4), absi(j - 4)))


func _center(i: int, j: int, h: int) -> Vector2:
	var half: Vector2 = Vector2(_art.surfaces.frame_size) / 2.0
	return Vector2((i - j) * half.x, (i + j) * half.y - h * _art.riser_px)


func _draw_map() -> void:
	var anchor := Vector2(_art.surfaces.anchor)
	var riser_region := Rect2(_art.risers.region_named(&"both"))
	# Painter's order: back to front by i + j, then each column bottom up.
	for depth: int in range(0, 2 * MAP_SIZE - 1):
		for i: int in MAP_SIZE:
			var j: int = depth - i
			if j < 0 or j >= MAP_SIZE:
				continue
			var h: int = _height(i, j)
			for k: int in h:
				draw_texture_rect_region(_art.risers.texture,
						Rect2(_center(i, j, k) - anchor, riser_region.size), riser_region)
			var surface: int = j % _art.surfaces.frame_count()
			var region := Rect2(_art.surfaces.region(surface))
			draw_texture_rect_region(_art.surfaces.texture,
					Rect2(_center(i, j, h) - anchor, region.size), region)
