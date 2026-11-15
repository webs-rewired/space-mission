extends Node3D

# A landing site on another world: its ground and sky, and the landing itself, like the real missions did it:
#   Mars and Venus: parachute, the heat shield drops away, then rockets, a sky crane (Perseverance) or airbags (Opportunity)
#   Titan: floating down under a parachute the whole way, like Huygens in 2005
#   Worlds with no air: rocket engines brake all the way down, like Apollo and the Viking landers' last seconds
# It ends with the real lander standing on the ground and the camera slowly circling it.
# launch.gd adds this scene when the probe reaches the ground. It sends "touched_down" at touchdown.

signal touched_down
signal driving_finished(summary)

const RocketModel = preload("res://scripts/rocket_model.gd")
const SAMPLE_LAB_SCENE = preload("res://scenes/sample_lab.tscn")
const BeltBuilder = preload("res://scripts/belt_builder.gd")
const SpaceTextures = preload("res://scripts/space_textures.gd")
const SpacecraftLookalike = preload("res://scripts/spacecraft_lookalike.gd")
const AEROSHELL_SCENE = preload("res://scenes/parts/aeroshell.tscn")
const PARACHUTE_SCENE = preload("res://scenes/parts/parachute.tscn")
const AIRBAGS_SCENE = preload("res://scenes/parts/airbags.tscn")
const SKY_CRANE_SCENE = preload("res://scenes/parts/sky_crane.tscn")
const DUST_SCENE = preload("res://scenes/effects/separation_burst.tscn")
# A lander on legs carries the rover on its deck and lets it drive down a ramp (like ESA's Kazachok platform
# for the Rosalind Franklin rover, or China's Chang'e landers with their Yutu rovers)
const ROVER_PLATFORM_SCENE = preload("res://scenes/parts/rover_platform.tscn")
# Each rocky world has its own landing-site scene (sky, sunlight, ground, rocks and its own sights), made by
# tools/make_sites.py and editable in Godot. A world without one gets the plain ground and sky below.
const SITE_FOLDER = "res://scenes/worlds/"
const WHEEL_TRACK_TEXTURE = "res://assets/surface/textures/wheel_track.png"
const MAX_CRATERS = 48
const Spacecraft = preload("res://scripts/spacecraft.gd")

# The rover is a real physics vehicle: a 1,025 kg body (Perseverance's mass) on six motorized wheels with springy
# suspension, pulled down by the world's own gravity. The ground and every rock big enough to matter have collision
# shapes, so wheels climb over small rocks and get stopped by big ones. Grip depends on what a wheel is on: loose soil,
# soft sand, slippery ice or solid rock, and on how hard gravity presses it down.
const ROVER_MASS = 1025.0                     # kg
const WHEEL_RADIUS = 0.2625                   # Perseverance's wheels are 52.5 cm across (aluminum, with curved treads)
const WHEELS_MODEL = "perseverance_wheels.glb"
const TERRAIN_SPACING = 2.0                   # meters between the ground's collision points
const TERRAIN_POINTS = 241                    # 241 x 241 points: 480 m square
const LOWEST_GRAVITY = 0.25                   # m/s^2: on Phobos (0.0057) a bump would launch the rover for minutes, so it's raised to this
const SURFACE_GRIP = {"soil": 2.4, "sand": 0.7, "ice": 0.9, "rock": 4.0}
const DRIVE_AREA_RADIUS = 215.0               # meters from the landing spot: the edge of the mission's planned driving area
const MISSION_BOUNDARY_SCENE = preload("res://scenes/effects/mission_boundary.tscn")
const TARGET_ROCKS = [
	preload("res://assets/surface/rocks/rock_angular_1.glb"), preload("res://assets/surface/rocks/rock_cobble.glb"),
	preload("res://assets/surface/rocks/rock_slab.glb"), preload("res://assets/surface/rocks/rock_angular_2.glb"),
	preload("res://assets/surface/rocks/rock_angular_3.glb"),
]
const BOUNDARY_MESSAGE = "MISSION BOUNDARY. The team on Earth planned this mission for the area around the landing site, and the rover's maps end here. Turn around."
var looking_around = false          # right mouse button held: the mouse swings the view around the rover
var look_yaw = 0.0
var look_pitch = 0.0
var look_zoom = 1.0
const DUST_STORM_SCENE = preload("res://scenes/effects/dust_storm.tscn")
var storm: Node3D = null
var storm_seconds_left = 0.0
var storm_seconds_total = 0.0
var storm_has_dust = false
var cables_started = false
var study_laser: MeshInstance3D = null
var boundary: MeshInstance3D = null
var boundary_message_wait = 0.0

# Ground colors (light, dark), sky colors (worlds with air), haze, how dim the sunlight is, and a planet hanging in the sky
const WORLDS = {
	"Mars": {"light": Color(0.58, 0.33, 0.19), "dark": Color(0.34, 0.18, 0.1), "sky_top": Color(0.42, 0.33, 0.26), "sky_horizon": Color(0.82, 0.64, 0.46), "haze": 0.0025},
	"Venus": {"light": Color(0.5, 0.38, 0.22), "dark": Color(0.28, 0.2, 0.12), "sky_top": Color(0.5, 0.38, 0.18), "sky_horizon": Color(0.85, 0.66, 0.35), "haze": 0.012, "dim": 0.35},
	"Titan": {"light": Color(0.42, 0.3, 0.17), "dark": Color(0.22, 0.15, 0.08), "sky_top": Color(0.52, 0.36, 0.17), "sky_horizon": Color(0.8, 0.55, 0.28), "haze": 0.018, "dim": 0.25},
	"Moon": {"light": Color(0.55, 0.54, 0.52), "dark": Color(0.26, 0.26, 0.25), "sky_planet": "Earth", "planet_size": 1.9},
	"Mercury": {"light": Color(0.5, 0.48, 0.45), "dark": Color(0.24, 0.23, 0.22)},
	"Phobos": {"light": Color(0.36, 0.31, 0.27), "dark": Color(0.18, 0.15, 0.13), "sky_planet": "Mars", "planet_size": 42.0},
	"Deimos": {"light": Color(0.42, 0.37, 0.32), "dark": Color(0.22, 0.19, 0.16), "sky_planet": "Mars", "planet_size": 16.0},
	"Io": {"light": Color(0.88, 0.78, 0.38), "dark": Color(0.55, 0.4, 0.16), "sky_planet": "Jupiter", "planet_size": 19.0},
	"Europa": {"light": Color(0.88, 0.86, 0.82), "dark": Color(0.6, 0.48, 0.38), "sky_planet": "Jupiter", "planet_size": 12.0},
	"Ganymede": {"light": Color(0.55, 0.52, 0.48), "dark": Color(0.3, 0.28, 0.25), "sky_planet": "Jupiter", "planet_size": 7.5},
	"Callisto": {"light": Color(0.45, 0.42, 0.38), "dark": Color(0.2, 0.19, 0.17), "sky_planet": "Jupiter", "planet_size": 4.3},
	"Enceladus": {"light": Color(0.94, 0.95, 0.97), "dark": Color(0.7, 0.75, 0.82), "sky_planet": "Saturn", "planet_size": 30.0},
	"Titania": {"light": Color(0.55, 0.53, 0.5), "dark": Color(0.3, 0.29, 0.27), "sky_planet": "Uranus", "planet_size": 9.0},
	"Triton": {"light": Color(0.82, 0.76, 0.72), "dark": Color(0.55, 0.45, 0.42), "sky_planet": "Neptune", "planet_size": 8.0},
	"Charon": {"light": Color(0.55, 0.53, 0.52), "dark": Color(0.32, 0.28, 0.27), "sky_planet": "Pluto", "planet_size": 3.8},
	"Ceres": {"light": Color(0.38, 0.37, 0.36), "dark": Color(0.2, 0.2, 0.19)},
	"Pluto": {"light": Color(0.88, 0.78, 0.66), "dark": Color(0.5, 0.36, 0.28), "sky_planet": "Charon", "planet_size": 3.5},
	"Haumea": {"light": Color(0.9, 0.9, 0.9), "dark": Color(0.6, 0.6, 0.62)},
	"Makemake": {"light": Color(0.85, 0.72, 0.62), "dark": Color(0.55, 0.4, 0.32)},
	"Eris": {"light": Color(0.92, 0.91, 0.9), "dark": Color(0.65, 0.64, 0.64)},
}

# Real conditions on each world's surface: gravity (m/s²), the usual temperature where you'd land (°C),
# and radiation from 0 (none) to 3 (Io, inside Jupiter's radiation belts)
const CONDITIONS = {
	"Mercury": [3.7, 430, 0], "Venus": [8.87, 465, 0], "Moon": [1.62, 60, 0], "Mars": [3.72, -60, 0],
	"Phobos": [0.0057, -40, 0], "Deimos": [0.003, -40, 0], "Io": [1.8, -130, 3], "Europa": [1.31, -160, 2],
	"Ganymede": [1.43, -160, 1], "Callisto": [1.24, -140, 0], "Enceladus": [0.11, -200, 0], "Titan": [1.35, -179, 0],
	"Titania": [0.37, -200, 0], "Triton": [0.78, -235, 0], "Charon": [0.29, -220, 0], "Ceres": [0.28, -105, 0],
	"Pluto": [0.62, -230, 0], "Haumea": [0.4, -240, 0], "Makemake": [0.5, -240, 0], "Eris": [0.82, -240, 0],
}

# Things worth driving to, by world
const SCIENCE_TARGETS = {
	"Mars": ["Layered mudstone from an ancient lake", "Rounded river pebbles", "Hematite \"blueberries\"", "Clay-rich rock", "Wind-carved boulder"],
	"Moon": ["Orange volcanic glass beads", "Bright highland rock", "Fresh crater ejecta", "Ancient lava rock", "A boulder that rolled down a hill"],
	"Venus": ["Basalt lava plain", "Folded \"tessera\" rock", "Lava channel edge"],
	"Mercury": ["Hollows of vanishing rock", "Shrinkage cliff rubble", "Dark carbon-rich soil"],
	"Titan": ["Water-ice pebbles", "Hydrocarbon sand dune", "Dry methane riverbed"],
	"Io": ["Fresh sulfur frost", "Cooling lava crust", "Volcanic plume fallout"],
	"Europa": ["Salt-stained ice", "Fresh crack in the ice shell", "Reddish ice ridge"],
	"Enceladus": ["Snow from the geysers", "Tiger-stripe crack edge", "Salty ice grains"],
	"Ceres": ["Bright salt deposit", "Clay-rich soil", "Icy crater rim"],
	"Pluto": ["Nitrogen ice glacier", "Methane snow", "Reddish tholin dust"],
}
const DRIVE_SPEED = 3.0                    # meters per second on screen (real rovers creep at about 4 cm/s; time runs faster here)
const MINUTES_PER_DRIVING_SECOND = 1.0     # each second of driving is a minute on the mission clock
const STUDY_SECONDS = 3.0

@onready var ground: MeshInstance3D = $Ground
@onready var lander_holder: Node3D = $LanderHolder
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var destination = ""
var landing = ""
var vehicle: Node3D            # everything coming down together
var lander: Node3D             # the real lander or rover
var lander_size = 3.0
var capsule: Node3D = null
var parachute: Node3D = null
var crane: Node3D = null
var airbags: Node3D = null
var lander_flames = []
var crane_flames = []
var phases = []                # [name, seconds, start height, end height]
var phase_index = 0
var phase_time = 0.0
var height = 0.0
var landed = false
var drifting = []              # pieces left behind: {"node", "velocity", "spin"}
var dust_color = Color.WHITE
var dust_timer = 0.0
var shake = 0.0
var camera_angle = 0.6
var parachute_full_size = 10.0
const CABLE_LENGTH = 7.5               # meters: Perseverance hung 6.4 m under its descent stage (a little longer here so it shows)
const DIVERT = Vector3(16.0, 0.0, 11.0)   # the descent stage flies this far sideways to the landing spot, out from under the backshell and parachute
var crane_stowed_height = 2.0          # how high the descent stage sits above the ground-level of the rover while they fly as one
var platform: Node3D = null        # the legged lander that carries the rover
var rover_ready = false            # the rover is on the ground and free to drive
var legs_deployed = false

# Driving
var driving = false
var rover_heading = 0.0
var rover_speed = 0.0
var rover_vertical_speed = 0.0
var last_ground_height = 0.0
var battery = 100.0
var heat = 0.0
var cold = 0.0
var radiation_dose = 0.0
var wheel_damage = 0.0
var odometer = 0.0
var mission_minutes = 0.0
var targets = []                # {"node", "name", "place", "studied"}
var studying = null
var study_time = 0.0
var science_found = 0
var findings = []
var big_rocks = []              # [place, radius]
var sand_patches = []           # [place, radius]
var height_image: Image = null
var messages_shown = {}
var message_seconds = 0.0
var failure = ""
var bump_cooldown = 0.0
var engine_sound_on = false
var parachute_sound_played = false

# The journey (launch.gd) pauses the landing or the rover while a decision is on screen, and opens the decisions
# made on the way down once the landing reaches its tense moment (just before the parachute opens, or on the way in)
var paused = false:
	set(value):
		paused = value
		if rover_body:
			rover_body.freeze = value   # the rover can't roll away while a decision is on screen
var reached_decision_point = false
var crash_landing = false          # a landing check failed or a decision went wrong: it comes down far too hard
var drive_seconds = 0.0            # time spent driving, so surface events come every so often while you drive

# The landing site scene and its ground
var site: Node3D = null
var crater_list = []               # Vector4: x, z, radius, depth (the same craters the ground shader draws)
var world_radius = 1.0e12          # how fast the ground curves away (meters)
var sights = []                    # things to notice at this site, shown while you drive
var sight_index = 0
var sight_timer = 6.0
var rover_body: VehicleBody3D = null
var rover_wheels = []                # [VehicleWheel3D, steering share: +1 front corners, -1 rear corners, 0 middle]
var terrain_body: StaticBody3D = null
var terrain_heights = PackedFloat32Array()
var terrain_rows_done = 0
var landing_ground = 0.0             # the ground's height right where the lander comes down
var airborne_seconds = 0.0
var tipped_seconds = 0.0
var track_mesh: ImmediateMesh = null
var track_points = []              # [left wheel, right wheel] for each step along the rover's path

func set_up(destination_name):
	destination = destination_name
	add_to_group("landing_site")
	landing = GameState.choices.get("landing", "landing_legs")
	var world = WORLDS.get(destination, WORLDS["Moon"])
	dust_color = world["light"].lightened(0.15)
	var site_path = SITE_FOLDER + destination.to_lower() + "_site.tscn"
	if ResourceLoader.exists(site_path):
		use_site(load(site_path).instantiate())
	else:
		set_up_ground(world)
		set_up_sky(world)
		scatter_rocks(world)
	landing_ground = ground_height(Vector2.ZERO) if site else 0.0
	start_world_sound()
	build_vehicle()
	plan_landing()
	update_vehicle(0.0)
	place_camera(1.0)

# ---------------------------------------------------------------------------
# Sound on another world depends on its air. Mars's thin air makes everything about 20 decibels quieter than on
# Earth and fades the high pitches; Venus and Titan's thick air carries sound well and makes it deeper;
# with no air at all (the Moon, Mercury, icy moons) you'd only hear vibrations coming up through the rover itself.
# ---------------------------------------------------------------------------
func audio():
	return get_node_or_null("/root/AudioManager")

func play_sound(sound_name, volume_db = 0.0, pitch = 1.0):
	if audio():
		audio().play_effect(sound_name, volume_db + air_loudness(), pitch * air_pitch())

func air_thickness():
	if destination in ["Venus", "Titan"]:
		return 1.0
	if destination == "Mars":
		return 0.3
	return 0.02

func air_loudness():
	return {"Venus": 3.0, "Titan": 2.0, "Mars": -8.0}.get(destination, -14.0)

func air_pitch():
	return {"Venus": 0.75, "Titan": 0.85}.get(destination, 1.0)

func start_world_sound():
	var sound = audio()
	if sound == null:
		return
	sound.set_air(air_thickness())
	if destination == "Mars":
		sound.play_ambience("mars_wind", 0.0)   # real wind, recorded by Perseverance's microphone
	elif destination in ["Venus", "Titan"]:
		sound.play_ambience("mars_wind", 4.0, 0.6)   # thick air: a deeper, stronger wind
	else:
		sound.stop_ambience(1.0)

func start_engine_sound():
	if engine_sound_on or audio() == null:
		return
	engine_sound_on = true
	audio().start_engine("engine_loop", -6.0 + air_loudness(), air_pitch())

func stop_engine_sound():
	if engine_sound_on and audio():
		audio().stop_engine(0.6)
	engine_sound_on = false

# How long the whole landing takes, in seconds
func landing_seconds():
	var total = 0.0
	for phase in phases:
		total += phase[1]
	return total

func has_air():
	return not destination in GameState.AIRLESS_WORLDS

# ---------------------------------------------------------------------------
# The world
# ---------------------------------------------------------------------------
# Moves in the site's sky, sunlight and ground, adds craters, and scatters its rocks on the ground
func use_site(site_scene):
	site = site_scene
	add_child(site)
	var site_sky = site.get_node_or_null("WorldEnvironment")
	if site_sky:
		world_environment.environment = site_sky.environment
		site_sky.queue_free()   # only one sky at a time
	var site_sun = site.get_node_or_null("Sun")
	if site_sun:
		sun.queue_free()
		sun = site_sun
	var near_ground = site.get_node_or_null("NearGround")
	if near_ground:
		ground.queue_free()
		ground = near_ground
	dust_color = site.get_meta("dust_color", dust_color)
	sights = Array(site.get_meta("sights", PackedStringArray()))
	var material = ground.get_active_material(0)
	if material is ShaderMaterial:
		world_radius = material.get_shader_parameter("world_radius")
		# The computer's copy of the ground's height noise (the same picture the shader reads, made right away)
		var noise_texture = material.get_shader_parameter("height_noise")
		if noise_texture is NoiseTexture2D and noise_texture.noise:
			height_image = noise_texture.noise.get_seamless_image(noise_texture.width, noise_texture.height, noise_texture.invert, noise_texture.in_3d_space, noise_texture.seamless_blend_skirt, noise_texture.normalize)
		make_craters(material)
	var rock_field = site.get_node_or_null("RockField")
	if rock_field and rock_field.has_method("scatter"):
		rock_field.scatter(self)

# Craters: lots of small ones and a few big ones, sized like real crater fields (many more small than big),
# kept clear of the landing spot. Big ones farther out shape the view.
func make_craters(material):
	var count = int(site.get_meta("crater_count", 0))
	var biggest = float(site.get_meta("crater_max_radius", 30.0))
	var depth_share = float(site.get_meta("crater_depth", 0.2))
	var random = RandomNumberGenerator.new()
	random.seed = hash(destination) + 3
	crater_list = []
	var far_count = min(int(count / 3), 12)
	for index in min(count + far_count, MAX_CRATERS):
		var far = index >= count
		var radius = lerp(2.0, biggest, pow(random.randf(), 2.2)) if not far else random.randf_range(biggest * 2.0, biggest * 6.0)
		for attempt in 10:
			var angle = random.randf() * TAU
			var distance = sqrt(random.randf()) * 230.0 if not far else random.randf_range(350.0, 3000.0)
			var place = Vector2(cos(angle), sin(angle)) * distance
			if place.length() > radius * 1.6 + 10.0:
				crater_list.append(Vector4(place.x, place.y, radius, radius * depth_share * random.randf_range(0.6, 1.2)))
				break
	material.set_shader_parameter("craters", crater_list)
	material.set_shader_parameter("crater_count", crater_list.size())

func craters_height(place):
	var total = 0.0
	for crater in crater_list:
		var r = place.distance_to(Vector2(crater.x, crater.y)) / crater.z
		if r > 4.0:
			continue
		var rim = crater.w * 0.22
		if r < 1.0:
			total += rim + crater.w * (r * r - 1.0)
		else:
			total += rim / (r * r * r)
	return total

func set_up_ground(world):
	var material = ground.get_active_material(0)
	if material is ShaderMaterial:
		material.set_shader_parameter("light_ground", world["light"])
		material.set_shader_parameter("dark_ground", world["dark"])

func set_up_sky(world):
	var environment = world_environment.environment
	if world.has("sky_top"):
		var sky = Sky.new()
		var sky_material = ProceduralSkyMaterial.new()
		sky_material.sky_top_color = world["sky_top"]
		sky_material.sky_horizon_color = world["sky_horizon"]
		sky_material.ground_horizon_color = world["sky_horizon"]
		sky_material.ground_bottom_color = world["dark"]
		sky_material.sun_angle_max = 8.0
		sky.sky_material = sky_material
		environment.background_mode = Environment.BG_SKY
		environment.sky = sky
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_energy = 0.7
		environment.fog_enabled = true
		environment.fog_light_color = world["sky_horizon"]
		environment.fog_density = world["haze"]
		sun.light_energy = 1.3 * world.get("dim", 1.0)
		sun.light_color = world["sky_horizon"].lerp(Color.WHITE, 0.6)
	else:
		# No air: a black sky full of stars even in daylight, and harsh sunlight with dark shadows
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color.BLACK
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.5, 0.52, 0.56)
		environment.ambient_light_energy = 0.12
		SpaceTextures.add_star_sky(world_environment)
		sun.light_energy = 1.7
	if world.has("sky_planet"):
		var planet = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 96
		sphere.rings = 48
		planet.mesh = sphere
		SpaceTextures.texture_planet(planet, world["sky_planet"])
		# How big it looks: "planet_size" is its width in the sky in degrees (Earth from the Moon is about 1.9)
		var distance = 9000.0
		planet.scale = Vector3.ONE * distance * tan(deg_to_rad(world["planet_size"]) * 0.5)
		planet.position = Vector3(-0.45, 0.28, -0.85).normalized() * distance
		planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(planet)

func scatter_rocks(world):
	var rocks = MultiMeshInstance3D.new()
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = BeltBuilder.make_rock_mesh(abs(destination.hash()) % 1000, 0.4, false)
	multimesh.instance_count = 320
	var random = RandomNumberGenerator.new()
	random.seed = destination.hash()
	for index in multimesh.instance_count:
		var angle = random.randf() * TAU
		var distance = random.randf_range(4.0, 45.0)
		var size = pow(random.randf(), 3.0) * 1.3 + 0.08   # lots of pebbles, a few boulders
		var basis = Basis(Vector3(random.randf(), random.randf(), random.randf()).normalized(), random.randf() * TAU).scaled(Vector3(size, size * 0.7, size))
		multimesh.set_instance_transform(index, Transform3D(basis, Vector3(cos(angle) * distance, -size * 0.25, sin(angle) * distance)))
		if size > 0.9:
			big_rocks.append([Vector2(cos(angle), sin(angle)) * distance, size * 0.6])
	rocks.multimesh = multimesh
	var rock_material = StandardMaterial3D.new()
	rock_material.albedo_color = world["dark"].lerp(world["light"], 0.35)
	rock_material.roughness = 0.95
	rocks.material_override = rock_material
	add_child(rocks)

# ---------------------------------------------------------------------------
# The lander and what brings it down
# ---------------------------------------------------------------------------
func build_vehicle():
	vehicle = Node3D.new()
	lander_holder.add_child(vehicle)
	# A rover is NASA's real Perseverance (Curiosity is its near twin); landers are the real lander they're most like
	var lookalike_id = "perseverance" if can_drive() else SpacecraftLookalike.closest()
	lander_size = SpacecraftLookalike.LOOKALIKES.get(lookalike_id, {"size": 3.0})["size"]
	lander = SpacecraftLookalike.load_model(lookalike_id, lander_size)
	if lander == null:
		lander = Node3D.new()
		var box = MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		lander.add_child(box)
	vehicle.add_child(lander)
	if lookalike_id in ["perseverance", "opportunity"]:
		lander.rotation.y = PI   # NASA's rover models face -Z; turn them to face the way they drive
	# The Apollo Lunar Module had one big descent engine; Viking, InSight and Phoenix had clusters of small thrusters
	if can_drive() and landing == "landing_legs":
		add_rover_platform()
		return
	var engine_spots = [Vector2.ZERO] if lookalike_id == "apollo_lunar_module" else [Vector2(0.25, 0.25), Vector2(-0.25, 0.25), Vector2(0.25, -0.25), Vector2(-0.25, -0.25)]
	for spot in engine_spots:
		var flame = RocketModel.make_flame("hydrogen")
		var nozzle = 0.45 if engine_spots.size() == 1 else 0.12
		flame.position = Vector3(spot.x * lander_size, lander_size * 0.12, spot.y * lander_size)
		flame.scale = Vector3(nozzle, 1.6, nozzle) * max(lander_size * 0.35, 1.0)
		flame.visible = false
		RocketModel.set_flame_vacuum(flame, 1.0 if not has_air() else 0.3)
		lander.add_child(flame)
		lander_flames.append(flame)

# The rover rides on the platform's deck; its four engines bring them down, and its legs swing out on the way
func add_rover_platform():
	platform = ROVER_PLATFORM_SCENE.instantiate()
	vehicle.add_child(platform)
	lander.position.y = platform.get_meta("deck_height", 1.475)
	var animation = platform.get_node_or_null("AnimationPlayer")
	if animation:
		animation.play("legs_out")
		animation.seek(0.0, true)
		animation.pause()   # folded up until the last part of the descent
	for engine in platform.get_children():
		if engine.name.begins_with("Engine"):
			var flame = RocketModel.make_flame("hydrogen")
			flame.position = Vector3(0, -0.22, 0)
			flame.scale = Vector3(0.2, 1.5, 0.2)
			flame.visible = false
			RocketModel.set_flame_vacuum(flame, 1.0 if not has_air() else 0.3)
			engine.add_child(flame)
			lander_flames.append(flame)

func deploy_legs():
	if legs_deployed or platform == null:
		return
	legs_deployed = true
	var animation = platform.get_node_or_null("AnimationPlayer")
	if animation:
		animation.play("legs_out")
	play_sound("servo", -6.0, 1.2)    # the legs swing out and lock
	if audio():
		audio().play_effect("latch", -6.0 + air_loudness(), air_pitch(), 0.5)

# After touchdown: the ramps fold down and the rover drives off the deck onto the ground
func deploy_rover():
	var animation = platform.get_node_or_null("AnimationPlayer")
	await get_tree().create_timer(1.0).timeout
	if animation:
		animation.play("ramps_down")
	play_sound("servo", -4.0, 0.9)    # the ramps fold down
	if audio():
		audio().play_effect("clank", -6.0 + air_loudness(), air_pitch(), 0.9)
	await get_tree().create_timer(2.2).timeout
	var deck = lander.position.y
	var ramp_length = platform.get_meta("ramp_length", 2.5)
	var ramp_angle = deg_to_rad(platform.get_meta("ramp_angle_degrees", 35.5))
	var ramp_top = 1.75
	var ramp_bottom = ramp_top + ramp_length * cos(ramp_angle)
	var drive = create_tween()
	drive.tween_property(lander, "position", Vector3(0, deck, ramp_top), 1.4).set_trans(Tween.TRANS_SINE)
	drive.tween_property(lander, "rotation:x", -ramp_angle, 0.5)
	drive.parallel().tween_property(lander, "position", Vector3(0, deck - 0.2, ramp_top + 0.3), 0.5)
	drive.tween_property(lander, "position", Vector3(0, 0.12, ramp_bottom - 0.3), 2.2)
	drive.tween_property(lander, "rotation:x", 0.0, 0.5)
	drive.parallel().tween_property(lander, "position", Vector3(0, 0.0, ramp_bottom + 0.4), 0.5)
	drive.tween_property(lander, "position", Vector3(0, 0.0, ramp_bottom + 2.2), 1.2).set_trans(Tween.TRANS_SINE)
	if audio():
		audio().start_engine("mars_rover_drive", -14.0 + air_loudness(), air_pitch())
	await drive.finished
	if audio():
		audio().stop_engine(0.5)
	# The platform stays behind; from here on the rover is the vehicle
	var platform_place = platform.global_transform
	vehicle.remove_child(platform)
	add_child(platform)
	platform.global_transform = platform_place
	vehicle.global_position += vehicle.global_transform.basis * lander.position
	lander.position = Vector3.ZERO
	rover_ready = true

# Huygens (2005) floated down onto Titan inside its capsule the whole way. A lander carrying a rover drops its
# heat shield and comes down under its own power instead, like at Mars.
func huygens_style():
	return destination == "Titan" and platform == null

func uses_heat_shield():
	return has_air() and not huygens_style() and GameState.choices.get("shield", "") in ["shield_heat", "shield_venus"]

func plan_landing():
	if huygens_style():
		# Huygens floated down for 2.5 hours under its parachute; here it's sped up
		add_capsule()
		phases = [["parachute", 9.0, 260.0, 0.0]]
		return
	if uses_heat_shield():
		add_capsule()
		phases = [["parachute", 4.5, 260.0, 110.0], ["release", 1.2, 110.0, 95.0]]
		if landing == "landing_skycrane":
			crane = SKY_CRANE_SCENE.instantiate()
			vehicle.add_child(crane)
			# The rover rides tucked right under the descent stage until the last 20 meters
			crane_stowed_height = lander_size * 0.62 + 0.45
			crane.position.y = crane_stowed_height
			set_cables(0.0)
			for engine in crane.get_children():
				if engine.name.begins_with("Engine"):
					var flame = RocketModel.make_flame("methane")
					flame.position = engine.position + Vector3(0, -0.2, 0)
					flame.scale = Vector3(0.14, 2.5, 0.14)
					flame.visible = false
					crane.add_child(flame)
					crane_flames.append(flame)
			crane.visible = false
			# Real order: drop out of the backshell, fire the engines and fly sideways (so the backshell and parachute
			# don't land on the rover), slow to a hover speed, then lower the rover on cables for the last 20 meters
			phases = [["parachute", 4.5, 260.0, 110.0], ["release", 1.1, 110.0, 97.0], ["crane_powered", 5.5, 97.0, 21.0], ["sky_crane", 6.0, 21.0, 0.0]]
		elif landing == "landing_airbags":
			airbags = AIRBAGS_SCENE.instantiate()
			airbags.scale = Vector3.ONE * (lander_size / 2.3)
			airbags.position.y = -0.3
			vehicle.add_child(airbags)
			airbags.visible = false
			phases.append(["airbags", 6.0, 95.0, 0.0])
		else:
			phases.append(["powered", 5.5, 95.0, 0.0])
		return
	phases = [["powered", 7.5, 180.0, 0.0]]

func add_capsule():
	capsule = AEROSHELL_SCENE.instantiate()
	var shell_size = max(lander_size * 1.5, 3.0) / 4.5   # Perseverance's aeroshell is 4.5 m wide for a 3 m rover
	capsule.scale = Vector3.ONE * shell_size
	vehicle.add_child(capsule)
	capsule.get_node("Backshell/CruiseStage").visible = false   # the cruise stage was dropped before entry
	parachute = PARACHUTE_SCENE.instantiate()
	parachute_full_size = 4.8 * 2.25 * shell_size     # the canopy is about 4.8 times as wide as the aeroshell
	parachute.scale = Vector3.ONE * 0.05
	capsule.add_child(parachute)
	lander.visible = false   # folded up inside the capsule
	if platform:
		platform.visible = false

# ---------------------------------------------------------------------------
# Every frame
# ---------------------------------------------------------------------------
func _process(delta):
	update_storm(delta)   # (weather keeps moving while a decision is on screen)
	if paused:
		return
	if site and terrain_rows_done < TERRAIN_POINTS:
		build_terrain_rows(12)   # the ground's collision shape, a few rows at a time while the lander comes down
	update_drifting(delta)
	shake = max(0.0, shake - delta * 1.5)
	if driving:
		update_driving(delta)
		return
	if landed:
		camera_angle += delta * 0.12
		place_camera(min(1.0, delta * 2.0))
		return
	if phase_index >= phases.size():
		return
	phase_time += delta
	var phase = phases[phase_index]
	var fraction = clamp(phase_time / phase[1], 0.0, 1.0)
	update_vehicle(fraction)
	place_camera(min(1.0, delta * 3.0))
	if fraction >= 1.0:
		finish_phase(phase[0])
		phase_index += 1
		phase_time = 0.0
		if phase_index >= phases.size():
			touchdown()

# Slowing down as it nears the end of each phase
func eased(fraction):
	return 1.0 - pow(1.0 - fraction, 2.0)

func update_vehicle(fraction):
	if phases.is_empty():
		return
	var phase = phases[min(phase_index, phases.size() - 1)]
	var phase_name = phase[0]
	var is_last_phase = phase_index >= phases.size() - 1
	height = lerp(phase[2], phase[3], fraction if crash_landing and is_last_phase else eased(fraction))
	if crane and phase_name in ["parachute", "release"]:
		# A sky crane's capsule comes down off to one side; the descent stage then flies over to the landing spot
		vehicle.position.x = -DIVERT.x
		vehicle.position.z = -DIVERT.z
	match phase_name:
		"parachute":
			# A moment of free fall (where the decisions on the way down happen), then the mortar fires
			# and the canopy snaps open, and the capsule sways under it
			if phase_time >= 0.3:
				reached_decision_point = true
			var open = smoothstep(0.75, 0.95, phase_time)
			if phase_time >= 0.75 and not parachute_sound_played and not crash_landing:
				parachute_sound_played = true
				play_sound("thump", -4.0, 1.3)   # the parachute bangs open
			if crash_landing:
				open = min(open, 0.15)   # it never opens properly
			if height < 70.0:
				deploy_legs()   # (only a lander with legs has any)
			parachute.scale = Vector3.ONE * max(0.05, parachute_full_size / capsule.scale.x * open)
			parachute.position.y = (2.6 * parachute.scale.y + 3.1)
			capsule.rotation.z = sin(phase_time * 1.7) * 0.06
			if not huygens_style() and phase_time > phase[1] * 0.55 and capsule.has_node("HeatShield"):
				drop_heat_shield()
		"release":
			lander.visible = true
			if platform:
				platform.visible = true
			if crane:
				crane.visible = true
			if airbags:
				airbags.visible = true
				lander.visible = false
		"powered":
			set_flames(lander_flames, true)
			start_engine_sound()
			if height < 90.0:
				deploy_legs()
			kick_up_dust(fraction)
			if fraction >= 0.3:
				reached_decision_point = true
		"crane_powered":
			# Eight engines light; the descent stage carries the rover sideways, away from the backshell above
			set_flames(crane_flames, true)
			start_engine_sound()
			var across = smoothstep(0.0, 0.85, fraction)
			vehicle.position.x = -DIVERT.x * (1.0 - across)
			vehicle.position.z = -DIVERT.z * (1.0 - across)
			vehicle.rotation.z = -sin(fraction * PI) * 0.16   # it leans the way it's flying
			if fraction >= 0.3:
				reached_decision_point = true
		"sky_crane":
			# The last 20 meters: a steady, slow descent while the rover is lowered on its cables
			set_flames(crane_flames, true)
			start_engine_sound()
			height = lerp(phase[2], phase[3], fraction)   # steady speed (the real one came down at 0.75 m/s)
			vehicle.position.x = 0.0
			vehicle.position.z = 0.0
			vehicle.rotation.z = 0.0
			if not cables_started:
				cables_started = true
				play_sound("servo", -2.0, 0.8)     # the cable reels start to turn
				if audio():
					audio().play_effect("servo_loop", -6.0 + air_loudness(), air_pitch(), 0.3)
			var lowered = smoothstep(0.05, 0.55, fraction)
			crane.position.y = lerp(crane_stowed_height, crane_stowed_height + CABLE_LENGTH, lowered)
			set_cables(lowered)
			lander.rotation.z = sin(phase_time * 2.2) * 0.02 * (1.0 - fraction)   # a slight swing on the cables
			kick_up_dust(fraction)
		"airbags":
			# Hit the ground at 70 % of the way, then bounce a few times (Opportunity bounced 26 times)
			if fraction < 0.7:
				height = lerp(phase[2], 0.0, fraction / 0.7)
			else:
				var bounce_time = (fraction - 0.7) / 0.3
				height = abs(sin(bounce_time * PI * 3.0)) * 6.0 * pow(1.0 - bounce_time, 2.0)
				if bounce_time > 0.85:
					airbags.scale = airbags.scale.lerp(Vector3.ONE * 0.05, 0.08)
					lander.visible = true
	vehicle.position.y = height + landing_ground

func finish_phase(phase_name):
	if phase_name == "parachute" and not huygens_style() and capsule:
		# The lander drops out of the backshell; the backshell and parachute drift off
		var place = capsule.global_transform
		vehicle.remove_child(capsule)
		add_child(capsule)
		capsule.global_transform = place
		# It keeps coming down slowly under its parachute and the wind carries it off; the lander falls away below it
		drifting.append({"node": capsule, "velocity": Vector3(-7.0, -6.5, -4.0), "spin": Vector3.ZERO, "lands": true, "sway": true})

func drop_heat_shield():
	var heat_shield = capsule.get_node("HeatShield")
	var place = heat_shield.global_transform
	capsule.remove_child(heat_shield)
	add_child(heat_shield)
	heat_shield.global_transform = place
	# It falls faster than everything else (nothing is slowing it) and hits the ground well away from the landing spot
	drifting.append({"node": heat_shield, "velocity": Vector3(-6.0, -24.0, 7.0), "spin": Vector3(0.6, 0, 0.4), "lands": true})
	play_sound("impact", -10.0, 0.8)

func fly_crane_away():
	# Cables cut: the descent stage throttles up and flies off to crash a safe distance away, like Perseverance's did
	# (it came down about 700 m from the rover)
	var place = crane.global_transform
	vehicle.remove_child(crane)
	add_child(crane)
	crane.global_transform = place
	set_cables(0.0)
	play_sound("clank", 0.0)   # the cable cutters fire
	set_flames(crane_flames, true)
	drifting.append({"node": crane, "velocity": Vector3(9.0, 13.0, -7.0), "spin": Vector3(0, 0, -0.12), "falls": true, "lands": true, "burn_seconds": 2.6, "crashes": true})
	play_sound("thruster", -2.0, 0.8)

# How far the rover's cables are let out (0 = stowed, 1 = all the way)
func set_cables(share):
	if crane == null:
		return
	for child in crane.get_children():
		if child.name.begins_with("Cable"):
			child.visible = share > 0.01
			child.scale.y = max(share, 0.01)
			child.position.y = -CABLE_LENGTH * share / 2.0

# Pieces that have been let go: they keep moving, and the ones that reach the ground land on it (with a puff of dust)
# instead of sinking through
func update_drifting(delta):
	for piece in drifting.duplicate():
		var node = piece["node"]
		if not is_instance_valid(node):
			drifting.erase(piece)
			continue
		if piece.get("falls", false):
			piece["velocity"].y -= max(CONDITIONS.get(destination, [3.7])[0], 1.0) * delta
		if piece.has("burn_seconds"):
			piece["burn_seconds"] -= delta
			if piece["burn_seconds"] <= 0.0:
				set_flames(crane_flames, false)
				piece.erase("burn_seconds")
		node.global_position += piece["velocity"] * delta
		node.rotation += piece["spin"] * delta
		if piece.get("sway", false):
			node.rotation.z = sin(Time.get_ticks_msec() / 1000.0 * 1.3) * 0.08
		var ground = ground_height(Vector2(node.global_position.x, node.global_position.z))
		if piece.get("lands", false) and node.global_position.y <= ground + 0.4 and piece["velocity"].y < 0.0:
			# Down: it stays where it fell
			node.global_position.y = ground + 0.3
			spawn_dust(Vector3(node.global_position.x, ground + 0.3, node.global_position.z), 4.0)
			var distance = node.global_position.distance_to(camera.global_position)
			play_sound("thump", clamp(-4.0 - distance * 0.05, -30.0, -4.0), 0.9)
			if piece.get("crashes", false):
				play_sound("crash", clamp(2.0 - distance * 0.04, -24.0, 2.0), 0.8)
				spawn_dust(Vector3(node.global_position.x, ground + 1.0, node.global_position.z), 9.0)
				node.rotation = Vector3(0.5, node.rotation.y, 1.1)
				set_flames(crane_flames, false)
			elif node == capsule:
				node.rotation = Vector3(0.0, node.rotation.y, 1.25)   # it tips onto its side
				if parachute and is_instance_valid(parachute):
					parachute.visible = false   # the canopy collapses
			else:
				node.rotation = Vector3(PI + 0.1, node.rotation.y, 0.12)   # the heat shield lies dish-up, like the real one photographed by Opportunity
			drifting.erase(piece)
			continue
		if node.global_position.y < -200.0 or node.global_position.length() > 1500.0:
			node.queue_free()
			drifting.erase(piece)

func set_flames(flames, on):
	for flame in flames:
		if is_instance_valid(flame):
			flame.visible = on

# Engine blast blowing dust off the ground in the last few meters
func kick_up_dust(fraction):
	dust_timer -= get_process_delta_time()
	if height < 25.0 and dust_timer <= 0.0:
		dust_timer = 0.15
		spawn_dust(Vector3(vehicle.position.x, landing_ground + 0.3, vehicle.position.z), 2.5 + (25.0 - height) * 0.25)

func spawn_dust(place, size):
	var dust = DUST_SCENE.instantiate()
	dust.color = dust_color
	dust.scale_amount_min *= size
	dust.scale_amount_max *= size
	dust.initial_velocity_min *= size
	dust.initial_velocity_max *= size
	dust.lifetime = 1.6
	add_child(dust)
	dust.global_position = place
	dust.restart()
	get_tree().create_timer(3.5).timeout.connect(dust.queue_free)

func touchdown():
	landed = true
	reached_decision_point = true
	vehicle.position.y = landing_ground
	if crash_landing:
		crash()
		touched_down.emit()
		return
	if parachute and is_instance_valid(parachute):
		parachute.visible = false   # the canopy collapses onto the ground
	set_flames(lander_flames, false)
	if crane and is_instance_valid(crane) and crane.get_parent() == vehicle:
		lander.rotation.z = 0.0
		fly_crane_away()   # wheels down: the cables are cut and the descent stage flies clear
	else:
		set_flames(crane_flames, false)
	shake = 0.6
	spawn_dust(Vector3(vehicle.position.x, landing_ground + 0.3, vehicle.position.z), 6.0 + lander_size)
	stop_engine_sound()
	play_sound("thump", 2.0, 0.8)
	if destination == "Moon" and audio():
		audio().play_voice("eagle_has_landed", 0.0, 1.5)   # Apollo 11: "Houston, Tranquility Base here. The Eagle has landed."
	if platform and can_drive():
		deploy_rover()
	else:
		rover_ready = true
	touched_down.emit()

# Far too fast: a cloud of dust, a bang, and a broken lander tipped over in its own crater
func crash():
	set_flames(lander_flames, false)
	set_flames(crane_flames, false)
	stop_engine_sound()
	if parachute and is_instance_valid(parachute):
		parachute.visible = false
	if airbags and is_instance_valid(airbags):
		airbags.visible = false
	if crane and is_instance_valid(crane) and crane.get_parent() == vehicle:
		crane.visible = false
	lander.visible = true
	lander.rotation = Vector3(0.35, lander.rotation.y, -0.55)
	vehicle.position.y = -lander_size * 0.25
	shake = 1.6
	for burst in 3:
		spawn_dust(Vector3(randf_range(-1.0, 1.0), 0.3, randf_range(-1.0, 1.0)) * lander_size, 8.0 + lander_size * 2.0)
	play_sound("thump", 6.0, 0.6)
	play_sound("impact", 2.0, 0.7)

# What a mission event looks like down here. Returns how long to wait before its panel opens.
func play_event_effect(kind):
	match kind:
		"quake":
			shake = 1.2
			# A real marsquake that NASA's InSight lander felt (sped up so we can hear it)
			play_sound("marsquake" if destination == "Mars" else "thump", 4.0)
			return 1.6
		"hit":
			shake = 0.6
			play_sound("impact", 0.0)
			return 1.0
		"storm":
			start_storm(9.0)
			return 2.5
		"drill":
			# The robotic arm goes to work: motor whirr, a puff of rock dust, the tool locking home
			play_sound("servo", -4.0)
			spawn_dust(vehicle.position + vehicle.global_transform.basis.z.normalized() * lander_size * 0.7 + Vector3(0, 0.2, 0), 0.8)
			if audio():
				audio().play_effect("servo_loop", -8.0 + air_loudness(), 1.3 * air_pitch(), 0.4)
				audio().play_effect("latch", -4.0 + air_loudness(), air_pitch(), 2.2)
			shake = 0.15
			return 2.4
		"night":
			start_storm(0.0, 7.0)   # just the darkness, no dust
			return 1.5
		"dust":
			var dust_devil = site.get_node_or_null("DustDevil1") if site else null
			if dust_devil and dust_devil.has_method("pass_near"):
				dust_devil.pass_near(vehicle.position)
			if has_air():
				spawn_dust(vehicle.position + Vector3(lander_size * 3.0, 0.5, -lander_size * 2.0), 6.0)
				spawn_dust(vehicle.position + Vector3(-lander_size * 2.0, 0.5, lander_size * 3.0), 5.0)
			else:
				spawn_dust(vehicle.position + Vector3(0, 0.3, 0), 2.5)   # dust clinging and lifting off the rover
			return 1.4
	return 0.4

# A dust storm rolls over the landing site: sheets of dust race past, the sky dims and turns the color of the
# dust, and the wind howls (on Mars that's Perseverance's real wind recording, turned up). Then it clears.
# With dust_seconds 0 only the darkening happens (nightfall, an eclipse).
func start_storm(dust_seconds, dark_seconds = 0.0):
	storm_seconds_left = max(dust_seconds, dark_seconds)
	storm_seconds_total = storm_seconds_left
	storm_has_dust = dust_seconds > 0.0 and has_air()
	if storm_has_dust:
		if storm == null:
			storm = DUST_STORM_SCENE.instantiate()
			add_child(storm)
			for particles in storm.get_children():
				particles.process_material = particles.process_material.duplicate()
				particles.process_material.color = Color(dust_color.r, dust_color.g, dust_color.b, particles.process_material.color.a)
		for particles in storm.get_children():
			particles.emitting = true
		if audio():
			audio().play_effect("mars_wind", 8.0 + air_loudness(), 0.75 * air_pitch())
			audio().play_effect("mars_wind", 6.0 + air_loudness(), 1.1 * air_pitch(), 1.5)

func update_storm(delta):
	if storm_seconds_total <= 0.0:
		return
	storm_seconds_left -= delta
	# Builds up over the first second and a half, clears over the last two
	var strength = clamp(min((storm_seconds_total - storm_seconds_left) / 1.5, storm_seconds_left / 2.0), 0.0, 1.0)
	var world_environment = get_node_or_null("WorldEnvironment")
	if world_environment and world_environment.environment:
		var environment: Environment = world_environment.environment
		if not has_meta("calm_weather"):
			set_meta("calm_weather", [environment.fog_density, environment.fog_light_color, environment.ambient_light_energy, environment.fog_enabled])
		var calm = get_meta("calm_weather")
		if storm_has_dust:
			environment.fog_enabled = true
			environment.fog_density = lerp(calm[0] if calm[3] else 0.0, 0.035, strength)
			environment.fog_light_color = calm[1].lerp(dust_color * 0.55, strength)
		environment.ambient_light_energy = calm[2] * lerp(1.0, 0.35, strength)
		if storm_seconds_left <= 0.0:
			environment.fog_enabled = calm[3]
			environment.fog_density = calm[0]
			environment.fog_light_color = calm[1]
			environment.ambient_light_energy = calm[2]
	if sun:
		if not sun.has_meta("calm_energy"):
			sun.set_meta("calm_energy", sun.light_energy)
		sun.light_energy = sun.get_meta("calm_energy") * lerp(1.0, 0.2, strength)
	if storm_has_dust:
		shake = max(shake, 0.12 * strength)
	if storm_seconds_left <= 2.0 and storm:
		for particles in storm.get_children():
			particles.emitting = false
	if storm_seconds_left <= 0.0:
		storm_seconds_total = 0.0

# ---------------------------------------------------------------------------
# The camera: tracking the lander down, then slowly circling it on the ground
# ---------------------------------------------------------------------------
func place_camera(blend):
	var target = vehicle.global_position + Vector3(0, lander_size * 0.5, 0)
	var wanted
	if landed:
		var distance = lander_size * 2.6 + 4.0
		wanted = target + Vector3(cos(camera_angle) * distance, lander_size * 0.35 + 0.8, sin(camera_angle) * distance)
	else:
		var distance = 26.0 + height * 0.25
		wanted = Vector3(target.x + distance * 0.7, max(1.8, target.y - 6.0 - height * 0.1), target.z + distance * 0.7)
		if capsule and parachute and capsule.get_parent() == vehicle:
			target += Vector3(0, parachute_full_size * 0.6, 0)   # keep the parachute in the picture
	camera.global_position = camera.global_position.lerp(wanted, blend) if blend < 1.0 else wanted
	camera.look_at(target, Vector3.UP)
	if shake > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * shake * 0.2
		camera.v_offset = randf_range(-1.0, 1.0) * shake * 0.2
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

# ---------------------------------------------------------------------------
# Driving the rover. The real conditions decide how long it lasts:
#   Venus and Mercury's heat cooks it (a pressure and heat hull and radiators buy time),
#   the icy worlds' cold freezes its batteries (heaters or an RTG's warmth keep it going),
#   Jupiter's radiation fries its electronics near Io and Europa (a hardened computer or a radiation vault helps),
#   solar panels barely charge far from the Sun or under Titan and Venus's clouds, and low gravity makes it bounce.
# ---------------------------------------------------------------------------
# Every rocky world can have a rover, whatever brings it down (sky crane, airbags, or a lander with legs and ramps)
func can_drive():
	return landing != "landing_none" and CONDITIONS.has(destination)

func start_driving():
	driving = true
	$DriveScreen.visible = true
	# The rover rolls off whatever brought it down: Titan's capsule, or its deflated airbags
	if capsule and is_instance_valid(capsule) and capsule.get_parent() == vehicle:
		var place = capsule.global_transform
		vehicle.remove_child(capsule)
		add_child(capsule)
		capsule.global_transform = place
		vehicle.position += Vector3(lander_size * 1.8, 0, 0)
	if airbags and is_instance_valid(airbags):
		airbags.visible = false
	lander.visible = true
	if height_image == null:
		var material = ground.get_active_material(0)
		var noise_texture = material.get_shader_parameter("height_noise") if material is ShaderMaterial else null
		if noise_texture:
			height_image = noise_texture.get_image()
	start_tracks()
	var conditions = CONDITIONS[destination]
	var temperature = conditions[1]
	$DriveScreen/DrivePanel/Column/DriveTitle.text = "PERSEVERANCE ON %s" % destination.to_upper()
	var heat_label = $DriveScreen/DrivePanel/Column/HeatLabel
	heat_label.text = "Heat soaking in (%d °C outside)" % temperature if temperature > 200 else ("Cold soaking in (%d °C outside)" % temperature if temperature < -100 else "Temperature: %d °C (fine)" % temperature)
	var shows_radiation = conditions[2] > 0
	$DriveScreen/DrivePanel/Column/RadiationLabel.visible = shows_radiation
	$DriveScreen/DrivePanel/Column/RadiationBar.visible = shows_radiation
	place_science_targets()
	if destination == "Mars":
		place_sand_patches()
	rover_heading = randf() * TAU
	last_ground_height = ground_height(Vector2(vehicle.position.x, vehicle.position.z))
	make_rover_body()
	add_mission_boundary()
	if audio():
		audio().start_engine("mars_rover_drive", -60.0, air_pitch())
	show_message(intro_message(), 9.0)

func intro_message():
	var conditions = CONDITIONS[destination]
	var gravity_share = conditions[0] / 9.81 * 100.0
	var choices = GameState.choices
	var has_rtg = choices.get("power", "") in ["rtg", "rtg_triple"]
	match destination:
		"Venus":
			return "Venus: 465 °C and 92 times Earth's air pressure. Your rover starts cooking the moment it lands (Venera 13 lasted 127 minutes)." + (" Your pressure and heat hull buys you time." if choices.get("shield", "") == "shield_venus" else " With no heat hull, you don't have long!")
		"Mercury":
			return "Mercury's day side is 430 °C, hot enough to melt lead." + (" Your radiators and sunshade help." if choices.get("thermal", "") in ["thermal_radiators", "thermal_both"] else " Without radiators the heat builds fast.")
		"Mars":
			return "Mars: gravity is 38 % of Earth's and it's -60 °C. The wind you hear is real, recorded by Perseverance. Watch out for soft sand: Spirit got stuck in sand in 2009 and never got out."
		"Moon":
			return "The Moon: gravity is 1/6 of Earth's, so the rover bounces over bumps like the Apollo moon buggies did. There's no air, so the sky is black even in daylight."
		"Titan":
			return "Titan: -179 °C under thick orange haze. Solar panels barely work here, so NASA's Dragonfly will run on nuclear power." + (" Your RTG keeps the rover warm." if has_rtg else "")
		"Io", "Europa":
			return "%s sits inside Jupiter's radiation belts: the radiation would kill a person in minutes and slowly fries electronics." % destination + (" Your radiation protection helps." if choices.get("computer", "") == "computer_radiation_hardened" or choices.get("shield", "") == "shield_radiation" else "")
		"Phobos", "Deimos", "Enceladus", "Ceres":
			return "Gravity here is only %s %% of Earth's, so a bump sends the rover on a long, slow hop. (On Phobos, driving faster than 11 m/s would launch you into space!)" % str(snapped(gravity_share, 0.01))
	if conditions[1] < -100:
		return "%d °C: cold enough to freeze batteries solid." % conditions[1] + (" Your heaters (or your RTG's warmth) keep the rover alive." if has_rtg or choices.get("thermal", "") in ["thermal_heaters", "thermal_both"] else " Without heaters, the cold soaks in fast!")
	return "Gravity here is %d %% of Earth's." % int(gravity_share)

func place_science_targets():
	var names = SCIENCE_TARGETS.get(destination, ["Unusual rock", "Crater rim", "Dark patch", "Bright patch", "Big boulder"])
	var random = RandomNumberGenerator.new()
	random.seed = destination.hash() + 7
	for index in min(5, names.size()):
		var angle = random.randf() * TAU
		var place = Vector2(cos(angle), sin(angle)) * random.randf_range(14.0, 48.0)
		var marker = Node3D.new()
		# A thin beam of light so you can find it from far away...
		var beam = MeshInstance3D.new()
		var beam_mesh = CylinderMesh.new()
		beam_mesh.top_radius = 0.03
		beam_mesh.bottom_radius = 0.09
		beam_mesh.height = 10.0
		beam_mesh.radial_segments = 8
		beam.mesh = beam_mesh
		var glow = StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.albedo_color = Color(0.3, 0.9, 1.0, 0.55)
		beam.material_override = glow
		beam.position.y = 5.6
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(beam)
		# ...a glowing ring on the ground around it...
		var ring = MeshInstance3D.new()
		var ring_mesh = TorusMesh.new()
		ring_mesh.inner_radius = 1.25
		ring_mesh.outer_radius = 1.4
		ring_mesh.rings = 48
		ring_mesh.ring_segments = 6
		ring.mesh = ring_mesh
		ring.material_override = glow
		ring.scale.y = 0.25
		ring.position.y = 0.12
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.name = "Ring"
		marker.add_child(ring)
		# ...and the thing to study: a real rock, painted like the other rocks at this site
		var rock = TARGET_ROCKS[index % TARGET_ROCKS.size()].instantiate()
		rock.scale = Vector3.ONE * random.randf_range(0.55, 0.8)
		rock.rotation.y = random.randf() * TAU
		var rock_field = get_tree().get_first_node_in_group("rock_field")
		if rock_field and rock_field.rock_material:
			for piece in rock.find_children("*", "MeshInstance3D", true, false):
				piece.material_override = rock_field.rock_material
		marker.add_child(rock)
		add_child(marker)
		marker.position = Vector3(place.x, ground_height(place), place.y)
		targets.append({"node": marker, "name": names[index], "place": place, "studied": false})

func place_sand_patches():
	var random = RandomNumberGenerator.new()
	random.seed = 2009
	var world = WORLDS["Mars"]
	for index in 5:
		var angle = random.randf() * TAU
		var place = Vector2(cos(angle), sin(angle)) * random.randf_range(10.0, 40.0)
		var radius = random.randf_range(4.0, 8.0)
		var patch = MeshInstance3D.new()
		var disc = PlaneMesh.new()
		disc.size = Vector2(radius * 2.4, radius * 2.4)
		patch.mesh = disc
		var fade = Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 0.75))
		fade.set_color(1, Color(1, 1, 1, 0.0))
		var soft_edge = GradientTexture2D.new()
		soft_edge.gradient = fade
		soft_edge.fill = GradientTexture2D.FILL_RADIAL
		soft_edge.fill_from = Vector2(0.5, 0.5)
		soft_edge.fill_to = Vector2(1.0, 0.5)
		var sand = StandardMaterial3D.new()
		sand.albedo_texture = soft_edge
		sand.albedo_color = world["light"].lerp(Color(0.9, 0.66, 0.45), 0.35)
		sand.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sand.roughness = 1.0
		patch.material_override = sand
		add_child(patch)
		patch.position = Vector3(place.x, ground_height(place) + 0.05, place.y)
		sand_patches.append([place, radius])

# The ground's height under a point: the same math as the terrain shader, read from the same noise picture
func noise_at(texture_place):
	if height_image == null:
		return 0.5
	var width = height_image.get_width()
	var height_pixels = height_image.get_height()
	var x = fposmod(texture_place.x, 1.0) * width - 0.5
	var y = fposmod(texture_place.y, 1.0) * height_pixels - 0.5
	var x0 = int(floor(x))
	var y0 = int(floor(y))
	var fx = x - x0
	var fy = y - y0
	var top = lerp(height_image.get_pixel(posmod(x0, width), posmod(y0, height_pixels)).r, height_image.get_pixel(posmod(x0 + 1, width), posmod(y0, height_pixels)).r, fx)
	var bottom = lerp(height_image.get_pixel(posmod(x0, width), posmod(y0 + 1, height_pixels)).r, height_image.get_pixel(posmod(x0 + 1, width), posmod(y0 + 1, height_pixels)).r, fx)
	return lerp(top, bottom, fy)

func ground_height(place):
	var material = ground.get_active_material(0)
	var hill_height = material.get_shader_parameter("hill_height") if material is ShaderMaterial else 0.0
	var flat_radius = material.get_shader_parameter("flat_radius") if material is ShaderMaterial else 30.0
	var keep_flat = smoothstep(flat_radius, flat_radius * 4.0, place.length())
	return (noise_at(place * 0.0035) - 0.5) * hill_height * keep_flat + (noise_at(place * 0.03) - 0.5) * 0.5 \
		+ craters_height(place) - place.length_squared() / (2.0 * world_radius)

func update_driving(delta):
	drive_seconds += delta
	var conditions = CONDITIONS[destination]
	var real_gravity = conditions[0]
	var gravity = max(real_gravity, 0.25)   # (tiny-gravity hops are shortened, or they'd last minutes)
	var choices = GameState.choices
	var throttle = 0.0
	var steering = 0.0
	if failure == "" and studying == null:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			throttle += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			throttle -= 0.6
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			steering += 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			steering -= 1.0
	if battery <= 0.0:
		throttle = 0.0
		show_message_once("flat", "Battery flat! Waiting for it to recharge...", 4.0)
	var here = Vector2(vehicle.position.x, vehicle.position.z)
	var in_sand = false
	for patch in sand_patches:
		if here.distance_to(patch[0]) < patch[1]:
			in_sand = true
	if in_sand:
		show_message_once("sand", "Soft sand! The wheels sink and spin. Spirit got stuck like this in 2009 and never got out.", 5.0)
	var top_speed = DRIVE_SPEED * (0.2 if in_sand else 1.0) * (1.0 - wheel_damage / 150.0)
	bump_cooldown -= delta
	var forward = Vector3(sin(rover_heading), 0.0, cos(rover_heading))
	var on_ground = true
	if rover_body:
		rover_speed = drive_physics(delta, throttle, steering, in_sand, top_speed)
		forward = rover_body.global_transform.basis.z
		rover_heading = atan2(forward.x, forward.z)
		on_ground = airborne_seconds == 0.0
		if not driving:
			return
	else:
		var grip = clamp(real_gravity / 3.7, 0.3, 1.0)   # less weight pressing the wheels down means less grip
		on_ground = vehicle.position.y <= last_ground_height + 0.05
		if on_ground:
			rover_speed = move_toward(rover_speed, throttle * top_speed, delta * 2.2 * grip)
			rover_heading += steering * delta * 1.1 * (1.0 if rover_speed >= 0.0 else -1.0) * clamp(abs(rover_speed) + 0.3, 0.0, 1.0)
		forward = Vector3(sin(rover_heading), 0.0, cos(rover_heading))
		var next = vehicle.position + forward * rover_speed * delta
		var next_place = Vector2(next.x, next.z)
		for rock in big_rocks:
			if next_place.distance_to(rock[0]) < rock[1] + lander_size * 0.3:
				if abs(rover_speed) > 0.4 and bump_cooldown <= 0.0:
					bump_cooldown = 1.0
					wheel_damage = min(100.0, wheel_damage + abs(rover_speed) * 4.0)
					shake = 0.4
					play_sound("impact", 0.0)
					show_message("Bang! You hit a rock. Curiosity's wheels got holes punched in them by sharp Mars rocks." if destination == "Mars" else "Bang! You hit a rock and damaged a wheel.", 3.0)
				rover_speed = -rover_speed * 0.3
				next = vehicle.position
				next_place = here
				break
		if next_place.length() > DRIVE_AREA_RADIUS:
			next = vehicle.position
			rover_speed = 0.0
			show_message(BOUNDARY_MESSAGE, 6.0)
		# Stay on the ground, or sail off the top of a bump in low gravity
		var ground_here = ground_height(Vector2(next.x, next.z))
		rover_vertical_speed -= gravity * delta
		var new_height = vehicle.position.y + rover_vertical_speed * delta
		if new_height <= ground_here:
			rover_vertical_speed = max((ground_here - last_ground_height) / max(delta, 0.001), 0.0) * 0.9
			new_height = ground_here
			if not on_ground and real_gravity < 2.0:
				spawn_dust(Vector3(next.x, ground_here + 0.2, next.z), 1.5)
		elif real_gravity < 2.0 and new_height > ground_here + 0.6:
			show_message_once("hop", "Wheee! In low gravity the rover sails off bumps.", 3.0)
		last_ground_height = ground_here
		vehicle.position = Vector3(next.x, new_height, next.z)
		# Tilt with the slope of the ground
		var step = 1.0
		var slope_x = ground_height(Vector2(next.x + step, next.z)) - ground_here
		var slope_z = ground_height(Vector2(next.x, next.z + step)) - ground_here
		var up = Vector3(-slope_x, step, -slope_z).normalized()
		var side = up.cross(forward).normalized()
		vehicle.basis = Basis(side, up, side.cross(up).normalized()).orthonormalized()
	odometer += abs(rover_speed) * delta
	if audio():
		var effort = clamp(abs(rover_speed) / DRIVE_SPEED, 0.0, 1.0)
		audio().set_engine(lerp(-40.0, -4.0, effort) + air_loudness() if effort > 0.02 else -60.0, (0.85 + effort * 0.3) * air_pitch())
	if abs(rover_speed) > 0.5 and on_ground and randf() < delta * 4.0:
		spawn_dust(vehicle.position - forward * lander_size * 0.5, 0.6)   # dust kicked up by the wheels

	# Power: driving drains the battery; the power source refills it
	var has_rtg = choices.get("power", "") in ["rtg", "rtg_triple"]
	var sunlight = 1.0
	if destination == "Titan":
		sunlight = 0.1   # thick orange haze
	elif destination == "Venus":
		sunlight = 0.05  # thick clouds: only a few percent of the sunlight reaches the ground
	var power_share = GameState.power_made() / max(GameState.power_needed(), 1.0)
	if not has_rtg:
		power_share *= sunlight
	var recharge = clamp(power_share, 0.0, 2.0) * 0.45
	var drain = abs(throttle) * 1.2 + 0.1
	var temperature = conditions[1]
	var has_heaters = choices.get("thermal", "") in ["thermal_heaters", "thermal_both"]
	if temperature < -100 and has_heaters and not has_rtg:
		drain += 0.3   # running the heaters
	battery = clamp(battery + (recharge - drain) * delta, 0.0, 100.0)
	mission_minutes += delta * MINUTES_PER_DRIVING_SECOND

	# Heat, cold and radiation soak in over time
	if temperature > 200:
		var protection = 1.0
		if choices.get("shield", "") == "shield_venus":
			protection *= 0.25
		if choices.get("thermal", "") in ["thermal_radiators", "thermal_both"]:
			protection *= 0.7
		heat = min(100.0, heat + (temperature - 200) / 265.0 * protection * delta)
	elif temperature < -100 and not has_heaters and not has_rtg:
		cold = min(100.0, cold + (-100 - temperature) / 140.0 * delta)
	if conditions[2] > 0:
		var shielding = 1.0
		if choices.get("computer", "") == "computer_radiation_hardened":
			shielding *= 0.35
		if choices.get("shield", "") == "shield_radiation":
			shielding *= 0.35
		radiation_dose = min(100.0, radiation_dose + [0.0, 0.15, 0.6, 1.6][conditions[2]] * shielding * delta)

	if heat >= 100.0:
		end_driving("The heat got in: the rover's electronics cooked after %s." % time_text(mission_minutes))
		return
	if cold >= 100.0:
		end_driving("The cold got in: the rover's batteries froze solid after %s." % time_text(mission_minutes))
		return
	if radiation_dose >= 100.0:
		end_driving("Jupiter's radiation fried the rover's computer after %s." % time_text(mission_minutes))
		return
	if wheel_damage >= 100.0:
		end_driving("Too many rock strikes: the wheels are wrecked and the rover can't move.")
		return

	update_science(delta)
	update_tracks()
	sight_timer -= delta
	if sight_timer <= 0.0 and message_seconds <= 0.0 and sight_index < sights.size():
		show_message(sights[sight_index], 9.0)
		sight_index += 1
		sight_timer = 20.0
	update_drive_screen()
	place_drive_camera(min(1.0, delta * 3.0))
	message_seconds -= delta
	$DriveScreen/DriveMessage.modulate.a = clamp(message_seconds / 0.8, 0.0, 1.0)

func update_science(delta):
	var here = Vector2(vehicle.position.x, vehicle.position.z)
	if studying != null:
		study_time += delta
		rover_speed = 0.0
		aim_study_laser(studying)
		if study_time >= STUDY_SECONDS:
			studying["studied"] = true
			studying["node"].get_child(0).visible = false   # the beam goes out
			studying["node"].get_node("Ring").visible = false
			if study_laser:
				study_laser.visible = false
			var points = 3
			if "instrument_drill" in GameState.instruments or "instrument_spectrometer" in GameState.instruments:
				points += 2   # the right tools tell you much more
			science_found += points
			findings.append(studying["name"])
			show_message("Studied: %s. +%d science!" % [studying["name"], points], 4.0)
			studying = null
		return
	for target in targets:
		if not target["studied"] and here.distance_to(target["place"]) < 4.0 + lander_size * 0.4:
			show_message_once("near_" + target["name"], "%s. Press E to study it." % target["name"], 3.0)
			if Input.is_key_pressed(KEY_E) and not GameState.skip_minigames:
				open_sample_lab(target)
				return
			if Input.is_key_pressed(KEY_E):
				studying = target
				study_time = 0.0
				# Perseverance's SuperCam zaps rocks with a laser and reads the light from the spark
				for zap in 3:
					if audio():
						audio().play_effect("laser", -6.0 + air_loudness(), 1.0, zap * 0.35)
				show_message("Studying the %s..." % target["name"].to_lower(), STUDY_SECONDS)

# Studying a target is two minigames (res://scenes/sample_lab.tscn): grab a sample with the robotic arm, then
# identify it with the instruments on board. The rover waits while the lab is open.
var sample_lab_open = false
func open_sample_lab(target):
	if sample_lab_open:
		return
	sample_lab_open = true
	paused = true
	var layer = get_tree().current_scene.get_node_or_null("CanvasLayer")
	if layer == null:
		layer = $DriveScreen
	var lab = SAMPLE_LAB_SCENE.instantiate()
	layer.add_child(lab)
	lab.start(target["name"])
	var result = await lab.finished
	target["studied"] = true
	if target["node"].get_child_count() > 0:
		target["node"].get_child(0).visible = false
	if target["node"].has_node("Ring"):
		target["node"].get_node("Ring").visible = false
	science_found += result["science"]
	findings.append("%s (%s)" % [target["name"], result["name"].to_lower()])
	if result["correct"]:
		GameState.add_mission_stat("samples_identified")
	show_message("%s: %s%s. +%d science!" % [target["name"], result["name"], "" if result["correct"] else " (misidentified at first)", result["science"]], 5.0)
	paused = false
	sample_lab_open = false

# The laser the rover studies rocks with (Perseverance's SuperCam fires from the top of its mast and reads the
# light of the spark): a flickering green line from the mast to the rock, with sparks where it hits
func aim_study_laser(target):
	if study_laser == null:
		study_laser = MeshInstance3D.new()
		var line = CylinderMesh.new()
		line.top_radius = 0.012
		line.bottom_radius = 0.012
		line.height = 1.0
		line.radial_segments = 6
		study_laser.mesh = line
		var glow = StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.albedo_color = Color(0.4, 1.0, 0.5, 0.9)
		study_laser.material_override = glow
		study_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(study_laser)
	var from = vehicle.global_position + vehicle.global_transform.basis.y.normalized() * lander_size * 0.72
	var to = target["node"].global_position + Vector3(0, 0.3, 0)
	var along = to - from
	if along.length() < 0.01:
		return
	study_laser.visible = int(study_time * 14.0) % 3 != 0   # it fires in quick pulses
	study_laser.global_position = (from + to) * 0.5
	var up = along.normalized()
	var side = up.cross(Vector3.UP).normalized() if abs(up.y) < 0.99 else Vector3.RIGHT
	study_laser.global_basis = Basis(side, up, side.cross(up)).scaled(Vector3(1.0, along.length(), 1.0))
	if study_laser.visible and randf() < 0.3:
		spawn_dust(to, 0.25)

func update_drive_screen():
	var column = $DriveScreen/DrivePanel/Column
	column.get_node("BatteryBar").value = battery
	column.get_node("BatteryLabel").text = "Battery: %d %%" % int(battery)
	column.get_node("HeatBar").value = max(heat, cold)
	column.get_node("RadiationBar").value = radiation_dose
	column.get_node("RadiationLabel").text = "Radiation dose: %d %% of what the electronics can take" % int(radiation_dose)
	column.get_node("DamageBar").value = wheel_damage
	var studied = 0
	for target in targets:
		if target["studied"]:
			studied += 1
	column.get_node("StatusLabel").text = "Driven: %d m   Mission clock: %s\nScience targets studied: %d of %d (+%d science)" % [int(odometer), time_text(mission_minutes), studied, targets.size(), science_found]

func time_text(minutes):
	if minutes < 60.0:
		return "%d min" % int(minutes)
	return "%d h %d min" % [int(minutes / 60.0), int(fmod(minutes, 60.0))]

func show_message(text, seconds):
	$DriveScreen/DriveMessage.text = text
	message_seconds = seconds

func show_message_once(key, text, seconds):
	if messages_shown.has(key):
		return
	messages_shown[key] = true
	show_message(text, seconds)

# Looking around the rover: hold the right mouse button and drag. The view swings around the rover and stays
# where you leave it, whether you're driving or parked; the mouse wheel moves it closer or farther.
func _unhandled_input(event):
	if not driving:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			looking_around = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking_around else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			look_zoom = max(0.45, look_zoom * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			look_zoom = min(2.5, look_zoom * 1.1)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		look_yaw = 0.0     # V: back to the view from behind the rover
		look_pitch = 0.0
		look_zoom = 1.0

func _input(event):
	# Once you're looking around, every mouse movement counts, even with the hidden mouse over a panel
	if looking_around and event is InputEventMouseMotion:
		look_yaw -= event.relative.x * 0.005
		look_pitch = clamp(look_pitch + event.relative.y * 0.004, -0.35, 1.1)
	elif looking_around and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		looking_around = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func place_drive_camera(blend):
	var forward = Vector3(sin(rover_heading), 0.0, cos(rover_heading))
	var target = vehicle.global_position + Vector3(0, lander_size * 0.4, 0)
	# Behind the rover by default; look_yaw and look_pitch swing the view around it
	var back = -forward.rotated(Vector3.UP, look_yaw)
	var distance = (lander_size * 3.0 + 4.0) * look_zoom
	var height_above = (lander_size * 1.2 + 1.5) * look_zoom
	var wanted = target + (back * distance + Vector3(0, height_above, 0)).rotated(back.cross(Vector3.UP).normalized(), -look_pitch)
	wanted.y = max(wanted.y, ground_height(Vector2(wanted.x, wanted.z)) + 1.0)
	camera.global_position = camera.global_position.lerp(wanted, 1.0 if looking_around else blend)
	camera.look_at(target + forward.rotated(Vector3.UP, look_yaw) * 2.0 * (1.0 - min(abs(look_pitch), 1.0)), Vector3.UP)
	camera.h_offset = randf_range(-1.0, 1.0) * shake * 0.2 if shake > 0.0 else 0.0
	camera.v_offset = randf_range(-1.0, 1.0) * shake * 0.2 if shake > 0.0 else 0.0

# ---------------------------------------------------------------------------
# Collision and the physics rover
# ---------------------------------------------------------------------------
func is_icy_world():
	return destination in ["Europa", "Enceladus", "Triton", "Pluto", "Haumea", "Makemake", "Eris", "Titania", "Charon", "Ganymede"]

# The ground's collision shape: a height grid made from the same heights the rover drives on
func build_terrain_rows(row_count):
	if terrain_heights.is_empty():
		terrain_heights.resize(TERRAIN_POINTS * TERRAIN_POINTS)
	var half = (TERRAIN_POINTS - 1) * TERRAIN_SPACING * 0.5
	var last_row = min(terrain_rows_done + row_count, TERRAIN_POINTS)
	for row in range(terrain_rows_done, last_row):
		for column in TERRAIN_POINTS:
			# (stored divided by the spacing, because the whole shape is scaled up evenly by it)
			terrain_heights[row * TERRAIN_POINTS + column] = ground_height(Vector2(column * TERRAIN_SPACING - half, row * TERRAIN_SPACING - half)) / TERRAIN_SPACING
	terrain_rows_done = last_row
	if terrain_rows_done >= TERRAIN_POINTS:
		var shape = HeightMapShape3D.new()
		shape.map_width = TERRAIN_POINTS
		shape.map_depth = TERRAIN_POINTS
		shape.map_data = terrain_heights
		terrain_body = StaticBody3D.new()
		terrain_body.name = "GroundCollision"
		var shape_node = CollisionShape3D.new()
		shape_node.shape = shape
		shape_node.scale = Vector3.ONE * TERRAIN_SPACING
		terrain_body.add_child(shape_node)
		add_child(terrain_body)

func make_rover_body():
	if not site:
		return   # (no landing-site scene: the simple driving below is used instead)
	if terrain_rows_done < TERRAIN_POINTS:
		build_terrain_rows(TERRAIN_POINTS)
	var size_share = lander_size / 3.0
	rover_body = VehicleBody3D.new()
	rover_body.name = "RoverBody"
	rover_body.mass = ROVER_MASS
	rover_body.gravity_scale = max(CONDITIONS[destination][0], LOWEST_GRAVITY) / ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	rover_body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	rover_body.center_of_mass = Vector3(0, 0.45 * size_share, 0)   # low and central, like the real rover's
	rover_body.angular_damp = 1.2
	rover_body.can_sleep = false
	rover_body.contact_monitor = true
	rover_body.max_contacts_reported = 6
	var chassis = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(2.0, 0.6, 2.3) * size_share
	chassis.shape = box
	chassis.position = Vector3(0, 1.0 * size_share, 0)    # the body rides about 70 cm above the ground
	rover_body.add_child(chassis)
	add_child(rover_body)
	var start = vehicle.global_position
	start.y = ground_height(Vector2(start.x, start.z)) + 0.12
	rover_body.global_transform = Transform3D(Basis(Vector3.UP, rover_heading), start)
	vehicle.global_transform = rover_body.global_transform
	add_wheels(size_share)
	rover_body.body_entered.connect(_on_rover_bumped)

# Six wheels where the real model's wheels are. The model's own wheels move onto them, so they turn and steer.
func add_wheels(size_share):
	var inner_model = lander.get_child(0) if lander.get_child_count() > 0 else null
	var wheels_path = Spacecraft.find_model(WHEELS_MODEL)
	var wheel_nodes = []
	if inner_model and wheels_path != "":
		var wheel_model = load(wheels_path).instantiate()
		var wheels_holder = Node3D.new()
		lander.add_child(wheels_holder)
		wheels_holder.transform = inner_model.transform
		wheels_holder.add_child(wheel_model)
		var original_wheels = inner_model.find_child("Wheels_objs", true, false)
		if original_wheels:
			original_wheels.visible = false
		for child in wheel_model.get_children():
			if child.name.begins_with("wheel_"):
				wheel_nodes.append(child)
	var places = []
	if wheel_nodes.size() == 6:
		for node in wheel_nodes:
			places.append(rover_body.global_transform.affine_inverse() * node.global_position)
	else:
		for corner in [Vector3(1.06, 0, 1.16), Vector3(-1.06, 0, 1.16), Vector3(1.18, 0, 0.09), Vector3(-1.18, 0, 0.09), Vector3(1.06, 0, -1.09), Vector3(-1.06, 0, -1.09)]:
			places.append(corner * size_share + Vector3(0, WHEEL_RADIUS * size_share, 0))
	var rest_length = 0.25 * size_share
	for index in places.size():
		var wheel = VehicleWheel3D.new()
		wheel.name = "Wheel%d" % index
		wheel.position = places[index] + Vector3(0, rest_length, 0)
		wheel.wheel_radius = WHEEL_RADIUS * size_share
		wheel.wheel_rest_length = rest_length
		wheel.suspension_travel = 0.22 * size_share
		wheel.suspension_stiffness = 28.0
		wheel.suspension_max_force = ROVER_MASS * 30.0
		wheel.damping_compression = 1.6
		wheel.damping_relaxation = 2.2
		wheel.wheel_roll_influence = 0.03
		wheel.wheel_friction_slip = SURFACE_GRIP["ice"] if is_icy_world() else SURFACE_GRIP["soil"]
		wheel.use_as_traction = true          # every wheel has its own motor
		wheel.use_as_steering = false         # steered one by one below: the corner wheels turn opposite ways
		rover_body.add_child(wheel)
		var steer_share = 0.0
		if places[index].z > 0.5 * size_share:
			steer_share = 1.0
		elif places[index].z < -0.5 * size_share:
			steer_share = -1.0
		rover_wheels.append([wheel, steer_share])
		if index < wheel_nodes.size():
			var mesh_node = wheel_nodes[index]
			var mesh_basis = mesh_node.global_transform.basis
			mesh_node.get_parent().remove_child(mesh_node)
			wheel.add_child(mesh_node)
			mesh_node.transform = Transform3D(rover_body.global_transform.basis.inverse() * mesh_basis, Vector3.ZERO)

# Drives the physics rover. Returns its forward speed.
func drive_physics(delta, throttle, steering, in_sand, top_speed):
	var forward = rover_body.global_transform.basis.z
	var speed = rover_body.linear_velocity.dot(forward)
	var gravity = max(CONDITIONS[destination][0], LOWEST_GRAVITY)
	var force_per_wheel = ROVER_MASS * (0.9 + gravity * 0.35) / 6.0
	var wheels_touching = 0
	for entry in rover_wheels:
		var wheel: VehicleWheel3D = entry[0]
		# The corner wheels turn like a car's front wheels at the front and the opposite way at the back.
		# (The real rover creeps at 4 cm/s; at this game's speed, sharp turns would flip it, so they get gentler as it speeds up.)
		wheel.steering = steering * max(0.12, 0.45 - 0.11 * abs(speed)) * entry[1]
		if abs(speed) < top_speed or sign(throttle) != sign(speed):
			wheel.engine_force = throttle * force_per_wheel
		else:
			wheel.engine_force = 0.0
		wheel.brake = 0.0 if throttle != 0.0 else ROVER_MASS * 0.06   # the motors hold the rover still when you let go
		# Grip: what is this wheel on?
		var surface = "ice" if is_icy_world() else "soil"
		if in_sand:
			surface = "sand"
		if wheel.is_in_contact():
			wheels_touching += 1
			var touching = wheel.get_contact_body()
			if touching and touching.name == "RockColliders":
				surface = "rock"
				if abs(speed) > 1.2:
					wheel_damage = min(100.0, wheel_damage + abs(speed) * delta * 0.6)   # sharp rocks chew the wheels
		wheel.wheel_friction_slip = SURFACE_GRIP[surface]
	if in_sand:
		rover_body.apply_central_force(-rover_body.linear_velocity * ROVER_MASS * 0.8)   # sinking wheels drag
	# The mission plan keeps the rover near the landing site: at the boundary it can't go any farther out
	var flat_place = Vector2(rover_body.global_position.x, rover_body.global_position.z)
	boundary_message_wait -= delta
	if flat_place.length() > DRIVE_AREA_RADIUS - 1.0:
		var outward = Vector3(flat_place.x, 0, flat_place.y).normalized()
		var outward_speed = rover_body.linear_velocity.dot(outward)
		if outward_speed > 0.0:
			rover_body.linear_velocity -= outward * outward_speed   # (all the speed away from the landing site is taken off)
		rover_body.apply_central_force(-outward * ROVER_MASS * 2.0)
		if boundary_message_wait <= 0.0:
			boundary_message_wait = 7.0
			show_message(BOUNDARY_MESSAGE, 6.0)
			play_sound("error", -8.0)
	if boundary and boundary.get_surface_override_material(0):
		boundary.get_surface_override_material(0).set_shader_parameter("rover_position", rover_body.global_position)
	# In the air (low gravity hops), or tipped over on a steep slope
	airborne_seconds = airborne_seconds + delta if wheels_touching == 0 else 0.0
	if airborne_seconds > 0.4:
		show_message_once("hop", "Wheee! In low gravity the rover sails off bumps.", 3.0)
	var up = rover_body.global_transform.basis.y
	tipped_seconds = tipped_seconds + delta if up.y < 0.25 else 0.0
	if tipped_seconds > 2.0:
		end_driving("The rover tipped over on a steep slope. Real rover drivers check every slope first: Curiosity avoids anything steeper than 30 degrees.")
	# Fell through the ground somehow: put it back on top
	var ground_here = ground_height(flat_place)
	if rover_body.global_position.y < ground_here - 3.0:
		rover_body.global_position.y = ground_here + 0.5
		rover_body.linear_velocity = Vector3.ZERO
	last_ground_height = ground_here
	vehicle.global_transform = rover_body.global_transform
	return speed

func _on_rover_bumped(body):
	if body == null or body.name != "RockColliders" or not driving:
		return
	var speed = rover_body.linear_velocity.length()
	if speed > 0.6 and bump_cooldown <= 0.0:
		bump_cooldown = 1.0
		wheel_damage = min(100.0, wheel_damage + speed * 5.0)
		shake = 0.4
		play_sound("impact", 0.0)
		show_message("Bang! You hit a rock. Curiosity's wheels got holes punched in them by sharp Mars rocks." if destination == "Mars" else "Bang! You hit a rock and damaged a wheel.", 3.0)

# The edge of the driving area: a curtain of warning stripes you can see when you get near it, and a wall the
# rover can't drive through (so it can never reach the place where the mapped ground ends)
func add_mission_boundary():
	if boundary:
		return
	boundary = MISSION_BOUNDARY_SCENE.instantiate()
	boundary.scale = Vector3(DRIVE_AREA_RADIUS + 1.5, 400.0, DRIVE_AREA_RADIUS + 1.5)
	add_child(boundary)
	var wall = StaticBody3D.new()
	wall.name = "MissionBoundaryWall"
	var pieces = 72
	var piece_length = TAU * (DRIVE_AREA_RADIUS + 3.0) / pieces * 1.1
	for index in pieces:
		var angle = TAU * index / pieces
		var shape = BoxShape3D.new()
		shape.size = Vector3(piece_length, 400.0, 3.0)
		var piece = CollisionShape3D.new()
		piece.shape = shape
		piece.position = Vector3(cos(angle), 0.0, sin(angle)) * (DRIVE_AREA_RADIUS + 3.0)
		piece.rotation.y = -angle + PI / 2.0
		wall.add_child(piece)
	add_child(wall)

# Wheel tracks: two ribbons pressed into the ground behind the rover's wheels
func start_tracks():
	track_mesh = ImmediateMesh.new()
	var tracks = MeshInstance3D.new()
	tracks.name = "WheelTracks"
	tracks.mesh = track_mesh
	tracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if ResourceLoader.exists(WHEEL_TRACK_TEXTURE):
		material.albedo_texture = load(WHEEL_TRACK_TEXTURE)
	material.albedo_color = Color(dust_color.darkened(0.35), 0.55)
	material.roughness = 1.0
	tracks.material_override = material
	add_child(tracks)
	track_points = []

func update_tracks():
	if track_mesh == null or vehicle.position.y > last_ground_height + 0.15:
		return   # (no tracks while the rover is in the air)
	var here = Vector3(vehicle.position.x, 0.0, vehicle.position.z)
	if not track_points.is_empty() and here.distance_to(track_points[-1][2]) < 0.35:
		return
	var side = vehicle.basis.x.normalized()
	var half_width = lander_size * 0.36
	var points = []
	for wheel_side in [-1.0, 1.0]:
		var wheel = here + side * half_width * wheel_side
		points.append(Vector3(wheel.x, ground_height(Vector2(wheel.x, wheel.z)) + 0.04, wheel.z))
	points.append(here)
	track_points.append(points)
	if track_points.size() > 1500:
		track_points.pop_front()
	track_mesh.clear_surfaces()
	if track_points.size() < 2:
		return
	var wheel_width = lander_size * 0.14
	track_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for wheel_index in 2:
		var travelled = 0.0
		for index in range(1, track_points.size()):
			var start = track_points[index - 1][wheel_index]
			var finish = track_points[index][wheel_index]
			var across = (finish - start).cross(Vector3.UP).normalized() * wheel_width * 0.5
			var next_travelled = travelled + start.distance_to(finish)
			var corners = [[start - across, Vector2(0, travelled)], [start + across, Vector2(1, travelled)], [finish + across, Vector2(1, next_travelled)],
				[start - across, Vector2(0, travelled)], [finish + across, Vector2(1, next_travelled)], [finish - across, Vector2(0, next_travelled)]]
			for corner in corners:
				track_mesh.surface_set_normal(Vector3.UP)
				track_mesh.surface_set_uv(corner[1] * Vector2(1.0, 1.0 / wheel_width))
				track_mesh.surface_add_vertex(corner[0])
			travelled = next_travelled
	track_mesh.surface_end()

func _on_done_driving():
	end_driving("")

func end_driving(reason):
	if not driving:
		return
	driving = false
	failure = reason
	looking_around = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$DriveScreen.visible = false
	for entry in rover_wheels:
		entry[0].engine_force = 0.0
		entry[0].brake = ROVER_MASS * 0.2   # parked
	if audio():
		audio().stop_engine(0.8)
		if reason != "":
			audio().play_effect("error", -4.0)
	var summary = "Drove %d m in %s and studied %d science target%s (+%d science)." % [int(odometer), time_text(mission_minutes), findings.size(), "" if findings.size() == 1 else "s", science_found]
	if findings.size() > 0:
		summary += " Found: " + ", ".join(findings) + "."
	if reason != "":
		summary = reason + " " + summary
	landed = true
	camera_angle = rover_heading + PI
	driving_finished.emit(summary)
