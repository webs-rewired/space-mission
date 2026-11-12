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
# the belt is packed tight so crossing it is a challenge: launch.gd lets you steer through it.
#
# launch.gd calls set_up() with a function that turns trip progress (0 to 1) into a point on the drawn path.

const Spacecraft = preload("res://scripts/spacecraft.gd")
const OrbitMath = preload("res://scripts/orbit_math.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const SpaceTextures = preload("res://scripts/space_textures.gd")
const MoonSurfaces = preload("res://scripts/moon_surfaces.gd")
const BeltBuilder = preload("res://scripts/belt_builder.gd")

const KILOMETERS_PER_AU = 149597870.7
const ROUTE_STEPS = 600
const PASSING_PLANETS = ["Mercury", "Venus", "Mars", "Ceres", "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"]
const ASTEROID_BELT = [2.1, 3.3]
const KUIPER_BELT = [30.0, 50.0]
const MOONS_TO_SHOW = {"Jupiter": ["Io", "Europa", "Ganymede", "Callisto"], "Saturn": ["Enceladus", "Titan"],
	"Uranus": ["Titania"], "Neptune": ["Triton"], "Mars": ["Phobos", "Deimos"], "Pluto": ["Charon"]}

# What launch.gd reads
var sights = []          # {"name", "progress", "distance_au", "near", "node"}, in order along the route
var belts = []           # {"name", "start", "end"} as trip progress
var dodge_rocks = []     # [position, radius] of rocks close to the path (the ones you can hit)
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
	var velocity = Spacecraft.lambert(start, finish, seconds)
	var previous = []
	var shown = {}
	for step in ROUTE_STEPS + 1:
		var progress = float(step) / ROUTE_STEPS
		var here = start if step == 0 else Spacecraft.coast(start, velocity, progress * seconds)[0]
		var radius = Spacecraft.length(here) / KILOMETERS_PER_AU
		radius_by_progress.append(radius)
		if not previous.is_empty():
			var previous_radius = Spacecraft.length(previous) / KILOMETERS_PER_AU
			var heading_out = Spacecraft.length(finish) > Spacecraft.length(start)
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
					var probe_velocity = Spacecraft.coast(start, velocity, progress * seconds)[1]
					add_sight(body_name, progress, here, body_now, probe_velocity)
					shown[body_name] = true
			for belt in [["Asteroid belt", ASTEROID_BELT], ["Kuiper belt", KUIPER_BELT]]:
				var limits = belt[1]
				var crossing_in = (previous_radius - limits[0]) * (radius - limits[0]) < 0.0
				if crossing_in:
					belts.append({"name": belt[0], "start": progress, "end": 1.0})
				var crossing_out = (previous_radius - limits[1]) * (radius - limits[1]) < 0.0
				if crossing_out:
					for each_belt in belts:
						if each_belt["name"] == belt[0] and each_belt["end"] == 1.0:
							each_belt["end"] = progress
		previous = here
	# Starting inside a belt (a trip to Ceres starts outside it, but a trip to Pluto ends inside the Kuiper belt)
	for each_belt in belts:
		build_belt(each_belt)
	sights.sort_custom(func(first, second): return first["progress"] < second["progress"])

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

# Rocks along the stretch of the path inside a belt. Some sit right on the path (those are the ones to dodge).
func build_belt(belt):
	var rock_mesh = BeltBuilder.make_rock_mesh(7, 0.35, true)
	var icy = belt["name"] == "Kuiper belt"
	var rock_material = StandardMaterial3D.new()
	rock_material.albedo_color = Color(0.62, 0.66, 0.75) if icy else Color(0.42, 0.38, 0.34)
	rock_material.roughness = 0.95
	var instances = MultiMeshInstance3D.new()
	instances.name = belt["name"].replace(" ", "")
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = rock_mesh
	var count = 380 if not icy else 260
	var close_count = 40
	multimesh.instance_count = count
	var length = belt["end"] - belt["start"]
	for index in count:
		var progress = belt["start"] + randf() * length
		var frame = path_frame.call(progress)
		var close_to_path = index < close_count
		var reach = randf_range(0.0, 1.2) if close_to_path else randf_range(2.0, 16.0)
		var angle = randf() * TAU
		var place = path_point.call(progress) + (frame["side"] * cos(angle) + frame["up"] * sin(angle) * 0.6) * reach
		var rock_size = randf_range(0.04, 0.09) if close_to_path else randf_range(0.02, 0.14)
		var turn = Basis(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized(), randf() * TAU)
		multimesh.set_instance_transform(index, Transform3D(turn.scaled(Vector3.ONE * rock_size), place))
		if close_to_path:
			dodge_rocks.append([place, rock_size])
	instances.multimesh = multimesh
	instances.material_override = rock_material
	add_child(instances)
	# A faint haze of dust and tiny rocks, so the belt reads as a band
	var dust = CPUParticles3D.new()
	dust.amount = 300
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
	dust.scale_amount_min = 0.02
	dust.scale_amount_max = 0.05
	var dot = SphereMesh.new()
	dot.radius = 1.0
	dot.height = 2.0
	dot.radial_segments = 6
	dot.rings = 3
	var dot_material = StandardMaterial3D.new()
	dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_material.albedo_color = Color(0.7, 0.75, 0.85) if icy else Color(0.6, 0.55, 0.5)
	dot.material = dot_material
	dust.mesh = dot
	add_child(dust)

# Which belt (if any) the probe is in at this point of the trip
func belt_at(progress):
	for belt in belts:
		if progress >= belt["start"] and progress <= belt["end"]:
			return belt
	return {}
