shader_type canvas_item;

// Adds pseudo-random patchiness to a baked grass texture: soft large-scale
// patches (worn dirt / longer grass) plus fine per-pixel grain, both snapped
// to the project's nearest-filter pixel-art look. Only affects green-ish
// pixels so painted lines and goal areas stay untouched.

uniform float patch_frequency : hint_range(1.0, 30.0) = 3.0;
uniform float patch_strength : hint_range(0.0, 1.0) = 0.12;
uniform float grain_pixel_size : hint_range(1.0, 16.0) = 3.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.08;
uniform float green_threshold : hint_range(0.0, 0.2) = 0.05;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;

	float greenness = base.g - max(base.r, base.b);
	float is_grass = smoothstep(0.0, green_threshold, greenness);

	float patch = value_noise(UV * vec2(patch_frequency, patch_frequency * tex_size.y / tex_size.x));
	float patch_signed = (patch - 0.5) * 2.0;

	vec2 grain_uv = floor(UV * tex_size / grain_pixel_size);
	float grain = hash21(grain_uv);
	float grain_signed = (grain - 0.5) * 2.0;

	float variation = (patch_signed * patch_strength + grain_signed * grain_strength) * is_grass;

	vec3 color = base.rgb * (1.0 + variation);
	color.r += variation * 0.02;

	COLOR = vec4(clamp(color, 0.0, 1.0), base.a);
}
