extends Node

# Add this as a child node anywhere in the solar system scene (the "Textures" node).
# When the game starts, it finds the planets by name (Sun, Earth, Moon, Mars, Venus, Jupiter, Saturn) and:
#   - puts the real images on them
#   - adds glowing atmospheres, Earth's clouds and the Sun's glow
#   - gives Saturn real rings
#   - adds the starry sky
#   - makes every planet spin on its tilted axis (following the time controls)

const SpaceTextures = preload("res://scripts/space_textures.gd")

# How fast each body spins, compared with Earth (Earth = 1 turn per real day).
# A day on Jupiter is about 10 hours, so it spins about 2.4 times faster than Earth.
# Venus spins backwards and very slowly: one turn takes 243 Earth days.
const SPIN_COMPARED_WITH_EARTH = {
	"Sun": 0.04,       # about 25 days at its equator
	"Venus": -0.0041,  # about 243 days, backwards
	"Earth": 1.0,
	"Mars": 0.97,      # about 24.6 hours
	"Jupiter": 2.42,   # about 9.9 hours
	"Saturn": 2.24,    # about 10.7 hours
}

# How far each axis is tilted, in degrees.
# Venus is really tilted almost upside down (177 degrees), which is why it spins backwards.
# Here Venus uses 2.6 degrees with a backwards spin instead, which looks the same.
const AXIS_TILT_DEGREES = {
	"Sun": 7.25,
	"Venus": 2.6,
	"Earth": 23.4,
	"Mars": 25.2,
	"Jupiter": 3.1,
	"Saturn": 26.7,
}

# Atmosphere glow color and strength. Venus has a very thick atmosphere, Mars a very thin one.
const ATMOSPHERES = {
	"Earth": [Color(0.35, 0.6, 1.0), 1.2],
	"Venus": [Color(1.0, 0.85, 0.55), 1.4],
	"Mars": [Color(0.95, 0.6, 0.45), 0.5],
	"Jupiter": [Color(0.95, 0.85, 0.7), 0.45],
	"Saturn": [Color(0.95, 0.88, 0.7), 0.45],
}

const ATMOSPHERE_SHADER = """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;
uniform vec4 glow_color : source_color;
uniform float strength = 1.0;
void fragment() {
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = glow_color.rgb * pow(edge, 3.0) * strength;
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

# How many radians per second Earth spins in the game. Everything else is scaled from this.
@export var earth_spin_speed: float = 1.0
# How bright the night side of each planet is. Real space is very dark (about 0.05).
# Set this to -1 to keep the brightness from your WorldEnvironment instead.
@export var night_side_brightness: float = 0.08

# Each entry is [planet node, spin speed, tilt in degrees, current spin angle]
var spinning_planets = []
var saturn_rings: Node3D = null
var cloud_layer: Node3D = null
var scene_root: Node = null

func _ready():
	# The scene this node was saved in (the solar system), or else the node it sits under
	scene_root = owner
	if scene_root == null:
		scene_root = get_parent()

	for planet_name in SpaceTextures.PLANET_IMAGE_NAMES:
		var planet = scene_root.find_child(planet_name, true, false)
		if not planet is MeshInstance3D:
			continue
		SpaceTextures.texture_planet(planet, planet_name)
		var planet_radius = sphere_radius(planet)
		if ATMOSPHERES.has(planet_name):
			add_atmosphere(planet, planet_radius, ATMOSPHERES[planet_name][0], ATMOSPHERES[planet_name][1])
		if planet_name == "Earth":
			add_clouds(planet, planet_radius)
		if planet_name == "Sun":
			add_sun_glow(planet, planet_radius)
		if SPIN_COMPARED_WITH_EARTH.has(planet_name):
			var speed = SPIN_COMPARED_WITH_EARTH[planet_name] * earth_spin_speed
			spinning_planets.append([planet, speed, AXIS_TILT_DEGREES[planet_name], 0.0])

	var world_environment = find_world_environment(scene_root)
	SpaceTextures.add_star_sky(world_environment)
	if world_environment and world_environment.environment and night_side_brightness >= 0:
		world_environment.environment.ambient_light_energy = night_side_brightness

	# Markers and rings are added once the scene has finished loading
	call_deferred("add_markers_and_rings")

func _process(delta):
	var time_speed = GameState.time_speed
	for entry in spinning_planets:
		var planet = entry[0]
		entry[3] += entry[1] * delta * time_speed
		# The tilted axis keeps pointing the same way in space while the planet goes around the Sun,
		# just like Earth's axis always points toward the North Star.
		var tilt = Basis(Vector3.BACK, deg_to_rad(entry[2]))
		var spin = Basis(Vector3.UP, entry[3])
		var planet_scale = planet.global_transform.basis.get_scale()
		planet.global_transform.basis = (tilt * spin).scaled(planet_scale)

	if saturn_rings and saturn_rings.is_inside_tree():
		var ring_scale = saturn_rings.global_transform.basis.get_scale()
		saturn_rings.global_transform.basis = Basis(Vector3.BACK, deg_to_rad(AXIS_TILT_DEGREES["Saturn"])).scaled(ring_scale)

	# Earth's clouds drift a little faster than the ground
	if cloud_layer:
		cloud_layer.rotate_object_local(Vector3.UP, 0.03 * delta * time_speed * earth_spin_speed)

func sphere_radius(planet: MeshInstance3D):
	if planet.mesh is SphereMesh:
		return planet.mesh.radius
	return 1.0

func make_shell(radius):
	var shell = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 64
	mesh.rings = 32
	shell.mesh = mesh
	return shell

func add_atmosphere(planet, planet_radius, color, strength):
	var shell = make_shell(planet_radius * 1.05)
	shell.name = "Atmosphere"
	var shader = Shader.new()
	shader.code = ATMOSPHERE_SHADER
	var glow_material = ShaderMaterial.new()
	glow_material.shader = shader
	glow_material.set_shader_parameter("glow_color", color)
	glow_material.set_shader_parameter("strength", strength)
	shell.material_override = glow_material
	planet.add_child(shell)

func add_clouds(earth, earth_radius):
	var cloud_image = SpaceTextures.find_texture("earth_clouds")
	if cloud_image == null:
		print("Tip: add 2k_earth_clouds.jpg to the textures folder to give Earth clouds.")
		return
	cloud_layer = make_shell(earth_radius * 1.015)
	cloud_layer.name = "Clouds"
	var shader = Shader.new()
	shader.code = CLOUD_SHADER
	var cloud_material = ShaderMaterial.new()
	cloud_material.shader = shader
	cloud_material.set_shader_parameter("clouds", cloud_image)
	cloud_layer.material_override = cloud_material
	earth.add_child(cloud_layer)

func add_sun_glow(sun, sun_radius):
	var glow = MeshInstance3D.new()
	glow.name = "SunGlow"
	var quad = QuadMesh.new()
	quad.size = Vector2.ONE * sun_radius * 4.0
	glow.mesh = quad
	# A soft glow that fades quickly away from the Sun's edge (the edge is at the middle of the gradient)
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.48, 0.56, 0.7, 0.85, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.95, 0.8, 0.6),
		Color(1.0, 0.92, 0.75, 0.5),
		Color(1.0, 0.85, 0.6, 0.22),
		Color(1.0, 0.75, 0.45, 0.08),
		Color(1.0, 0.7, 0.4, 0.02),
		Color(1.0, 0.7, 0.4, 0.0),
	])
	var glow_texture = GradientTexture2D.new()
	glow_texture.gradient = gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(1.0, 0.5)
	glow_texture.width = 256
	glow_texture.height = 256
	var glow_material = StandardMaterial3D.new()
	glow_material.albedo_texture = glow_texture
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.material_override = glow_material
	sun.add_child(glow)

# Each planet gets a "Marker": an invisible point that follows the planet around the Sun
# but doesn't spin with it. Labels, gravity fields and moons hang off the marker,
# so they don't whirl around with the planet's day.
func add_markers_and_rings():
	for planet_name in SpaceTextures.PLANET_IMAGE_NAMES:
		var planet = scene_root.find_child(planet_name, true, false)
		if not planet is MeshInstance3D:
			continue
		var marker = Node3D.new()
		marker.name = planet_name + "Marker"
		planet.get_parent().add_child(marker)
		marker.position = planet.position

		# Move moons (like MoonOrbit under Earth) onto the marker so they don't spin with the planet
		for child in planet.get_children():
			if child is MeshInstance3D or not child is Node3D:
				continue
			if child.name.contains("Orbit") or child.find_child("Moon", true, false):
				var local_position = child.position
				child.reparent(marker, false)
				child.position = local_position

		if planet_name == "Saturn":
			replace_saturn_rings(planet, marker)

func replace_saturn_rings(saturn: MeshInstance3D, marker: Node3D):
	# Hide the old donut-shaped ring, if there is one
	for child in saturn.get_children():
		if child is MeshInstance3D and child.mesh is TorusMesh:
			child.visible = false
	saturn_rings = SpaceTextures.make_saturn_rings(sphere_radius(saturn))
	marker.add_child(saturn_rings)
	saturn_rings.scale = saturn.scale

func find_world_environment(node):
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var found = find_world_environment(child)
		if found:
			return found
	return null
