shader_type canvas_item;

// Variant of replace_color.gdshader for the referee: skin and hair still use
// the normal palette-swap system (see Referee._apply_random_look), but
// clothing (shirt/shorts/boots — whatever the team_palette's reference row
// would normally recolor per-club) is remapped to grayscale by luminance
// instead, so the referee reads as a neutral black-and-white kit no matter
// which two teams are playing.
group_uniforms Palettes;
uniform sampler2D team_palette : filter_nearest;
uniform sampler2D skin_palette : filter_nearest;
uniform sampler2D hair_palette : filter_nearest;
group_uniforms;

uniform int skin_color : hint_enum("Light", "Medium", "Dark", "Radioactive", "Demonic", "Alien", "Robot");
uniform int hair_color : hint_enum("Blonde", "LightRed", "Green", "Purple", "LightBrown", "DarkBrown", "Gray", "DarkRed", "Black", "DarkBlue", "LightBlue");

uniform vec4 shadow_color : source_color = vec4(0.08, 0.08, 0.09, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.92, 0.92, 0.94, 1.0);

vec2 px_to_uv(ivec2 pos, ivec2 tex_size) {
	return vec2(
		(float(pos[0]) + 0.5) / float(tex_size[0]),
		(float(pos[1]) + 0.5) / float(tex_size[1])
		);
}

vec4 get_palette_color(vec4 color, sampler2D palette, int selection){
	ivec2 tex_size = textureSize(palette, 0);
	for (int i=0; i < tex_size[0]; i++){
		vec2 uv_color_ref = px_to_uv(ivec2(i,0), tex_size);
		vec4 color_ref = texture(palette, uv_color_ref);
		if (color == color_ref){
			vec2 uv_color_dest = px_to_uv(ivec2(i,selection), tex_size);
			return texture(palette,uv_color_dest);
		}
	}
	return color;
}

// Clothing pixels are exactly the ones team_palette's reference row would
// otherwise recolor per-club — detect membership the same way
// get_palette_color does, but map by luminance instead of a palette lookup.
bool is_clothing_color(vec4 color, sampler2D palette) {
	ivec2 tex_size = textureSize(palette, 0);
	for (int i=0; i < tex_size[0]; i++){
		vec2 uv_color_ref = px_to_uv(ivec2(i,0), tex_size);
		if (color == texture(palette, uv_color_ref)){
			return true;
		}
	}
	return false;
}

void fragment() {
	COLOR = texture(TEXTURE, UV);
	if (is_clothing_color(COLOR, team_palette)) {
		float luminance = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
		COLOR = vec4(mix(shadow_color.rgb, highlight_color.rgb, smoothstep(0.1, 0.7, luminance)), COLOR.a);
	} else {
		if (skin_color > 0) {
			COLOR = get_palette_color(COLOR, skin_palette, skin_color);
		}
		if (hair_color > 0) {
			COLOR = get_palette_color(COLOR, hair_palette, hair_color);
		}
	}
}
