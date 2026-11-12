// Billowing exhaust smoke and steam: a lumpy puff on a card that faces the camera.
// Used by particles, so each puff's color and fade come from the particle (COLOR).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap;
uniform vec3 lit_color : source_color = vec3(0.97, 0.97, 0.96);
uniform vec3 shade_color : source_color = vec3(0.62, 0.64, 0.68);
varying float puff_seed;

void vertex() {
	puff_seed = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453) * 10.0;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float lumps = texture(noise_texture, UV * 0.7 + vec2(puff_seed, puff_seed * 1.3)).r;
	float detail = texture(noise_texture, UV * 2.2 + vec2(puff_seed * 2.1, puff_seed)).r;
	float shape = smoothstep(0.5, 0.15, length(centered) + (0.5 - lumps) * 0.4 + (0.5 - detail) * 0.12);
	ALBEDO = mix(shade_color, lit_color, clamp((1.0 - UV.y) * 0.8 + lumps * 0.4, 0.0, 1.0)) * COLOR.rgb;
	ALPHA = shape * COLOR.a;
}
