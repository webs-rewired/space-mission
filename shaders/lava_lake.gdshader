// A lava lake on Io (like Loki Patera): a dark crust that keeps cracking to show glowing lava underneath.
shader_type spatial;

uniform vec3 crust_color : source_color = vec3(0.05, 0.04, 0.035);
uniform vec3 lava_color : source_color = vec3(1.0, 0.35, 0.08);
uniform float glow = 6.0;
uniform float crack_scale = 22.0;

vec2 hash2(vec2 point) {
	point = vec2(dot(point, vec2(127.1, 311.7)), dot(point, vec2(269.5, 183.3)));
	return fract(sin(point) * 43758.5453);
}

float nearest_two_difference(vec2 point) {
	vec2 cell = floor(point);
	vec2 inside = fract(point);
	float first = 8.0;
	float second = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 wobble = 0.5 + 0.5 * sin(TIME * 0.15 + 6.2831 * hash2(cell + neighbor));
			float distance_to_point = length(neighbor + wobble - inside);
			if (distance_to_point < first) {
				second = first;
				first = distance_to_point;
			} else if (distance_to_point < second) {
				second = distance_to_point;
			}
		}
	}
	return second - first;
}

void fragment() {
	vec2 place = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	float crack = 1.0 - smoothstep(0.0, 0.08, nearest_two_difference(place / crack_scale));
	float pulse = 0.8 + 0.2 * sin(TIME * 1.3 + place.x * 0.01);
	ALBEDO = crust_color;
	ROUGHNESS = 0.8;
	EMISSION = lava_color * crack * glow * pulse;
}
