shader_type canvas_item;

// Recolours a tourist's outfit -- like Photoshop's Replace Color with two
// samples: the pink shirts and the red shorts/swimwear. Matching pixels are
// turned to one target colour, keeping their shading; nothing else is touched.
// One set of sprites gives a crowd in several colours.
//
// Selection, measured from the sprites:
//   * PINK (330): fully recoloured within 15 deg, fading out by 22;
//   * RED (356): fully within 6 deg, fading out by 10 -- tight, because skin
//     starts around 8-10 deg;
//   * red is never taken from the head (top third of the frame): the drunk
//     tourists' flushed faces are exactly that red;
//   * dark and near-grey pixels are never touched: the outlines and shadows
//     round the skin are a dark, saturated red.
// Both samples land on the same target hue, so the outfit is one colour.

uniform float target = 330.0;                     // outfit colour, degrees
uniform float pink = 330.0;
uniform float red = 356.0;
uniform float head_cut = 0.32;

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

float hue_dist(float a, float b) {
	return abs(mod(a - b + 180.0, 360.0) - 180.0);
}

void fragment() {
	// COLOR arrives as the texture already multiplied by the modulate. Sampling
	// TEXTURE again and multiplying by COLOR would square every channel.
	vec4 tex = COLOR;
	if (tex.a > 0.0) {
		vec3 hsv = rgb2hsv(tex.rgb);
		float h = hsv.x * 360.0;
		float gate = smoothstep(0.25, 0.4, hsv.y) * smoothstep(0.2, 0.32, hsv.z);
		float wp = (1.0 - smoothstep(15.0, 22.0, hue_dist(h, pink))) * gate;
		float wr = (1.0 - smoothstep(6.0, 10.0, hue_dist(h, red))) * gate * step(head_cut, UV.y);
		float w = max(wp, wr);
		if (w > 0.0) {
			float from = wp >= wr ? pink : red;
			float nh = fract((target + (h - from)) / 360.0);
			tex.rgb = mix(tex.rgb, hsv2rgb(vec3(nh, hsv.y, hsv.z)), w);
		}
	}
	COLOR = tex;
}
