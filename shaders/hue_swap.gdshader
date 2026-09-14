shader_type canvas_item;

// Recolours one narrow hue band in a sprite, leaving everything else alone.
// Used for the rain jacket: the same walking art with its yellow hi-vis turned
// red, with no second set of textures to author, slice or keep in sync.
//
// Measured from the sprites, and the window is TIGHT for a reason:
//
//   skin           21-33 deg
//   tool handle    30-47 deg
//   VEST           50-58 deg   <- the only thing that should change
//   backpack       60-73 deg
//
// A generous window catches the olive backpack and the wooden handle, which
// both turn red and look like a bug. Saturation gating additionally protects
// the pale reflective stripes, which are near-white and should stay that way.

uniform bool enabled = false;
uniform float hue_min : hint_range(0.0, 1.0) = 0.139;    // 50 deg
uniform float hue_max : hint_range(0.0, 1.0) = 0.164;    // 59 deg
uniform float target_hue : hint_range(0.0, 1.0) = 0.985; // red
uniform float min_sat : hint_range(0.0, 1.0) = 0.60;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (enabled && tex.a > 0.0) {
		vec3 hsv = rgb2hsv(tex.rgb);
		if (hsv.x >= hue_min && hsv.x <= hue_max && hsv.y >= min_sat) {
			hsv.x = target_hue;
			// Nudge saturation up: red at the vest's original saturation reads
			// muddy next to the dark shorts, where yellow read as bright.
			hsv.y = min(1.0, hsv.y * 1.08);
			tex.rgb = hsv2rgb(hsv);
		}
	}
	COLOR = tex * COLOR;
}
