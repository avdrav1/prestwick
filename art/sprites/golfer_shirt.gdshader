// E3-S28: dresses a golfer frame in its group's shirt (art/specs/golfer.md "Shirts").
// The sheets draw the shirt in one key colour (chalk); every key pixel becomes the body
// colour, or the trim on the rows the pattern picks (GolferArt.shirt_color is the same rule).
// Rows are sheet rows: the sheets are one row of frames, so a sheet row is a frame row.
// No colour hints: 2D draws in sRGB, so the texture and the uniforms compare as they are.
// The texture is multiplied in once (E3-S28 review): in a canvas_item fragment() COLOR
// already holds the vertex colour times the TEXTURE sample, so the vertex colour (the
// modulate) is kept from vertex() and the swapped texel is multiplied by it alone.
// scripts/shirt_render_check.gd renders every shirt and checks the pixels are exact.
shader_type canvas_item;

uniform vec4 key_color;
uniform vec4 body_color;
uniform vec4 trim_color;
// GolferArt.Pattern: 0 plain, 1 hoops (odd rows), 2 yoke (rows above yoke_row).
uniform int pattern = 0;
uniform int yoke_row = 12;

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a > 0.5 && distance(c.rgb, key_color.rgb) < 0.02) {
		int row = int(floor(UV.y / TEXTURE_PIXEL_SIZE.y));
		bool trim = (pattern == 1 && row % 2 == 1) || (pattern == 2 && row < yoke_row);
		c.rgb = trim ? trim_color.rgb : body_color.rgb;
	}
	COLOR = c * modulate;
}
