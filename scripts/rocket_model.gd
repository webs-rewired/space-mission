extends RefCounted

# Builds the rocket the player designed in the rocket builder, as separate pieces that can fall away
# during launch: the side boosters, the bottom stage, the top stage, the two fairing halves and the probe.
# Same shapes and real sizes as the rocket builder (1 unit = 1 meter; tank heights come from how much fuel they hold).

const RocketData = preload("res://scripts/rocket_data.gd")
const GIANT_BOOSTER_SCENE = "res://scenes/parts/giant_booster.tscn"
const SHUTTLE_BOOSTER_LENGTH = 45.24   # meters, nozzle to nose
const FLAME_SHADER = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform float flicker = 0.0;
varying vec3 local_position;
void vertex() {
	local_position = VERTEX;
}
void fragment() {
	// The flame mesh runs from y = 0.5 (engine) to y = -0.5 (tail): bright and white near the engine, orange and fading at the tail
	float along = clamp(0.5 - local_position.y, 0.0, 1.0);
	float rim = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	vec3 color = mix(core_color.rgb, edge_color.rgb, smoothstep(0.0, 0.6, along));
	float strength = (1.0 - along) * (0.55 + 0.45 * rim) * (0.85 + 0.15 * sin(TIME * 40.0 + local_position.y * 25.0 + flicker));
	ALBEDO = color * strength * 1.6;
	ALPHA = strength;
}
"""

static var flame_shader: Shader = null
static var flame_noise: NoiseTexture2D = null
const FLAME_SHADER_FILE = "res://shaders/rocket_flame.gdshader"

# How each kind of propellant burns: [core, middle, tail colors, brightness, shock diamonds, turbulence]
const FLAME_LOOKS = {
	"kerosene": [Color(1.0, 0.96, 0.82), Color(1.0, 0.6, 0.16), Color(0.8, 0.22, 0.04), 6.0, 0.45, 0.45],   # Merlin, RD-180: yellow-orange
	"hydrogen": [Color(0.86, 0.9, 1.0), Color(0.62, 0.68, 1.0), Color(0.45, 0.4, 0.85), 3.0, 1.3, 0.2],    # RS-25, RL10: nearly clear, with bright diamonds
	"methane": [Color(0.72, 0.78, 1.0), Color(1.0, 0.58, 0.38), Color(0.85, 0.32, 0.28), 5.0, 0.9, 0.35],  # Raptor: blue near the nozzle, then orange-pink
	"solid": [Color(1.0, 1.0, 0.93), Color(1.0, 0.82, 0.48), Color(1.0, 0.55, 0.2), 9.0, 0.15, 0.55],      # solid boosters: blinding white-yellow
}

# NASA's Shuttle booster model, standing up with its nozzle at y = 0 and 1 unit = 1 meter.
# Uses scenes/parts/giant_booster.tscn, or finds solid_rocket_booster.glb anywhere in the project. Null if it's missing.
static func load_giant_booster():
	if ResourceLoader.exists(GIANT_BOOSTER_SCENE) and ResourceLoader.exists("res://assets/rockets/solid_rocket_booster.glb"):
		var booster_scene = load(GIANT_BOOSTER_SCENE)
		if booster_scene is PackedScene:
			var booster = booster_scene.instantiate()
			if booster.get_child_count() > 0:
				return booster
			booster.free()
	var path = preload("res://scripts/spacecraft.gd").find_model("solid_rocket_booster.glb")
	if path == "" or not load(path) is PackedScene:
		return null
	var holder = Node3D.new()
	var model = load(path).instantiate()
	# The model lies along x in inches: stand it up and turn inches into meters
	model.transform = Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0).scaled(Vector3.ONE * 0.0254), Vector3(0, SHUTTLE_BOOSTER_LENGTH / 2.0, 0))
	holder.add_child(model)
	return holder

static func make_material(color, metallic = 0.0, roughness = 0.55):
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material

static func tank_height(tank):
	var radius = tank["radius"]
	var volume = tank["propellant"] / float(RocketData.FUEL_DENSITY[tank["fuel"]])
	return volume / (PI * radius * radius) + 1.5

static func add_cylinder(parent, top_radius, bottom_radius, height, place, material):
	var mesh_instance = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 40
	mesh.rings = 1
	mesh_instance.mesh = mesh
	mesh_instance.position = place
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

static func add_ogive(parent, radius, height, base_y, center, material):
	var steps = 10
	for step in steps:
		var lower_radius = radius * pow(cos(float(step) / steps * PI / 2.0), 0.6)
		var upper_radius = radius * pow(cos(float(step + 1) / steps * PI / 2.0), 0.6)
		var ring_height = height / steps
		add_cylinder(parent, upper_radius, lower_radius, ring_height, center + Vector3(0, base_y + ring_height * (step + 0.5), 0), material)

static func add_tank(parent, radius, height, base_y, fuel):
	var body = make_material(RocketData.TANK_COLORS[fuel], 0.25 if fuel == "methane" else 0.0, 0.45)
	var band = make_material(Color(0.12, 0.12, 0.13), 0.2, 0.6)
	add_cylinder(parent, radius, radius, height, Vector3(0, base_y + height / 2.0, 0), body)
	add_cylinder(parent, radius + 0.03, radius + 0.03, 0.4, Vector3(0, base_y + 0.2, 0), band)
	add_cylinder(parent, radius + 0.03, radius + 0.03, 0.4, Vector3(0, base_y + height - 0.2, 0), band)
	if fuel == "hydrogen":
		for stripe in range(1, 4):
			add_cylinder(parent, radius + 0.02, radius + 0.02, 0.15, Vector3(0, base_y + height * stripe / 4.0, 0), make_material(Color(0.7, 0.36, 0.12), 0.0, 0.8))

# Engine bells under a stage; returns the spots (x, z) where they sit, for the flames
static func add_engines(parent, count, tank_radius, bottom_y, bell_height):
	var bell_radius = clamp(tank_radius * 1.7 / (count + 1), 0.35, 1.3)
	var bell_material = make_material(Color(0.3, 0.3, 0.32), 0.9, 0.35)
	var chamber_material = make_material(Color(0.55, 0.5, 0.45), 0.8, 0.4)
	var spots = []
	if count == 1:
		spots.append(Vector2.ZERO)
	elif count >= 13:
		# Super Heavy style: 3 in the middle, 10 in an inner ring, the rest around the edge
		bell_radius = clamp(tank_radius * 3.1 / count, 0.3, 1.3)
		for index in 3:
			spots.append(Vector2(cos(TAU * index / 3.0), sin(TAU * index / 3.0)) * tank_radius * 0.12)
		for index in 10:
			spots.append(Vector2(cos(TAU * index / 10.0), sin(TAU * index / 10.0)) * tank_radius * 0.45)
		var outer = count - 13
		for index in outer:
			spots.append(Vector2(cos(TAU * index / outer), sin(TAU * index / outer)) * tank_radius * 0.85)
	else:
		var ring = count
		if count >= 7:
			spots.append(Vector2.ZERO)   # one in the middle, like Falcon 9
			ring = count - 1
		for index in ring:
			var angle = TAU * index / ring
			spots.append(Vector2(cos(angle), sin(angle)) * tank_radius * 0.62)
	for spot in spots:
		add_cylinder(parent, bell_radius * 0.35, bell_radius, bell_height, Vector3(spot.x, bottom_y + bell_height / 2.0, spot.y), bell_material)
		add_cylinder(parent, bell_radius * 0.4, bell_radius * 0.35, bell_height * 0.35, Vector3(spot.x, bottom_y + bell_height * 1.15, spot.y), chamber_material)
	return {"spots": spots, "bell_radius": bell_radius}

# A glowing exhaust flame pointing down from y = 0. Scale it to set its width and length.
static func make_flame(fuel = "kerosene"):
	if flame_shader == null:
		if ResourceLoader.exists(FLAME_SHADER_FILE):
			flame_shader = load(FLAME_SHADER_FILE)
		else:
			flame_shader = Shader.new()
			flame_shader.code = FLAME_SHADER
	if flame_noise == null:
		var noise = FastNoiseLite.new()
		noise.frequency = 0.02
		noise.fractal_octaves = 4
		flame_noise = NoiseTexture2D.new()
		flame_noise.noise = noise
		flame_noise.seamless = true
		flame_noise.width = 128
		flame_noise.height = 128
	var flame = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 0.25
	mesh.height = 1.0
	mesh.radial_segments = 24
	mesh.rings = 4
	mesh.cap_top = false
	mesh.cap_bottom = false
	flame.mesh = mesh
	var material = ShaderMaterial.new()
	material.shader = flame_shader
	material.set_shader_parameter("flicker", randf() * 10.0)
	var look = FLAME_LOOKS.get(fuel, FLAME_LOOKS["kerosene"])
	material.set_shader_parameter("core_color", look[0])
	material.set_shader_parameter("middle_color", look[1])
	material.set_shader_parameter("tail_color", look[2])
	material.set_shader_parameter("brightness", look[3])
	material.set_shader_parameter("diamonds", look[4])
	material.set_shader_parameter("turbulence", look[5])
	material.set_shader_parameter("seed", randf() * 10.0)
	material.set_shader_parameter("noise_texture", flame_noise)
	flame.material_override = material
	# Shift the cone so it hangs below its node: top (wide end) at y = 0, tail at y = -1
	var holder = Node3D.new()
	holder.set_meta("is_flame", true)   # so size measurements can leave the flames out
	holder.add_child(flame)
	flame.position = Vector3(0, -0.5, 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return holder

# Half of a surface of revolution (the fairing is split down the middle)
static func half_shell(profile, from_angle, material):
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps = 24
	for index in profile.size() - 1:
		var lower = profile[index]
		var upper = profile[index + 1]
		for step in steps:
			var angle_one = from_angle + PI * step / steps
			var angle_two = from_angle + PI * (step + 1) / steps
			var corners = [
				Vector3(cos(angle_one) * lower.x, lower.y, sin(angle_one) * lower.x),
				Vector3(cos(angle_two) * lower.x, lower.y, sin(angle_two) * lower.x),
				Vector3(cos(angle_two) * upper.x, upper.y, sin(angle_two) * upper.x),
				Vector3(cos(angle_one) * upper.x, upper.y, sin(angle_one) * upper.x)]
			for corner_index in [0, 2, 1, 0, 3, 2]:
				surface.add_vertex(corners[corner_index])
	surface.generate_normals()
	var shell = MeshInstance3D.new()
	shell.mesh = surface.commit()
	var two_sided = material.duplicate()
	two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	shell.material_override = two_sided
	return shell

# Builds the whole rocket. Returns its pieces and the places its flames attach.
static func build(rocket):
	var root = Node3D.new()
	root.name = "Rocket"
	var white = make_material(Color(0.95, 0.95, 0.95), 0.0, 0.4)
	var dark = make_material(Color(0.1, 0.1, 0.11), 0.3, 0.5)
	var pieces = {"root": root, "boosters": [], "booster_flames": [], "bottom_flames": [], "top_flames": [], "fairing": []}

	# Bottom stage (with the interstage on top, which falls away with it, like on a Falcon 9)
	var bottom = Node3D.new()
	bottom.name = "BottomStage"
	root.add_child(bottom)
	var bottom_tank = RocketData.TANKS[rocket["bottom_tank"]]
	var bottom_radius = bottom_tank["radius"]
	add_cylinder(bottom, bottom_radius, bottom_radius * 1.05, 2.0, Vector3(0, 4.0, 0), dark)
	var bottom_engines = add_engines(bottom, rocket["bottom_engine_count"], bottom_radius, 0.3, 2.8)
	var y = 5.0
	var bottom_height = tank_height(bottom_tank)
	add_tank(bottom, bottom_radius, bottom_height, y, bottom_tank["fuel"])
	y += bottom_height
	var top_tank = RocketData.TANKS[rocket["top_tank"]]
	var top_radius = top_tank["radius"]
	add_cylinder(bottom, top_radius, bottom_radius, 4.0, Vector3(0, y + 2.0, 0), dark)
	pieces["bottom"] = bottom
	for spot in bottom_engines["spots"]:
		var flame = make_flame(RocketData.ENGINES[rocket["bottom_engine"]]["fuel"])
		flame.position = Vector3(spot.x, 0.3, spot.y)
		flame.scale = Vector3(bottom_engines["bell_radius"] * 0.95, 14.0, bottom_engines["bell_radius"] * 0.95)
		bottom.add_child(flame)
		pieces["bottom_flames"].append(flame)

	# Side boosters
	var booster = RocketData.BOOSTERS[rocket["boosters"]]
	pieces["booster_count"] = booster["count"]
	for index in booster["count"]:
		# Two boosters sit on opposite sides (like SLS, lined up with the launch tower's hold-down posts); four go diagonally
		var angle = TAU * index / booster["count"] + (PI / 2.0 if booster["count"] == 2 else PI / 4.0)
		var distance_from_center = bottom_radius + booster["radius"] + 0.15
		var holder = Node3D.new()
		holder.name = "Booster%d" % (index + 1)
		holder.position = Vector3(cos(angle) * distance_from_center, 0, sin(angle) * distance_from_center)
		root.add_child(holder)
		var booster_height = booster["height"]
		var real_booster = load_giant_booster() if rocket["boosters"] == "giant_boosters_2" else null
		if real_booster != null:
			# NASA's 3D model of the Space Shuttle booster (45.2 m), stretched to SLS's 5-segment length
			real_booster.scale = Vector3(1.0, booster_height / SHUTTLE_BOOSTER_LENGTH, 1.0)
			holder.add_child(real_booster)
		else:
			add_cylinder(holder, booster["radius"], booster["radius"], booster_height, Vector3(0, 3.0 + booster_height / 2.0, 0), white)
			add_cylinder(holder, booster["radius"] + 0.04, booster["radius"] + 0.04, 0.5, Vector3(0, 3.0 + booster_height * 0.7, 0), dark)
			add_ogive(holder, booster["radius"], booster["radius"] * 3.0, 3.0 + booster_height, Vector3.ZERO, white)
			add_cylinder(holder, booster["radius"] * 0.5, booster["radius"] * 0.9, 2.2, Vector3(0, 1.9, 0), make_material(Color(0.3, 0.3, 0.32), 0.9, 0.35))
		var flame = make_flame("solid")
		flame.position = Vector3(0, 0.8, 0)
		flame.scale = Vector3(booster["radius"] * 0.95, 18.0, booster["radius"] * 0.95)
		holder.add_child(flame)
		pieces["boosters"].append(holder)
		pieces["booster_flames"].append(flame)

	# Top stage, with its engine sitting inside the interstage
	y += 4.0
	var top = Node3D.new()
	top.name = "TopStage"
	root.add_child(top)
	var top_engines = add_engines(top, rocket["top_engine_count"], top_radius, y - 3.2, 2.6)
	var top_height = tank_height(top_tank)
	add_tank(top, top_radius, top_height, y, top_tank["fuel"])
	pieces["top"] = top
	for spot in top_engines["spots"]:
		var flame = make_flame(RocketData.ENGINES[rocket["top_engine"]]["fuel"])
		flame.position = Vector3(spot.x, y - 3.2, spot.y)
		flame.scale = Vector3(top_engines["bell_radius"] * 1.1, 10.0, top_engines["bell_radius"] * 1.1)
		top.add_child(flame)
		pieces["top_flames"].append(flame)
	y += top_height

	# Probe (and kick stage) inside the fairing
	var payload = Node3D.new()
	payload.name = "Payload"
	top.add_child(payload)
	var payload_base = y + 1.2
	if rocket["kick_stage"] != "none":
		var kick = RocketData.KICK_STAGES[rocket["kick_stage"]]
		add_cylinder(payload, kick["radius"] * 0.6, kick["radius"], kick["height"], Vector3(0, payload_base + kick["height"] / 2.0, 0), make_material(Color(0.25, 0.25, 0.27), 0.6, 0.4))
		payload_base += kick["height"]
	var gold = make_material(Color(0.85, 0.65, 0.25), 0.7, 0.35)
	var probe_body = MeshInstance3D.new()
	var probe_box = BoxMesh.new()
	probe_box.size = Vector3(1.6, 1.4, 1.6)
	probe_body.mesh = probe_box
	probe_body.material_override = gold
	probe_body.position = Vector3(0, payload_base + 0.7, 0)
	payload.add_child(probe_body)
	add_cylinder(payload, 1.3, 0.3, 0.4, Vector3(0, payload_base + 1.65, 0), make_material(Color(0.93, 0.93, 0.9)))
	pieces["payload"] = payload

	# Fairing: two halves that split apart once the rocket is above the air
	var fairing_radius = max(top_radius, 2.2)
	var fairing_height = 6.0 + (2.0 if rocket["kick_stage"] != "none" else 0.0)
	var profile = [Vector2(top_radius, y), Vector2(fairing_radius, y + 1.2), Vector2(fairing_radius, y + 1.2 + fairing_height)]
	var nose_base = y + 1.2 + fairing_height
	for step in range(1, 11):
		var fraction = float(step) / 10.0
		profile.append(Vector2(max(0.02, fairing_radius * pow(cos(fraction * PI / 2.0), 0.6)), nose_base + fairing_radius * 2.6 * fraction))
	for half in 2:
		var shell = half_shell(profile, PI * half, white)
		shell.name = "FairingHalf%d" % (half + 1)
		top.add_child(shell)
		pieces["fairing"].append(shell)
	pieces["height"] = nose_base + fairing_radius * 2.6
	pieces["width"] = max(bottom_radius, fairing_radius) * 2.0
	return pieces
