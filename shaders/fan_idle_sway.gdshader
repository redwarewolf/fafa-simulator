shader_type canvas_item;

// Subtle vertical "breathing" for tribune fans: stretches/shrinks a few
// percent, anchored at the sprite's BASE (bottom edge stays fixed, top
// moves). pivot_y is the local-space Y of that bottom edge
// (region_rect.size.y/2 for a centered Sprite2D) — set from GDScript since
// the shader has no way to know the mesh's own extents. time_offset
// randomizes each fan's phase so a whole tribune doesn't sway in lockstep.

uniform float amplitude : hint_range(0.0, 0.3) = 0.03; // fraction of height, ~5-10%
uniform float speed : hint_range(0.0, 5.0) = 3.0;
uniform float time_offset : hint_range(0.0, 6.2832) = 0.0;
uniform float pivot_y = 98.5; // local Y of the fixed base edge

// Recolors the source art's red/white kit (stripes, scarf, cap) to the home
// club's colors. Matched by hue/saturation/value range rather than exact hex
// so it survives the art's shading gradients and per-fan lighting glow —
// skin, hair and the background vignette fall outside these ranges and pass
// through untouched. Defaults match the original red/white so fans look
// unchanged until a club's colors are explicitly applied.
group_uniforms Recolor;
uniform vec4 primary_color   : source_color = vec4(0.75, 0.15, 0.17, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.95, 0.93, 0.9, 1.0);
group_uniforms;

// Measured off tribune-fans.png directly: shirt-red pixels sit within
// hue-distance 0.015 of pure red at sat >=0.5; skin highlights start at
// hue-distance 0.037 (sat ~0.5-0.6) and the red-haired variant's hair
// starts at 0.016 — tight, but there's no wider gap available in this art
// without a hand-authored mask. Tuned narrow on purpose to keep skin/hair
// out even at the cost of missing a few heavily anti-aliased stripe edges.
const float RED_HUE_TOLERANCE = 0.018;
const float RED_SAT_MIN = 0.5;
const float RED_VAL_MIN = 0.2;
const float WHITE_SAT_MAX = 0.26;
const float WHITE_VAL_MIN = 0.55;

// Optional per-seat hair recolor, set by TribuneSection.gd only for the two
// variations whose hair is colorimetrically separable from skin in this art
// (blonde and the redhead — brown/black hair overlaps skin's hue/sat/value
// range too closely to isolate safely, so those variations are left alone).
// Thresholds are measured off tribune-fans.png: skin never exceeds hue-dist
// 0.066 or saturation 0.69 anywhere sampled, so each band below is kept
// clear of that ceiling.
group_uniforms Hair;
uniform int hair_variant : hint_enum("None", "Blonde", "Redhead") = 0;
uniform vec4 hair_color : source_color = vec4(1.0);
group_uniforms;

const float BLONDE_HUE_DIST_MIN = 0.07;
const float BLONDE_HUE_DIST_MAX = 0.12;
const float BLONDE_SAT_MIN = 0.5;
const float REDHEAD_HUE_DIST_MIN = 0.02;
const float REDHEAD_HUE_DIST_MAX = 0.055;
const float REDHEAD_SAT_MIN = 0.72;

// Per-seat random skin tone. Skin and brown/black hair share the same
// hue/sat/value range in this art (same reason most hair can't be
// recolored), so color alone can't isolate skin. Instead this pairs the
// skin hue/sat/value range with two UV boxes hand-checked against all 8 fan
// variations, so the mask holds regardless of which column/hair_variant is
// showing:
//   FACE — narrow enough to clear every variation's side hair, and spanning
//          y=54..109 of 197: the earliest forehead across all eight columns
//          starts at y=55, and the neck runs to the collar at ~109. Starting
//          any higher recolors the hairline (brown hair sits inside the skin
//          color range); stopping any earlier leaves the jaw and neck pale.
//   ARMS — full width, starting below y=148/197, where the longest hair in
//          the sheet already ends and the resting forearms begin. Without it
//          the hands stay pale while the face darkens.
// Shirts don't need excluding here: the kit branches above claim red/white
// first, and the dark/gray hoodies fall outside the sat/value range below.
group_uniforms Skin;
uniform vec4 skin_color : source_color = vec4(1.0);
group_uniforms;

const vec2 SKIN_BOX_MIN = vec2(0.232, 0.274);
const vec2 SKIN_BOX_MAX = vec2(0.744, 0.556);
const vec2 ARM_BOX_MIN = vec2(0.0, 0.751);
const vec2 ARM_BOX_MAX = vec2(1.0, 1.0);
const float SKIN_HUE_DIST_MAX = 0.09;
const float SKIN_SAT_MIN = 0.25;
const float SKIN_SAT_MAX = 0.75;
const float SKIN_VAL_MIN = 0.2;

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

void vertex() {
	float stretch = 1.0 + sin(TIME * speed + time_offset) * amplitude;
	VERTEX.y = pivot_y - (pivot_y - VERTEX.y) * stretch;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	if (tex.a < 0.01) {
		COLOR = tex;
	} else {
		vec3 hsv = rgb2hsv(tex.rgb);
		float hue_dist_from_red = min(hsv.x, 1.0 - hsv.x);
		bool is_red = hue_dist_from_red <= RED_HUE_TOLERANCE && hsv.y >= RED_SAT_MIN && hsv.z >= RED_VAL_MIN;
		bool is_white = hsv.y <= WHITE_SAT_MAX && hsv.z >= WHITE_VAL_MIN;

		if (is_red) {
			vec3 target_hsv = rgb2hsv(primary_color.rgb);
			// Keep the pixel's own value so shading/highlights survive; blend
			// saturation toward the target so muted club colors stay muted.
			vec3 new_hsv = vec3(target_hsv.x, mix(hsv.y, target_hsv.y, 0.6), hsv.z);
			COLOR = vec4(hsv2rgb(new_hsv), tex.a);
		} else if (is_white) {
			// Treat the white area as a brightness mask over the target color.
			COLOR = vec4(secondary_color.rgb * hsv.z, tex.a);
		} else {
			bool is_hair = false;
			if (hair_variant == 1) {
				is_hair = hue_dist_from_red >= BLONDE_HUE_DIST_MIN && hue_dist_from_red <= BLONDE_HUE_DIST_MAX && hsv.y >= BLONDE_SAT_MIN;
			} else if (hair_variant == 2) {
				is_hair = hue_dist_from_red >= REDHEAD_HUE_DIST_MIN && hue_dist_from_red <= REDHEAD_HUE_DIST_MAX && hsv.y >= REDHEAD_SAT_MIN;
			}

			bool in_face_box = UV.x >= SKIN_BOX_MIN.x && UV.x <= SKIN_BOX_MAX.x && UV.y >= SKIN_BOX_MIN.y && UV.y <= SKIN_BOX_MAX.y;
			bool in_arm_box = UV.x >= ARM_BOX_MIN.x && UV.x <= ARM_BOX_MAX.x && UV.y >= ARM_BOX_MIN.y && UV.y <= ARM_BOX_MAX.y;
			bool is_skin = (in_face_box || in_arm_box) && hue_dist_from_red <= SKIN_HUE_DIST_MAX && hsv.y >= SKIN_SAT_MIN && hsv.y <= SKIN_SAT_MAX && hsv.z >= SKIN_VAL_MIN;

			if (is_hair) {
				vec3 target_hsv = rgb2hsv(hair_color.rgb);
				vec3 new_hsv = vec3(target_hsv.x, mix(hsv.y, target_hsv.y, 0.6), hsv.z);
				COLOR = vec4(hsv2rgb(new_hsv), tex.a);
			} else if (is_skin) {
				vec3 target_hsv = rgb2hsv(skin_color.rgb);
				// Unlike the kit/hair swaps, also blend value toward the target so a
				// dark tone actually reads darker — full value preservation would
				// just tint the original art's brightness instead of shifting it.
				vec3 new_hsv = vec3(target_hsv.x, mix(hsv.y, target_hsv.y, 0.6), mix(hsv.z, target_hsv.z, 0.6));
				COLOR = vec4(hsv2rgb(new_hsv), tex.a);
			} else {
				COLOR = tex;
			}
		}
	}
}
