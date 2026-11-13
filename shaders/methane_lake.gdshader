// A lake of liquid methane and ethane on Titan: almost black, glassy smooth (Cassini's radar saw ripples only
// millimeters high), mirroring the orange sky.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 liquid_color : source_color = vec3(0.04, 0.03, 0.02);
uniform sampler2D ripple_noise : repeat_enable, filter_linear_mipmap;

void fragment() {
	vec2 place = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	ALBEDO = liquid_color;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	vec2 drift = vec2(TIME * 0.004, TIME * 0.0025);
	NORMAL_MAP = mix(texture(ripple_noise, place * 0.02 + drift).rgb, texture(ripple_noise, place * 0.05 - drift).rgb, 0.5);
	NORMAL_MAP_DEPTH = 0.15;
}
