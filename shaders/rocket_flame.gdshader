// A rocket engine's exhaust plume on a cone hanging below the nozzle (y = 0.5 at the nozzle, y = -0.5 at the tail).
// Bright where you look through the middle of the plume, faint at its edges, with flowing turbulence
// and "shock diamonds": bright knots where the exhaust squeezes and expands as it leaves the nozzle.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.96, 0.82, 1.0);
uniform vec4 middle_color : source_color = vec4(1.0, 0.62, 0.18, 1.0);
uniform vec4 tail_color : source_color = vec4(0.85, 0.25, 0.05, 1.0);
uniform float brightness = 2.0;
uniform float diamonds = 0.5;       // how strong the shock diamonds are
uniform float diamond_count = 5.0;
uniform float turbulence = 0.4;
uniform float seed = 0.0;
uniform float vacuum = 0.0;          // 0 = thick air (a tight column of fire), 1 = space (a wide, faint glow)
uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap;
varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
	// With no air pressing on it, exhaust spreads out wide as soon as it leaves the nozzle
	float along = clamp(0.5 - VERTEX.y, 0.0, 1.0);
	float sea_level_radius = mix(1.0, 0.25, along);   // the cone's own shape
	float space_radius = 1.0 + along * 3.5;
	VERTEX.xz *= mix(sea_level_radius, space_radius, vacuum) / sea_level_radius;
}

void fragment() {
	float along = clamp(0.5 - local_position.y, 0.0, 1.0);   // 0 at the nozzle, 1 at the tail
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float thickness = pow(facing, 1.6);                          // looking through more hot gas in the middle
	float around = atan(local_position.x, local_position.z) / 6.2832;
	vec2 flow = vec2(around * 3.0 + seed, along * 2.2 - TIME * 3.0);
	float swirl = texture(noise_texture, flow).r;
	float fine = texture(noise_texture, flow * vec2(2.0, 3.0) + vec2(seed, -TIME * 2.5)).r;
	float noise_value = mix(1.0, swirl * 0.8 + fine * 0.5, turbulence);
	// (shock diamonds only form in air)
	float knots = pow(0.5 + 0.5 * cos(along * diamond_count * 6.2832), 8.0) * exp(-along * 3.0) * diamonds * smoothstep(0.55, 0.95, facing) * (1.0 - vacuum);
	vec3 color = mix(core_color.rgb, middle_color.rgb, smoothstep(0.0, 0.3, along));
	color = mix(color, tail_color.rgb, smoothstep(0.3, 0.95, along));
	float strength = pow(1.0 - along, mix(1.5, 3.2, vacuum)) * thickness * noise_value * mix(1.0, 0.45, vacuum);
	float flicker = 0.92 + 0.08 * sin(TIME * 53.0 + seed * 17.0);
	ALBEDO = (color * strength + core_color.rgb * knots) * brightness * mix(1.0, 0.35, vacuum) * flicker;
	ALPHA = clamp(strength + knots, 0.0, 1.0);
}
