shader_type canvas_item;

// The tutorial's dimmer: darkens the whole screen except up to two holes, each
// a circle or a rounded rectangle, with a soft edge so it reads as a light
// rather than a cut-out.

uniform vec4 hole_a = vec4(0.0);    // x, y, w, h in screen px; w <= 0 means no hole
uniform float circle_a = 0.0;       // 1 = circle/ellipse, 0 = rounded rectangle
uniform vec4 hole_b = vec4(0.0);
uniform float circle_b = 0.0;
uniform float dim = 0.64;
uniform vec2 size = vec2(360.0, 640.0);

float box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float hole(vec2 p, vec4 h, float circ) {
	if (h.z <= 0.0) {
		return 1.0e5;
	}
	vec2 half_size = h.zw * 0.5;
	vec2 c = h.xy + half_size;
	if (circ > 0.5) {
		float r = min(half_size.x, half_size.y);
		return length((p - c) / half_size) * r - r;
	}
	return box(p - c, half_size, 8.0);
}

void fragment() {
	vec2 p = UV * size;
	float d = min(hole(p, hole_a, circle_a), hole(p, hole_b, circle_b));
	COLOR = vec4(0.016, 0.03, 0.055, dim * smoothstep(-1.0, 4.0, d));
}
