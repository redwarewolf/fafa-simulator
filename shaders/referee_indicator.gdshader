shader_type canvas_item;

// Recolors the two-tone red player-indicator arrow (1p.png) into a neutral
// gray so the same art can mark the referee without reading as "team 1".
// Maps by luminance rather than exact color match so it still works if the
// source art gains anti-aliased edges later.
uniform vec4 shadow_color : source_color = vec4(0.42, 0.42, 0.46, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.82, 0.82, 0.86, 1.0);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float luminance = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(shadow_color.rgb, highlight_color.rgb, smoothstep(0.2, 0.3, luminance)), tex_color.a);
}
