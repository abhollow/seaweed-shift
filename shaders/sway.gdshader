shader_type canvas_item;

// Makes the painted palms, flags and kites on a background move in the wind.
//
// They are part of the background image, so they cannot be animated as sprites.
// Instead, pixels marked in sway_mask are shifted sideways over time. The shift
// is a steady LEAN downwind plus a wobble, and both grow with the current gust --
// so the palms whip hardest exactly when a gust shoves the player.
//
// PHASE, not time. The first version passed elapsed seconds and computed
// sin(t * speed). Two things went wrong as t grew: phone GPUs often run
// fragment shaders at reduced precision, so a large t could only change in
// coarse jumps and the sway stuttered to a halt a few minutes in; and changing
// the speed in a gust with a large t jumped the phase wildly, turning gusts into
// flicker. The phase is now accumulated on the CPU and wrapped to 0..2pi, so the
// shader only ever sees a small number and speed changes are smooth.
//
// Displacement is in texels and the texture is sampled nearest, so motion comes
// in whole-pixel steps: it sways like pixel art rather than smearing like video.

uniform sampler2D sway_mask : filter_linear;
uniform float phase = 0.0;      // radians, always 0..2pi
uniform float gust = 0.0;       // 0 calm .. 1 peak of a gust
uniform float lean = 1.0;       // steady downwind lean, texels
uniform float amp = 1.4;        // wobble, texels
uniform float tex_w = 180.0;    // background width in texels

void fragment() {
	float m = texture(sway_mask, UV).r;
	vec4 c = texture(TEXTURE, UV);
	if (m > 0.02) {
		// Offset varies across and down the image, so neighbouring palms and
		// the fronds within one palm never move in lockstep.
		float wob = sin(phase + UV.x * 38.0 + UV.y * 22.0);
		float d = m * (lean * (1.0 + 1.6 * gust) + amp * (0.8 + 1.0 * gust) * wob);
		// Sample from the LEFT to move content right -- downwind.
		c = texture(TEXTURE, UV - vec2(d / tex_w, 0.0));
	}
	COLOR = c;
}
