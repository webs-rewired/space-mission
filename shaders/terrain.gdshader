// The ground at a landing site: gentle hills (flat right where the lander comes down), with colour variation.
shader_type spatial;

uniform sampler2D height_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_noise : repeat_enable, filter_linear_mipmap;
uniform vec3 light_ground : source_color = vec3(0.55, 0.32, 0.18);
uniform vec3 dark_ground : source_color = vec3(0.32, 0.18, 0.1);
uniform float hill_height = 10.0;
uniform float flat_radius = 30.0;
varying vec3 ground_position;

float height_at(vec2 place) {
	float keep_flat = smoothstep(flat_radius, flat_radius * 4.0, length(place));
	return (texture(height_noise, place * 0.0035).r - 0.5) * hill_height * keep_flat
		+ (texture(height_noise, place * 0.03).r - 0.5) * 0.5;
}

void vertex() {
	vec2 place = VERTEX.xz;
	float height = height_at(place);
	VERTEX.y += height;
	float step_size = 1.5;
	float east = height_at(place + vec2(step_size, 0.0));
	float north = height_at(place + vec2(0.0, step_size));
	NORMAL = normalize(vec3(height - east, step_size, height - north));
	ground_position = VERTEX;
}

void fragment() {
	float patches = texture(detail_noise, ground_position.xz * 0.02).r;
	float grit = texture(detail_noise, ground_position.xz * 0.35).r;
	ALBEDO = mix(dark_ground, light_ground, clamp(patches * 0.9 + grit * 0.45 - 0.15, 0.0, 1.0));
	ROUGHNESS = 0.96;
}
