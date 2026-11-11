extends RefCounted

# Builds the asteroid belt, Jupiter's Trojan asteroids and the Kuiper belt.
#
# Every rock has its own tilted, real-sized orbit and moves at its real speed (Kepler's third law:
# farther rocks go around more slowly). The moving happens on the graphics card, so thousands of rocks
# stay smooth. The rocks are lumpy, tumble slowly, and come in several shapes and shades.
#
# The main belt has the real Kirkwood gaps: empty lanes where Jupiter's pull clears rocks out
# (at 2.50, 2.82, 2.95 and 3.27 AU).

const OrbitMath = preload("res://scripts/orbit_math.gd")

const BELT_SHADER = """
shader_type spatial;
render_mode world_vertex_coords;
uniform float days_passed = 0.0;      // days of game time since this belt was built
uniform vec3 sun_center = vec3(0.0);
uniform vec4 rock_color : source_color = vec4(0.5, 0.46, 0.42, 1.0);
uniform float color_variety = 0.35;
varying float shade;

vec3 turn_around(vec3 v, vec3 axis, float angle) {
	return v * cos(angle) + cross(axis, v) * sin(angle) + axis * dot(axis, v) * (1.0 - cos(angle));
}

void vertex() {
	// Custom data: r = orbit speed (radians per day), g = orbit tilt, b = tilt direction, a = tumble speed
	float tilt = INSTANCE_CUSTOM.g;
	float tilt_direction = INSTANCE_CUSTOM.b;
	vec3 orbit_axis = vec3(sin(tilt_direction) * sin(tilt), cos(tilt), cos(tilt_direction) * sin(tilt));
	vec3 center = MODEL_MATRIX[3].xyz;
	float id = float(INSTANCE_ID);
	vec3 tumble_axis = normalize(vec3(sin(id * 1.3), cos(id * 0.7), sin(id * 2.1) + 0.1));
	float tumble = INSTANCE_CUSTOM.a * TIME;
	vec3 offset = turn_around(VERTEX - center, tumble_axis, tumble);
	vec3 normal = turn_around(NORMAL, tumble_axis, tumble);
	float angle = INSTANCE_CUSTOM.r * days_passed;
	vec3 moved_center = sun_center + turn_around(center - sun_center, orbit_axis, angle);
	VERTEX = moved_center + turn_around(offset, orbit_axis, angle);
	NORMAL = turn_around(normal, orbit_axis, angle);
	shade = fract(sin(id * 12.9898) * 43758.5453);
}

void fragment() {
	ALBEDO = rock_color.rgb * (1.0 - color_variety * 0.5 + color_variety * shade);
	ROUGHNESS = 1.0;
}
"""

const KIRKWOOD_GAPS = [2.50, 2.82, 2.95, 3.27]

# A lumpy potato-shaped rock
static func make_rock_mesh(seed_number):
	var sphere = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var arrays = sphere.get_mesh_arrays()
	var noise = FastNoiseLite.new()
	noise.seed = seed_number
	noise.frequency = 0.9
	var random = RandomNumberGenerator.new()
	random.seed = seed_number
	var stretch = Vector3(random.randf_range(0.8, 1.4), random.randf_range(0.55, 0.9), random.randf_range(0.7, 1.1))
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size():
		var point = vertices[index]
		vertices[index] = point * (1.0 + 0.35 * noise.get_noise_3dv(point * 1.7)) * stretch
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var lumpy = ArrayMesh.new()
	lumpy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface = SurfaceTool.new()
	surface.create_from(lumpy, 0)
	surface.generate_normals()
	return surface.commit()

# Where a rock on a circular, tilted orbit starts, in game units
static func start_position(distance_au, tilt, tilt_direction, angle_in_orbit, true_scale):
	var x = distance_au * (cos(tilt_direction) * cos(angle_in_orbit) - sin(tilt_direction) * sin(angle_in_orbit) * cos(tilt))
	var y = distance_au * (sin(tilt_direction) * cos(angle_in_orbit) + cos(tilt_direction) * sin(angle_in_orbit) * cos(tilt))
	var z = distance_au * sin(angle_in_orbit) * sin(tilt)
	return OrbitMath.to_game_units(Vector3(x, y, z), true_scale)

# Builds one belt made of several rock shapes.
# rocks: a list of [distance in AU, tilt (radians), tilt direction (radians), angle in orbit (radians)]
# days_ahead: how many days the rocks have moved along their orbits since the list was made
static func make_belt(belt_name, rocks, rock_size, color, true_scale, seed_number, days_ahead = 0.0):
	var belt = Node3D.new()
	belt.name = belt_name
	var shader = Shader.new()
	shader.code = BELT_SHADER
	var belt_material = ShaderMaterial.new()
	belt_material.shader = shader
	belt_material.set_shader_parameter("rock_color", color)
	belt.set_meta("belt_material", belt_material)

	var shape_count = 4
	var random = RandomNumberGenerator.new()
	random.seed = seed_number
	for shape in shape_count:
		var rock_mesh = make_rock_mesh(seed_number * 10 + shape)
		var shape_rocks = []
		for index in rocks.size():
			if index % shape_count == shape:
				shape_rocks.append(rocks[index])
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = rock_mesh
		multimesh.instance_count = shape_rocks.size()
		for index in shape_rocks.size():
			var rock = shape_rocks[index]
			var size = rock_size * random.randf_range(0.35, 1.6)
			var turned = Basis(Vector3(random.randf() - 0.5, random.randf() - 0.5, random.randf() - 0.5).normalized(), random.randf() * TAU)
			# Kepler's third law: one orbit takes distance^1.5 years
			var orbit_speed = TAU / (365.25 * pow(rock[0], 1.5))
			var position = start_position(rock[0], rock[1], rock[2], rock[3] + orbit_speed * days_ahead, true_scale)
			multimesh.set_instance_transform(index, Transform3D(turned.scaled(Vector3.ONE * size), position))
			multimesh.set_instance_custom_data(index, Color(orbit_speed, rock[1], rock[2], random.randf_range(0.2, 1.2)))
		var rocks_node = MultiMeshInstance3D.new()
		rocks_node.multimesh = multimesh
		rocks_node.material_override = belt_material
		belt.add_child(rocks_node)
	return belt

# The main asteroid belt between Mars and Jupiter, with the Kirkwood gaps
static func main_belt_rocks(count, seed_number):
	var random = RandomNumberGenerator.new()
	random.seed = seed_number
	var rocks = []
	while rocks.size() < count:
		var distance = random.randf_range(2.1, 3.3)
		var in_gap = false
		for gap in KIRKWOOD_GAPS:
			if abs(distance - gap) < 0.025:
				in_gap = true
		if in_gap:
			continue
		var tilt = deg_to_rad(abs(random.randfn(0.0, 7.0)))
		rocks.append([distance, tilt, random.randf() * TAU, random.randf() * TAU])
	return rocks

# Jupiter's Trojans: two swarms sharing Jupiter's orbit, 60° ahead of and behind it
static func trojan_rocks(count, jupiter_angle, seed_number):
	var random = RandomNumberGenerator.new()
	random.seed = seed_number
	var rocks = []
	for index in count:
		var ahead = 1.0 if index % 2 == 0 else -1.0
		var tilt = deg_to_rad(abs(random.randfn(0.0, 11.0)))
		var tilt_direction = random.randf() * TAU
		var longitude = jupiter_angle + ahead * deg_to_rad(60.0) + deg_to_rad(random.randfn(0.0, 9.0))
		rocks.append([5.2 * (1.0 + random.randfn(0.0, 0.015)), tilt, tilt_direction, longitude - tilt_direction])
	return rocks

# The Kuiper belt beyond Neptune: a calm, flat "cold" group, a more tilted "hot" group,
# and the plutinos that share Pluto's 2:3 rhythm with Neptune at about 39.4 AU
static func kuiper_rocks(count, seed_number):
	var random = RandomNumberGenerator.new()
	random.seed = seed_number
	var rocks = []
	for index in count:
		var group = random.randf()
		var distance = 0.0
		var tilt = 0.0
		if group < 0.5:
			distance = random.randf_range(42.0, 47.5)
			tilt = abs(random.randfn(0.0, 2.5))
		elif group < 0.82:
			distance = random.randf_range(36.0, 55.0)
			tilt = abs(random.randfn(0.0, 13.0))
		else:
			distance = 39.4 + random.randfn(0.0, 0.3)
			tilt = abs(random.randfn(0.0, 10.0))
		rocks.append([distance, deg_to_rad(tilt), random.randf() * TAU, random.randf() * TAU])
	return rocks
