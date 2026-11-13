// The map an orbiter builds as it flies. The parts of the world it hasn't mapped yet are dimmed; mapped parts show
// in full color, with a glowing line along the edge of what's been mapped. A ring marks the patch of ground the
// instruments are looking at right now.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D coverage : filter_linear;   // white where mapped (made by orbit_science.gd)
uniform float mapped_value = 1.0;              // how bright "mapped" is in that picture (dimmer where only cloud tops were mapped)
uniform vec3 footprint_center = vec3(0.0, 1.0, 0.0);
uniform float footprint_size = 0.1;            // radians
uniform vec3 edge_color : source_color = vec3(0.3, 0.85, 1.0);
uniform float unmapped_dimming = 0.5;          // how much darker the unmapped parts are (0 to 1)
varying vec3 local_direction;

void vertex() {
	local_direction = normalize(VERTEX);
}

void fragment() {
	float mapped = clamp(texture(coverage, UV).r / mapped_value, 0.0, 1.0);
	float edge = smoothstep(0.05, 0.5, mapped) * (1.0 - smoothstep(0.5, 0.95, mapped));
	float angle = acos(clamp(dot(normalize(local_direction), normalize(footprint_center)), -1.0, 1.0));
	float ring = 1.0 - smoothstep(0.0, footprint_size * 0.1, abs(angle - footprint_size));
	float glow = clamp(edge * 0.45 + ring, 0.0, 1.0);
	ALBEDO = mix(vec3(0.0, 0.01, 0.03), edge_color, glow);
	ALPHA = clamp((1.0 - mapped) * unmapped_dimming + edge * 0.2 + ring * 0.85, 0.0, 1.0);
}
