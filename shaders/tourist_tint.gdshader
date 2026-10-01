shader_type canvas_item;

// Recolours a tourist's clothes -- the pink shirts and red shorts/bikinis --
// so one set of sprites gives a crowd in several colours. Rotates the hue of
// that band only, so the shading and pattern inside the clothes survive.
//
// Measured from the sprites: clothes sit at 300-4 deg, skin at 8-30 deg. The
// drunk tourists' flushed faces fall in the clothes band too, so the top of
// each frame (the head) is never touched; every frame, walking or wading, has
// its head in the top third.

uniform float hue_offset = 0.0;                          // 0..1 turn of the colour wheel
uniform float hue_lo : hint_range(0.0, 1.0) = 0.833;     // 300 deg
uniform float hue_hi : hint_range(0.0, 1.0) = 0.011;     // 4 deg (the band wraps past 0)
uniform float min_sat : hint_range(0.0, 1.0) = 0.35;
uniform float head_cut : hint_range(0.0, 1.0) = 0.32;

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
	if (hue_offset != 0.0 && tex.a > 0.0 && UV.y >= head_cut) {
		vec3 hsv = rgb2hsv(tex.rgb);
		if ((hsv.x >= hue_lo || hsv.x <= hue_hi) && hsv.y >= min_sat) {
			hsv.x = fract(hsv.x + hue_offset);
			tex.rgb = hsv2rgb(hsv);
		}
	}
	COLOR = tex * COLOR;
}
