shader_type canvas_item;

// Set to true to paint all opaque pixels bright magenta — confirms the shader is active.
uniform bool debug_mode = false;

// Sampled the same way as the working player palette shader:
// no source_color hint so Godot treats both TEXTURE and pixelsheet identically.
uniform sampler2D pixelsheet : filter_nearest, repeat_disable;

uniform vec4 primary_color   : source_color = vec4(1.0);
uniform vec4 secondary_color : source_color = vec4(1.0);
uniform float shade_factor : hint_range(0.0, 1.0) = 0.35;

const float EPSILON = 0.12;

bool color_match(vec4 a, vec4 b) {
	return length(a.rgb - b.rgb) < EPSILON;
}

void fragment() {
	vec4 pixel = COLOR;

	if (pixel.a < 0.01) {
		COLOR = pixel;
	} else if (debug_mode) {
		COLOR = vec4(1.0, 0.0, 1.0, pixel.a);
	} else {
		// Sample reference rows from the 1x3 pixelsheet
		vec4 shade_ref   = texture(pixelsheet, vec2(0.5, 0.5 / 3.0));
		vec4 primary_ref = texture(pixelsheet, vec2(0.5, 1.5 / 3.0));
		vec4 second_ref  = texture(pixelsheet, vec2(0.5, 2.5 / 3.0));

		vec4 shade_out = vec4(mix(primary_color.rgb, vec3(0.0), shade_factor), primary_color.a);

		if (color_match(pixel, shade_ref)) {
			COLOR = shade_out;
		} else if (color_match(pixel, primary_ref)) {
			COLOR = primary_color;
		} else if (color_match(pixel, second_ref)) {
			COLOR = secondary_color;
		} else {
			COLOR = pixel;
		}
	}
}
