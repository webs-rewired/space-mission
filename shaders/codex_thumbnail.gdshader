// A planet's map wrapped onto a little ball, for the list in the destination codex: the map is bent around a
// sphere (so it looks round, not flat) and lit from the upper left, with a thin gold edge.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0);
uniform bool has_map = true;
uniform vec4 edge_color : source_color = vec4(0.78, 0.65, 0.42, 0.9);
uniform float turn = 0.0;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float distance_from_middle = length(centered);
	if (distance_from_middle > 1.0) {
		discard;
	}
	float depth = sqrt(max(1.0 - distance_from_middle * distance_from_middle, 0.0));
	vec3 normal = vec3(centered.x, -centered.y, depth);
	vec2 map_place = vec2(fract(0.5 + atan(normal.x, normal.z) / (2.0 * PI) + turn), acos(clamp(normal.y, -1.0, 1.0)) / PI);
	vec3 surface = has_map ? texture(TEXTURE, map_place).rgb * tint.rgb : tint.rgb;
	float light = clamp(dot(normal, normalize(vec3(-0.55, 0.5, 0.65))), 0.0, 1.0) * 0.9 + 0.1;
	vec3 color = surface * light;
	float edge = smoothstep(0.86, 1.0, distance_from_middle);
	color = mix(color, edge_color.rgb, edge * edge_color.a * 0.8);
	COLOR = vec4(color, 1.0 - smoothstep(0.96, 1.0, distance_from_middle));
}
