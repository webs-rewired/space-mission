// The dark backdrop of the destination codex: near-black with a warm glow behind the globe, a heavy vignette
// toward the edges, and a little film grain.
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.03, 0.026, 0.024, 0.975);
uniform vec4 glow_color : source_color = vec4(0.42, 0.3, 0.15, 1.0);
uniform vec2 glow_center = vec2(0.5, 0.42);
uniform float glow_strength = 0.16;

void fragment() {
	vec2 stretched = (UV - glow_center) * vec2(1.7, 1.0);
	float glow = 1.0 - smoothstep(0.0, 0.75, length(stretched));
	float vignette = smoothstep(0.45, 1.05, length((UV - vec2(0.5)) * vec2(1.25, 1.5)));
	vec3 color = base_color.rgb + glow_color.rgb * glow_strength * glow;
	color *= 1.0 - vignette * 0.8;
	float grain = fract(sin(dot(UV * 1000.0 + vec2(TIME * 7.0), vec2(12.9898, 78.233))) * 43758.5453);
	color += (grain - 0.5) * 0.018;
	COLOR = vec4(color, clamp(base_color.a + vignette * 0.06, 0.0, 1.0));
}
