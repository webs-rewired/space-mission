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
const RealRocket = preload("res://scripts/real_rocket.gd")
const Spacecraft = preload("res://scripts/spacecraft.gd")
const SEPARATION_SCENE = preload("res://scenes/effects/separation_burst.tscn")
const CLOUD_SHADER = preload("res://shaders/cloud_puff.gdshader")
const SMOKE_SHADER = preload("res://shaders/smoke_puff.gdshader")
const SKY_PHOTO = "kloofendal_48d_partly_cloudy_2k.hdr"   # Poly Haven (CC0): a real partly cloudy sky
const LAUNCH_TOWER_SCALE = 47.2     # NASA's Mobile Launcher model is 2.46 units tall; the real one is 116 m
const LAUNCH_DECK_HEIGHT = 14.2     # the rocket stands on the launcher's deck, above the flame trench

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
var exhaust_trail: CPUParticles3D   # the column of smoke the rocket leaves behind as it climbs
var smoke_noise: NoiseTexture2D

var timeline = []              # [real mission seconds, event name], in order
var next_event = 0
var mission_seconds = -10.0    # real mission time: starts at T-10 for the countdown
const COUNTDOWN_TIME_SPEED = 2.0 # the countdown runs twice as fast as real time (real time when there's a countdown voice)
# Seconds into each real countdown recording when "zero" / "liftoff" is called, to line it up with T-0
# (Apollo 11: "...ten, nine, ignition sequence start... two, one, zero" at 14.6 s; Artemis I: "booster ignition" right at the start)
const COUNTDOWN_VOICE_LIFTOFF_AT = {"countdown_apollo": 14.6, "countdown_artemis": 0.3}
const IGNITION_SECONDS = -3.0    # engines light 3 seconds before liftoff (like a Falcon 9)
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
var tower: Node3D
var tower_arm: Node3D
var engine_light: OmniLight3D
var shake = 0.0                # camera shake strength
var camera_target = Vector3.ZERO   # the high view's camera follows the stage that's still flying
var camera_distance = 15.0
var stage_separated = false
var deck_height = 0.0          # how high the rocket's base sits on the pad (on the Mobile Launcher's deck if it's there)
var reusable_booster = false   # Falcon 9 and Starship boosters fly back to land
var booster_flip: Node3D = null
var booster_flip_seconds = 0.0

var caption: Label
var caption_seconds_left = 0.0
var countdown_speed = COUNTDOWN_TIME_SPEED
var countdown_voice = ""
var last_roar_distance = -1.0
var silence_announced = false
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
	start_countdown_voice()

# ---------------------------------------------------------------------------
# Sound: a real NASA countdown, then the roar. Sound travels at 343 m/s, so it reaches the camera a moment
# after the flames light; it drops in pitch as the rocket races away (the Doppler effect), and fades to silence
# as the air thins: above about 50 km there's almost no air left to carry it.
# ---------------------------------------------------------------------------
func audio():
	return get_node_or_null("/root/AudioManager")

func start_countdown_voice():
	var sound = audio()
	if sound == null:
		return
	# SLS gets the Artemis I call; the others, Apollo 11's
	var voice = "countdown_artemis" if pieces.get("real_rocket", "") == "SLS" else "countdown_apollo"
	if not sound.has_sound(voice):
		voice = "countdown_apollo" if voice == "countdown_artemis" else "countdown_artemis"
	if not sound.has_sound(voice):
		return
	countdown_speed = 1.0   # a real countdown voice runs in real time
	countdown_voice = voice
	var seconds_to_liftoff = -mission_seconds / countdown_speed
	var start_at = COUNTDOWN_VOICE_LIFTOFF_AT[voice] - seconds_to_liftoff
	sound.play_voice(voice, 0.0, max(-start_at, 0.0), max(start_at, 0.0))

func start_roar():
	var sound = audio()
	if sound == null:
		return
	var distance = camera.global_position.distance_to(rocket_root.global_position)
	var roar = "launch_atlas" if pieces.get("real_rocket", "") == "Atlas V" and sound.has_sound("launch_atlas") else "launch_roar"
	sound.start_engine(roar, roar_volume(distance), 1.0, sound.sound_delay(distance))
	last_roar_distance = distance

# Louder up close: about 6 decibels quieter every time the distance doubles
func roar_volume(distance):
	return clamp(4.0 - 20.0 * log(max(distance, 60.0) / 150.0) / log(10.0), -40.0, 6.0)

func update_roar(delta):
	var sound = audio()
	if sound == null or last_roar_distance < 0.0:
		return
	if in_high_shot:
		# Air gets thinner by about 2.7 times every 8.5 km up
		var air = exp(-shown_altitude(mission_seconds) / 8.5)
		sound.set_air(air)
		var volume = -6.0 + 20.0 * log(max(air, 0.0005)) / log(10.0)
		sound.set_engine(volume if (flames_on["bottom"] or flames_on["booster"] or flames_on["top"]) else -60.0, 0.7)
		if not silence_announced and air < 0.004 and caption_seconds_left <= 0.0:
			silence_announced = true
			show_caption("Silence: up here there's almost no air left to carry sound")
		return
	var distance = camera.global_position.distance_to(rocket_root.global_position)
	var moving_away = (distance - last_roar_distance) / max(delta, 0.001)
	last_roar_distance = distance
	# The Doppler effect: a sound source racing away sounds lower
	sound.set_engine(roar_volume(distance), clamp(343.0 / (343.0 + moving_away), 0.55, 1.1))

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

	reusable_booster = rocket["bottom_engine"] in ["merlin", "raptor"]
	# Mach 1 comes first, then Max-Q a few seconds later (Falcon 9: about T+1:02 and T+1:12)
	var mach_one_seconds = time_when_speed_reaches(0.3)
	timeline = [[0.0, "liftoff"], [mach_one_seconds, "mach1"], [max(time_when_altitude_reaches(12.0), mach_one_seconds + 8.0), "maxq"]]
	if reusable_booster:
		timeline.append([main_engine_cutoff_seconds + 20.0, "boostback"])
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

# When the shown speed (km/s) or altitude (km) first reaches a value, in mission seconds
func time_when_speed_reaches(speed):
	var seconds = 0.0
	while seconds < main_engine_cutoff_seconds and shown_speed(seconds) < speed:
		seconds += 1.0
	return seconds

func time_when_altitude_reaches(altitude):
	var seconds = 0.0
	while seconds < main_engine_cutoff_seconds and shown_altitude(seconds) < altitude:
		seconds += 1.0
	return seconds

# ---------------------------------------------------------------------------
# Building the two views
# ---------------------------------------------------------------------------
func build_pad_world():
	pad_world = Node3D.new()
	add_child(pad_world)
	sky_environment = Environment.new()
	var sky = Sky.new()
	var photo_path = find_file("res://", SKY_PHOTO)
	if photo_path != "":
		# A real photo of a partly cloudy sky (it lights the rocket too)
		var photo_sky = PanoramaSkyMaterial.new()
		photo_sky.panorama = load(photo_path)
		photo_sky.energy_multiplier = 1.25
		sky.sky_material = photo_sky
		sky_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		sky_environment.ambient_light_energy = 0.45
		sky_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		var sky_material = ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color(0.16, 0.32, 0.62)
		sky_material.sky_horizon_color = Color(0.72, 0.78, 0.86)
		sky_material.ground_horizon_color = Color(0.6, 0.62, 0.6)
		sky_material.ground_bottom_color = Color(0.25, 0.27, 0.22)
		sky.sky_material = sky_material
		sky_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		sky_environment.ambient_light_color = Color(0.85, 0.85, 0.82)
		sky_environment.ambient_light_energy = 0.55
	sky_environment.background_mode = Environment.BG_SKY
	# Bloom: the engine fire is far brighter than the sky, so it glows
	sky_environment.glow_enabled = true
	sky_environment.glow_hdr_threshold = 2.2
	sky_environment.glow_intensity = 0.9
	sky_environment.sky = sky
	sky_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	sky_environment.fog_enabled = true
	sky_environment.fog_light_color = Color(0.72, 0.78, 0.86)
	sky_environment.fog_density = 0.00012
	sky_environment.fog_aerial_perspective = 0.9
	sky_environment.fog_sky_affect = 0.0

	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(30000, 30000)
	ground.mesh = plane
	ground.position.y = -0.05
	var grass = StandardMaterial3D.new()
	var grass_noise = FastNoiseLite.new()
	grass_noise.frequency = 0.03
	grass_noise.fractal_octaves = 4
	var grass_texture = NoiseTexture2D.new()
	grass_texture.noise = grass_noise
	grass_texture.seamless = true
	var grass_colors = Gradient.new()
	grass_colors.set_color(0, Color(0.13, 0.17, 0.08))
	grass_colors.set_color(1, Color(0.25, 0.29, 0.15))
	grass_texture.color_ramp = grass_colors
	grass.albedo_texture = grass_texture
	grass.uv1_scale = Vector3(400, 400, 400)
	grass.roughness = 1.0
	ground.material_override = grass
	pad_world.add_child(ground)
	var pad = MeshInstance3D.new()
	var pad_mesh = CylinderMesh.new()
	pad_mesh.top_radius = 70
	pad_mesh.bottom_radius = 72
	pad_mesh.height = 1.0
	pad.mesh = pad_mesh
	pad.position.y = -0.5
	pad.material_override = RocketModel.make_material(Color(0.24, 0.24, 0.23), 0.0, 1.0)
	pad_world.add_child(pad)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)   # the sun in the sky photo is 48 degrees up
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 800.0
	add_child(sun)
	build_clouds()

	# The engines' glow lights up the pad and the clouds of steam
	engine_light = OmniLight3D.new()
	engine_light.light_color = Color(1.0, 0.65, 0.3)
	engine_light.light_energy = 0.0
	engine_light.omni_range = 120.0
	add_child(engine_light)

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
	smoke.mesh = smoke_card()
	var fade_out = Gradient.new()
	fade_out.set_color(0, Color(1, 1, 1, 0.9))
	fade_out.set_color(1, Color(1, 1, 1, 0.0))
	smoke.color_ramp = fade_out
	smoke.position = Vector3(0, 1.0, 0)
	pad_world.add_child(smoke)
	build_exhaust_trail()

	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 20000.0
	add_child(camera)

# Finds a file by name anywhere in the project ("" if it isn't there)
func find_file(folder, file_name):
	var directory = DirAccess.open(folder)
	if directory == null:
		return ""
	for found in directory.get_files():
		if found.to_lower() == file_name.to_lower():
			return folder.path_join(found)
	for sub_folder in directory.get_directories():
		if sub_folder.begins_with("."):
			continue
		var path = find_file(folder.path_join(sub_folder), file_name)
		if path != "":
			return path
	return ""

# Puffy cumulus clouds about 1 to 2 km up. A few hang right over the pad, so the rocket climbs through them.
func build_clouds():
	var noise = FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	var noise_texture = NoiseTexture2D.new()
	noise_texture.noise = noise
	noise_texture.seamless = true
	noise_texture.width = 256
	noise_texture.height = 256
	var random = RandomNumberGenerator.new()
	random.seed = 2026
	var cloud_places = [Vector3(90, 1300, 110), Vector3(-120, 1550, -70)]   # over the pad, off to the sides of the camera's view
	for index in 26:
		var angle = random.randf() * TAU
		var distance = random.randf_range(700.0, 6000.0)
		cloud_places.append(Vector3(cos(angle) * distance, random.randf_range(1000.0, 2200.0), sin(angle) * distance))
	for place in cloud_places:
		var cloud_size = random.randf_range(160.0, 420.0)
		for puff_index in random.randi_range(5, 9):
			var puff = MeshInstance3D.new()
			var card = QuadMesh.new()
			card.size = Vector2(1, 1)
			puff.mesh = card
			var material = ShaderMaterial.new()
			material.shader = CLOUD_SHADER
			material.set_shader_parameter("noise_texture", noise_texture)
			material.set_shader_parameter("seed", random.randf() * 10.0)
			puff.material_override = material
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var puff_size = cloud_size * random.randf_range(0.45, 0.8)
			puff.scale = Vector3(puff_size, puff_size * 0.75, 1.0)
			puff.position = place + Vector3(random.randf_range(-0.5, 0.5) * cloud_size, random.randf_range(-0.1, 0.25) * cloud_size, random.randf_range(-0.4, 0.4) * cloud_size)
			pad_world.add_child(puff)

# A card that draws as a lumpy puff of smoke (for particles)
func smoke_card():
	if smoke_noise == null:
		var noise = FastNoiseLite.new()
		noise.frequency = 0.015
		noise.fractal_octaves = 5
		smoke_noise = NoiseTexture2D.new()
		smoke_noise.noise = noise
		smoke_noise.seamless = true
		smoke_noise.width = 256
		smoke_noise.height = 256
	var card = QuadMesh.new()
	card.size = Vector2(1, 1)
	var material = ShaderMaterial.new()
	material.shader = SMOKE_SHADER
	material.set_shader_parameter("noise_texture", smoke_noise)
	card.material = material
	return card

# The exhaust leaves a column of smoke behind the climbing rocket. Solid boosters make thick white smoke,
# kerosene a thinner grey trail, and hydrogen and methane engines almost none (their exhaust is mostly water vapor).
func build_exhaust_trail():
	exhaust_trail = CPUParticles3D.new()
	var has_boosters = RocketData.BOOSTERS[GameState.rocket["boosters"]]["count"] > 0
	var fuel = RocketData.ENGINES[GameState.rocket["bottom_engine"]]["fuel"]
	var thickness = 1.0 if has_boosters else (0.55 if fuel == "kerosene" else 0.3)
	exhaust_trail.amount = 1400
	exhaust_trail.lifetime = 8.0
	exhaust_trail.local_coords = false
	exhaust_trail.emitting = false
	exhaust_trail.direction = Vector3(0, -1, 0)
	exhaust_trail.spread = 12.0
	exhaust_trail.initial_velocity_min = 6.0
	exhaust_trail.initial_velocity_max = 14.0
	exhaust_trail.damping_min = 2.0
	exhaust_trail.damping_max = 4.0
	exhaust_trail.gravity = Vector3(0.8, 0.25, 0.3)   # a light sea breeze carries it away
	exhaust_trail.scale_amount_min = 6.0 * (1.0 + thickness)
	exhaust_trail.scale_amount_max = 12.0 * (1.0 + thickness)
	var grow = Curve.new()
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(1, 3.0))
	exhaust_trail.scale_amount_curve = grow
	exhaust_trail.mesh = smoke_card()
	var fade = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(0.9, 0.9, 0.9, 0.0))
	fade.add_point(0.04, Color(1, 0.97, 0.9, 0.75 * thickness))
	fade.add_point(0.5, Color(0.95, 0.95, 0.95, 0.4 * thickness))
	exhaust_trail.color_ramp = fade
	pad_world.add_child(exhaust_trail)

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
	pieces = RealRocket.build(GameState.rocket)   # the real Falcon 9, Atlas V, SLS or Starship, split into its stages
	if pieces == null:
		pieces = RocketModel.build(GameState.rocket)   # model files missing: build it from the parts
	rocket_root = Node3D.new()
	add_child(rocket_root)
	rocket_root.add_child(pieces["root"])
	build_tower()
	set_flames("booster", false)
	set_flames("bottom", false)
	set_flames("top", false)

# The launch tower beside the rocket, with an access arm that swings away before liftoff
func build_tower():
	var launcher_path = Spacecraft.find_model("mobile_launcher.glb")
	if launcher_path != "" and load(launcher_path) is PackedScene:
		# NASA's Mobile Launcher: the rocket stands on its deck over the flame trench, with the 116 m tower beside it
		tower = load(launcher_path).instantiate()
		tower.scale = Vector3.ONE * LAUNCH_TOWER_SCALE
		pad_world.add_child(tower)
		deck_height = LAUNCH_DECK_HEIGHT
		return
	tower = Node3D.new()
	pad_world.add_child(tower)
	var steel = RocketModel.make_material(Color(0.55, 0.3, 0.22), 0.6, 0.5)
	var height = pieces["height"] * 1.05
	var side = -(pieces["width"] * 0.5 + 9.0)
	for corner_x in [-2.0, 2.0]:
		for corner_z in [-2.0, 2.0]:
			var post = MeshInstance3D.new()
			var post_mesh = BoxMesh.new()
			post_mesh.size = Vector3(0.5, height, 0.5)
			post.mesh = post_mesh
			post.material_override = steel
			post.position = Vector3(side + corner_x, height / 2.0, corner_z)
			tower.add_child(post)
	var level = 8.0
	while level < height:
		var floor_box = MeshInstance3D.new()
		var floor_mesh = BoxMesh.new()
		floor_mesh.size = Vector3(4.6, 0.35, 4.6)
		floor_box.mesh = floor_mesh
		floor_box.material_override = steel
		floor_box.position = Vector3(side, level, 0)
		tower.add_child(floor_box)
		level += 8.0
	# The arm pivots at the tower, so it can swing away
	tower_arm = Node3D.new()
	tower_arm.position = Vector3(side + 2.0, height * 0.85, 0)
	tower.add_child(tower_arm)
	var arm_length = abs(side) - 2.0 - pieces["width"] * 0.45
	var arm = MeshInstance3D.new()
	var arm_mesh = BoxMesh.new()
	arm_mesh.size = Vector3(arm_length, 1.2, 1.6)
	arm.mesh = arm_mesh
	arm.material_override = steel
	arm.position = Vector3(arm_length / 2.0, 0, 0)
	tower_arm.add_child(arm)

# A quick, faint burst of vapor where pieces let go (separation springs, pushers and small thrusters)
func separation_puff(place):
	var burst = SEPARATION_SCENE.instantiate()
	var size = ROCKET_SIZE_HIGH / 14.0 if in_high_shot else pieces["height"] / 40.0
	burst.scale_amount_min *= size
	burst.scale_amount_max *= size
	burst.initial_velocity_min *= size
	burst.initial_velocity_max *= size
	(high_world if in_high_shot else pad_world).add_child(burst)
	burst.global_position = place
	burst.restart()
	get_tree().create_timer(2.0).timeout.connect(burst.queue_free)

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
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long captions wrap instead of running off the screen
	caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	caption.offset_left = 120
	caption.offset_right = -120
	caption.offset_top = 60
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
	var time_speed = countdown_speed
	if mission_seconds >= 0.0:
		time_speed = PAD_SHOT_TIME_SPEED if mission_seconds < PAD_SHOT_SECONDS else compression
	var before = mission_seconds
	mission_seconds += delta * time_speed
	# During the countdown, the clock follows the recording, so "...three, two, one, zero" always lines up with T-0
	if mission_seconds < 0.0 and countdown_voice != "" and audio():
		var player = audio().voice
		if player.playing and player.stream == audio().get_stream(countdown_voice):
			var heard = player.get_playback_position() + AudioServer.get_time_since_last_mix() - COUNTDOWN_VOICE_LIFTOFF_AT[countdown_voice]
			if abs(heard - mission_seconds) > 0.12:
				mission_seconds = min(heard, -0.001) if before < 0.0 else mission_seconds
	if before < 0.0:
		var count_before = ceil(-before)
		var count_now = ceil(-mission_seconds)
		if count_now < count_before and count_now > 0:
			show_caption(str(int(count_now)))
		if before < -6.0 and mission_seconds >= -6.0:
			show_caption("Access arm retracting")
		if before < IGNITION_SECONDS and mission_seconds >= IGNITION_SECONDS:
			show_caption("Ignition!")
			start_roar()
			set_flames("bottom", true)       # main engines light 3 seconds before liftoff
			set_flames("booster", false)
			smoke.emitting = true
	if tower_arm:
		tower_arm.rotation.y = -deg_to_rad(80.0) * smoothstep(-6.0, -4.0, mission_seconds)
	if flames_on["bottom"] or flames_on["booster"]:
		engine_light.light_energy = 6.0 * (1.0 + randf_range(-0.15, 0.15)) if not in_high_shot else 0.0
		shake = max(shake, 0.6 if mission_seconds < 6.0 else 0.25)
	else:
		engine_light.light_energy = 0.0
	while next_event < timeline.size() and mission_seconds >= timeline[next_event][0]:
		run_event(timeline[next_event][1])
		next_event += 1
	if not in_high_shot and mission_seconds >= PAD_SHOT_SECONDS:
		switch_to_high_shot()
	if in_high_shot:
		update_high_shot(delta, delta * time_speed)
	else:
		update_pad_shot()
	update_roar(delta)
	update_falling_pieces(delta)
	update_booster_flip(delta)
	flicker_flames()
	apply_shake(delta)
	update_screen(delta)
	if mission_seconds >= escape_end_seconds + 2.5 * compression:
		finish()

# The camera rumbles while the engines roar, most of all at liftoff and at Max-Q
func apply_shake(delta):
	if shake > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * shake * 0.04
		camera.v_offset = randf_range(-1.0, 1.0) * shake * 0.04
		shake = max(0.0, shake - delta * 0.8)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

# A Falcon 9 (or Starship) booster flips around and fires its engines to fly back and land
func update_booster_flip(delta):
	if booster_flip == null or not is_instance_valid(booster_flip):
		return
	booster_flip_seconds += delta
	booster_flip.rotate_z(delta * 1.6 if booster_flip_seconds < 1.8 else 0.0)

func update_pad_shot():
	var seconds = max(mission_seconds, 0.0)
	engine_light.position = rocket_root.position + Vector3(0, 2.0, 0)
	# Climbing faster and faster as it burns fuel and gets lighter
	var height = 0.5 * liftoff_acceleration * seconds * seconds * (1.0 + seconds / 60.0)
	rocket_root.position = Vector3(0, deck_height + height, 0)
	rocket_root.rotation = Vector3.ZERO
	var rocket_height = pieces["height"]
	# Like a real tracking camera miles away, it backs off as the rocket climbs so it never has to look straight up
	var distance = max(rocket_height * 1.6 + 60.0, (rocket_root.position.y - deck_height) * 1.4)
	camera.position = Vector3(-distance * 0.8, 3.0, distance * 0.6)
	var look_point = rocket_root.position + Vector3(0, rocket_height * 0.22, 0)   # low enough to see the fire under it
	if mission_seconds < 2.0:
		# Close-up of the engines lighting, then cut to the wide shot as it clears the tower
		camera.position = Vector3(-(pieces["width"] * 4.0 + 22.0), deck_height + 7.0, pieces["width"] * 4.0 + 30.0)
		look_point = rocket_root.position + Vector3(0, rocket_height * 0.18, 0)
	camera.look_at(look_point, Vector3.UP)
	var away = camera.position.distance_to(look_point)
	camera.fov = clamp(rad_to_deg(2.0 * atan(rocket_height * 1.25 / away)), 3.0, 55.0)
	smoke.emitting = seconds < 14.0
	# The smoke starts where the fire ends, so it doesn't hide the flames
	exhaust_trail.global_position = rocket_root.position + Vector3(0, -pieces["height"] * 0.4, 0)
	exhaust_trail.emitting = mission_seconds > 0.2 and (flames_on["bottom"] or flames_on["booster"])

func switch_to_high_shot():
	in_high_shot = true
	pad_world.visible = false
	high_world.visible = true
	smoke.emitting = false
	exhaust_trail.emitting = false
	if world_environment and space_environment:
		world_environment.environment = space_environment
	rocket_root.position = Vector3.ZERO
	rocket_root.scale = Vector3.ONE * (ROCKET_SIZE_HIGH / pieces["height"])
	camera.fov = 50.0
	sun.rotation_degrees = Vector3(-25, -60, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	camera_target = part_point(pieces["root"], 0.55)
	camera_distance = ROCKET_SIZE_HIGH * 2.2
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
	# Follow whatever is still flying: the whole rocket, then just the top stage once the bottom stage drops away
	var flying = pieces["top"] if stage_separated else pieces["root"]
	var flying_length = part_length(flying) * rocket_root.scale.y
	var blend = min(1.0, delta * 2.0)
	camera_target = camera_target.lerp(part_point(flying, 0.55), blend)
	camera_distance = lerp(camera_distance, max(flying_length * 2.2, 2.5), blend)
	camera.position = camera_target + Vector3(-0.36, 0.16, 0.92) * camera_distance
	camera.look_at(camera_target + Vector3(0, -flying_length * 0.08, 0), Vector3.UP)
	camera.far = 20000.0

# A point along a rocket piece, from its bottom (0) to its top (1), in the world
func part_point(piece, fraction):
	var box = RealRocket.solid_bounds(piece, Transform3D.IDENTITY, null)
	if box == null:
		return piece.global_position
	var local_point = Vector3(box.get_center().x, box.position.y + box.size.y * fraction, box.get_center().z)
	return piece.get_parent().global_transform * local_point

func part_length(piece):
	var box = RealRocket.solid_bounds(piece, Transform3D.IDENTITY, null)
	return box.size.y if box != null else pieces["height"]

func run_event(event_name):
	match event_name:
		"liftoff":
			show_caption("Liftoff! The rocket has cleared the tower.")
			set_flames("booster", true)
		"mach1":
			show_caption("Mach 1: faster than the speed of sound")
		"maxq":
			show_caption("Max-Q: the moment the air pushes hardest on the rocket")
			shake = max(shake, 0.5)
		"boostback":
			if booster_flip and is_instance_valid(booster_flip):
				show_caption("Boostback: the booster flips around to fly home and land")
				for flame in pieces.get("bottom_flames", []):
					if is_instance_valid(flame):
						flame.visible = true
		"boosters":
			show_caption("Booster separation")
			play_sound("thump", -4.0)
			set_flames("booster", false)
			for booster in pieces["boosters"]:
				# Small thrusters at each end push the booster sideways, away from the core
				var box = RealRocket.solid_bounds(booster, booster.get_parent().global_transform, null)
				var middle = box.get_center() if box != null else booster.global_position
				separation_puff(middle)
				var outward = rocket_root.global_transform.basis.inverse() * (middle - rocket_root.global_position)
				outward = Vector3(outward.x, 0, outward.z).normalized()
				drop_piece(booster, rocket_root.global_transform.basis.orthonormalized() * (outward * 1.2) + Vector3(-1.5, -0.6, 0), Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.6)
		"cutoff":
			show_caption("Main engine cutoff")
			if audio():
				audio().play_voice("call_meco")
			set_flames("bottom", false)
			set_flames("booster", false)
		"separation":
			if pieces.get("real_rocket", "") == "Starship":
				show_caption("Hot staging: the ship lights its engines while still on the booster")
				set_flames("top", true)
			else:
				show_caption("Stage separation")
			stage_separated = true
			play_sound("thump", -2.0)
			separation_puff(part_point(pieces["top"], 0.0))   # right at the joint between the stages
			var falling_stage = drop_piece(pieces["bottom"], Vector3(-2.5, -0.8, 0), Vector3(0, 0, 0.35))
			if reusable_booster:
				booster_flip = falling_stage
				booster_flip_seconds = 0.0
		"top_ignition":
			show_caption("Top stage ignition")
			play_sound("thruster", -12.0)
			set_flames("top", true)
		"fairing":
			if pieces["fairing"].is_empty():
				pass   # Starship has no fairing: its probe rides inside the ship's cargo bay
			elif pieces["fairing"].size() == 1:
				# SLS: the launch abort tower fires its own motor and flies off ahead
				show_caption(pieces.get("fairing_caption", "Launch abort tower jettisoned"))
				separation_puff(pieces["fairing"][0].global_position)
				drop_piece(pieces["fairing"][0], Vector3(2.5, 1.2, 0.4), Vector3(0, 0, 0.6))
			else:
				show_caption(pieces.get("fairing_caption", "Fairing separation: there's your probe!"))
				play_sound("thump", -6.0)
				pieces["payload"].visible = true   # (no puff here: it would hide the probe)
				for half_index in pieces["fairing"].size():
					# The two halves split apart like a clamshell (sideways from the rocket, across the view) and fall behind
					var side = -1.0 if half_index == 0 else 1.0
					var apart = rocket_root.global_transform.basis.orthonormalized() * Vector3(side * 1.6, 0.2, 0.0)
					drop_piece(pieces["fairing"][half_index], apart + Vector3(-0.8, -0.1, 0.0), Vector3(0, 0, side * 0.9))
		"orbit":
			show_caption("In orbit around Earth!")
			play_sound("confirm", -6.0)
			set_flames("top", false)
		"escape":
			show_caption("Escape burn: heading for %s" % GameState.destination)
			set_flames("top", true)
		"probe":
			set_flames("top", false)
			play_sound("thump", -8.0)
			var kick = GameState.rocket["kick_stage"] != "none"
			show_caption("Probe separation. Kick stage fires: on to %s!" % GameState.destination if kick else "Probe separation: on to %s!" % GameState.destination)

func play_sound(sound_name, volume_db = 0.0):
	if audio():
		audio().play_effect(sound_name, volume_db)

# A stage, booster or fairing half lets go: it keeps its place in the world and drifts away tumbling
func drop_piece(piece, velocity, spin):
	if piece == null or not is_instance_valid(piece):
		return null
	var place = piece.global_transform
	var holder = high_world if in_high_shot else pad_world
	# Tumble around the piece's middle (its center of mass), not around the bottom of the rocket
	var box = RealRocket.solid_bounds(piece, piece.get_parent().global_transform, null)
	var pivot = Node3D.new()
	holder.add_child(pivot)
	pivot.global_transform = Transform3D(place.basis.orthonormalized(), box.get_center() if box != null else place.origin)
	piece.get_parent().remove_child(piece)
	pivot.add_child(piece)
	piece.global_transform = place
	var size = ROCKET_SIZE_HIGH if in_high_shot else pieces["height"] * 0.2
	falling_pieces.append({"node": pivot, "velocity": velocity * size * 0.35, "spin": spin, "age": 0.0})
	return pivot

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

# Flames flicker, and spread out wide and faint as the air thins (fully by about 70 km up)
func flicker_flames():
	var thin_air = smoothstep(12.0, 70.0, shown_altitude(mission_seconds)) if in_high_shot else 0.0
	for group in ["booster", "bottom", "top"]:
		for flame in pieces.get(group + "_flames", []):
			if is_instance_valid(flame) and flame.visible:
				var base = flame.get_meta("base_scale", flame.scale)
				flame.set_meta("base_scale", base)
				var wobble = 1.0 + randf_range(-0.06, 0.06)
				flame.scale = Vector3(base.x, base.y * wobble * (1.0 + thin_air * 0.4), base.z)
				RocketModel.set_flame_vacuum(flame, thin_air)

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
	if audio():
		audio().stop_engine(1.0)
		audio().stop_voice()
		audio().set_air(1.0)
	if world_environment and space_environment:
		world_environment.environment = space_environment
	finished.emit()
