// The parachute's suspension lines: thin lines on a see-through cone, from the canopy's rim down to the capsule.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float line_count = 24.0;

void fragment() {
	float around = fract(UV.x * line_count);
	float line = smoothstep(0.08, 0.0, abs(around - 0.5) - 0.42);
	ALBEDO = vec3(0.85, 0.83, 0.78);
	ALPHA = line * 0.8;
}
