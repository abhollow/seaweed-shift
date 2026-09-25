shader_type canvas_item;

// Darkness over the playable beach, with pools of light cut out of it: the
// worker's lantern, tourists' phones, the resort's torches and the lit bay.
//
// The light falls off in a few hard BANDS rather than a smooth gradient, on a
// 2px grid -- the retro way to draw a lantern, and it keeps the darkness
// looking like part of the pixel art rather than a filter laid over it.

uniform vec3 lights[24];          // x, y, radius -- in world px
uniform int light_count = 0;
uniform float darkness = 0.86;
uniform float top_y = 180.0;      // the fog fades in below this row
uniform vec2 rect_size = vec2(360.0, 640.0);

void fragment() {
	vec2 p = floor(UV * rect_size / 2.0) * 2.0;
	float lit = 0.0;
	for (int i = 0; i < 24; i++) {
		if (i >= light_count) {
			break;
		}
		vec3 L = lights[i];
		float d = distance(p, L.xy);
		lit = max(lit, 1.0 - smoothstep(L.z * 0.45, L.z, d));
	}
	lit = floor(lit * 4.0 + 0.5) / 4.0;
	// The resort band is already painted as night, with its own glowing
	// lights; darkness fades in only below it, over the playable beach.
	float top = smoothstep(top_y - 30.0, top_y + 10.0, p.y);
	COLOR = vec4(0.01, 0.02, 0.07, darkness * (1.0 - lit) * top);
}
