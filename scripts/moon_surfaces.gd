extends RefCounted

# Detailed surfaces for the moons, drawn by a shader so they have no seams and stay sharp up close.
# Each moon's look comes from its "surface" settings in solar_system_data.gd:
#   Io's yellow sulfur and black lava spots, Europa's reddish cracks, Ganymede's bright and dark terrain,
#   Callisto's craters, Enceladus' blue "tiger stripes", Titan's orange haze, Triton's pink polar cap and
#   bumpy "cantaloupe" ground, Charon's red north pole, and Phobos' grooves and craters.
# Craters and cracks also tilt the lighting a little (bump shading), so they show relief as the Sun moves.
#
# If you add a real map (for example 2k_io.jpg in res://assets/textures/), it is used instead.

const SpaceTextures = preload("res://scripts/space_textures.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")

const MOON_SHADER = """
shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 second_color : source_color = vec4(0.4, 0.4, 0.4, 1.0);
uniform float patch_scale = 2.0;
uniform float patch_amount = 0.6;
uniform float crater_amount = 0.0;
uniform float crater_scale = 6.0;
uniform vec4 crack_color : source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform float crack_amount = 0.0;
uniform float crack_scale = 3.0;
uniform vec4 spot_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);
uniform float spot_amount = 0.0;
uniform float spot_scale = 5.0;
uniform vec4 cap_color : source_color = vec4(1.0);
uniform float cap_amount = 0.0;
uniform float cap_side = 1.0;       // 1 = north cap, -1 = south cap, 0 = both poles
uniform float cap_size = 0.75;      // how far down from the pole the cap reaches
uniform vec4 stripe_color : source_color = vec4(0.5, 0.65, 0.85, 1.0);
uniform float stripe_amount = 0.0;  // Enceladus' tiger stripes
uniform float cell_amount = 0.0;    // Triton's cantaloupe terrain
uniform float haze_amount = 0.0;    // Titan's smooth haze
uniform float bump_strength = 0.6;
uniform float seed = 0.0;
varying vec3 local_position;
varying float object_scale;

float hash(vec3 point) {
	point = fract(point * 0.3183099 + vec3(0.71, 0.113, 0.419) + seed * 0.0137);
	point *= 17.0;
	return fract(point.x * point.y * point.z * (point.x + point.y + point.z));
}

float value_noise(vec3 point) {
	vec3 corner = floor(point);
	vec3 inside = fract(point);
	inside = inside * inside * (3.0 - 2.0 * inside);
	return mix(mix(mix(hash(corner), hash(corner + vec3(1.0, 0.0, 0.0)), inside.x),
				   mix(hash(corner + vec3(0.0, 1.0, 0.0)), hash(corner + vec3(1.0, 1.0, 0.0)), inside.x), inside.y),
			   mix(mix(hash(corner + vec3(0.0, 0.0, 1.0)), hash(corner + vec3(1.0, 0.0, 1.0)), inside.x),
				   mix(hash(corner + vec3(0.0, 1.0, 1.0)), hash(corner + vec3(1.0, 1.0, 1.0)), inside.x), inside.y), inside.z);
}

float layered_noise(vec3 point) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int layer = 0; layer < 5; layer++) {
		total += amplitude * value_noise(point);
		point *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}

// Distance to the nearest random point in a grid of cells, and a random number for that cell
vec2 nearest_cell(vec3 point) {
	vec3 corner = floor(point);
	vec3 inside = fract(point);
	float nearest = 8.0;
	float cell_number = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 offset = vec3(float(x), float(y), float(z));
				vec3 cell_point = vec3(hash(corner + offset), hash(corner + offset + 13.7), hash(corner + offset + 27.1));
				float distance_here = length(offset + cell_point - inside);
				if (distance_here < nearest) {
					nearest = distance_here;
					cell_number = hash(corner + offset + 5.3);
				}
			}
		}
	}
	return vec2(nearest, cell_number);
}

// A field of craters: a dark bowl inside a bright raised rim. Returns the height.
float craters(vec3 point) {
	vec2 cell = nearest_cell(point);
	if (cell.y > 0.75) {
		return 0.0;   // not every cell has a crater
	}
	float radius = 0.15 + 0.3 * cell.y;
	float distance_in_radii = cell.x / radius;
	float bowl = 1.0 - smoothstep(0.0, 1.0, distance_in_radii);
	float rim = smoothstep(0.75, 1.0, distance_in_radii) * (1.0 - smoothstep(1.0, 1.35, distance_in_radii));
	return rim * 0.6 - bowl * 0.8;
}

void vertex() {
	local_position = VERTEX;
	object_scale = length(MODEL_MATRIX[0].xyz);
}

void fragment() {
	vec3 point = normalize(local_position);
	float height = 0.0;
	float patches = layered_noise(point * patch_scale + seed);
	vec3 color = mix(base_color.rgb, second_color.rgb, smoothstep(0.5 - patch_amount * 0.5, 0.5 + patch_amount * 0.5, patches));
	color *= 0.86 + 0.28 * layered_noise(point * patch_scale * 6.0 + 3.1);

	if (crater_amount > 0.0) {
		float crater_height = craters(point * crater_scale) + 0.5 * craters(point * crater_scale * 3.1 + 7.7);
		height += crater_height * crater_amount;
		color *= 1.0 + crater_height * 0.25 * crater_amount;
	}
	if (crack_amount > 0.0) {
		float ridge_one = 1.0 - abs(layered_noise(point * crack_scale + 11.0) * 2.0 - 1.0);
		float ridge_two = 1.0 - abs(layered_noise(point * crack_scale * 2.3 + 23.0) * 2.0 - 1.0);
		float lines = max(pow(ridge_one, 18.0), 0.6 * pow(ridge_two, 26.0));
		color = mix(color, crack_color.rgb, clamp(lines * crack_amount, 0.0, 1.0));
		height += lines * 0.15 * crack_amount;
	}
	if (spot_amount > 0.0) {
		float spots = smoothstep(0.62, 0.7, layered_noise(point * spot_scale + 41.0));
		color = mix(color, spot_color.rgb, spots * spot_amount);
	}
	if (cell_amount > 0.0) {
		float dimples = smoothstep(0.2, 0.55, nearest_cell(point * 14.0).x);
		color *= 1.0 - cell_amount * 0.25 * dimples;
		height -= dimples * 0.3 * cell_amount;
	}
	if (cap_amount > 0.0) {
		float toward_pole = cap_side == 0.0 ? abs(point.y) : point.y * cap_side;
		float edge = cap_size + 0.08 * (layered_noise(point * 5.0) - 0.5);
		color = mix(color, cap_color.rgb, smoothstep(edge - 0.06, edge + 0.06, toward_pole) * cap_amount);
	}
	if (stripe_amount > 0.0) {
		// Four long parallel cracks across the south pole, where the geysers erupt
		float near_south_pole = smoothstep(-0.62, -0.82, point.y);
		float across = point.x * 0.8 + point.z * 0.6 + 0.04 * layered_noise(point * 8.0);
		float stripes = pow(abs(sin(across * 7.0)), 30.0) * near_south_pole * step(abs(across), 0.6);
		color = mix(color, stripe_color.rgb, stripes * stripe_amount);
		height -= stripes * 0.2;
	}
	if (haze_amount > 0.0) {
		float bands = 0.92 + 0.08 * sin(point.y * 9.0 + layered_noise(point * 3.0) * 2.0);
		color = mix(color, base_color.rgb * bands, haze_amount);
		height *= 1.0 - haze_amount;
	}
	ALBEDO = color * 0.85;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;

	// Bump shading: tilt the surface by how quickly the height changes across the screen.
	// It fades out when the moon is small on screen, where craters would be smaller than a pixel.
	float pixel_footprint = length(dFdx(point)) + length(dFdy(point));
	float detail_visible = 1.0 - smoothstep(0.004, 0.02, pixel_footprint);
	float bump = height * object_scale * bump_strength * 0.02 * detail_visible;
	vec3 position_change_x = dFdx(VERTEX);
	vec3 position_change_y = dFdy(VERTEX);
	vec3 side_one = cross(position_change_y, NORMAL);
	vec3 side_two = cross(NORMAL, position_change_x);
	float determinant = dot(position_change_x, side_one);
	vec3 slope = sign(determinant) * (dFdx(bump) * side_one + dFdy(bump) * side_two);
	NORMAL = normalize(abs(determinant) * NORMAL - slope);
}
"""

static var shared_shader: Shader = null

# The material for a moon: its real map if there is one, otherwise the detailed generated surface
static func make_material(body_name):
	var data = SolarSystemData.BODIES[body_name]
	var image = SpaceTextures.find_texture(data.get("images", []))
	if image:
		var map_material = StandardMaterial3D.new()
		map_material.albedo_texture = image
		map_material.roughness = 0.95
		map_material.metallic_specular = 0.2
		return map_material
	if shared_shader == null:
		shared_shader = Shader.new()
		shared_shader.code = MOON_SHADER
	var surface_material = ShaderMaterial.new()
	surface_material.shader = shared_shader
	surface_material.set_shader_parameter("seed", float(abs(body_name.hash()) % 97))
	var settings = data.get("surface", {})
	for setting in settings:
		surface_material.set_shader_parameter(setting, settings[setting])
	return surface_material
