extends Node3D

# The launch, before the trip: a countdown, liftoff from the pad, then the climb to orbit with the
# boosters, the bottom stage and the fairing falling away, then the burn that sends the probe on its way.
#
# It's YOUR rocket from the rocket builder, and the timing comes from your design: how long the boosters
# and the bottom stage burn depends on how much fuel they hold and how fast your engines use it
# (a Falcon 9 bottom stage burns out after about 2.5 minutes, the SLS core after about 8).
# Time runs faster than real life (the clock in the corner shows real mission time).
#
# launch.gd adds this node, waits for "finished" (also sent when the player presses Skip), then starts the trip.

signal finished

const RocketModel = preload("res://scripts/rocket_model.gd")
const RocketData = preload("res://scripts/rocket_data.gd")
const SpaceTextures = preload("res://scripts/space_textures.gd")

const GRAVITY = 9.81
const PAD_SHOT_SECONDS = 25.0       # real mission seconds watched from the ground camera
const PAD_SHOT_TIME_SPEED = 3.0     # how much faster than real time the liftoff plays
const HIGH_SHOT_GAME_SECONDS = 24.0 # how long (in game seconds) the climb to orbit and the escape burn take
const EARTH_RADIUS_UNITS = 1500.0   # the Earth below in the high view (its curve is exaggerated so you can see it)
const UNITS_PER_KILOMETER = 0.5
const ROCKET_SIZE_HIGH = 6.0        # how tall the rocket is drawn in the high view
const ORBIT_SPEED = 7.8             # km/s in low Earth orbit
const ORBIT_ALTITUDE = 200.0        # km

const ATMOSPHERE_SHADER = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
void fragment() {
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float glow = pow(edge, 3.0);
	ALBEDO = vec3(0.35, 0.6, 1.0) * glow * 1.4;
	ALPHA = glow;
}
"""

var world_environment: WorldEnvironment = null
var space_environment: Environment = null
var sky_environment: Environment = null
var pieces = {}
var rocket_root: Node3D
var pad_world: Node3D
var high_world: Node3D
var earth_ball: MeshInstance3D
var camera: Camera3D
var sun: DirectionalLight3D
var smoke: CPUParticles3D

var timeline = []              # [real mission seconds, event name], in order
var next_event = 0
var mission_seconds = -3.0     # real mission time: starts at T-3 for the countdown
var compression = 18.0
var in_high_shot = false
var flames_on = {"booster": false, "bottom": false, "top": false}
var falling_pieces = []        # {"node", "velocity", "spin", "age"}
var report = {}
var booster_seconds = -1.0
var main_engine_cutoff_seconds = 150.0
var fairing_seconds = 200.0
var orbit_seconds = 500.0
var escape_start_seconds = 560.0
var escape_end_seconds = 700.0
var cutoff_speed = 2.3
var cutoff_altitude = 70.0
var final_speed = 11.0
var liftoff_acceleration = 4.0
var finished_sent = false
var travel_angle = 0.0

var caption: Label
var caption_seconds_left = 0.0
var telemetry: Label
var fade: ColorRect

# Sets everything up and starts the countdown. "environment_node" is the scene's WorldEnvironment (its starry
# sky is used once the rocket is in space).
func start(environment_node):
	world_environment = environment_node
	if world_environment:
		space_environment = world_environment.environment
	report = GameState.rocket_report()
	work_out_timeline()
	build_pad_world()
	build_high_world()
	build_rocket()
	build_screen()
	if world_environment:
		world_environment.environment = sky_environment
	camera.current = true
	show_caption("3")

# ---------------------------------------------------------------------------
# When things happen, from the rocket's design
# ---------------------------------------------------------------------------
func work_out_timeline():
	var rocket = GameState.rocket
	var bottom_engine = RocketData.ENGINES[rocket["bottom_engine"]]
	var bottom_tank = RocketData.TANKS[rocket["bottom_tank"]]
	var top_engine = RocketData.ENGINES[rocket["top_engine"]]
	var top_tank = RocketData.TANKS[rocket["top_tank"]]
	var booster = RocketData.BOOSTERS[rocket["boosters"]]
	# Fuel used per second = thrust / (Isp × g)
	var core_isp = (bottom_engine["isp_sea_level"] + bottom_engine["isp_vacuum"]) / 2.0
	var core_fuel_per_second = bottom_engine["thrust_sea_level"] * 1000.0 * rocket["bottom_engine_count"] / (core_isp * GRAVITY)
	main_engine_cutoff_seconds = clamp(bottom_tank["propellant"] / core_fuel_per_second, 60.0, 600.0)
	if booster["count"] > 0:
		var booster_fuel_per_second = booster["thrust_each"] * 1000.0 / (booster["isp"] * GRAVITY)
		booster_seconds = min(booster["propellant_each"] / booster_fuel_per_second, main_engine_cutoff_seconds - 8.0)
	var top_fuel_per_second = top_engine["thrust_vacuum"] * 1000.0 * rocket["top_engine_count"] / (top_engine["isp_vacuum"] * GRAVITY)
	var top_burn_seconds = top_tank["propellant"] / top_fuel_per_second
	# How much of the top stage's fuel it takes to finish reaching orbit (about 9.4 km/s counting losses)
	var still_needed = max(9400.0 - report["bottom_stage_speed"], 300.0)
	var share_to_orbit = clamp(still_needed / max(report["top_stage_speed"], 1.0), 0.1, 0.9)
	orbit_seconds = main_engine_cutoff_seconds + 8.0 + max(30.0, top_burn_seconds * share_to_orbit)
	fairing_seconds = clamp(main_engine_cutoff_seconds + 40.0, 150.0, 230.0)
	fairing_seconds = min(fairing_seconds, orbit_seconds - 10.0)
	escape_start_seconds = orbit_seconds + 60.0
	escape_end_seconds = escape_start_seconds + clamp(top_burn_seconds * (1.0 - share_to_orbit), 40.0, 400.0)
	# What the clock, altimeter and speedometer show along the way
	var bottom_share = clamp(report["bottom_stage_speed"] / 9400.0, 0.2, 0.95)
	cutoff_speed = ORBIT_SPEED * pow(bottom_share, 1.6)
	cutoff_altitude = 60.0 + 110.0 * bottom_share * bottom_share
	final_speed = ORBIT_SPEED + (report["speed_needed"] - 9400.0) / 1000.0
	liftoff_acceleration = GRAVITY * (clamp(report["liftoff_thrust_to_weight"], 1.15, 3.0) - 1.0)
	compression = max(12.0, (escape_end_seconds + 3.0 - PAD_SHOT_SECONDS) / HIGH_SHOT_GAME_SECONDS)

	timeline = [[0.0, "liftoff"]]
	if booster_seconds > 0.0:
		timeline.append([booster_seconds, "boosters"])
	timeline.append([main_engine_cutoff_seconds, "cutoff"])
	timeline.append([main_engine_cutoff_seconds + 3.0, "separation"])
	timeline.append([main_engine_cutoff_seconds + 7.0, "top_ignition"])
	timeline.append([fairing_seconds, "fairing"])
	timeline.append([orbit_seconds, "orbit"])
	timeline.append([escape_start_seconds, "escape"])
	timeline.append([escape_end_seconds, "probe"])
	timeline.sort_custom(func(first, second): return first[0] < second[0])

# ---------------------------------------------------------------------------
# Building the two views
# ---------------------------------------------------------------------------
func build_pad_world():
	pad_world = Node3D.new()
	add_child(pad_world)
	sky_environment = Environment.new()
	var sky = Sky.new()
	var sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.16, 0.32, 0.62)
	sky_material.sky_horizon_color = Color(0.72, 0.78, 0.86)
	sky_material.ground_horizon_color = Color(0.6, 0.62, 0.6)
	sky_material.ground_bottom_color = Color(0.25, 0.27, 0.22)
	sky.sky_material = sky_material
	sky_environment.background_mode = Environment.BG_SKY
	sky_environment.sky = sky
	sky_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky_environment.ambient_light_color = Color(0.85, 0.85, 0.82)
	sky_environment.ambient_light_energy = 0.55
	sky_environment.tonemap_mode = Environment.TONE_MAPPER_ACES

	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(6000, 6000)
	ground.mesh = plane
	ground.position.y = -0.05
	ground.material_override = RocketModel.make_material(Color(0.32, 0.4, 0.24), 0.0, 0.95)
	pad_world.add_child(ground)
	var pad = MeshInstance3D.new()
	var pad_mesh = CylinderMesh.new()
	pad_mesh.top_radius = 32
	pad_mesh.bottom_radius = 34
	pad_mesh.height = 1.0
	pad.mesh = pad_mesh
	pad.position.y = -0.5
	pad.material_override = RocketModel.make_material(Color(0.4, 0.4, 0.39), 0.0, 1.0)
	pad_world.add_child(pad)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.3
	add_child(sun)

	# Clouds of exhaust and steam billowing out from the pad
	smoke = CPUParticles3D.new()
	smoke.amount = 160
	smoke.lifetime = 4.0
	smoke.emitting = false
	smoke.direction = Vector3(0, 0.15, 0)
	smoke.spread = 90.0
	smoke.flatness = 0.85
	smoke.initial_velocity_min = 18.0
	smoke.initial_velocity_max = 34.0
	smoke.damping_min = 6.0
	smoke.damping_max = 9.0
	smoke.gravity = Vector3(0, 1.5, 0)
	smoke.scale_amount_min = 6.0
	smoke.scale_amount_max = 12.0
	var grow = Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 2.2))
	smoke.scale_amount_curve = grow
	var puff = QuadMesh.new()
	puff.size = Vector2(1, 1)
	var puff_material = StandardMaterial3D.new()
	puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.albedo_texture = soft_dot_texture()
	puff_material.albedo_color = Color(0.92, 0.92, 0.9, 0.55)
	puff_material.vertex_color_use_as_albedo = true
	puff.material = puff_material
	smoke.mesh = puff
	var fade_out = Gradient.new()
	fade_out.set_color(0, Color(1, 1, 1, 0.9))
	fade_out.set_color(1, Color(1, 1, 1, 0.0))
	smoke.color_ramp = fade_out
	smoke.position = Vector3(0, 1.0, 0)
	pad_world.add_child(smoke)

	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 20000.0
	add_child(camera)

func soft_dot_texture():
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture

func build_high_world():
	high_world = Node3D.new()
	high_world.visible = false
	add_child(high_world)
	earth_ball = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = EARTH_RADIUS_UNITS
	sphere.height = EARTH_RADIUS_UNITS * 2.0
	sphere.radial_segments = 256
	sphere.rings = 128
	earth_ball.mesh = sphere
	SpaceTextures.texture_planet(earth_ball, "Earth")
	high_world.add_child(earth_ball)
	var air = MeshInstance3D.new()
	var air_sphere = SphereMesh.new()
	air_sphere.radius = EARTH_RADIUS_UNITS * 1.012
	air_sphere.height = air_sphere.radius * 2.0
	air_sphere.radial_segments = 256
	air_sphere.rings = 128
	air.mesh = air_sphere
	var air_material = ShaderMaterial.new()
	var air_shader = Shader.new()
	air_shader.code = ATMOSPHERE_SHADER
	air_material.shader = air_shader
	air.material_override = air_material
	earth_ball.add_child(air)

func build_rocket():
	pieces = RocketModel.build(GameState.rocket)
	rocket_root = Node3D.new()
	add_child(rocket_root)
	rocket_root.add_child(pieces["root"])
	set_flames("booster", false)
	set_flames("bottom", false)
	set_flames("top", false)

func build_screen():
	var layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(fade)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 36)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	caption.add_theme_constant_override("outline_size", 8)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	caption.position.y = 70
	caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(caption)
	telemetry = Label.new()
	telemetry.add_theme_font_size_override("font_size", 18)
	telemetry.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	telemetry.add_theme_constant_override("outline_size", 6)
	telemetry.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	telemetry.position = Vector2(20, -110)
	layer.add_child(telemetry)
	var skip_button = Button.new()
	skip_button.text = "Skip launch"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	skip_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skip_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	skip_button.pressed.connect(finish)
	layer.add_child(skip_button)

# ---------------------------------------------------------------------------
# Every frame
# ---------------------------------------------------------------------------
func _process(delta):
	if finished_sent:
		return
	var time_speed = 1.0
	if mission_seconds >= 0.0:
		time_speed = PAD_SHOT_TIME_SPEED if mission_seconds < PAD_SHOT_SECONDS else compression
	var before = mission_seconds
	mission_seconds += delta * time_speed
	if before < 0.0:
		var count_before = ceil(-before)
		var count_now = ceil(-mission_seconds)
		if count_now < count_before and count_now > 0:
			show_caption(str(int(count_now)))
		if before < -1.0 and mission_seconds >= -1.0:
			set_flames("bottom", true)       # engines light just before liftoff
			set_flames("booster", false)
			smoke.emitting = true
	while next_event < timeline.size() and mission_seconds >= timeline[next_event][0]:
		run_event(timeline[next_event][1])
		next_event += 1
	if not in_high_shot and mission_seconds >= PAD_SHOT_SECONDS:
		switch_to_high_shot()
	if in_high_shot:
		update_high_shot(delta, delta * time_speed)
	else:
		update_pad_shot()
	update_falling_pieces(delta)
	flicker_flames()
	update_screen(delta)
	if mission_seconds >= escape_end_seconds + 2.5 * compression:
		finish()

func update_pad_shot():
	var seconds = max(mission_seconds, 0.0)
	# Climbing faster and faster as it burns fuel and gets lighter
	var height = 0.5 * liftoff_acceleration * seconds * seconds * (1.0 + seconds / 60.0)
	rocket_root.position = Vector3(0, height, 0)
	rocket_root.rotation = Vector3.ZERO
	var rocket_height = pieces["height"]
	var distance = rocket_height * 1.6 + 60.0
	camera.position = Vector3(-distance * 0.8, 3.0, distance * 0.6)
	var look_point = rocket_root.position + Vector3(0, rocket_height * 0.45, 0)
	camera.look_at(look_point, Vector3.UP)
	var away = camera.position.distance_to(look_point)
	camera.fov = clamp(rad_to_deg(2.0 * atan(rocket_height * 0.9 / away)), 3.0, 55.0)
	smoke.emitting = seconds < 14.0

func switch_to_high_shot():
	in_high_shot = true
	pad_world.visible = false
	high_world.visible = true
	smoke.emitting = false
	if world_environment and space_environment:
		world_environment.environment = space_environment
	rocket_root.position = Vector3.ZERO
	rocket_root.scale = Vector3.ONE * (ROCKET_SIZE_HIGH / pieces["height"])
	camera.fov = 50.0
	sun.rotation_degrees = Vector3(-25, -60, 0)
	sun.light_energy = 0.9
	fade.color.a = 1.0     # a quick fade from black between the two views

func update_high_shot(delta, mission_delta):
	var altitude = shown_altitude(mission_seconds)
	var speed = shown_speed(mission_seconds)
	earth_ball.position = Vector3(0, -(EARTH_RADIUS_UNITS + altitude * UNITS_PER_KILOMETER), 0)
	# Florida's Space Coast (28.5° N, 80.6° W) starts right below the rocket, and the ground slides west as it flies east
	travel_angle += speed * UNITS_PER_KILOMETER * mission_delta / (EARTH_RADIUS_UNITS * 4.0)
	earth_ball.basis = Basis(Vector3(0, 0, 1), travel_angle) * Basis(Vector3(1, 0, 0), deg_to_rad(-61.5)) * Basis(Vector3(0, 1, 0), deg_to_rad(-99.4))
	# Tipping over toward the horizon as it climbs (a "gravity turn"), then flying level along it
	var turn = smoothstep(PAD_SHOT_SECONDS, orbit_seconds, mission_seconds)
	rocket_root.rotation.z = -deg_to_rad(lerp(30.0, 86.0, turn))
	camera.position = Vector3(-ROCKET_SIZE_HIGH * 0.9, ROCKET_SIZE_HIGH * 0.35, ROCKET_SIZE_HIGH * 2.3)
	camera.look_at(Vector3(ROCKET_SIZE_HIGH * 0.15, -ROCKET_SIZE_HIGH * 0.1, 0), Vector3.UP)
	camera.far = 20000.0

func run_event(event_name):
	match event_name:
		"liftoff":
			show_caption("Liftoff!")
			set_flames("booster", true)
		"boosters":
			show_caption("Booster separation")
			set_flames("booster", false)
			for booster in pieces["boosters"]:
				var outward = Vector3(booster.position.x, 0, booster.position.z).normalized()
				drop_piece(booster, outward * 1.2 + Vector3(-1.5, -0.6, 0), Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.6)
		"cutoff":
			show_caption("Main engine cutoff")
			set_flames("bottom", false)
			set_flames("booster", false)
		"separation":
			show_caption("Stage separation")
			drop_piece(pieces["bottom"], Vector3(-2.5, -0.8, 0), Vector3(0, 0, 0.35))
		"top_ignition":
			show_caption("Top stage ignition")
			set_flames("top", true)
		"fairing":
			show_caption("Fairing separation: there's your probe!")
			for half_index in pieces["fairing"].size():
				var side = 1.0 if half_index == 0 else -1.0
				drop_piece(pieces["fairing"][half_index], Vector3(-1.0, -0.2, side * 2.0), Vector3(side * 0.8, 0, 0))
		"orbit":
			show_caption("In orbit around Earth!")
			set_flames("top", false)
		"escape":
			show_caption("Escape burn: heading for %s" % GameState.destination)
			set_flames("top", true)
		"probe":
			set_flames("top", false)
			var kick = GameState.rocket["kick_stage"] != "none"
			show_caption("Probe separation. Kick stage fires: on to %s!" % GameState.destination if kick else "Probe separation: on to %s!" % GameState.destination)

# A stage, booster or fairing half lets go: it keeps its place in the world and drifts away tumbling
func drop_piece(piece, velocity, spin):
	if piece == null or not is_instance_valid(piece):
		return
	var place = piece.global_transform
	var holder = high_world if in_high_shot else pad_world
	piece.get_parent().remove_child(piece)
	holder.add_child(piece)
	piece.global_transform = place
	var size = ROCKET_SIZE_HIGH if in_high_shot else pieces["height"] * 0.2
	falling_pieces.append({"node": piece, "velocity": velocity * size * 0.35, "spin": spin, "age": 0.0})

func update_falling_pieces(delta):
	for falling in falling_pieces.duplicate():
		var node = falling["node"]
		if not is_instance_valid(node):
			falling_pieces.erase(falling)
			continue
		falling["age"] += delta
		falling["velocity"] += Vector3(-0.4, -0.25, 0) * delta * ROCKET_SIZE_HIGH * 0.1   # falls behind as the rocket speeds on
		node.global_position += falling["velocity"] * delta
		node.rotate_x(falling["spin"].x * delta)
		node.rotate_z(falling["spin"].z * delta)
		if falling["age"] > 7.0:
			node.queue_free()
			falling_pieces.erase(falling)

func set_flames(group, on):
	flames_on[group] = on
	for flame in pieces.get(group + "_flames", []):
		if is_instance_valid(flame):
			flame.visible = on

# Flames flicker, and spread out wide in the near-vacuum of space
func flicker_flames():
	var spread = 2.2 if in_high_shot else 1.0
	for group in ["booster", "bottom", "top"]:
		for flame in pieces.get(group + "_flames", []):
			if is_instance_valid(flame) and flame.visible:
				var base = flame.get_meta("base_scale", flame.scale)
				flame.set_meta("base_scale", base)
				var wobble = 1.0 + randf_range(-0.06, 0.06)
				flame.scale = Vector3(base.x * spread, base.y * wobble * (1.3 if in_high_shot else 1.0), base.z * spread)

# What the screen shows: the altitude and speed follow a typical climb shaped by your rocket's design
func shown_altitude(seconds):
	if seconds <= 0.0:
		return 0.0
	if seconds <= main_engine_cutoff_seconds:
		return cutoff_altitude * pow(seconds / main_engine_cutoff_seconds, 2.2)
	if seconds <= orbit_seconds:
		var share = (seconds - main_engine_cutoff_seconds) / (orbit_seconds - main_engine_cutoff_seconds)
		return lerp(cutoff_altitude, ORBIT_ALTITUDE, 1.0 - pow(1.0 - share, 2.0))
	if seconds <= escape_start_seconds:
		return ORBIT_ALTITUDE
	return ORBIT_ALTITUDE + 300.0 * clamp((seconds - escape_start_seconds) / (escape_end_seconds - escape_start_seconds), 0.0, 1.0)

func shown_speed(seconds):
	if seconds <= 0.0:
		return 0.0
	if seconds <= main_engine_cutoff_seconds:
		return cutoff_speed * pow(seconds / main_engine_cutoff_seconds, 2.2)
	if seconds <= orbit_seconds:
		return lerp(cutoff_speed, ORBIT_SPEED, pow((seconds - main_engine_cutoff_seconds) / (orbit_seconds - main_engine_cutoff_seconds), 1.2))
	if seconds <= escape_start_seconds:
		return ORBIT_SPEED
	return lerp(ORBIT_SPEED, final_speed, clamp((seconds - escape_start_seconds) / (escape_end_seconds - escape_start_seconds), 0.0, 1.0))

func show_caption(text):
	caption.text = text
	caption.modulate.a = 1.0
	caption_seconds_left = 2.6

func update_screen(delta):
	caption_seconds_left -= delta
	caption.modulate.a = clamp(caption_seconds_left / 0.6, 0.0, 1.0)
	fade.color.a = max(0.0, fade.color.a - delta * 2.5)
	var seconds = max(mission_seconds, 0.0)
	var clock = "T-%d" % int(ceil(-mission_seconds)) if mission_seconds < 0.0 else "T+%02d:%02d" % [int(seconds / 60.0), int(fmod(seconds, 60.0))]
	var stage_text = "On the pad"
	if mission_seconds >= escape_end_seconds:
		stage_text = "Probe on its way"
	elif mission_seconds >= escape_start_seconds:
		stage_text = "Escape burn"
	elif mission_seconds >= orbit_seconds:
		stage_text = "Coasting in orbit"
	elif mission_seconds >= main_engine_cutoff_seconds + 7.0:
		stage_text = "Top stage burning"
	elif mission_seconds >= 0.0:
		stage_text = "Bottom stage burning" + (" with boosters" if booster_seconds > 0.0 and mission_seconds < booster_seconds else "")
	var altitude = shown_altitude(mission_seconds)
	var speed = shown_speed(mission_seconds)
	var altitude_text = "%d m" % int(altitude * 1000.0) if altitude < 1.0 else ("%.1f km" % altitude if altitude < 10.0 else "%d km" % int(altitude))
	var speed_text = "%d m/s" % int(speed * 1000.0) if speed < 1.0 else "%.2f km/s" % speed
	telemetry.text = "%s    Altitude: %s    Speed: %s\n%s    (time runs faster than real life)" % [clock, altitude_text, speed_text, stage_text]

func finish():
	if finished_sent:
		return
	finished_sent = true
	if world_environment and space_environment:
		world_environment.environment = space_environment
	finished.emit()
