// Rocks at a landing site, painted with a real rock photo (ambientCG Rock023, CC0) from all three sides, so any shape
// looks right without unwrapping it. Each rock gets a slightly different shade, and dust (or frost) settles on top.
shader_type spatial;

uniform sampler2D rock_detail : repeat_enable, filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D rock_normal : repeat_enable, filter_linear_mipmap_anisotropic, hint_normal;
uniform sampler2D regolith_detail : repeat_enable, filter_linear_mipmap_anisotropic, hint_default_white;
uniform vec3 rock_color : source_color = vec3(0.3, 0.22, 0.17);
uniform vec3 dust_color : source_color = vec3(0.55, 0.33, 0.2);
uniform float dust_amount = 0.4;          // dust or frost on top (0 to 1)
uniform float texture_scale = 0.9;
uniform float shade_variety = 0.35;       // how different one rock is from the next
uniform float rock_roughness = 0.9;
uniform float ice_sheen = 0.0;
uniform vec3 glow_color : source_color = vec3(0.0);   // a glowing target rock

varying vec3 world_position;
varying vec3 world_normal;
varying float variety;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 origin = MODEL_MATRIX[3].xyz;
	variety = fract(sin(dot(origin, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	vec3 blend = pow(abs(world_normal), vec3(4.0));
	blend /= blend.x + blend.y + blend.z;
	vec3 point = world_position * texture_scale + variety * 13.0;
	float grain = texture(rock_detail, point.zy).r * blend.x + texture(rock_detail, point.xz).r * blend.y + texture(rock_detail, point.xy).r * blend.z;
	vec3 color = rock_color * (0.45 + grain) * (1.0 - shade_variety * 0.5 + shade_variety * variety);
	float top = smoothstep(0.35, 0.85, world_normal.y) * dust_amount;
	float dust_grain = texture(regolith_detail, world_position.xz * 0.8).r;
	color = mix(color, dust_color * (0.7 + dust_grain * 0.6), clamp(top * (0.6 + dust_grain * 0.8), 0.0, 1.0));
	ALBEDO = clamp(color, 0.0, 1.0);
	ROUGHNESS = mix(rock_roughness, 0.35, ice_sheen);
	SPECULAR = 0.4 + ice_sheen * 0.3;
	EMISSION = glow_color;

	// Bumps from the same photo, blended the same way: each side's bumps tilt the normal along that side's directions
	vec2 bump_x = (texture(rock_normal, point.zy).rg * 2.0 - 1.0) * 0.8;
	vec2 bump_y = (texture(rock_normal, point.xz).rg * 2.0 - 1.0) * 0.8;
	vec2 bump_z = (texture(rock_normal, point.xy).rg * 2.0 - 1.0) * 0.8;
	vec3 bumped = normalize(
		(world_normal + vec3(0.0, bump_x.y, bump_x.x)) * blend.x
		+ (world_normal + vec3(bump_y.x, 0.0, bump_y.y)) * blend.y
		+ (world_normal + vec3(bump_z.x, bump_z.y, 0.0)) * blend.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
}
