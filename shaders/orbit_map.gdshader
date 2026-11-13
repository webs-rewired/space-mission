// The map an orbiter builds as it flies: a faint grid of latitude and longitude lines appears over every part of the
// world that's been mapped, and the strip the instruments are looking at right now glows.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D coverage : filter_linear;   // white where mapped (made by orbit_science.gd)
uniform vec3 footprint_center = vec3(0.0, 1.0, 0.0);
uniform float footprint_size = 0.1;            // radians
uniform vec3 grid_color : source_color = vec3(0.3, 0.85, 1.0);
varying vec3 local_direction;

void vertex() {
	local_direction = normalize(VERTEX);
}

void fragment() {
	float mapped = texture(coverage, UV).r;
	vec2 lines = vec2(UV.x * 36.0, UV.y * 18.0);   // every 10 degrees
	vec2 distance_to_line = abs(fract(lines + 0.5) - 0.5) / max(fwidth(lines), vec2(0.0001));
	float line = 1.0 - clamp(min(distance_to_line.x, distance_to_line.y), 0.0, 1.0);
	float angle = acos(clamp(dot(normalize(local_direction), normalize(footprint_center)), -1.0, 1.0));
	float footprint = 1.0 - smoothstep(footprint_size * 0.8, footprint_size, angle);
	ALBEDO = grid_color;
	ALPHA = clamp(mapped * (0.05 + line * 0.4) + footprint * 0.22, 0.0, 1.0);
}
