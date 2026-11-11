extends Node

# THE "Bodies" NODE: builds and moves everything in the solar system view.
# Put this script on the node that used to be called "Textures" (and rename that node "Bodies").
#
# When the scene starts it:
#   - finds the planets you made (Sun, Venus, Earth, Moon, Mars, Jupiter, Saturn) and creates the rest:
#     Mercury, Uranus, Neptune, the five dwarf planets (Ceres, Pluto, Haumea, Makemake, Eris) and four comets
#   - puts every body on its REAL orbit at its REAL position for today's date (NASA JPL orbit data),
#     so every orbit has its own size, stretch, tilt and direction
#   - tilts every body the real way and spins it at its real speed (IAU data), so day and night on Earth
#     fall on the right places for the real date and time
#   - adds textures, atmospheres, Earth's clouds and city lights, rings, comet tails and the animated Sun
#   - builds the asteroid belt (with its real gaps), Jupiter's Trojan asteroids and the Kuiper belt
#   - draws every orbit path
#
# TIME: GameState.time_speed is how many DAYS pass every real second (0 = paused, negative = backwards).
#
# WHY NOTHING JITTERS, EVEN AT TRUE SCALE: games store positions with limited precision, so far from the
# center of the game world positions get rounded and small things shake. This script keeps whatever the
# camera is looking at in the center of the world (a "floating origin") and moves the solar system around it.

const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const OrbitMath = preload("res://scripts/orbit_math.gd")
const SpaceTextures = preload("res://scripts/space_textures.gd")
const BeltBuilder = preload("res://scripts/belt_builder.gd")
const SunEffects = preload("res://scripts/sun_effects.gd")

signal built                  # everything is ready to use
signal layout_changed         # true scale was switched on or off
signal date_limit_reached     # time reached the year 1800 or 2200 and stopped

const EARLIEST_DATE = 2378496.5        # Jan 1, 1800 (NASA's planet table is made for 1800 to 2050)
const LATEST_DATE = 2524593.5          # Jan 1, 2200
const VIEWABLE_SUN_RADIUS = 2.0
const MOON_MASS_FRACTION = 0.0121506   # the Moon's share of the Earth + Moon mass
const SUN_GRAVITY_KM = 1.32712440018e11      # GM of the Sun, km³/s²
const EARTH_MOON_GRAVITY_KM = 403503.2       # GM of Earth + Moon, km³/s²
const LIGHT_SPEED_KM = 299792.458
const CAMERA_LIMITS_VIEWABLE = [0.05, 450.0]
const CAMERA_LIMITS_TRUE_SCALE = [0.0002, 15000.0]
const DAYS_BEFORE_REBUILDING_PATHS = 36525.0   # orbits slowly change shape over centuries

# How bright the night side of each planet is. Real space is very dark (about 0.05).
@export var night_side_brightness: float = 0.08
# The fastest Earth may visibly spin (radians per second). At high time speeds every body slows down
# by the same amount, so their spins stay in the right proportions without blurring.
@export var fastest_earth_spin: float = 1.5
@export var fastest_spin: float = 6.0
@export var asteroid_count: int = 4000
@export var trojan_count: int = 700
@export var kuiper_count: int = 4000

const ATMOSPHERE_SHADER = """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;
uniform vec4 glow_color : source_color;
uniform float strength = 1.0;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);   // from the planet toward the Sun
void fragment() {
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// The air glows on the day side and fades out past the line between day and night
	float daylight = smoothstep(-0.35, 0.3, dot(world_normal, sun_direction));
	ALBEDO = glow_color.rgb * pow(edge, 3.0) * strength * (0.06 + 0.94 * daylight);
}
"""

const CLOUD_SHADER = """
shader_type spatial;
render_mode cull_back, depth_draw_never;
uniform sampler2D clouds : source_color;
void fragment() {
	ALBEDO = vec3(1.0);
	ALPHA = texture(clouds, UV).r * 0.9;
	ROUGHNESS = 1.0;
}
"""

# Earth: the day map where the Sun shines, city lights on the night side
const EARTH_SURFACE_SHADER = """
shader_type spatial;
uniform sampler2D day_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D night_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform float city_light_strength = 1.6;
void fragment() {
	ALBEDO = texture(day_map, UV).rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float night = smoothstep(0.08, -0.18, dot(world_normal, sun_direction));
	vec3 lights = texture(night_map, UV).rgb;
	EMISSION = lights * lights * night * city_light_strength;
}
"""

const GRAVITY_FIELD_SHADER = """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;
uniform vec4 field_color : source_color;
void fragment() {
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = field_color.rgb * (0.06 + 0.45 * pow(edge, 2.0));
}
"""

# A comet tail: brightest along its middle and near the comet, fading toward the end, with faint streaks
const TAIL_SHADER = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
uniform vec4 tail_color : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform float brightness = 1.0;
void fragment() {
	float along = UV.y;
	float middle = pow(abs(dot(NORMAL, VIEW)), 2.0);
	float fade = pow(1.0 - along, 1.6) * smoothstep(0.0, 0.03, along);
	float streaks = 0.75 + 0.25 * sin(UV.x * 40.0 + along * 6.0 - TIME * 0.4);
	ALBEDO = tail_color.rgb * middle * fade * streaks * brightness;
}
"""

var julian_date = 0.0
var true_scale = false
var is_built = false
var scene_root: Node = null
var world: Node3D = null
var camera_pivot: Node3D = null
var sun_light: OmniLight3D = null
var sphere_mesh: SphereMesh = null
var tail_mesh: ArrayMesh = null
var focus_line: MeshInstance3D = null
var focus_line_mesh: ArrayMesh = null
var line_material_cache = {}

# The point in the solar system (in game units, with the Sun at 0) that sits at the center of the game world.
# Plain numbers in a list keep full precision; Vector3 would round them.
var origin = [0.0, 0.0, 0.0]
var home_origin = [0.0, 0.0, 0.0]

# name -> everything about that body (its nodes, position, spin...)
var bodies = {}
var missing_images = []

var orbit_lines_shown = true
var spin_axes_shown = false
var gravity_fields_shown = false
var hidden_kinds = {}          # "dwarf" or "comet" -> true when switched off
var lines_built_date = 0.0
var moon_line_date = 0.0

# Belts
var belts = {}                 # "asteroids", "trojans", "kuiper" -> belt node
var belt_shown = {"asteroids": true, "kuiper": true}
var belt_epoch = 0.0           # the date the belts were last placed
var belt_rocks = {}
var rocks_epoch = 0.0          # the date the rock lists were made

func _ready():
	process_priority = -100     # move the planets before the camera follows them, so the camera never lags
	add_to_group("solar_system_world")
	scene_root = owner if owner else get_parent()
	julian_date = OrbitMath.julian_date_now()
	# Wait until the whole scene has loaded before moving its planets around
	call_deferred("build_solar_system")

# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------
func build_solar_system():
	camera_pivot = scene_root.find_child("CameraPivot", true, false)
	world = Node3D.new()
	world.name = "SolarSystemWorld"
	add_child(world)

	var sun_node = scene_root.find_child("Sun", true, false)
	if sun_node is Node3D:
		var sun_start = sun_node.global_position
		home_origin = [-sun_start.x, -sun_start.y, -sun_start.z]
	origin = home_origin.duplicate()

	sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 1.0
	sphere_mesh.height = 2.0
	sphere_mesh.radial_segments = 96
	sphere_mesh.rings = 48
	tail_mesh = make_tail_mesh()

	for body_name in SolarSystemData.BODY_ORDER:
		add_body(body_name)
	stop_old_orbit_scripts()
	set_up_lighting()
	apply_sizes()

	focus_line = MeshInstance3D.new()
	focus_line.name = "FocusOrbitPath"
	focus_line_mesh = ArrayMesh.new()
	focus_line.mesh = focus_line_mesh
	world.add_child(focus_line)

	build_orbit_lines()
	build_belts()
	update_positions(0.0)

	if missing_images.size() > 0:
		print("Tip: these images weren't found in %s, so generated surfaces are used instead: %s" % [SpaceTextures.TEXTURE_FOLDER, ", ".join(missing_images)])
	is_built = true
	built.emit()

func add_body(body_name):
	var data = SolarSystemData.BODIES[body_name]
	var info = {"name": body_name, "data": data, "kind": data["kind"], "position": [0.0, 0.0, 0.0],
		"orbit_position": [0.0, 0.0, 0.0], "ecliptic": [0.0, 0.0, 0.0], "radius": 1.0, "line": null,
		"sun_facing_materials": []}
	var marker = Node3D.new()
	marker.name = body_name + "Marker"
	world.add_child(marker)
	info["marker"] = marker

	# Use the planet from the scene if there is one, otherwise make it
	var body = scene_root.find_child(body_name, true, false)
	if body != null and not body is MeshInstance3D:
		body = null
	if body == null:
		body = MeshInstance3D.new()
		body.name = body_name
		marker.add_child(body)
	else:
		clean_up_old_body(body)
		body.reparent(marker, false)
	body.transform = Transform3D.IDENTITY
	if info["kind"] == "comet":
		body.mesh = BeltBuilder.make_rock_mesh(abs(body_name.hash()) % 1000)
	else:
		body.mesh = sphere_mesh
	body.set_meta("body_name", body_name)
	info["mesh"] = body
	info["pole_basis"] = OrbitMath.pole_basis(data)
	info["prime_meridian"] = SolarSystemData.PRIME_MERIDIANS.get(body_name, [0.0, 360.0 * 24.0 / data["rotation_hours"]])
	info["spin_angle"] = OrbitMath.spin_angle_at(info["prime_meridian"], julian_date)
	info["shape"] = data.get("shape", Vector3.ONE)
	bodies[body_name] = info
	dress_body(info)

# Hides Saturn's old donut ring, and turns off the old click spheres (clicking is now worked out on screen,
# which also works for tiny planets at true scale)
func clean_up_old_body(body):
	for child in body.get_children():
		if child is MeshInstance3D and child.mesh is TorusMesh:
			child.visible = false
		elif child is CollisionObject3D:
			child.input_ray_pickable = false

func stop_old_orbit_scripts():
	for node in scene_root.find_children("*", "Node3D", true, false):
		if "orbit_speed" in node:
			node.set_process(false)
			node.rotation = Vector3.ZERO

func dress_body(info):
	var data = info["data"]
	var body = info["mesh"]
	var image = null
	if data["images"].size() > 0:
		image = SpaceTextures.find_texture(data["images"])
		if image == null:
			missing_images.append("2k_" + data["images"][0] + ".jpg")
	match info["kind"]:
		"star":
			var effects = SunEffects.new()
			effects.name = "SunEffects"
			info["marker"].add_child(effects)
			effects.set_up(body, 1.0, image)
			info["sun_effects"] = effects
		"comet":
			var rock_material = StandardMaterial3D.new()
			rock_material.albedo_color = data["color"]
			rock_material.roughness = 1.0
			body.material_override = rock_material
			add_comet_parts(info)
		_:
			body.material_override = make_surface_material(info, image)
	if data.has("atmosphere"):
		add_atmosphere(info)
	if data.has("clouds"):
		add_clouds(info)
	if data.has("rings"):
		var rings = SpaceTextures.make_rings(data["rings"], 1.0)
		info["marker"].add_child(rings)
		info["rings"] = rings
	add_spin_axis(info)
	if data["mass_earths"] > 0.0:
		add_gravity_field(info)

func make_surface_material(info, image):
	var data = info["data"]
	if image and data.has("night_lights"):
		var night_image = SpaceTextures.find_texture(data["night_lights"])
		if night_image:
			var shader = Shader.new()
			shader.code = EARTH_SURFACE_SHADER
			var earth_material = ShaderMaterial.new()
			earth_material.shader = shader
			earth_material.set_shader_parameter("day_map", image)
			earth_material.set_shader_parameter("night_map", night_image)
			info["sun_facing_materials"].append(earth_material)
			return earth_material
		missing_images.append("2k_" + data["night_lights"][0] + ".jpg")
	var surface_material = StandardMaterial3D.new()
	if image:
		surface_material.albedo_texture = image
	else:
		var banded = data["mass_earths"] > 5.0   # giant planets have cloud bands
		surface_material.albedo_texture = SpaceTextures.generated_surface(data["color"], banded, abs(info["name"].hash()) % 10000)
	surface_material.roughness = 0.9
	surface_material.metallic_specular = 0.2
	return surface_material

func make_shell(scale_factor):
	var shell = MeshInstance3D.new()
	shell.mesh = sphere_mesh
	shell.scale = Vector3.ONE * scale_factor
	return shell

func add_atmosphere(info):
	var shell = make_shell(1.025)
	shell.name = "Atmosphere"
	var shader = Shader.new()
	shader.code = ATMOSPHERE_SHADER
	var glow_material = ShaderMaterial.new()
	glow_material.shader = shader
	glow_material.set_shader_parameter("glow_color", info["data"]["atmosphere"][0])
	glow_material.set_shader_parameter("strength", info["data"]["atmosphere"][1])
	shell.material_override = glow_material
	info["mesh"].add_child(shell)
	info["sun_facing_materials"].append(glow_material)

func add_clouds(info):
	var cloud_image = SpaceTextures.find_texture(info["data"]["clouds"])
	if cloud_image == null:
		missing_images.append("2k_" + info["data"]["clouds"][0] + ".jpg")
		return
	var cloud_layer = make_shell(1.012)
	cloud_layer.name = "Clouds"
	var shader = Shader.new()
	shader.code = CLOUD_SHADER
	var cloud_material = ShaderMaterial.new()
	cloud_material.shader = shader
	cloud_material.set_shader_parameter("clouds", cloud_image)
	cloud_layer.material_override = cloud_material
	info["mesh"].add_child(cloud_layer)
	info["clouds"] = cloud_layer

# A thin line through the poles, so you can see each body's tilt. North is blue, south is red.
func add_spin_axis(info):
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	surface.set_color(Color(0.4, 0.8, 1.0))
	surface.add_vertex(Vector3(0, 1.0, 0))
	surface.add_vertex(Vector3(0, 1.8, 0))
	surface.set_color(Color(1.0, 0.45, 0.35))
	surface.add_vertex(Vector3(0, -1.0, 0))
	surface.add_vertex(Vector3(0, -1.8, 0))
	var axis = MeshInstance3D.new()
	axis.name = "SpinAxis"
	axis.mesh = surface.commit()
	var axis_material = StandardMaterial3D.new()
	axis_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	axis_material.vertex_color_use_as_albedo = true
	axis.material_override = axis_material
	axis.visible = spin_axes_shown
	info["marker"].add_child(axis)
	info["axis"] = axis

func add_gravity_field(info):
	var field = make_shell(1.0)
	field.name = "GravityField"
	var shader = Shader.new()
	shader.code = GRAVITY_FIELD_SHADER
	var field_material = ShaderMaterial.new()
	field_material.shader = shader
	field_material.set_shader_parameter("field_color", Color(0.4, 0.7, 1.0))
	field.material_override = field_material
	field.visible = false
	info["marker"].add_child(field)
	info["gravity_field"] = field

# ---------------------------------------------------------------------------
# Comets: a glowing cloud (the coma), a straight blue gas tail and a wider, curving dust tail.
# Both tails point away from the Sun and grow as the comet gets closer to it.
# ---------------------------------------------------------------------------
func make_tail_mesh():
	# A cone that starts at the comet and flares out along +Y, 1 unit long
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps_along = 16
	var steps_around = 24
	for step in steps_along:
		for around in steps_around:
			for corner in [[step, around], [step + 1, around], [step + 1, around + 1], [step, around], [step + 1, around + 1], [step, around + 1]]:
				var along = float(corner[0]) / steps_along
				var angle = TAU * corner[1] / steps_around
				var width = 0.12 + 0.88 * pow(along, 0.6)
				var normal = Vector3(cos(angle), 0.0, sin(angle))
				surface.set_normal(normal)
				surface.set_uv(Vector2(float(corner[1]) / steps_around, along))
				surface.add_vertex(Vector3(cos(angle) * width, along, sin(angle) * width))
	return surface.commit()

func make_tail(tail_name, color):
	var tail = MeshInstance3D.new()
	tail.name = tail_name
	tail.mesh = tail_mesh
	var shader = Shader.new()
	shader.code = TAIL_SHADER
	var tail_material = ShaderMaterial.new()
	tail_material.shader = shader
	tail_material.set_shader_parameter("tail_color", color)
	tail.material_override = tail_material
	tail.visible = false
	return tail

func add_comet_parts(info):
	var marker = info["marker"]
	var coma = MeshInstance3D.new()
	coma.name = "Coma"
	var quad = QuadMesh.new()
	quad.size = Vector2.ONE
	coma.mesh = quad
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(0.9, 1.0, 1.0, 0.9), Color(0.6, 0.9, 1.0, 0.5), Color(0.4, 0.75, 1.0, 0.12), Color(0.3, 0.6, 1.0, 0.0)])
	var coma_texture = GradientTexture2D.new()
	coma_texture.gradient = gradient
	coma_texture.fill = GradientTexture2D.FILL_RADIAL
	coma_texture.fill_from = Vector2(0.5, 0.5)
	coma_texture.fill_to = Vector2(1.0, 0.5)
	var coma_material = StandardMaterial3D.new()
	coma_material.albedo_texture = coma_texture
	coma_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	coma_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	coma_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	coma_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	coma_material.billboard_keep_scale = true
	coma.material_override = coma_material
	coma.visible = false
	marker.add_child(coma)
	info["coma"] = coma
	info["ion_tail"] = make_tail("GasTail", Color(0.45, 0.7, 1.0))
	info["dust_tail"] = make_tail("DustTail", Color(1.0, 0.9, 0.72))
	marker.add_child(info["ion_tail"])
	marker.add_child(info["dust_tail"])

func update_comet(info):
	var ecliptic = info["ecliptic"]
	var distance_au = sqrt(ecliptic[0] * ecliptic[0] + ecliptic[1] * ecliptic[1] + ecliptic[2] * ecliptic[2])
	# Ice turns to gas as the comet nears the Sun: almost nothing past about 4 AU, a lot inside 1 AU
	var activity = clamp(1.0 / (distance_au * distance_au), 0.0, 6.0) * smoothstep(4.5, 2.0, distance_au)
	var active = activity > 0.01
	info["coma"].visible = active
	info["ion_tail"].visible = active
	info["dust_tail"].visible = active
	if not active:
		return
	var size_factor = clamp(sqrt(info["data"]["radius_km"] / 5.5), 0.6, 2.5)   # bigger cores make bigger tails
	var tail_length_au = 0.06 * activity * size_factor
	# Game units per AU here: exact at true scale; in the viewable layout distances are squeezed, so tails are too
	var units_per_au = OrbitMath.TRUE_SCALE_UNITS_PER_AU if true_scale else 6.0 * pow(distance_au, -0.4)
	var tail_length = tail_length_au * units_per_au
	var marker = info["marker"]
	var away_from_sun = (marker.position - bodies["Sun"]["marker"].position).normalized()
	# Which way the comet is moving (to bend the dust tail back along its path)
	var ahead = OrbitMath.game_xyz(OrbitMath.ecliptic_xyz(info["data"]["orbit"], julian_date + 0.5), true_scale)
	var position = info["position"]
	var moving = Vector3(ahead[0] - position[0], ahead[1] - position[1], ahead[2] - position[2]).normalized()
	var dust_direction = (away_from_sun - moving * 0.35).normalized()
	info["ion_tail"].basis = Basis(Quaternion(Vector3.UP, away_from_sun)) * Basis.from_scale(Vector3(tail_length * 0.04, tail_length, tail_length * 0.04))
	info["dust_tail"].basis = Basis(Quaternion(Vector3.UP, dust_direction)) * Basis.from_scale(Vector3(tail_length * 0.11, tail_length * 0.7, tail_length * 0.11))
	var brightness = clamp(activity, 0.2, 1.5)
	info["ion_tail"].material_override.set_shader_parameter("brightness", brightness)
	info["dust_tail"].material_override.set_shader_parameter("brightness", brightness * 0.8)
	var coma_size = (0.05 if true_scale else 0.35) * sqrt(clamp(activity, 0.0, 2.0)) * sqrt(size_factor)
	info["coma"].scale = Vector3.ONE * coma_size

# ---------------------------------------------------------------------------
# Light, sizes and the starry sky
# ---------------------------------------------------------------------------
func set_up_lighting():
	var sun_info = bodies["Sun"]
	for child in sun_info["mesh"].get_children():
		if child is OmniLight3D:
			sun_light = child
	if sun_light == null:
		sun_light = OmniLight3D.new()
		sun_light.light_energy = 8.0
		sun_info["marker"].add_child(sun_light)
	else:
		# The light hangs off the Sun's marker so the Sun's size and spin don't change it
		sun_light.reparent(sun_info["marker"], false)
	sun_light.position = Vector3.ZERO
	sun_light.shadow_enabled = false

	var world_environment = find_world_environment(scene_root)
	SpaceTextures.add_star_sky(world_environment)
	if world_environment and world_environment.environment:
		if night_side_brightness >= 0.0:
			world_environment.environment.ambient_light_energy = night_side_brightness
		orient_star_sky(world_environment.environment)

# The Milky Way image is drawn with the galaxy's middle across its middle. In the real sky the galaxy
# is tilted about 60° to the planets' orbits, with its center toward Sagittarius. This turns the sky to match.
func orient_star_sky(environment):
	if environment.sky == null:
		return
	# Directions of the galactic north pole and the galactic center, in the ecliptic frame (J2000)
	var galactic_north = OrbitMath.to_godot(OrbitMath.equatorial_to_ecliptic(sky_direction(192.85948, 27.12825))).normalized()
	var galactic_center = OrbitMath.to_godot(OrbitMath.equatorial_to_ecliptic(sky_direction(266.40510, -28.936175))).normalized()
	# Godot shows a panorama's middle (the galactic center in this image) toward +Z and its top toward +Y,
	# with the left of the image toward +X (galactic longitude grows to the left on sky maps)
	var sky_basis = Basis(galactic_north.cross(galactic_center).normalized(), galactic_north, galactic_center)
	sky_basis = sky_basis.orthonormalized()
	environment.sky_rotation = sky_basis.get_euler()

func sky_direction(right_ascension_degrees, declination_degrees):
	var right_ascension = deg_to_rad(right_ascension_degrees)
	var declination = deg_to_rad(declination_degrees)
	return Vector3(cos(declination) * cos(right_ascension), cos(declination) * sin(right_ascension), sin(declination))

func apply_light_range():
	if sun_light == null:
		return
	sun_light.omni_range = 15000.0 if true_scale else 600.0
	sun_light.omni_attenuation = 0.25 if true_scale else 0.3

func find_world_environment(node):
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var found = find_world_environment(child)
		if found:
			return found
	return null

# How big each body is drawn: real size at true scale; otherwise squeezed so small worlds stay visible
func display_radius(body_name):
	var info = bodies[body_name]
	var data = info["data"]
	if true_scale:
		return data["radius_km"] / SolarSystemData.KILOMETERS_PER_AU * OrbitMath.TRUE_SCALE_UNITS_PER_AU
	if body_name == "Sun":
		return VIEWABLE_SUN_RADIUS
	var radius = 0.5 * pow(data["radius_km"] / SolarSystemData.EARTH_RADIUS_KM, 0.45)
	if info["kind"] == "comet":
		radius *= 3.0    # comet cores are only a few km wide; drawn 3 times bigger so you can find them
	return radius

func apply_sizes():
	for body_name in bodies:
		var info = bodies[body_name]
		var radius = display_radius(body_name)
		info["radius"] = radius
		info["mesh"].set_meta("radius", radius * max(info["shape"].x, max(info["shape"].y, info["shape"].z)))
		if info.has("rings"):
			info["rings"].transform = Transform3D(info["pole_basis"].scaled(Vector3.ONE * radius), Vector3.ZERO)
		info["axis"].transform = Transform3D(info["pole_basis"].scaled(Vector3.ONE * radius * info["shape"].y), Vector3.ZERO)
		if info.has("gravity_field"):
			var mass = info["data"]["mass_earths"]
			var field_radius = radius * 1.3 + 0.8 * (log(1.0 + mass * 10.0) / log(10.0))
			info["gravity_field"].scale = Vector3.ONE * field_radius
			info["gravity_field"].visible = gravity_fields_shown and not true_scale
		if info.has("sun_effects"):
			info["sun_effects"].scale = Vector3.ONE * radius

# ---------------------------------------------------------------------------
# Every frame
# ---------------------------------------------------------------------------
func _process(delta):
	if not is_built:
		return
	julian_date += delta * GameState.time_speed
	if julian_date < EARLIEST_DATE or julian_date > LATEST_DATE:
		julian_date = clamp(julian_date, EARLIEST_DATE, LATEST_DATE)
		GameState.time_speed = 0.0
		date_limit_reached.emit()
	update_positions(delta)

func update_positions(delta):
	calculate_positions()
	move_origin()
	for body_name in bodies:
		var info = bodies[body_name]
		var position = info["position"]
		info["marker"].position = Vector3(position[0] - origin[0], position[1] - origin[1], position[2] - origin[2])
	spin_bodies(delta)

	var sun_position = bodies["Sun"]["marker"].position
	for body_name in bodies:
		var info = bodies[body_name]
		if info["sun_facing_materials"].size() > 0:
			var toward_sun = (sun_position - info["marker"].position).normalized()
			for facing_material in info["sun_facing_materials"]:
				facing_material.set_shader_parameter("sun_direction", toward_sun)
		if info.has("clouds") and GameState.time_speed != 0.0:
			# Clouds drift slowly over the ground
			info["clouds"].rotate_object_local(Vector3.UP, 0.01 * delta * sign(GameState.time_speed))
		if info["kind"] == "comet" and info["marker"].visible:
			update_comet(info)

	update_focus_line()
	update_belts(sun_position)
	if abs(julian_date - moon_line_date) > 0.5:
		build_orbit_line(bodies["Moon"])
	if abs(julian_date - lines_built_date) > DAYS_BEFORE_REBUILDING_PATHS:
		build_orbit_lines()

# Real positions for the current date, in game units with the Sun at 0
func calculate_positions():
	for body_name in SolarSystemData.BODY_ORDER:
		var info = bodies[body_name]
		var orbit = info["data"].get("orbit")
		if orbit == null:
			continue
		var ecliptic = OrbitMath.ecliptic_xyz(orbit, julian_date)
		info["ecliptic"] = ecliptic
		if info["kind"] == "moon":
			var offset = OrbitMath.moon_offset_game_xyz(ecliptic, true_scale)
			var earth = bodies["Earth"]
			if true_scale:
				# NASA's table gives the middle point that Earth and the Moon both circle (4,700 km from
				# Earth's center). At true scale that matters, so Earth and the Moon sit on either side of it.
				var middle = earth["orbit_position"]
				earth["position"] = [middle[0] - offset[0] * MOON_MASS_FRACTION, middle[1] - offset[1] * MOON_MASS_FRACTION, middle[2] - offset[2] * MOON_MASS_FRACTION]
				var moon_share = 1.0 - MOON_MASS_FRACTION
				info["position"] = [middle[0] + offset[0] * moon_share, middle[1] + offset[1] * moon_share, middle[2] + offset[2] * moon_share]
			else:
				var earth_position = earth["position"]
				info["position"] = [earth_position[0] + offset[0], earth_position[1] + offset[1], earth_position[2] + offset[2]]
			info["orbit_position"] = info["position"]
		else:
			var position = OrbitMath.game_xyz(ecliptic, true_scale)
			info["position"] = position
			info["orbit_position"] = position

func followed_body():
	if camera_pivot and "followed_planet" in camera_pivot:
		var body_name = camera_pivot.followed_planet
		if bodies.has(body_name) and is_body_shown(body_name):
			return body_name
	return ""

# Keeps the camera's target at the center of the game world (see the note at the top)
func move_origin():
	var new_origin = origin
	var focus = followed_body()
	if focus != "":
		new_origin = bodies[focus]["position"].duplicate()
	elif camera_pivot:
		var pivot_position = camera_pivot.global_position
		new_origin = [origin[0] + pivot_position.x, origin[1] + pivot_position.y, origin[2] + pivot_position.z]
	if camera_pivot:
		camera_pivot.global_position -= Vector3(new_origin[0] - origin[0], new_origin[1] - origin[1], new_origin[2] - origin[2])
	origin = new_origin

# Puts the Sun back where it started (used when the camera view is reset)
func reset_origin():
	origin = home_origin.duplicate()

func spin_bodies(delta):
	var days_per_second = GameState.time_speed
	var earth_spin = deg_to_rad(360.9856235) * abs(days_per_second)
	var slow_down = 1.0 if earth_spin <= fastest_earth_spin else fastest_earth_spin / earth_spin
	for body_name in bodies:
		var info = bodies[body_name]
		var real_angle = OrbitMath.spin_angle_at(info["prime_meridian"], julian_date)
		if info["data"].get("locked", false):
			info["spin_angle"] = real_angle   # the Moon keeps the same face toward Earth at any speed
		else:
			var real_spin = deg_to_rad(info["prime_meridian"][1]) * days_per_second
			var shown_spin = clamp(real_spin * slow_down, -fastest_spin, fastest_spin)
			info["spin_angle"] += shown_spin * delta
			if is_equal_approx(shown_spin, real_spin):
				# Spinning at the real speed, so slide gently onto the real angle for today's date and time
				info["spin_angle"] += wrapf(real_angle - info["spin_angle"], -PI, PI) * min(1.0, 2.0 * delta)
			info["spin_angle"] = fposmod(info["spin_angle"], TAU)
		var orientation = info["pole_basis"] * Basis(Vector3.UP, info["spin_angle"]) * Basis.from_scale(info["shape"] * info["radius"])
		info["mesh"].transform = Transform3D(orientation, Vector3.ZERO)

# ---------------------------------------------------------------------------
# Orbit paths
# ---------------------------------------------------------------------------
func line_material(color, strength):
	var key = str(color) + str(strength)
	if not line_material_cache.has(key):
		var path_material = StandardMaterial3D.new()
		path_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		path_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		path_material.albedo_color = Color(color.r, color.g, color.b, strength)
		line_material_cache[key] = path_material
	return line_material_cache[key]

func line_strength(info):
	match info["kind"]:
		"comet":
			return 0.22
		"dwarf":
			return 0.28
	return 0.4

func build_orbit_lines():
	lines_built_date = julian_date
	for body_name in bodies:
		if bodies[body_name]["data"].has("orbit"):
			build_orbit_line(bodies[body_name])

func build_orbit_line(info):
	if info["line"] != null:
		info["line"].queue_free()
	var is_moon = info["kind"] == "moon"
	var point_count = 256 if is_moon else 720
	var points = OrbitMath.orbit_path_points(info["data"]["orbit"], julian_date, point_count, true_scale, is_moon)
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		surface.add_vertex(point)
	var line = MeshInstance3D.new()
	line.name = info["name"] + "OrbitPath"
	line.mesh = surface.commit()
	line.material_override = line_material(info["data"]["label_color"], line_strength(info))
	# Paths around the Sun hang off the Sun's marker; the Moon's path hangs off Earth's
	var parent = bodies["Earth"]["marker"] if is_moon else bodies["Sun"]["marker"]
	parent.add_child(line)
	info["line"] = line
	if is_moon:
		moon_line_date = julian_date
	update_line_visibility(info)

func update_line_visibility(info):
	if info["line"] != null:
		info["line"].visible = orbit_lines_shown and is_body_shown(info["name"]) and info["name"] != followed_body()

# The path of the body the camera follows is redrawn every frame around the body itself, with points packed
# tightly near it, so it passes exactly through the body even when you zoom right in at true scale.
func update_focus_line():
	var focus = followed_body()
	for body_name in bodies:
		update_line_visibility(bodies[body_name])
	if focus == "" or not bodies[focus]["data"].has("orbit") or not orbit_lines_shown:
		focus_line.visible = false
		return
	var info = bodies[focus]
	var elements = OrbitMath.elements_at(info["data"]["orbit"], julian_date)
	var eccentric_now = OrbitMath.solve_kepler(elements["mean_anomaly"], elements["e"])
	var is_moon = info["kind"] == "moon"
	var center = bodies["Earth"]["position"] if is_moon else [0.0, 0.0, 0.0]
	var anchor = info["orbit_position"]

	# How far the body travels for a tiny step around its orbit, to pick a fine enough first step
	var here = path_point(elements, eccentric_now, is_moon, center)
	var nearby = path_point(elements, eccentric_now + 0.000001, is_moon, center)
	var step_length = Vector3(nearby[0] - here[0], nearby[1] - here[1], nearby[2] - here[2]).length() / 0.000001
	var first_step = max(1e-9, 0.05 * info["radius"] / max(step_length, 1e-12))
	var offsets = [0.0]
	var step = first_step
	while step < PI:
		offsets.push_front(-step)
		offsets.push_back(step)
		step *= 1.12
	offsets.push_front(-PI)
	offsets.push_back(PI)

	var points = PackedVector3Array()
	for offset in offsets:
		var point = path_point(elements, eccentric_now + offset, is_moon, center)
		points.append(Vector3(point[0] - anchor[0], point[1] - anchor[1], point[2] - anchor[2]))
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	focus_line_mesh.clear_surfaces()
	focus_line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	focus_line.material_override = line_material(info["data"]["label_color"], line_strength(info) + 0.15)
	# The focused body sits at the world center; Earth's path is drawn through Earth itself
	focus_line.position = Vector3.ZERO
	focus_line.visible = true

func path_point(elements, eccentric, is_moon, center):
	var ecliptic = OrbitMath.position_xyz(elements, eccentric)
	var point = OrbitMath.moon_offset_game_xyz(ecliptic, true_scale) if is_moon else OrbitMath.game_xyz(ecliptic, true_scale)
	return [center[0] + point[0], center[1] + point[1], center[2] + point[2]]

# ---------------------------------------------------------------------------
# Belts
# ---------------------------------------------------------------------------
func build_belts():
	for belt_name in belts:
		belts[belt_name].queue_free()
	belts.clear()
	if belt_rocks.is_empty():
		rocks_epoch = julian_date
		var jupiter = OrbitMath.ecliptic_xyz(SolarSystemData.BODIES["Jupiter"]["orbit"], julian_date)
		var jupiter_longitude = atan2(jupiter[1], jupiter[0])
		belt_rocks["asteroids"] = BeltBuilder.main_belt_rocks(asteroid_count, 2026)
		belt_rocks["trojans"] = BeltBuilder.trojan_rocks(trojan_count, jupiter_longitude, 2027)
		belt_rocks["kuiper"] = BeltBuilder.kuiper_rocks(kuiper_count, 2028)
	belt_epoch = julian_date
	var days_ahead = julian_date - rocks_epoch
	var sun_marker = bodies["Sun"]["marker"]
	# Rocks are drawn far bigger than real at true scale (real asteroids would be invisible specks)
	var sizes = {"asteroids": 0.35, "trojans": 0.45, "kuiper": 5.0} if true_scale else {"asteroids": 0.035, "trojans": 0.04, "kuiper": 0.2}
	# Real asteroids are dark, like charcoal or old asphalt; Kuiper belt objects are icy and reddish
	var colors = {"asteroids": Color(0.34, 0.31, 0.28), "trojans": Color(0.3, 0.25, 0.22), "kuiper": Color(0.62, 0.52, 0.47)}
	var names = {"asteroids": "AsteroidBelt", "trojans": "JupiterTrojans", "kuiper": "KuiperBelt"}
	for belt_name in ["asteroids", "trojans", "kuiper"]:
		var belt = BeltBuilder.make_belt(names[belt_name], belt_rocks[belt_name], sizes[belt_name], colors[belt_name], true_scale, belt_name.length() * 7, days_ahead)
		sun_marker.add_child(belt)
		belts[belt_name] = belt
	apply_belt_visibility()

func update_belts(sun_position):
	if abs(julian_date - belt_epoch) > DAYS_BEFORE_REBUILDING_PATHS:
		build_belts()   # start fresh now and then, so very long runs stay precise
	for belt_name in belts:
		var belt_material = belts[belt_name].get_meta("belt_material")
		belt_material.set_shader_parameter("days_passed", julian_date - belt_epoch)
		belt_material.set_shader_parameter("sun_center", sun_position)

func apply_belt_visibility():
	if belts.has("asteroids"):
		belts["asteroids"].visible = belt_shown["asteroids"]
		belts["trojans"].visible = belt_shown["asteroids"]
		belts["kuiper"].visible = belt_shown["kuiper"]

# ---------------------------------------------------------------------------
# For the controls and the stats panel
# ---------------------------------------------------------------------------
func set_true_scale(on):
	if on == true_scale or not is_built:
		return
	true_scale = on
	apply_sizes()
	apply_light_range()
	var focus = followed_body()
	if focus == "":
		# Look at the whole solar system from the Sun
		origin = [0.0, 0.0, 0.0] if on else home_origin.duplicate()
		if camera_pivot:
			camera_pivot.position = Vector3.ZERO
	calculate_positions()
	if focus != "":
		origin = bodies[focus]["position"].duplicate()
	update_positions(0.0)
	build_orbit_lines()
	build_belts()
	if camera_pivot:
		var limits = CAMERA_LIMITS_TRUE_SCALE if on else CAMERA_LIMITS_VIEWABLE
		camera_pivot.min_distance = limits[0]
		camera_pivot.max_distance = limits[1]
		if focus != "" and camera_pivot.has_method("follow_planet"):
			camera_pivot.follow_planet(focus)
		elif camera_pivot.has_method("zoom_to"):
			camera_pivot.zoom_to(260.0 if on else camera_pivot.start_distance)
	layout_changed.emit()

func reset_to_today():
	julian_date = OrbitMath.julian_date_now()
	build_orbit_lines()

func set_orbit_lines_visible(on):
	orbit_lines_shown = on
	for body_name in bodies:
		update_line_visibility(bodies[body_name])

func set_spin_axes_visible(on):
	spin_axes_shown = on
	for body_name in bodies:
		bodies[body_name]["axis"].visible = on

func set_gravity_fields_visible(on):
	gravity_fields_shown = on
	for body_name in bodies:
		if bodies[body_name].has("gravity_field"):
			bodies[body_name]["gravity_field"].visible = on and not true_scale

func set_belt_visible(belt_name, on):
	belt_shown[belt_name] = on
	apply_belt_visibility()

# kind is "dwarf" (dwarf planets) or "comet"
func set_kind_visible(kind, on):
	hidden_kinds[kind] = not on
	for body_name in bodies:
		var info = bodies[body_name]
		if info["kind"] == kind:
			info["marker"].visible = on
			update_line_visibility(info)
	if not on and camera_pivot and "followed_planet" in camera_pivot and bodies.has(camera_pivot.followed_planet):
		if bodies[camera_pivot.followed_planet]["kind"] == kind:
			camera_pivot.followed_planet = ""

func is_body_shown(body_name):
	return not hidden_kinds.get(bodies[body_name]["kind"], false)

func body_names():
	return SolarSystemData.BODY_ORDER

func body_node(body_name):
	return bodies[body_name]["mesh"] if bodies.has(body_name) else null

func body_marker(body_name):
	return bodies[body_name]["marker"] if bodies.has(body_name) else null

func body_radius(body_name):
	return bodies[body_name]["mesh"].get_meta("radius", 1.0) if bodies.has(body_name) else 1.0

# A live line for the stats panel, like "Right now: 0.99 AU from the Sun, moving at 30.2 km/s"
func live_facts(body_name):
	if not bodies.has(body_name) or not bodies[body_name]["data"].has("orbit"):
		return ""
	var info = bodies[body_name]
	var ecliptic = info["ecliptic"]
	var distance_au = sqrt(ecliptic[0] * ecliptic[0] + ecliptic[1] * ecliptic[1] + ecliptic[2] * ecliptic[2])
	var distance_km = distance_au * SolarSystemData.KILOMETERS_PER_AU
	var elements = OrbitMath.elements_at(info["data"]["orbit"], julian_date)
	var size_km = elements["a"] * SolarSystemData.KILOMETERS_PER_AU
	if info["kind"] == "moon":
		var moon_speed = sqrt(EARTH_MOON_GRAVITY_KM * (2.0 / distance_km - 1.0 / size_km))
		return "Right now: %s km from Earth, moving at %.2f km/s around it" % [format_number(distance_km), moon_speed]
	# Vis-viva equation: speed from distance to the Sun and the orbit's size
	var speed = sqrt(SUN_GRAVITY_KM * (2.0 / distance_km - 1.0 / size_km))
	var light_minutes = distance_km / LIGHT_SPEED_KM / 60.0
	var light_text = "%.1f minutes" % light_minutes if light_minutes < 120.0 else "%.1f hours" % (light_minutes / 60.0)
	return "Right now: %.3f AU (%s million km) from the Sun, moving at %.1f km/s. Sunlight takes %s to get there." % [
		distance_au, format_number(distance_km / 1000000.0), speed, light_text]

func format_number(number):
	var digits = str(int(round(number)))
	var result = ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return digits + result
