shader_type canvas_item;

// Recolours a seaweed sprite as sargassum: its greens are remapped onto a
// golden-orange ramp by brightness, and the dark outline is left alone.
//
// Not a colour-multiply tint. Multiplying green by brown just looks muddy --
// and brown is how ROTTING seaweed already looks, so a muddy sargassum would be
// mistaken for rot. Gold keeps it bright and clearly its own thing.

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.g > c.r + 0.03 && c.g >= c.b) {
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		float t = clamp(l * 1.6, 0.0, 1.0);
		// Deep amber rather than straw gold: the first ramp was too close to
		// Mahahual's pale golden sand, and sargassum rots fast, so it has to
		// be spotted quickly.
		vec3 dark = vec3(0.30, 0.13, 0.03);
		vec3 mid = vec3(0.74, 0.38, 0.07);
		vec3 light = vec3(0.98, 0.66, 0.20);
		c.rgb = t < 0.5 ? mix(dark, mid, t * 2.0) : mix(mid, light, (t - 0.5) * 2.0);
	}
	COLOR = c * COLOR;
}
