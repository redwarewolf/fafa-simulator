shader_type canvas_item;

// UI palette: 6 columns x 5 rows
// Rows: 0=border, 1=corner, 2=light, 3=main, 4=dark
// Columns: 0=general, 1=common, 2=uncommon, 3=rare, 4=epic, 5=legendary
// Column 1 is the source (grey scale matching UI_Frame.png)

uniform sampler2D ui_palette;
uniform int quality_tier : hint_range(0, 5, 1) = 0;

vec2 px_to_uv(ivec2 pos, ivec2 tex_size) {
	return vec2(
		(float(pos[0]) + 0.5) / float(tex_size[0]),
		(float(pos[1]) + 0.5) / float(tex_size[1])
	);
}

vec4 get_ui_color(vec4 col, sampler2D palette, int target_col) {
	ivec2 tex_size = textureSize(palette, 0);
	for (int row = 0; row < tex_size[1]; row++) {
		vec2 uv_src = px_to_uv(ivec2(1, row), tex_size);
		vec4 src = texture(palette, uv_src);
		if (distance(col.rgb, src.rgb) < 0.01) {
			vec2 uv_dst = px_to_uv(ivec2(target_col, row), tex_size);
			return texture(palette, uv_dst);
		}
	}
	return col;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	COLOR = get_ui_color(base, ui_palette, quality_tier);
}
