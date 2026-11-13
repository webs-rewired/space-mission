// The glow of a world's air around its edge, brightest on the side the Sun lights.
// outer_amount adds a thin second layer just outside it: Titan's blue haze layer, which Cassini photographed
// floating above the orange smog.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

uniform vec4 glow_color : source_color = vec4(0.4, 0.6, 1.0, 1.0);
uniform vec4 outer_color : source_color = vec4(0.45, 0.55, 1.0, 1.0);
uniform float outer_amount = 0.0;
uniform float strength = 1.0;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);   // from the world toward the Sun

void fragment() {
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float daylight = smoothstep(-0.35, 0.3, dot(world_normal, sun_direction));
	vec3 glow = glow_color.rgb * pow(edge, 3.0) * strength;
	glow += outer_color.rgb * smoothstep(0.78, 0.96, edge) * outer_amount;
	ALBEDO = glow * (0.06 + 0.94 * daylight);
}
