// A soft, puffy cloud on a flat card that always faces the camera. Several of them together make a cumulus cloud.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap;
uniform float seed = 0.0;
uniform vec3 sunlit_color : source_color = vec3(1.0, 1.0, 0.98);
uniform vec3 shadow_color : source_color = vec3(0.62, 0.67, 0.75);
uniform float opacity = 0.95;

void vertex() {
	// Face the camera, keeping the card's size
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float distance_from_middle = length(centered * vec2(1.0, 1.4));
	float lumps = texture(noise_texture, UV * 0.8 + vec2(seed, seed * 1.7)).r;
	float detail = texture(noise_texture, UV * 2.6 + vec2(seed * 2.3, seed)).r;
	float shape = smoothstep(0.5, 0.2, distance_from_middle + (0.5 - lumps) * 0.45 + (0.5 - detail) * 0.12);
	// Sunlit on top, grey underneath, like real cumulus
	float height = 1.0 - UV.y;
	ALBEDO = mix(shadow_color, sunlit_color, clamp(height * 0.9 + lumps * 0.45 - 0.1, 0.0, 1.0));
	ALPHA = shape * opacity;
}
