// The cloud that flashes around a rocket as it passes the speed of sound: the air pressure drops so sharply
// behind the shock wave that water vapor condenses into a cone of mist for a moment.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform float amount = 1.0;   // 1 = just formed, 0 = gone

void fragment() {
	// Thickest at the wide trailing edge, wispy toward the front, with soft streaks around it
	float along = UV.y;
	float streaks = 0.75 + 0.25 * sin(UV.x * 90.0 + along * 12.0);
	float edge_on = pow(1.0 - abs(dot(NORMAL, VIEW)), 0.6);
	ALBEDO = vec3(1.0);
	ALPHA = clamp(amount * smoothstep(0.0, 0.5, along) * (1.0 - smoothstep(0.8, 1.0, along)) * streaks * (0.2 + 0.4 * edge_on), 0.0, 0.6);
}
