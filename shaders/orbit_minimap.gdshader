// The flat mission map in the corner of the orbit screen: dark where the orbiter hasn't mapped yet, clear where
// it has, with a glowing line along the edge (the same picture as on the globe).
shader_type canvas_item;

uniform sampler2D coverage : filter_linear;   // white where mapped (made by orbit_science.gd)
uniform float mapped_value = 1.0;              // how bright "mapped" is in that picture (dimmer where only cloud tops were mapped)

void fragment() {
	float mapped = clamp(texture(coverage, UV).r / mapped_value, 0.0, 1.0);
	float edge = smoothstep(0.05, 0.5, mapped) * (1.0 - smoothstep(0.5, 0.95, mapped));
	COLOR = vec4(mix(vec3(0.0, 0.02, 0.05), vec3(0.3, 0.85, 1.0), edge), clamp((1.0 - mapped) * 0.75 + edge * 0.6, 0.0, 1.0));
}
