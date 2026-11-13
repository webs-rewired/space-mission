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
const BeltBuilder = preload("res://scripts/belt_builder.gd")
const SpaceTextures = preload("res://scripts/space_textures.gd")
const SpacecraftLookalike = preload("res://scripts/spacecraft_lookalike.gd")
const AEROSHELL_SCENE = preload("res://scenes/parts/aeroshell.tscn")
const PARACHUTE_SCENE = preload("res://scenes/parts/parachute.tscn")
const AIRBAGS_SCENE = preload("res://scenes/parts/airbags.tscn")
const SKY_CRANE_SCENE = preload("res://scenes/parts/sky_crane.tscn")
const DUST_SCENE = preload("res://scenes/effects/separation_burst.tscn")

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

func set_up(destination_name):
	destination = destination_name
	landing = GameState.choices.get("landing", "landing_legs")
	var world = WORLDS.get(destination, WORLDS["Moon"])
	dust_color = world["light"].lightened(0.15)
	set_up_ground(world)
	set_up_sky(world)
	start_world_sound()
	scatter_rocks(world)
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
	var lookalike_id = SpacecraftLookalike.closest()
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

func uses_heat_shield():
	return has_air() and destination != "Titan" and GameState.choices.get("shield", "") in ["shield_heat", "shield_venus"]

func plan_landing():
	if destination == "Titan":
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
			crane.position.y = 7.5 + lander_size * 0.5
			for engine in crane.get_children():
				if engine.name.begins_with("Engine"):
					var flame = RocketModel.make_flame("methane")
					flame.position = engine.position + Vector3(0, -0.2, 0)
					flame.scale = Vector3(0.14, 2.5, 0.14)
					flame.visible = false
					crane.add_child(flame)
					crane_flames.append(flame)
			crane.visible = false
			phases.append(["sky_crane", 6.5, 95.0, 0.0])
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

# ---------------------------------------------------------------------------
# Every frame
# ---------------------------------------------------------------------------
func _process(delta):
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
	height = lerp(phase[2], phase[3], eased(fraction))
	match phase_name:
		"parachute":
			# The canopy snaps open, and the capsule sways under it
			var open = smoothstep(0.0, 0.18, phase_time)
			if not parachute_sound_played:
				parachute_sound_played = true
				play_sound("thump", -4.0, 1.3)   # the parachute bangs open
			parachute.scale = Vector3.ONE * max(0.05, parachute_full_size / capsule.scale.x * open)
			parachute.position.y = (2.6 * parachute.scale.y + 3.1)
			capsule.rotation.z = sin(phase_time * 1.7) * 0.06
			if destination != "Titan" and phase_time > phase[1] * 0.55 and capsule.has_node("HeatShield"):
				drop_heat_shield()
		"release":
			lander.visible = true
			if crane:
				crane.visible = true
			if airbags:
				airbags.visible = true
				lander.visible = false
		"powered":
			set_flames(lander_flames, true)
			start_engine_sound()
			kick_up_dust(fraction)
		"sky_crane":
			set_flames(crane_flames, true)
			start_engine_sound()
			lander.position.y = 0.0
			if fraction > 0.92 and crane.get_parent() == vehicle:
				fly_crane_away()
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
	vehicle.position.y = height

func finish_phase(phase_name):
	if phase_name == "parachute" and destination != "Titan" and capsule:
		# The lander drops out of the backshell; the backshell and parachute drift off
		var place = capsule.global_transform
		vehicle.remove_child(capsule)
		add_child(capsule)
		capsule.global_transform = place
		drifting.append({"node": capsule, "velocity": Vector3(4.0, -3.0, 2.0), "spin": Vector3(0, 0, 0.05)})

func drop_heat_shield():
	var heat_shield = capsule.get_node("HeatShield")
	var place = heat_shield.global_transform
	capsule.remove_child(heat_shield)
	add_child(heat_shield)
	heat_shield.global_transform = place
	drifting.append({"node": heat_shield, "velocity": Vector3(0.5, -22.0, -0.3), "spin": Vector3(0.6, 0, 0.4)})
	play_sound("impact", -10.0, 0.8)

func fly_crane_away():
	# Cables cut: the sky crane flies off to crash a safe distance away, like Perseverance's did
	var place = crane.global_transform
	vehicle.remove_child(crane)
	add_child(crane)
	crane.global_transform = place
	drifting.append({"node": crane, "velocity": Vector3(14.0, 9.0, -6.0), "spin": Vector3(0, 0, -0.2)})
	for child in crane.get_children():
		if child.name.begins_with("Cable"):
			child.visible = false

func update_drifting(delta):
	for piece in drifting.duplicate():
		var node = piece["node"]
		if not is_instance_valid(node):
			drifting.erase(piece)
			continue
		node.global_position += piece["velocity"] * delta
		node.rotation += piece["spin"] * delta
		if node.global_position.y < -2.0 or node.global_position.length() > 600.0:
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
		spawn_dust(Vector3(vehicle.position.x, 0.3, vehicle.position.z), 2.5 + (25.0 - height) * 0.25)

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
	vehicle.position.y = 0.0
	if parachute and is_instance_valid(parachute):
		parachute.visible = false   # the canopy collapses onto the ground
	set_flames(lander_flames, false)
	set_flames(crane_flames, false)
	shake = 0.6
	spawn_dust(Vector3(0, 0.3, 0), 6.0 + lander_size)
	stop_engine_sound()
	play_sound("thump", 2.0, 0.8)
	if destination == "Moon" and audio():
		audio().play_voice("eagle_has_landed", 0.0, 1.5)   # Apollo 11: "Houston, Tranquility Base here. The Eagle has landed."
	touched_down.emit()

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
func can_drive():
	return landing in ["landing_skycrane", "landing_airbags"] and CONDITIONS.has(destination)

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
	var material = ground.get_active_material(0)
	var noise_texture = material.get_shader_parameter("height_noise") if material is ShaderMaterial else null
	if noise_texture:
		height_image = noise_texture.get_image()
	var conditions = CONDITIONS[destination]
	var temperature = conditions[1]
	$DriveScreen/DrivePanel/Column/DriveTitle.text = "%s ON %s" % [SpacecraftLookalike.LOOKALIKES.get(SpacecraftLookalike.closest(), {"name": "ROVER"})["name"].to_upper(), destination.to_upper()]
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
		var beam = MeshInstance3D.new()
		var beam_mesh = CylinderMesh.new()
		beam_mesh.top_radius = 0.15
		beam_mesh.bottom_radius = 0.35
		beam_mesh.height = 12.0
		beam.mesh = beam_mesh
		var glow = StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.albedo_color = Color(0.3, 0.9, 1.0, 0.35)
		beam.material_override = glow
		beam.position.y = 6.0
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(beam)
		var rock = MeshInstance3D.new()
		rock.mesh = BeltBuilder.make_rock_mesh(index * 13 + 5, 0.45, false)
		rock.scale = Vector3(0.9, 0.6, 0.8)
		var rock_material = StandardMaterial3D.new()
		var world = WORLDS.get(destination, WORLDS["Moon"])
		rock_material.albedo_color = world["light"].lerp(Color(0.85, 0.85, 0.9), 0.25)
		rock.material_override = rock_material
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
	return (noise_at(place * 0.0035) - 0.5) * hill_height * keep_flat + (noise_at(place * 0.03) - 0.5) * 0.5

func update_driving(delta):
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
	var grip = clamp(real_gravity / 3.7, 0.3, 1.0)   # less weight pressing the wheels down means less grip
	var on_ground = vehicle.position.y <= last_ground_height + 0.05
	var top_speed = DRIVE_SPEED * (0.2 if in_sand else 1.0) * (1.0 - wheel_damage / 150.0)
	if on_ground:
		rover_speed = move_toward(rover_speed, throttle * top_speed, delta * 2.2 * grip)
		rover_heading += steering * delta * 1.1 * (1.0 if rover_speed >= 0.0 else -1.0) * clamp(abs(rover_speed) + 0.3, 0.0, 1.0)
	var forward = Vector3(sin(rover_heading), 0.0, cos(rover_heading))
	var next = vehicle.position + forward * rover_speed * delta
	var next_place = Vector2(next.x, next.z)
	bump_cooldown -= delta
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
	if next_place.length() > 220.0:
		next = vehicle.position
		rover_speed = 0.0
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
	update_drive_screen()
	place_drive_camera(min(1.0, delta * 3.0))
	message_seconds -= delta
	$DriveScreen/DriveMessage.modulate.a = clamp(message_seconds / 0.8, 0.0, 1.0)

func update_science(delta):
	var here = Vector2(vehicle.position.x, vehicle.position.z)
	if studying != null:
		study_time += delta
		rover_speed = 0.0
		if study_time >= STUDY_SECONDS:
			studying["studied"] = true
			studying["node"].get_child(0).visible = false   # the beam goes out
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
			if Input.is_key_pressed(KEY_E):
				studying = target
				study_time = 0.0
				# Perseverance's SuperCam zaps rocks with a laser and reads the light from the spark
				for zap in 3:
					if audio():
						audio().play_effect("laser", -6.0 + air_loudness(), 1.0, zap * 0.35)
				show_message("Studying the %s..." % target["name"].to_lower(), STUDY_SECONDS)

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

func place_drive_camera(blend):
	var forward = Vector3(sin(rover_heading), 0.0, cos(rover_heading))
	var target = vehicle.global_position + Vector3(0, lander_size * 0.4, 0)
	var wanted = target - forward * (lander_size * 3.0 + 4.0) + Vector3(0, lander_size * 1.2 + 1.5, 0)
	wanted.y = max(wanted.y, ground_height(Vector2(wanted.x, wanted.z)) + 1.0)
	camera.global_position = camera.global_position.lerp(wanted, blend)
	camera.look_at(target + forward * 2.0, Vector3.UP)
	camera.h_offset = randf_range(-1.0, 1.0) * shake * 0.2 if shake > 0.0 else 0.0
	camera.v_offset = randf_range(-1.0, 1.0) * shake * 0.2 if shake > 0.0 else 0.0

func _on_done_driving():
	end_driving("")

func end_driving(reason):
	if not driving:
		return
	driving = false
	failure = reason
	$DriveScreen.visible = false
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
