shader_type canvas_item;

// Colour grade for the whole scene. Happy Hour pushes saturation ABOVE 1 and
// lifts exposure, so the beach goes lurid and club-lit rather than drained.
//
// A plain overlay cannot do this: adding colour washes bright sand toward white
// and leaves dark water untouched. Pushing each pixel further from its own
// luminance boosts what is already there, so sand, surf and sea all intensify.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

// 1.0 = untouched. Below 1 drains toward grey, above 1 oversaturates.
uniform float saturation : hint_range(0.0, 3.0) = 1.0;
// Added after saturation. Negative darkens, positive lifts.
uniform float exposure : hint_range(-1.0, 1.0) = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	// Rec.601 luma: green carries most of perceived brightness, so a flat
	// average would push the sand far harder than the sea.
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c += exposure;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
