extends Node3D

# Science from orbit, for probes that stay in orbit (no lander).
# The spacecraft maps the world below as it turns underneath (a near-polar orbit passes over all of it), photographs
# famous places when they pass under its camera, and radios everything home to Earth.
# The numbers are real: the orbit's height, speed and period come from the world's gravity, the data rate from the
# antenna and the distance to Earth (GameState), and power from sunlight, with the battery taking over in the
# world's shadow.
# launch.gd adds this scene once an orbiter is in orbit, and pauses it while a decision is on screen.

signal finished(summary, science_points)

const MAP_WIDTH = 128
const MAP_HEIGHT = 64
const LAP_SECONDS = 14.0              # one trip around on screen (launch.gd's ORBIT_LAP_SECONDS)
const SWATH_DEGREES = 11.0            # how wide a strip the instruments see. Real ones see a strip 30 km wide (0.5 degrees
                                      # at Mars), which takes months to map a world, so it's much wider here.
const CAMERA_VIEW_DEGREES = 10.0      # how close to straight below a place has to be for a picture
const PHOTO_GIGABITS = 4.0            # one compressed HiRISE picture from Mars Reconnaissance Orbiter is a few gigabits
const MAP_GIGABITS_PER_CELL = 0.004   # mapping data for each new patch of ground (the whole world is about 8,000 patches)
const RECORDER_GIGABITS = 160.0       # Mars Reconnaissance Orbiter's recorder holds 160 gigabits
const PHOTO_POINTS = 6
const MAP_POINTS = 30                 # for mapping the whole world
const MAP_SHADER = preload("res://shaders/orbit_map.gdshader")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const SpacecraftLookalike = preload("res://scripts/spacecraft_lookalike.gd")

# For each world: gravity (GM, km^3/s^2), the height of a real (or planned) mapping orbit (km), which mission flew it,
# and the places worth a picture: [name, latitude, longitude east, what's special about it]
const WORLDS = {
	"Mars": {"gm": 42828.0, "altitude": 300.0, "like": "Mars Reconnaissance Orbiter flies about 300 km up", "targets": [
		["Olympus Mons", 18.65, -133.8, "The tallest volcano in the solar system: 22 km high and as wide as Arizona."],
		["Valles Marineris", -13.9, -59.2, "A canyon 4,000 km long and up to 7 km deep. It would stretch across the United States."],
		["Jezero Crater", 18.4, 77.6, "An old lake with a river delta, where Perseverance is collecting rock samples to bring to Earth."],
		["Gale Crater", -5.4, 137.8, "Curiosity has been driving here since 2012, climbing the layered Mount Sharp."],
		["Hellas Basin", -42.4, 70.5, "An impact basin 2,300 km across and 7 km deep, the lowest place on Mars."],
		["North polar cap", 85.0, 0.0, "Layers of water ice and dust 3 km thick. In winter, carbon dioxide frost covers it too."]]},
	"Moon": {"gm": 4904.9, "altitude": 50.0, "like": "Lunar Reconnaissance Orbiter mapped it from 50 km up", "targets": [
		["Tranquility Base", 0.67, 23.47, "Where Apollo 11 landed in 1969. From orbit, LRO photographed the astronauts' footpaths."],
		["Tycho", -43.3, -11.2, "A young crater (108 million years old) whose bright rays spread across the near side."],
		["Copernicus", 9.6, -20.1, "A 93 km crater with mountains in the middle, pushed up by the impact."],
		["Shackleton Crater", -89.9, 0.0, "At the south pole, its floor is always in shadow and may hold water ice. Artemis astronauts will land nearby."],
		["Aristarchus", 23.7, -47.4, "The brightest spot on the Moon, bright enough to see from Earth with the naked eye."]]},
	"Mercury": {"gm": 22032.0, "altitude": 200.0, "like": "MESSENGER dipped to about 200 km above it", "targets": [
		["Caloris Basin", 30.5, 170.2, "An impact basin 1,550 km across. The shock wave jumbled the ground on the opposite side of Mercury."],
		["Hokusai", 57.8, 16.8, "A crater whose bright rays reach more than 1,000 km."],
		["North polar ice", 85.0, 0.0, "Water ice hides in craters that never see the Sun, on the planet closest to it."]]},
	"Venus": {"gm": 324859.0, "altitude": 300.0, "like": "Magellan mapped it by radar from about 300 km up", "radar": true, "targets": [
		["Maxwell Montes", 65.2, 3.3, "Venus's highest mountains, 11 km tall. Seen only by radar, through the clouds."],
		["Maat Mons", 0.5, -165.4, "The biggest volcano on Venus. Magellan's radar saw lava flows that may be young."],
		["Aphrodite Terra", -5.8, 104.8, "A highland the size of Africa."],
		["Venera 13 site", -7.5, -57.0, "Where the Soviet Venera 13 lander took the first color photos of Venus's ground, in 1982."]]},
	"Jupiter": {"gm": 126686534.0, "altitude": 4200.0, "like": "Juno swoops to about 4,200 km above the clouds", "targets": [
		["Great Red Spot", -20.0, -50.0, "A storm wider than Earth that has been raging for at least 190 years."],
		["North polar cyclones", 85.0, 0.0, "Juno found 8 cyclones circling one big cyclone at the north pole, each wider than the United States."]]},
	"Saturn": {"gm": 37931187.0, "altitude": 3000.0, "like": "Cassini's Grand Finale orbits dived about 3,000 km above the clouds", "targets": [
		["North polar hexagon", 78.0, 0.0, "A six-sided jet stream wider than two Earths, found by Voyager and photographed by Cassini."],
		["Storm alley", -35.0, 40.0, "Where giant thunderstorms flash with lightning 10,000 times stronger than Earth's."]]},
	"Uranus": {"gm": 5793939.0, "altitude": 4000.0, "like": "A planned Uranus orbiter", "targets": [
		["Polar collar", 70.0, 0.0, "A bright band around the pole. Uranus is tipped on its side, so each pole gets 42 years of daylight."]]},
	"Neptune": {"gm": 6836529.0, "altitude": 4000.0, "like": "Voyager 2 flew 4,950 km above it in 1989", "targets": [
		["Great Dark Spot", -18.0, 24.0, "A storm the size of Earth, seen by Voyager 2. Hubble later saw it vanish."]]},
	"Ceres": {"gm": 62.6, "altitude": 385.0, "like": "Dawn mapped it from 385 km up", "targets": [
		["Occator Crater", 19.8, -120.7, "Its bright spots are salt left behind by salty water from underground."],
		["Ahuna Mons", -10.5, -43.8, "An ice volcano 4 km tall."]]},
	"Phobos": {"gm": 0.000711, "altitude": 20.0, "like": "Japan's MMX mission will orbit close to it"},
	"Deimos": {"gm": 0.0000985, "altitude": 10.0, "like": "No spacecraft has orbited it yet"},
	"Io": {"gm": 5959.9, "altitude": 200.0, "like": "Galileo and Juno flew past it, the closest about 200 km up"},
	"Europa": {"gm": 3202.7, "altitude": 100.0, "like": "Europa Clipper flies past it 49 times, as low as 25 km"},
	"Ganymede": {"gm": 9887.8, "altitude": 500.0, "like": "ESA's JUICE will orbit it 500 km up from 2034"},
	"Callisto": {"gm": 7179.3, "altitude": 200.0, "like": "Galileo flew past it 8 times"},
	"Enceladus": {"gm": 7.211, "altitude": 100.0, "like": "Cassini flew through its plumes, once only 25 km up"},
	"Titan": {"gm": 8978.1, "altitude": 1400.0, "like": "Cassini mapped it by radar from about 1,000 to 1,400 km up", "radar": true},
	"Titania": {"gm": 228.2, "altitude": 200.0, "like": "Only Voyager 2 has visited, in 1986"},
	"Triton": {"gm": 1427.6, "altitude": 500.0, "like": "Only Voyager 2 has visited, in 1989"},
	"Charon": {"gm": 106.1, "altitude": 200.0, "like": "New Horizons flew past in 2015"},
	"Pluto": {"gm": 869.6, "altitude": 500.0, "like": "New Horizons flew past 12,500 km up in 2015"},
	"Haumea": {"gm": 267.0, "altitude": 300.0, "like": "No spacecraft has visited"},
	"Makemake": {"gm": 207.0, "altitude": 300.0, "like": "No spacecraft has visited"},
	"Eris": {"gm": 1108.0, "altitude": 300.0, "like": "No spacecraft has visited"},
}
# Places on worlds without a detailed map: the kinds of things a probe would look for
const GENERIC_TARGETS = [["A fresh crater", 25.0, 40.0, "Its bright rays show where the impact threw out clean material from underground."],
	["A dark plain", -15.0, -70.0, "Darker ground is often older, or stained by radiation and dust."],
	["The north pole", 82.0, 0.0, "Poles can trap frost and ice in craters that never see the Sun."],
	["A long ridge", -40.0, 150.0, "Ridges and cracks show the crust being squeezed or pulled apart."]]

@onready var title_label: Label = $Screen/Panel/Column/Title
@onready var orbit_label: Label = $Screen/Panel/Column/OrbitLabel
@onready var coverage_label: Label = $Screen/Panel/Column/CoverageLabel
@onready var coverage_bar: ProgressBar = $Screen/Panel/Column/CoverageBar
@onready var data_label: Label = $Screen/Panel/Column/DataLabel
@onready var data_bar: ProgressBar = $Screen/Panel/Column/DataBar
@onready var power_label: Label = $Screen/Panel/Column/PowerLabel
@onready var power_bar: ProgressBar = $Screen/Panel/Column/PowerBar
@onready var targets_label: Label = $Screen/Panel/Column/TargetsLabel
@onready var message_label: Label = $Screen/Message
@onready var flash: ColorRect = $Screen/Flash

var launch: Node3D            # the journey scene: its probe, target world and camera
var world_id = ""
var world = {}
var running = false
var paused = false
var science_seconds = 0.0     # time spent doing science, so mission events come every so often
var coverage_image: Image
var coverage_texture: ImageTexture
var covered = PackedByteArray()
var coverage_share = 0.0
var map_material: ShaderMaterial = null
var beam: MeshInstance3D = null
var targets = []              # {"name", "fact", "point" (unit vector in the world's frame), "marker", "done"}
var photos = []
var stored_gigabits = 0.0
var sent_gigabits = 0.0
var lost_gigabits = 0.0
var battery_share = 1.0
var in_shadow = false
var safe_mode = false
var orbit_count = 0.0
var real_seconds_per_second = 1.0
var period_seconds = 1.0
var orbit_speed_km_s = 0.0
var message_seconds = 0.0
var messages_shown = {}
var map_refresh = 0.0
var target_near = null

func start(journey):
	launch = journey
	world_id = GameState.destination
	world = WORLDS.get(world_id, {"gm": 1000.0, "altitude": 300.0, "like": ""})
	var radius_km = SolarSystemData.BODIES.get(world_id, {}).get("radius_km", 1000.0)
	var orbit_radius_km = radius_km + world["altitude"]
	# Kepler: period = 2 pi sqrt(r^3 / GM), and speed = sqrt(GM / r) for a circular orbit
	period_seconds = TAU * sqrt(pow(orbit_radius_km, 3.0) / world["gm"])
	orbit_speed_km_s = sqrt(world["gm"] / orbit_radius_km)
	real_seconds_per_second = period_seconds / LAP_SECONDS
	title_label.text = "%s IN ORBIT" % SpacecraftLookalike.LOOKALIKES.get(SpacecraftLookalike.closest(), {"name": "YOUR PROBE"})["name"].to_upper()
	coverage_image = Image.create(MAP_WIDTH, MAP_HEIGHT, false, Image.FORMAT_L8)
	coverage_texture = ImageTexture.create_from_image(coverage_image)
	covered.resize(MAP_WIDTH * MAP_HEIGHT)
	add_map_overlay()
	add_beam()
	add_targets()
	running = true
	$Screen.visible = true
	show_message("%s: %s %s" % [world_id, world_name_text(), orbit_fact_text()], 9.0)

func world_name_text():
	return "one orbit at %s km up takes %s." % [format_number(world["altitude"]), duration_text(period_seconds)]

func orbit_fact_text():
	var text = "(%s.)" % world["like"] if world.get("like", "") != "" else ""
	if world.get("radar", false) and not "instrument_radar" in GameState.instruments:
		text += " Thick clouds hide the ground: without radar you can only map the cloud tops."
	return text

# ---------------------------------------------------------------------------
# The map overlay, the instruments' beam and the targets
# ---------------------------------------------------------------------------
func planet():
	return launch.target_planet

func sphere_radius():
	return planet().mesh.radius if planet().mesh is SphereMesh else 1.0

func add_map_overlay():
	if not planet().mesh is SphereMesh:
		return   # (Phobos and Deimos are lumpy, not spheres: no overlay)
	var overlay = MeshInstance3D.new()
	overlay.name = "MapOverlay"
	var sphere = SphereMesh.new()
	sphere.radius = sphere_radius() * 1.004
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	overlay.mesh = sphere
	map_material = ShaderMaterial.new()
	map_material.shader = MAP_SHADER
	map_material.set_shader_parameter("coverage", coverage_texture)
	overlay.material_override = map_material
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet().add_child(overlay)

func add_beam():
	beam = MeshInstance3D.new()
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 32
	cone.cap_bottom = false
	cone.cap_top = false
	beam.mesh = cone
	var glow = StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.albedo_color = Color(0.35, 0.85, 1.0, 0.12)
	beam.material_override = glow
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

# Latitude and longitude to a point on the world's sphere (the same layout as the planet maps and Godot's sphere)
func point_on_world(latitude, longitude):
	var u = (longitude + 180.0) / 360.0
	var v = (90.0 - latitude) / 180.0
	var ring = sin(PI * v)
	return Vector3(sin(u * TAU) * ring, cos(PI * v), cos(u * TAU) * ring)

func add_targets():
	var list = world.get("targets", GENERIC_TARGETS)
	for entry in list:
		var point = point_on_world(entry[1], entry[2])
		var marker = MeshInstance3D.new()
		var ring = TorusMesh.new()
		ring.inner_radius = 0.8
		ring.outer_radius = 1.0
		ring.rings = 32
		ring.ring_segments = 8
		marker.mesh = ring
		var glow = StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(1.0, 0.8, 0.25)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.75, 0.2)
		glow.emission_energy_multiplier = 1.5
		marker.material_override = glow
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		planet().add_child(marker)
		var size = sphere_radius() * 0.035
		# Lying flat on the ground, facing out
		var up = point.normalized()
		var side = up.cross(Vector3.FORWARD if abs(up.y) > 0.9 else Vector3.UP).normalized()
		marker.transform = Transform3D(Basis(side, up, side.cross(up)).scaled(Vector3(size, size * 0.4, size)), up * sphere_radius() * 1.006)
		targets.append({"name": entry[0], "fact": entry[3], "point": up, "marker": marker, "done": false})

# ---------------------------------------------------------------------------
# Every frame
# ---------------------------------------------------------------------------
func _process(delta):
	if not running:
		return
	pulse_markers()
	if paused:
		return
	science_seconds += delta
	orbit_count += delta / LAP_SECONDS
	var below = point_below()
	update_power(delta)
	update_beam(below)
	if not safe_mode:
		map_strip(below, delta)
	send_data(delta)
	look_for_targets(below)
	update_screen()
	message_seconds -= delta
	message_label.modulate.a = clamp(message_seconds / 0.8, 0.0, 1.0)
	flash.color.a = max(0.0, flash.color.a - delta * 3.0)

func _unhandled_input(event):
	if not running or paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		take_picture()

# The point straight below the spacecraft, as a direction in the world's own (turning) frame
func point_below():
	var local = planet().global_transform.affine_inverse() * launch.probe.global_position
	return local.normalized()

func latitude_longitude(direction):
	var latitude = rad_to_deg(asin(clamp(direction.y, -1.0, 1.0)))
	var longitude = rad_to_deg(atan2(direction.x, direction.z)) - 180.0
	return Vector2(latitude, wrapf(longitude, -180.0, 180.0))

# Marks the strip the instruments can see, around the point below
func map_strip(below, _delta):
	var cloudy = world.get("radar", false) and not "instrument_radar" in GameState.instruments
	var place = latitude_longitude(below)
	var half_width = SWATH_DEGREES * 0.5
	var newly_mapped = 0
	var rows = int(ceil(half_width / 180.0 * MAP_HEIGHT)) + 1
	var center_row = int((90.0 - place.x) / 180.0 * MAP_HEIGHT)
	for row in range(center_row - rows, center_row + rows + 1):
		if row < 0 or row >= MAP_HEIGHT:
			continue
		var row_latitude = 90.0 - (row + 0.5) / MAP_HEIGHT * 180.0
		var squeeze = max(cos(deg_to_rad(row_latitude)), 0.05)   # near the poles, a strip covers far more longitude
		var columns = int(ceil(half_width / squeeze / 360.0 * MAP_WIDTH)) + 1
		var center_column = int((place.y + 180.0) / 360.0 * MAP_WIDTH)
		for column_offset in range(-columns, columns + 1):
			var column = posmod(center_column + column_offset, MAP_WIDTH)
			var cell_point = point_on_world(row_latitude, (column + 0.5) / MAP_WIDTH * 360.0 - 180.0)
			if rad_to_deg(cell_point.angle_to(below)) > half_width:
				continue
			var index = row * MAP_WIDTH + column
			if covered[index] == 0:
				covered[index] = 1
				newly_mapped += 1
				coverage_image.set_pixel(column, row, Color(1, 1, 1) if not cloudy else Color(0.4, 0.4, 0.4))
	stored_gigabits += newly_mapped * MAP_GIGABITS_PER_CELL
	map_refresh -= get_process_delta_time()
	if map_refresh <= 0.0:
		map_refresh = 0.25
		coverage_texture.update(coverage_image)
		coverage_share = mapped_share()

# The share of the world's area that's been mapped (rows near the poles cover less area)
func mapped_share():
	var total = 0.0
	var mapped = 0.0
	for row in MAP_HEIGHT:
		var weight = cos(deg_to_rad(90.0 - (row + 0.5) / MAP_HEIGHT * 180.0))
		for column in MAP_WIDTH:
			total += weight
			if covered[row * MAP_WIDTH + column] == 1:
				mapped += weight
	return mapped / max(total, 0.001)

func update_beam(below):
	if beam == null:
		return
	var probe_place = launch.probe.global_position
	var ground = planet().global_transform * (below * sphere_radius())
	var length = probe_place.distance_to(ground)
	var footprint = sphere_radius() * planet().scale.x * deg_to_rad(SWATH_DEGREES * 0.5)
	beam.visible = not safe_mode and length > 0.0001
	beam.global_position = (probe_place + ground) * 0.5
	var down = (ground - probe_place).normalized()
	var side = down.cross(Vector3.UP).normalized() if abs(down.y) < 0.95 else Vector3.RIGHT
	beam.global_basis = Basis(side, -down, side.cross(-down)).scaled(Vector3(footprint, length, footprint))
	if map_material:
		map_material.set_shader_parameter("footprint_center", below)
		map_material.set_shader_parameter("footprint_size", deg_to_rad(SWATH_DEGREES * 0.5))

# Solar panels go dark in the world's shadow, and the battery takes over (an RTG doesn't care)
func update_power(delta):
	var sun_direction = Vector3(0, 0.7071, 0.7071)   # toward the Sun (the scene's sunlight comes from there)
	var light = launch.get_node_or_null("DirectionalLight3D")
	if light:
		sun_direction = light.global_transform.basis.z
	var from_center = launch.probe.global_position - planet().global_position
	var world_radius = sphere_radius() * planet().scale.x
	var behind = from_center.dot(sun_direction) < 0.0
	var off_axis = (from_center - sun_direction * from_center.dot(sun_direction)).length()
	in_shadow = behind and off_axis < world_radius
	var has_rtg = GameState.choices.get("power", "") in ["rtg", "rtg_triple"]
	var capacity = GameState.PARTS[GameState.choices.get("battery", "battery_small")].get("capacity_wh", 1000.0)
	var needed = GameState.power_needed()
	var made = GameState.power_made()
	var real_hours = delta * real_seconds_per_second / 3600.0
	var balance = (made if (has_rtg or not in_shadow) else 0.0) - needed
	battery_share = clamp(battery_share + balance * real_hours / capacity, 0.0, 1.0)
	if battery_share <= 0.0 and not safe_mode:
		safe_mode = true
		show_message("Battery empty in the shadow: the probe switched to safe mode and turned off its instruments until sunlight returns.", 6.0)
	elif safe_mode and battery_share > 0.25:
		safe_mode = false
		show_message("Back in sunlight with the battery recharged: instruments back on.", 4.0)
	if in_shadow and not has_rtg:
		show_message_once("shadow", "Passing through %s's shadow: no sunlight for the solar panels, so the battery takes over." % world_id, 5.0)

# Data goes home at the antenna's rate, which falls with the square of the distance to Earth
func send_data(delta):
	var rate_gigabits = GameState.data_rate_kilobits() / 1000000.0 * real_seconds_per_second * 0.6   # (Earth is only in view part of the time)
	var sent = min(stored_gigabits, rate_gigabits * delta)
	stored_gigabits -= sent
	sent_gigabits += sent
	if stored_gigabits > RECORDER_GIGABITS:
		lost_gigabits += stored_gigabits - RECORDER_GIGABITS
		stored_gigabits = RECORDER_GIGABITS
		show_message_once("full", "The recorder is full! New data is being lost until older data radios home. A bigger antenna sends it faster.", 6.0)

func look_for_targets(below):
	target_near = null
	for target in targets:
		if target["done"]:
			continue
		if rad_to_deg(below.angle_to(target["point"])) < CAMERA_VIEW_DEGREES:
			target_near = target
			show_message_once("near_" + target["name"] + str(int(orbit_count)), "%s is below you: press SPACE to take a picture!" % target["name"], 3.0)
			break

func take_picture():
	if not "instrument_camera" in GameState.instruments:
		show_message("Your probe has no camera, so it can't take pictures. Its other instruments keep mapping.", 4.0)
		return
	if safe_mode:
		show_message("Safe mode: the camera is off until the battery recharges.", 3.0)
		return
	flash.color = Color(1, 1, 1, 0.5)
	if launch.has_method("play_sound"):
		launch.play_sound("click", -2.0)
	if target_near == null:
		show_message("Click! Nothing special below right now. Wait for a glowing ring to pass under the probe.", 3.0)
		stored_gigabits += PHOTO_GIGABITS * 0.25
		return
	target_near["done"] = true
	target_near["marker"].material_override.albedo_color = Color(0.3, 1.0, 0.45)
	target_near["marker"].material_override.emission = Color(0.2, 1.0, 0.4)
	photos.append(target_near["name"])
	stored_gigabits += PHOTO_GIGABITS
	var points = PHOTO_POINTS + (3 if "instrument_spectrometer" in GameState.instruments else 0)
	show_message("Photographed %s! %s (+%d science)" % [target_near["name"], target_near["fact"], points], 8.0)
	target_near = null

func pulse_markers():
	var glow = 1.0 + 0.6 * sin(Time.get_ticks_msec() / 250.0)
	for target in targets:
		if not target["done"] and is_instance_valid(target["marker"]):
			target["marker"].material_override.emission_energy_multiplier = glow

# ---------------------------------------------------------------------------
# The screen
# ---------------------------------------------------------------------------
func update_screen():
	var altitude = world["altitude"]
	orbit_label.text = "Height: %s km   Speed: %s\nOne orbit: %s   Orbits done: %d\nRadio signal to Earth: %s" % [
		format_number(altitude), speed_text(orbit_speed_km_s), duration_text(period_seconds), int(orbit_count), duration_text(GameState.radio_delay_minutes() * 60.0)]
	coverage_label.text = ("Cloud tops mapped" if world.get("radar", false) and not "instrument_radar" in GameState.instruments else "Surface mapped") + ": %d %%" % int(coverage_share * 100.0)
	coverage_bar.value = coverage_share * 100.0
	data_label.text = "Recorder: %d of %d Gb   Sent home: %d Gb%s" % [int(stored_gigabits), int(RECORDER_GIGABITS), int(sent_gigabits), ("   Lost: %d Gb" % int(lost_gigabits)) if lost_gigabits > 0.5 else ""]
	data_bar.value = stored_gigabits / RECORDER_GIGABITS * 100.0
	var has_rtg = GameState.choices.get("power", "") in ["rtg", "rtg_triple"]
	power_label.text = "Battery: %d %%%s" % [int(battery_share * 100.0), "   (nuclear power)" if has_rtg else ("   IN SHADOW" if in_shadow else "   (sunlight)")]
	power_bar.value = battery_share * 100.0
	targets_label.text = "Pictures taken: %d of %d places" % [photos.size(), targets.size()]

func speed_text(km_s):
	return "%.2f km/s" % km_s if km_s >= 0.1 else "%d m/s" % int(round(km_s * 1000.0))

func duration_text(seconds):
	if seconds < 120.0:
		return "%d s" % int(seconds)
	if seconds < 7200.0:
		return "%d min" % int(seconds / 60.0)
	if seconds < 172800.0:
		return "%d h %d min" % [int(seconds / 3600.0), int(fmod(seconds, 3600.0) / 60.0)]
	return "%.1f days" % (seconds / 86400.0)

func format_number(value):
	var text = str(int(round(value)))
	var with_commas = ""
	while text.length() > 3:
		with_commas = "," + text.right(3) + with_commas
		text = text.left(text.length() - 3)
	return text + with_commas

func show_message(text, seconds):
	message_label.text = text
	message_seconds = seconds

func show_message_once(key, text, seconds):
	if messages_shown.has(key):
		return
	messages_shown[key] = true
	show_message(text, seconds)

# ---------------------------------------------------------------------------
# Ending the orbit mission
# ---------------------------------------------------------------------------
func _on_done_pressed():
	end_mission()

func end_mission():
	if not running:
		return
	running = false
	$Screen.visible = false
	if beam:
		beam.visible = false
	var points = int(round(coverage_share * MAP_POINTS)) + photos.size() * PHOTO_POINTS
	if "instrument_spectrometer" in GameState.instruments:
		points += photos.size() * 3
	if "instrument_magnetometer" in GameState.instruments:
		points += min(int(orbit_count), 10)   # measuring the magnetic field on every orbit
	# Data that never made it home doesn't count
	if sent_gigabits + stored_gigabits > 0.0:
		points = int(points * clamp((sent_gigabits + stored_gigabits * 0.5) / (sent_gigabits + stored_gigabits + lost_gigabits), 0.4, 1.0))
	var summary = "Orbited %s %d times and mapped %d %% of it%s. Sent %d Gb of data home (+%d science)." % [
		"the Moon" if world_id == "Moon" else world_id, int(orbit_count), int(coverage_share * 100.0),
		(", photographing " + ", ".join(photos)) if not photos.is_empty() else "", int(sent_gigabits + stored_gigabits), points]
	if lost_gigabits > 0.5:
		summary += " %d Gb was lost when the recorder filled up." % int(lost_gigabits)
	finished.emit(summary, points)
