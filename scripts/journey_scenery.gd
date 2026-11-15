extends Node3D

# What the probe passes on its way, worked out from the real route on the real launch date.
#
# The route is the actual curve around the Sun from Earth (on the launch date) to the destination (on the
# arrival date), found with Lambert's problem like the Voyager routes (spacecraft.gd). Every time the route
# crosses a planet's orbit, we check where that planet really is at that moment. If it's close, you fly right
# past it (with its moons); if it's on the far side of the Sun, you see it small and far away. The planets
# hardly ever line up, which is why real missions pick their launch dates so carefully.
#
# The asteroid belt (2.1 to 3.3 AU from the Sun) and the Kuiper belt (30 to 50 AU) show up where the route
# crosses them. Real asteroids are about a million km apart, so no probe has ever had to dodge one, but here
# a few rocks sit near the path so crossing it is a challenge: launch.gd lets you steer around them.
#
# Long trips (like 4 years to Ceres) can't be one simple coast: real missions get there with flybys and several
# trips around the Sun. For those, the route is drawn as a smooth spiral from Earth's orbit to the destination's,
# so the probe never seems to swing out past its target.
#
# launch.gd calls set_up() with a function that turns trip progress (0 to 1) into a point on the drawn path.

const Spacecraft = preload("res://scripts/spacecraft.gd")
const OrbitMath = preload("res://scripts/orbit_math.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const SpaceTextures = preload("res://scripts/space_textures.gd")
const MoonSurfaces = preload("res://scripts/moon_surfaces.gd")
const BeltBuilder = preload("res://scripts/belt_builder.gd")

const ROCK_SHADER = preload("res://shaders/surface_rock.gdshader")
const ROCK_DETAIL = preload("res://assets/surface/textures/rock_detail.png")
const ROCK_NORMAL = preload("res://assets/surface/textures/rock_normal.png")
const REGOLITH_DETAIL = preload("res://assets/surface/textures/regolith_detail.png")
const ROCK_SHAPES = [
	preload("res://assets/surface/rocks/rock_angular_1_medium.glb"),
	preload("res://assets/surface/rocks/rock_angular_2_medium.glb"),
	preload("res://assets/surface/rocks/rock_angular_3_medium.glb"),
	preload("res://assets/surface/rocks/rock_cobble_medium.glb"),
	preload("res://assets/surface/rocks/rock_slab_medium.glb"),
]
const ICE_SHAPES = [
	preload("res://assets/surface/rocks/ice_block.glb"),
	preload("res://assets/surface/rocks/rock_cobble_medium.glb"),
	preload("res://assets/surface/rocks/rock_angular_2_medium.glb"),
]

const WARNING_RING = preload("res://assets/ui/warning_ring.png")

const KILOMETERS_PER_AU = 149597870.7
const ROUTE_STEPS = 600
const ROUTE_SWING_LIMIT = 1.12       # a coasting route may swing this far past its start and end distances from the Sun
const SHORTEST_BELT = 0.08           # a belt covers at least this share of the trip, so there's time to steer
const DODGE_ROCKS_PER_BELT = 12      # the rocks near the path (the ones you can hit)
const DODGE_REACH = 0.95             # they sit at most this far from the middle of the path (you can steer 1.4 away)
const ROCKS_FOR_DIFFICULTY = [0.5, 0.85, 1.3]   # fewer rocks for a Cadet, more for a Veteran
# Science shards: glowing bits of ice and dust in a belt that the probe can fly into for bonus science.
# They come in short lines of three, so flying straight through a line makes a combo (launch.gd counts them).
const SHARD_LINES_PER_BELT = 3
const SHARDS_PER_LINE = 3
const SHARD_REACH = 1.15
const SHARD_GLOW = preload("res://assets/ui/warning_ring.png")
const BACKGROUND_ROCKS = 420         # rocks too far from the path to hit: they make the belt look like a belt
const BACKGROUND_NEAREST = 2.6       # nothing you can't hit is closer to the path than this
const PASSING_PLANETS = ["Mercury", "Venus", "Mars", "Ceres", "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"]
const ASTEROID_BELT = [2.1, 3.3]
const KUIPER_BELT = [30.0, 50.0]
const MOONS_TO_SHOW = {"Jupiter": ["Io", "Europa", "Ganymede", "Callisto"], "Saturn": ["Enceladus", "Titan"],
	"Uranus": ["Titania"], "Neptune": ["Triton"], "Mars": ["Phobos", "Deimos"], "Pluto": ["Charon"]}

# What launch.gd reads
var sights = []          # {"name", "progress", "distance_au", "near", "node"}, in order along the route
var belts = []           # {"name", "start", "end"} as trip progress
var route_km = []        # where the probe is (km from the Sun) at each step of the trip, for launch.gd's live telemetry
var route_launch_date = 0.0
var route_days = 0.0
var dodge_rocks = []     # [position, radius, node, progress] of rocks close to the path (the ones you can hit)
var science_shards = []  # [position, node, progress] of the glowing science shards you can steer into in a belt
var probe_progress = 0.0 # where the probe is along the trip (launch.gd keeps this up to date), for the warning rings
const WARNING_DISTANCE = 0.06   # a rock gets its warning ring when the probe is this share of the trip away from it
var radius_by_progress = []   # distance from the Sun (AU) along the route

var path_point: Callable
var path_frame: Callable

func set_up(destination, launch_date, trip_days, path_point_function, path_frame_function):
	path_point = path_point_function
	path_frame = path_frame_function
	if trip_days < 20.0 or destination == "Moon":
		return   # a trip to the Moon stays close to Earth
	var data = SolarSystemData.BODIES.get(destination, {})
	var target_name = data.get("parent", destination) if data.get("kind", "") == "moon" else destination
	if not SolarSystemData.BODIES.has(target_name) or not SolarSystemData.BODIES[target_name].has("orbit"):
		return
	var seconds = trip_days * 86400.0
	var start = body_km("Earth", launch_date)
	var finish = body_km(target_name, launch_date + trip_days)
	var route = make_route(start, finish, seconds)
	route_km = route
	route_launch_date = launch_date
	route_days = trip_days
	var heading_out = Spacecraft.length(finish) > Spacecraft.length(start)
	var shown = {}
	for step in ROUTE_STEPS + 1:
		var progress = float(step) / ROUTE_STEPS
		var here = route[step]
		var radius = Spacecraft.length(here) / KILOMETERS_PER_AU
		radius_by_progress.append(radius)
		if step == 0:
			continue
		var previous_radius = radius_by_progress[step - 1]
		for body_name in PASSING_PLANETS:
			if body_name == target_name or body_name == destination or shown.has(body_name):
				continue
			# Only planets on the way: outward trips skip the inner planets (and inward trips the outer ones),
			# even if the route swings a little past them
			var orbit_size = SolarSystemData.BODIES[body_name]["orbit"].get("a", 0.0)
			if SolarSystemData.BODIES[body_name]["orbit"].has("jpl"):
				orbit_size = SolarSystemData.BODIES[body_name]["orbit"]["jpl"][0]
			if heading_out == (orbit_size < 1.0):
				continue
			var body_now = body_km(body_name, launch_date + progress * trip_days)
			var orbit_radius = Spacecraft.length(body_now) / KILOMETERS_PER_AU
			if (previous_radius - orbit_radius) * (radius - orbit_radius) < 0.0:
				var before = route[step - 1]
				var probe_velocity = [here[0] - before[0], here[1] - before[1], here[2] - before[2]]
				add_sight(body_name, progress, here, body_now, probe_velocity)
				shown[body_name] = true
		for belt in [["Asteroid belt", ASTEROID_BELT], ["Kuiper belt", KUIPER_BELT]]:
			var limits = belt[1]
			var inside_before = previous_radius >= limits[0] and previous_radius <= limits[1]
			var inside_now = radius >= limits[0] and radius <= limits[1]
			if inside_now and not inside_before:
				belts.append({"name": belt[0], "start": progress, "end": 1.0})
			elif inside_before and not inside_now:
				for each_belt in belts:
					if each_belt["name"] == belt[0] and each_belt["end"] == 1.0:
						each_belt["end"] = progress
	tidy_belts()
	# Starting inside a belt (a trip to Ceres starts outside it, but a trip to Pluto ends inside the Kuiper belt)
	for each_belt in belts:
		build_belt(each_belt)
	sights.sort_custom(func(first, second): return first["progress"] < second["progress"])

# Where the probe is at each step of the trip (kilometers from the Sun).
# First choice: the real coasting route (Lambert's problem). If that route would swing far past the destination or
# dive far inside Earth's orbit (it does when the trip is much longer than a direct coast), a smooth spiral is used.
func make_route(start, finish, seconds):
	var start_distance = Spacecraft.length(start)
	var finish_distance = Spacecraft.length(finish)
	var farthest_allowed = max(start_distance, finish_distance) * ROUTE_SWING_LIMIT
	var nearest_allowed = min(start_distance, finish_distance) / ROUTE_SWING_LIMIT
	var velocity = Spacecraft.lambert(start, finish, seconds)
	var route = []
	var sensible = true
	for step in ROUTE_STEPS + 1:
		var here = start if step == 0 else Spacecraft.coast(start, velocity, seconds * step / ROUTE_STEPS)[0]
		var distance = Spacecraft.length(here)
		if is_nan(distance) or distance > farthest_allowed or distance < nearest_allowed:
			sensible = false
			break
		route.append(here)
	if sensible:
		return route
	return spiral_route(start, finish, seconds)

# A smooth spiral: the distance from the Sun changes steadily from start to finish, and the probe goes around the
# Sun at the speed a real orbit would at each distance, ending exactly where the destination will be.
func spiral_route(start, finish, seconds):
	var start_distance = Spacecraft.length(start)
	var finish_distance = Spacecraft.length(finish)
	var start_angle = atan2(start[1], start[0])
	var finish_angle = atan2(finish[1], finish[0])
	# How far around the Sun a real orbit would travel in this time, at each distance along the way
	var swept = [0.0]
	var step_seconds = seconds / ROUTE_STEPS
	for step in ROUTE_STEPS:
		var distance = lerp(start_distance, finish_distance, (step + 0.5) / ROUTE_STEPS)
		swept.append(swept[step] + sqrt(Spacecraft.SUN_GRAVITY_KM / pow(distance, 3.0)) * step_seconds)
	# Turn that into whole trips around the Sun plus the last part, so the spiral ends at the destination
	var last_part = fposmod(finish_angle - start_angle, TAU)
	var whole_turns = max(0.0, round((swept[ROUTE_STEPS] - last_part) / TAU))
	var total_angle = last_part + whole_turns * TAU
	var route = []
	for step in ROUTE_STEPS + 1:
		var progress = float(step) / ROUTE_STEPS
		var distance = lerp(start_distance, finish_distance, progress)
		var angle = start_angle + total_angle * (swept[step] / max(swept[ROUTE_STEPS], 0.000001))
		var height = lerp(start[2], finish[2], progress)
		var flat = sqrt(max(distance * distance - height * height, 0.0))
		route.append([cos(angle) * flat, sin(angle) * flat, height])
	return route

# Joins belts that touch, drops repeats and makes sure every belt lasts long enough to steer through
func tidy_belts():
	var tidy = []
	for belt in belts:
		var joined = false
		for kept in tidy:
			if kept["name"] == belt["name"]:
				kept["start"] = min(kept["start"], belt["start"])
				kept["end"] = max(kept["end"], belt["end"])
				joined = true
		if not joined:
			tidy.append(belt)
	for belt in tidy:
		if belt["end"] - belt["start"] < SHORTEST_BELT:
			var middle = 0.5 * (belt["start"] + belt["end"])
			belt["start"] = clamp(middle - SHORTEST_BELT / 2.0, 0.1, 1.0 - SHORTEST_BELT)
			belt["end"] = belt["start"] + SHORTEST_BELT
		belt["start"] = max(belt["start"], 0.1)   # never during the departure from Earth
	belts = tidy

# Where the probe is (km from the Sun) at a point of the trip (0 to 1), between the route's steps
func probe_km(progress):
	if route_km.is_empty():
		return []
	var step = clamp(progress, 0.0, 1.0) * (route_km.size() - 1)
	var before = route_km[int(floor(step))]
	var after = route_km[min(int(floor(step)) + 1, route_km.size() - 1)]
	var share = step - floor(step)
	return [lerp(before[0], after[0], share), lerp(before[1], after[1], share), lerp(before[2], after[2], share)]

func body_km(body_name, julian_date):
	var au = OrbitMath.ecliptic_xyz(SolarSystemData.BODIES[body_name]["orbit"], julian_date)
	return [au[0] * KILOMETERS_PER_AU, au[1] * KILOMETERS_PER_AU, au[2] * KILOMETERS_PER_AU]

# A planet whose orbit the route crosses: placed beside the path in the real direction, nearer if it's really near
func add_sight(body_name, progress, probe_km, body_now_km, probe_velocity):
	var between = [body_now_km[0] - probe_km[0], body_now_km[1] - probe_km[1], body_now_km[2] - probe_km[2]]
	var distance_au = Spacecraft.length(between) / KILOMETERS_PER_AU
	var forward = Vector3(probe_velocity[0], probe_velocity[1], probe_velocity[2]).normalized()
	var north = Vector3(0, 0, 1)
	var side = forward.cross(north).normalized()
	var relative = Vector3(between[0], between[1], between[2]).normalized()
	var across = Vector2(relative.dot(side), relative.dot(north) * 0.5)
	if across.length() < 0.15:
		across = Vector2(1, 0.1)
	across = across.normalized()
	var near = distance_au < 1.0 or (distance_au < 3.0 and body_name in ["Jupiter", "Saturn", "Uranus", "Neptune"])
	var offset = clamp(2.5 + distance_au * 3.0, 3.0, 40.0)
	# Near planets sit a little ahead of the crossing point, so you see them coming
	var shown_at = min(progress + (0.03 if near else 0.0), 0.97)
	var frame = path_frame.call(shown_at)
	var place = path_point.call(shown_at) + (frame["side"] * across.x + frame["up"] * across.y) * offset
	var data = SolarSystemData.BODIES[body_name]
	var size = clamp(data["radius_km"] / 6371.0 * (0.8 if near else 0.5), 0.25 if near else 0.15, 3.5)
	var planet = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	planet.mesh = sphere
	planet.name = "Passing" + body_name
	add_child(planet)
	planet.position = place
	planet.scale = Vector3.ONE * size
	SpaceTextures.texture_planet(planet, body_name)
	if data.has("rings"):
		var rings = SpaceTextures.make_saturn_rings(1.0) if body_name == "Saturn" else SpaceTextures.make_rings(data["rings"], 1.0)
		planet.add_child(rings)
		planet.rotation_degrees.z = {"Saturn": 27.0, "Uranus": 98.0, "Neptune": 28.0, "Jupiter": 3.0}.get(body_name, 0.0)
	if near:
		add_moons(body_name, planet, size)
	var label = Label3D.new()
	label.text = "%s\n%s" % [data["label"], distance_text(distance_au)]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.004 * max(1.0, offset / 6.0)
	label.outline_size = 12
	label.modulate = data.get("label_color", Color.WHITE)
	label.position = place + Vector3(0, size * 1.3 + 0.4 * max(1.0, offset / 6.0), 0)
	add_child(label)
	sights.append({"name": body_name, "progress": progress, "distance_au": distance_au, "near": near, "node": planet})

func distance_text(distance_au):
	var kilometers = distance_au * KILOMETERS_PER_AU
	if kilometers < 10000000.0:
		return "%s million km away" % str(snapped(kilometers / 1000000.0, 0.1))
	return "%s AU away" % str(snapped(distance_au, 0.1))

# The biggest moons, circling their planet (sizes and spacing squeezed so they fit on screen)
func add_moons(body_name, planet, size):
	var index = 0
	for moon_name in MOONS_TO_SHOW.get(body_name, []):
		var moon_data = SolarSystemData.BODIES[moon_name]
		var moon = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		moon.mesh = sphere
		moon.material_override = MoonSurfaces.make_material(moon_name)
		var moon_size = clamp(moon_data["radius_km"] / 6371.0 * 0.5, 0.05, 0.3)
		var angle = TAU * index / 4.0 + 0.7
		var distance = 2.2 + 1.1 * index   # in planet radii (the moon is a child of the planet)
		moon.position = Vector3(cos(angle) * distance, 0.15 * sin(angle * 2.0), sin(angle) * distance)
		moon.scale = Vector3.ONE * (moon_size / size)
		planet.add_child(moon)
		index += 1

# Rocks along the stretch of the path inside a belt. A few sit near the path, spaced out so there is always a way
# around (those are the ones to dodge); the rest are too far away to hit and make the belt look like a belt.
func build_belt(belt):
	var icy = belt["name"] == "Kuiper belt"
	var random = RandomNumberGenerator.new()
	random.seed = hash(belt["name"]) + int(belt["start"] * 1000.0)
	var material = rock_material(icy)
	var shapes = []
	for scene in (ICE_SHAPES if icy else ROCK_SHAPES):
		var mesh = first_mesh(scene)
		if mesh:
			shapes.append(mesh)
	if shapes.is_empty():
		return
	var length = belt["end"] - belt["start"]
	var holder = Node3D.new()
	holder.name = belt["name"].replace(" ", "")
	add_child(holder)

	# The rocks to dodge: one at a time along the path, each on a different side from the one before
	var side_angle = random.randf() * TAU
	var rock_count = int(round(DODGE_ROCKS_PER_BELT * ROCKS_FOR_DIFFICULTY[GameState.difficulty]))
	for index in rock_count:
		var progress = belt["start"] + length * (index + 0.6 + random.randf_range(-0.2, 0.2)) / (rock_count + 0.4)
		if progress > 0.985:
			continue   # leave the last stretch clear for the arrival
		var frame = path_frame.call(progress)
		side_angle += random.randf_range(1.6, 3.4)
		var reach = random.randf_range(0.0, DODGE_REACH)
		var place = path_point.call(progress) + (frame["side"] * cos(side_angle) + frame["up"] * sin(side_angle)) * reach
		var rock_size = random.randf_range(0.2, 0.38)
		var rock = MeshInstance3D.new()
		rock.mesh = shapes[random.randi() % shapes.size()]
		rock.material_override = material
		rock.position = place
		rock.basis = Basis(Vector3(random.randf() - 0.5, random.randf() - 0.5, random.randf() - 0.5).normalized(), random.randf() * TAU).scaled(Vector3.ONE * rock_size)
		rock.set_meta("tumble_axis", Vector3(random.randf() - 0.5, random.randf() - 0.5, random.randf() - 0.5).normalized())
		rock.set_meta("tumble_speed", random.randf_range(0.15, 0.5))
		holder.add_child(rock)
		# An amber warning ring around it, shown when the probe gets near: "this one is in your way"
		var ring = MeshInstance3D.new()
		var ring_quad = QuadMesh.new()
		ring_quad.size = Vector2.ONE * 3.2   # (in the rock's own size)
		ring.mesh = ring_quad
		var ring_material = StandardMaterial3D.new()
		ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		ring_material.billboard_keep_scale = true
		ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_material.albedo_texture = WARNING_RING
		ring_material.no_depth_test = true
		ring.material_override = ring_material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.visible = false
		ring.name = "WarningRing"
		rock.add_child(ring)
		dodge_rocks.append([place, rock_size, rock, progress])

	add_science_shards(belt, holder, icy, random)

	# The rest of the belt: too far from the path to hit, drawn in groups (one group per rock shape)
	var groups = []
	for shape in shapes:
		groups.append([])
	for index in int((BACKGROUND_ROCKS if not icy else BACKGROUND_ROCKS * 0.7) * GameState.detail_share()):
		var progress = belt["start"] + random.randf() * length
		var frame = path_frame.call(progress)
		var angle = random.randf() * TAU
		var reach = BACKGROUND_NEAREST + pow(random.randf(), 1.6) * 22.0
		var place = path_point.call(progress) + (frame["side"] * cos(angle) + frame["up"] * sin(angle) * 0.6) * reach
		# Many small ones, few big ones; the far ones are bigger so they can still be seen
		var rock_size = lerp(0.05, 0.5, pow(random.randf(), 3.0)) * (1.0 + reach * 0.08)
		var turn = Basis(Vector3(random.randf() - 0.5, random.randf() - 0.5, random.randf() - 0.5).normalized(), random.randf() * TAU)
		var stretch = Vector3(random.randf_range(0.8, 1.3), random.randf_range(0.7, 1.1), random.randf_range(0.8, 1.3))
		groups[random.randi() % shapes.size()].append(Transform3D(turn.scaled(stretch * rock_size), place))
	for shape_index in shapes.size():
		var transforms = groups[shape_index]
		if transforms.is_empty():
			continue
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = shapes[shape_index]
		multimesh.instance_count = transforms.size()
		for index in transforms.size():
			multimesh.set_instance_transform(index, transforms[index])
		var instances = MultiMeshInstance3D.new()
		instances.multimesh = multimesh
		instances.material_override = material
		holder.add_child(instances)

	# A faint haze of dust, so the belt reads as a band
	var dust = CPUParticles3D.new()
	dust.amount = 260
	dust.lifetime = 100000.0
	dust.explosiveness = 1.0   # all the dust appears at once and just hangs there
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var middle = path_point.call(belt["start"] + length / 2.0)
	var span = path_point.call(belt["end"]).distance_to(path_point.call(belt["start"]))
	dust.emission_box_extents = Vector3(max(span / 2.0, 1.0), 4.0, 10.0)
	dust.position = middle
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.0
	dust.initial_velocity_max = 0.0
	dust.scale_amount_min = 0.008
	dust.scale_amount_max = 0.02
	var dot = SphereMesh.new()
	dot.radius = 1.0
	dot.height = 2.0
	dot.radial_segments = 6
	dot.rings = 3
	var dot_material = StandardMaterial3D.new()
	dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_material.albedo_color = Color(0.55, 0.6, 0.7) if icy else Color(0.45, 0.41, 0.37)
	dot.material = dot_material
	dust.mesh = dot
	holder.add_child(dust)

# Real rock, painted with the same rock photo as the rocks at the landing sites (icy and pale in the Kuiper belt)
func rock_material(icy):
	var material = ShaderMaterial.new()
	material.shader = ROCK_SHADER
	material.set_shader_parameter("rock_detail", ROCK_DETAIL)
	material.set_shader_parameter("rock_normal", ROCK_NORMAL)
	material.set_shader_parameter("regolith_detail", REGOLITH_DETAIL)
	material.set_shader_parameter("rock_color", Color(0.62, 0.66, 0.72) if icy else Color(0.42, 0.38, 0.34))
	material.set_shader_parameter("dust_amount", 0.0)
	material.set_shader_parameter("texture_scale", 2.6)
	material.set_shader_parameter("shade_variety", 0.5)
	material.set_shader_parameter("ice_sheen", 0.5 if icy else 0.0)
	return material

# The first mesh inside a model file, sized so it's about 1 unit across
var mesh_cache = {}
func first_mesh(scene):
	if mesh_cache.has(scene):
		return mesh_cache[scene]
	var model = scene.instantiate()
	var found = null
	var waiting = [model]
	while not waiting.is_empty() and found == null:
		var node = waiting.pop_front()
		if node is MeshInstance3D:
			found = node.mesh
		waiting.append_array(node.get_children())
	model.free()
	mesh_cache[scene] = found
	return found

# The science shards: short lines of glowing crystals at different places around the path
func add_science_shards(belt, holder, icy, random):
	var length = belt["end"] - belt["start"]
	var crystal_mesh = SphereMesh.new()   # with 4 sides and 2 rings a sphere becomes a pointed crystal
	crystal_mesh.radial_segments = 4
	crystal_mesh.rings = 2
	crystal_mesh.radius = 0.07
	crystal_mesh.height = 0.22
	var crystal_material = StandardMaterial3D.new()
	crystal_material.albedo_color = Color(0.75, 0.95, 1.0) if icy else Color(0.45, 1.0, 0.85)
	crystal_material.emission_enabled = true
	crystal_material.emission = crystal_material.albedo_color
	crystal_material.emission_energy_multiplier = 3.0
	crystal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow_material = StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.albedo_texture = SHARD_GLOW
	glow_material.albedo_color = Color(crystal_material.albedo_color, 0.8)
	var glow_quad = QuadMesh.new()
	glow_quad.size = Vector2.ONE * 0.55
	for line in SHARD_LINES_PER_BELT:
		var line_start = belt["start"] + length * (0.12 + 0.76 * (line + random.randf_range(0.1, 0.6)) / SHARD_LINES_PER_BELT)
		var angle = random.randf() * TAU
		var reach = random.randf_range(0.35, SHARD_REACH)
		for step in SHARDS_PER_LINE:
			var progress = line_start + step * length * 0.03
			if progress > 0.985:
				continue
			var frame = path_frame.call(progress)
			var place = path_point.call(progress) + (frame["side"] * cos(angle) + frame["up"] * sin(angle)) * reach
			var shard = MeshInstance3D.new()
			shard.mesh = crystal_mesh
			shard.material_override = crystal_material
			shard.position = place
			shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var glow = MeshInstance3D.new()
			glow.mesh = glow_quad
			glow.material_override = glow_material
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			shard.add_child(glow)
			holder.add_child(shard)
			science_shards.append([place, shard, progress])

# A shard the probe flew into: it flares up and vanishes in a puff of sparkles
func collect_shard(index):
	var node = science_shards[index][1]
	if not is_instance_valid(node) or not node.visible:
		return
	var flare = create_tween().set_parallel(true)
	flare.tween_property(node, "scale", Vector3.ONE * 3.0, 0.25)
	flare.chain().tween_callback(func(): node.visible = false)
	var sparkles = CPUParticles3D.new()
	sparkles.one_shot = true
	sparkles.emitting = true
	sparkles.amount = 24
	sparkles.lifetime = 0.9
	sparkles.explosiveness = 1.0
	sparkles.spread = 180.0
	sparkles.gravity = Vector3.ZERO
	sparkles.initial_velocity_min = 0.4
	sparkles.initial_velocity_max = 1.2
	sparkles.scale_amount_min = 0.02
	sparkles.scale_amount_max = 0.05
	var sparkle_mesh = SphereMesh.new()
	sparkle_mesh.radius = 0.5
	sparkle_mesh.height = 1.0
	sparkle_mesh.radial_segments = 4
	sparkle_mesh.rings = 2
	sparkles.mesh = sparkle_mesh
	sparkles.material_override = node.material_override
	sparkles.position = node.position
	node.get_parent().add_child(sparkles)
	get_tree().create_timer(1.5).timeout.connect(sparkles.queue_free)

# The rocks near the path tumble slowly
func _process(delta):
	for shard in science_shards:
		var node = shard[1]
		if is_instance_valid(node) and node.visible:
			node.rotate_y(delta * 2.0)
			node.position = shard[0] + Vector3(0, sin(Time.get_ticks_msec() / 1000.0 * 2.0 + shard[2] * 50.0) * 0.03, 0)
	for rock in dodge_rocks:
		var node = rock[2]
		if is_instance_valid(node) and node.visible:
			node.rotate(node.get_meta("tumble_axis"), node.get_meta("tumble_speed") * delta)
			var ahead = rock[3] - probe_progress
			var ring = node.get_node("WarningRing")
			ring.visible = ahead > -0.004 and ahead < WARNING_DISTANCE
			if ring.visible:
				ring.material_override.albedo_color.a = clamp((WARNING_DISTANCE - ahead) / (WARNING_DISTANCE * 0.4), 0.0, 1.0) * (0.75 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * 6.0))

# A rock the probe hit: it breaks into pieces that fly apart
func break_rock(index):
	var node = dodge_rocks[index][2]
	if not is_instance_valid(node) or not node.visible:
		return
	node.visible = false
	var pieces = CPUParticles3D.new()
	pieces.one_shot = true
	pieces.emitting = true
	pieces.amount = 18
	pieces.lifetime = 2.2
	pieces.explosiveness = 1.0
	pieces.spread = 180.0
	pieces.gravity = Vector3.ZERO
	pieces.initial_velocity_min = 0.25
	pieces.initial_velocity_max = 1.0
	pieces.angular_velocity_min = -200.0
	pieces.angular_velocity_max = 200.0
	pieces.scale_amount_min = dodge_rocks[index][1] * 0.15
	pieces.scale_amount_max = dodge_rocks[index][1] * 0.4
	pieces.mesh = node.mesh
	pieces.material_override = node.material_override
	pieces.position = node.position
	add_child(pieces)
	get_tree().create_timer(3.0).timeout.connect(pieces.queue_free)

# Which belt (if any) the probe is in at this point of the trip
func belt_at(progress):
	for belt in belts:
		if progress >= belt["start"] and progress <= belt["end"]:
			return belt
	return {}
