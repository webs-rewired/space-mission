extends RefCounted

# Real spacecraft: where each one is on any date, the path it flew, and its 3D model.
#
# Voyager 1, Voyager 2 and New Horizons follow their real routes. Between planet flybys a spacecraft just
# coasts on a curve around the Sun, so each leg of the trip is worked out from the real flyby dates: the one
# curve around the Sun that leaves one planet and reaches the next at exactly the right times (this is called
# Lambert's problem). The last leg ends where NASA's tracking says the spacecraft is today.
# Checked against NASA's numbers:
#   Voyager 1 crossed into interstellar space at 121.6 AU on Aug 25, 2012 (here: 121.6 AU)
#   Voyager 2 crossed at 119.0 AU on Nov 5, 2018 (here: 119.0 AU)
#   New Horizons flew past Arrokoth at 43.3 AU on Jan 1, 2019 (here: 43.3 AU)
#   Today's speeds match NASA's within 0.01 km/s
#
# Parker Solar Probe, Juno and the ISS use ordinary orbits (see solar_system_data.gd).
#
# Models: NASA's free 3D models go in res://assets/models/ (voyager.glb, new_horizons.glb, juno.glb,
# parker_solar_probe.glb, iss.glb). If one is missing, a simple probe shape is drawn instead.

const OrbitMath = preload("res://scripts/orbit_math.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")

const SUN_GRAVITY_KM = 1.32712440018e11   # GM of the Sun, km³/s²
const KILOMETERS_PER_AU = 149597870.7
const SECONDS_PER_DAY = 86400.0
const MODEL_FOLDER = "res://assets/models/"
const POINTS_PER_LEG = 240

static var route_cache = {}   # spacecraft name -> its legs, worked out once
static var model_paths = {}   # every .glb file in the project: file name (lowercase) -> its path

# ---------------------------------------------------------------------------
# Small helpers for [x, y, z] arrays (plain numbers keep full precision, which matters billions of km out)
# ---------------------------------------------------------------------------
static func add_scaled(first, second, amount):
	return [first[0] + second[0] * amount, first[1] + second[1] * amount, first[2] + second[2] * amount]

static func dot(first, second):
	return first[0] * second[0] + first[1] * second[1] + first[2] * second[2]

static func cross(first, second):
	return [first[1] * second[2] - first[2] * second[1], first[2] * second[0] - first[0] * second[2], first[0] * second[1] - first[1] * second[0]]

static func length(vector):
	return sqrt(dot(vector, vector))

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
# Where a planet is on a date, in km from the Sun (ecliptic frame)
static func planet_km(body_name, julian_date):
	var au = OrbitMath.ecliptic_xyz(SolarSystemData.BODIES[body_name]["orbit"], julian_date)
	return [au[0] * KILOMETERS_PER_AU, au[1] * KILOMETERS_PER_AU, au[2] * KILOMETERS_PER_AU]

# A stop on a route: [date, "Planet"] or [date, [right ascension (hours), declination (degrees), distance from Earth (AU)]]
static func waypoint_km(waypoint):
	var julian_date = waypoint[0]
	var place = waypoint[1]
	if place is String:
		return planet_km(place, julian_date)
	# Where it is in Earth's sky and how far away, turned into a position measured from the Sun
	var right_ascension = deg_to_rad(place[0] * 15.0)
	var declination = deg_to_rad(place[1])
	var direction = OrbitMath.equatorial_to_ecliptic(Vector3(cos(declination) * cos(right_ascension), cos(declination) * sin(right_ascension), sin(declination)))
	var earth = planet_km("Earth", julian_date)
	var distance = place[2] * KILOMETERS_PER_AU
	return [earth[0] + direction.x * distance, earth[1] + direction.y * distance, earth[2] + direction.z * distance]

# Each leg: when it starts and ends, and the position and velocity at its start
static func route_legs(body_name):
	if route_cache.has(body_name):
		return route_cache[body_name]
	var route = SolarSystemData.BODIES[body_name]["route"]
	var legs = []
	for index in route.size() - 1:
		var start = waypoint_km(route[index])
		var finish = waypoint_km(route[index + 1])
		var seconds = (route[index + 1][0] - route[index][0]) * SECONDS_PER_DAY
		legs.append({"start_date": route[index][0], "end_date": route[index + 1][0], "position": start,
			"velocity": lambert(start, finish, seconds)})
	route_cache[body_name] = legs
	return legs

# Position and velocity (km and km/s from the Sun) on a date, or null before launch
static func route_state(body_name, julian_date):
	var legs = route_legs(body_name)
	if legs.is_empty() or julian_date < legs[0]["start_date"]:
		return null
	var leg = legs[legs.size() - 1]   # after the last stop it keeps coasting on its last curve
	for each_leg in legs:
		if julian_date <= each_leg["end_date"]:
			leg = each_leg
			break
	return coast(leg["position"], leg["velocity"], (julian_date - leg["start_date"]) * SECONDS_PER_DAY)

# Points along the whole route, in game units, for drawing its path
static func route_path_points(body_name, true_scale, extra_days):
	var legs = route_legs(body_name)
	var points = PackedVector3Array()
	for leg_index in legs.size():
		var leg = legs[leg_index]
		var end_date = leg["end_date"]
		if leg_index == legs.size() - 1:
			end_date += extra_days
		for step in POINTS_PER_LEG + 1:
			var julian_date = lerp(leg["start_date"], end_date, float(step) / POINTS_PER_LEG)
			var state = coast(leg["position"], leg["velocity"], (julian_date - leg["start_date"]) * SECONDS_PER_DAY)
			var kilometers = state[0]
			var game = OrbitMath.game_xyz([kilometers[0] / KILOMETERS_PER_AU, kilometers[1] / KILOMETERS_PER_AU, kilometers[2] / KILOMETERS_PER_AU], true_scale)
			points.append(Vector3(game[0], game[1], game[2]))
	return points

# ---------------------------------------------------------------------------
# Coasting around the Sun (works for closed orbits and for escape paths)
# ---------------------------------------------------------------------------
# The Stumpff functions C(z) and S(z) used by the "universal variable" method
static func stumpff(z):
	if z > 1e-8:
		var root = sqrt(z)
		return [(1.0 - cos(root)) / z, (root - sin(root)) / (root * root * root)]
	if z < -1e-8:
		var root = sqrt(-z)
		return [(cosh(root) - 1.0) / -z, (sinh(root) - root) / (root * root * root)]
	return [0.5, 1.0 / 6.0]

# Where something is after coasting for some seconds: returns [position, velocity]
static func coast(position, velocity, seconds, gravity = SUN_GRAVITY_KM):
	if seconds == 0.0:
		return [position, velocity]
	var distance = length(position)
	var speed = length(velocity)
	var root_gravity = sqrt(gravity)
	var radial_speed = dot(position, velocity) / distance
	var alpha = 2.0 / distance - speed * speed / gravity   # 1 / semi-major axis (negative on an escape path)
	var x = root_gravity * abs(alpha) * seconds
	if alpha < -1e-12:
		var inside = (-2.0 * gravity * alpha * seconds) / (dot(position, velocity) + sign(seconds) * sqrt(-gravity / alpha) * (1.0 - distance * alpha))
		x = sign(seconds) * sqrt(-1.0 / alpha) * log(inside) if inside > 0.0 else root_gravity * seconds / distance
	elif abs(alpha) <= 1e-12:
		x = root_gravity * seconds / distance
	# Find x so the trip takes exactly "seconds". The time always grows with x, so the answer is trapped between a
	# low and a high guess: Newton's method does the fast work, and whenever it would jump outside those two
	# guesses (it can fly off on long, stretched orbits) the step is replaced by the halfway point.
	var direction = 1.0 if seconds > 0.0 else -1.0
	var target = root_gravity * seconds
	var low = 0.0
	var high = max(abs(x), 1e-6)
	for step in 200:
		if direction * coast_time(direction * high, alpha, distance, radial_speed, root_gravity)[0] >= abs(target):
			break
		low = high
		high *= 2.0
	if is_nan(x) or abs(x) <= low or abs(x) >= high or x * direction < 0.0:
		x = direction * 0.5 * (low + high)
	for step in 200:
		var time_and_slope = coast_time(x, alpha, distance, radial_speed, root_gravity)
		var time_error = time_and_slope[0] - target
		if direction * time_error > 0.0:
			high = abs(x)
		else:
			low = abs(x)
		var better = x - time_error / time_and_slope[1] if time_and_slope[1] > 0.0 else NAN
		if is_nan(better) or is_inf(better) or better * direction < 0.0 or abs(better) <= low or abs(better) >= high:
			better = direction * 0.5 * (low + high)
		var change = better - x
		x = better
		if abs(change) < 1e-11 * max(1.0, abs(x)) or high - low < 1e-11 * max(1.0, high):
			break
	var final_values = stumpff(alpha * x * x)
	var f = 1.0 - x * x / distance * final_values[0]
	var g = seconds - x * x * x / root_gravity * final_values[1]
	var new_position = [f * position[0] + g * velocity[0], f * position[1] + g * velocity[1], f * position[2] + g * velocity[2]]
	var new_distance = length(new_position)
	var f_rate = root_gravity / (new_distance * distance) * (alpha * x * x * x * final_values[1] - x)
	var g_rate = 1.0 - x * x / new_distance * final_values[0]
	var new_velocity = [f_rate * position[0] + g_rate * velocity[0], f_rate * position[1] + g_rate * velocity[1], f_rate * position[2] + g_rate * velocity[2]]
	return [new_position, new_velocity]

# For coast(): [how much time (times the square root of gravity) the universal variable x stands for, and how fast that grows]
static func coast_time(x, alpha, distance, radial_speed, root_gravity):
	var values = stumpff(alpha * x * x)
	var time = distance * radial_speed / root_gravity * x * x * values[0] + (1.0 - alpha * distance) * x * x * x * values[1] + distance * x
	var slope = distance * radial_speed / root_gravity * x * (1.0 - alpha * x * x * values[1]) + (1.0 - alpha * distance) * x * x * values[0] + distance
	return [time, slope]

# Lambert's problem: the velocity needed at "start" to coast to "finish" in exactly "seconds",
# going around the Sun the same way the planets do
static func lambert(start, finish, seconds):
	var start_distance = length(start)
	var finish_distance = length(finish)
	var angle = acos(clamp(dot(start, finish) / (start_distance * finish_distance), -1.0, 1.0))
	if cross(start, finish)[2] < 0.0:
		angle = TAU - angle
	var a_value = sin(angle) * sqrt(start_distance * finish_distance / (1.0 - cos(angle)))
	# Find z by halving the search range; "no orbit here" sits below the answer when a_value > 0, above it otherwise
	var low = -4.0
	var high = 4.0 * PI * PI * 0.999999
	for step in 200:
		var check = lambert_time_error(low, start_distance, finish_distance, a_value, seconds)
		if not check[0] or check[1] < 0.0:
			break
		low *= 2.0
	for step in 400:
		var middle = 0.5 * (low + high)
		var check = lambert_time_error(middle, start_distance, finish_distance, a_value, seconds)
		if not check[0]:
			if a_value > 0.0:
				low = middle
			else:
				high = middle
		elif check[1] > 0.0:
			high = middle
		else:
			low = middle
	var z = 0.5 * (low + high)
	var y = lambert_y(z, start_distance, finish_distance, a_value)
	var f = 1.0 - y / start_distance
	var g = a_value * sqrt(y / SUN_GRAVITY_KM)
	return [(finish[0] - f * start[0]) / g, (finish[1] - f * start[1]) / g, (finish[2] - f * start[2]) / g]

static func lambert_y(z, start_distance, finish_distance, a_value):
	var values = stumpff(z)
	return start_distance + finish_distance + a_value * (z * values[1] - 1.0) / sqrt(values[0])

# [is there an orbit for this z, how much too long (+) or too short (-) the trip would take]
static func lambert_time_error(z, start_distance, finish_distance, a_value, seconds):
	var y = lambert_y(z, start_distance, finish_distance, a_value)
	if y < 0.0:
		return [false, 0.0]
	var values = stumpff(z)
	return [true, pow(y / values[0], 1.5) * values[1] + a_value * sqrt(y) - sqrt(SUN_GRAVITY_KM) * seconds]

# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
# The spacecraft's model, centered and sized to fit inside a ball of radius 1 (the Bodies node scales it from there)
static func make_model(data):
	var model = null
	var path = find_model(data.get("model_file", ""))
	if path != "":
		var scene = load(path)
		if scene is PackedScene:
			model = scene.instantiate()
	if model == null:
		model = build_simple_probe()
		push_warning("Spacecraft model %s wasn't found, so a simple box-and-dish shape is drawn instead. Put %s in %s (Godot imports it when you click back into the editor)." % [data.get("model_file", "?"), data.get("model_file", "?"), MODEL_FOLDER])
	var holder = Node3D.new()
	holder.add_child(model)
	var box = model_bounds(model, Transform3D.IDENTITY, null)
	if box != null:
		var biggest = max(box.size.x, max(box.size.y, box.size.z))
		var shrink = 2.0 / max(biggest, 0.000001)
		model.scale = model.scale * shrink
		model.position = -body_center(model) * shrink
	# Put every part on light layer 2 too, so the spacecraft's own little sunlight lights only the spacecraft
	for part in holder.find_children("*", "VisualInstance3D", true, false):
		part.layers = part.layers | 2
	return holder

# Where a model file is: res://assets/models/ first, otherwise anywhere in the project (in case it landed in another folder)
static func find_model(file_name):
	if file_name == "":
		return ""
	if ResourceLoader.exists(MODEL_FOLDER + file_name):
		return MODEL_FOLDER + file_name
	if model_paths.is_empty():
		collect_models("res://")
	var path = model_paths.get(file_name.to_lower(), "")
	if path != "" and ResourceLoader.exists(path):
		return path
	return ""

static func collect_models(folder):
	var directory = DirAccess.open(folder)
	if directory == null:
		return
	for file_name in directory.get_files():
		if file_name.get_extension().to_lower() in ["glb", "gltf"]:
			model_paths[file_name.to_lower()] = folder.path_join(file_name)
	for sub_folder in directory.get_directories():
		if not sub_folder.begins_with("."):
			collect_models(folder.path_join(sub_folder))

# The box around every mesh in a model, using each part's position inside the model
static func model_bounds(node, parent_transform, box):
	var here = parent_transform
	if node is Node3D:
		here = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var mesh_box = here * node.mesh.get_aabb()
		box = mesh_box if box == null else box.merge(mesh_box)
	for child in node.get_children():
		box = model_bounds(child, here, box)
	return box

# The middle of a model's main body, seen from above (x and z; y is the middle of the box). A plain box around
# the model gets pulled toward long wings and booms (Juno's three solar wings and its magnetometer arm, a dish on
# one side), so models centered on their box sat off-center on the turntable and in front of the camera. The body
# is where most of a model's points are (wings and booms are mostly flat panels with few points), so the middle of
# the points, half on each side, lands on the body.
static func body_center(model):
	var points = PackedVector3Array()
	collect_points(model, Transform3D.IDENTITY, points)
	var box = model_bounds(model, Transform3D.IDENTITY, null)
	if points.size() < 8 or box == null:
		return box.get_center() if box != null else Vector3.ZERO
	var across = []
	var deep = []
	for point in points:
		across.append(point.x)
		deep.append(point.z)
	across.sort()
	deep.sort()
	var middle = Vector3(across[across.size() / 2], box.get_center().y, deep[deep.size() / 2])
	# Stay inside the box (a model made of a few big flat panels could pull the middle out to an edge)
	middle.x = clamp(middle.x, box.position.x + box.size.x * 0.2, box.end.x - box.size.x * 0.2)
	middle.z = clamp(middle.z, box.position.z + box.size.z * 0.2, box.end.z - box.size.z * 0.2)
	return middle

# Every point of every mesh in a model (only some of them for very detailed meshes), placed where it is in the model
static func collect_points(node, parent_transform, points):
	var here = parent_transform
	if node is Node3D:
		here = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var arrays = node.mesh.surface_get_arrays(surface)
			if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var step = max(1, vertices.size() / 3000)
			for index in range(0, vertices.size(), step):
				points.append(here * vertices[index])
	for child in node.get_children():
		collect_points(child, here, points)

# A simple stand-in probe (gold box, white dish pointing along +Y, and a boom), used when a model file is missing
static func build_simple_probe():
	var probe = Node3D.new()
	var gold = StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.65, 0.25)
	gold.metallic = 0.6
	gold.roughness = 0.4
	var white = StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.9)
	var body = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.8, 0.5, 0.8)
	body.mesh = box
	body.material_override = gold
	probe.add_child(body)
	var dish = MeshInstance3D.new()
	var dish_mesh = CylinderMesh.new()
	dish_mesh.top_radius = 1.0
	dish_mesh.bottom_radius = 0.25
	dish_mesh.height = 0.3
	dish.mesh = dish_mesh
	dish.material_override = white
	dish.position = Vector3(0, 0.45, 0)
	probe.add_child(dish)
	var boom = MeshInstance3D.new()
	var boom_mesh = CylinderMesh.new()
	boom_mesh.top_radius = 0.03
	boom_mesh.bottom_radius = 0.03
	boom_mesh.height = 1.6
	boom.mesh = boom_mesh
	boom.material_override = white
	boom.rotation_degrees = Vector3(0, 0, 90)
	boom.position = Vector3(1.1, -0.1, 0)
	probe.add_child(boom)
	return probe

# Turns a model so its chosen side ("+y", "-z", ...) faces a direction (both in Godot coordinates)
static func facing_basis(side, direction):
	var forward = direction.normalized()
	var helper = Vector3.UP if abs(forward.y) < 0.95 else Vector3.RIGHT
	var across = helper.cross(forward).normalized()
	var other = forward.cross(across).normalized()
	# Basis that sends +Y to "forward"
	var y_forward = Basis(across, forward, -other)
	match side:
		"-z":
			return Basis(across, -other, -forward)   # sends -Z to "forward"
		"+z":
			return Basis(across, other, forward)
	return y_forward
