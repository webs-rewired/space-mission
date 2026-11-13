// The edge of the rover's planned driving area: a see-through curtain of slow amber warning stripes.
// It only shows near the rover, so the landscape stays clear until you actually reach the edge.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 line_color : source_color = vec4(1.0, 0.68, 0.2, 1.0);
uniform vec3 rover_position = vec3(0.0);
uniform float show_distance = 75.0;      // how near the rover has to be before the curtain appears (meters)
uniform float stripes_around = 420.0;    // how many stripes go around the whole circle

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float away = distance(world_position.xz, rover_position.xz);
	float near = 1.0 - smoothstep(show_distance * 0.4, show_distance, away);
	float height = world_position.y - rover_position.y;
	// Brightest near the ground, fading out above the rover and below it
	float band = smoothstep(-4.0, -0.5, height) * (1.0 - smoothstep(1.5, 12.0, height));
	float stripe = step(0.5, fract(UV.x * stripes_around + height * 0.35 - TIME * 0.25));
	float ground_line = 1.0 - smoothstep(0.0, 0.35, abs(height));
	ALBEDO = line_color.rgb;
	ALPHA = clamp(near * (band * (0.08 + 0.3 * stripe) + ground_line * 0.7), 0.0, 0.9);
}
