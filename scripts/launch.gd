extends Node3D

# Launch: first the liftoff (launch_liftoff.gd: countdown, liftoff, stages falling away, escape burn), then the
# probe flies to its destination and the flight events pop up along the way. The camera rides along behind
# the probe, its engine glows during the big burns, and a fading trail shows the path it has flown.
#
# Mission Control (top right) shows the mission clock, using the same trip time as the probe builder
# (from real missions: Juno took 5 years to reach Jupiter, New Horizons 9.5 years to reach Pluto).
# Pause, Slow and Fast change how quickly mission time passes. Whatever the destination, the trip takes
# about 45 seconds on Fast. Trip events happen during the cruise; the rest happen once you arrive.

# Change this if your results scene lives somewhere else (right-click the file > Copy Path)
const RESULTS_SCENE = "res://scenes/results.tscn"

# Real planet images, Saturn's rings and the starry sky
const SpaceTextures = preload("res://scripts/space_textures.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const MoonSurfaces = preload("res://scripts/moon_surfaces.gd")
const BeltBuilder = preload("res://scripts/belt_builder.gd")
const LaunchLiftoff = preload("res://scripts/launch_liftoff.gd")
const RocketModel = preload("res://scripts/rocket_model.gd")
const JourneyScenery = preload("res://scripts/journey_scenery.gd")
const OrbitMath = preload("res://scripts/orbit_math.gd")
const Spacecraft = preload("res://scripts/spacecraft.gd")
const SpacecraftLookalike = preload("res://scripts/spacecraft_lookalike.gd")
const AEROSHELL_SCENE = preload("res://scenes/parts/aeroshell.tscn")
const SURFACE_SCENE = preload("res://scenes/surface_view.tscn")
const PROBE_SIZE = 0.9               # how big the spacecraft is drawn on the trip
const ORBIT_ECCENTRICITY = 0.32      # captured orbits are stretched ovals: close to the world on one side, far on the other

@onready var probe = $Probe
@onready var target_planet = $Target
@onready var event_panel = $CanvasLayer/EventPanel
@onready var event_title = $CanvasLayer/EventPanel/VBox/EventTitle
@onready var event_text = $CanvasLayer/EventPanel/VBox/EventText
@onready var choice_buttons = $CanvasLayer/EventPanel/VBox/ChoiceButtons
@onready var continue_button = $CanvasLayer/EventPanel/VBox/ContinueButton

# Real sizes compared with Earth (Earth = 1.0). The Earth sphere in this scene has radius 1.
const SIZE_COMPARED_WITH_EARTH = {
	"Moon": 0.27,
	"Mars": 0.53,
	"Venus": 0.95,
	"Jupiter": 11.2,
	"Saturn": 9.45,
}

const FLIGHT_START = Vector3(-8.8, 0, 0)   # just above Earth (the Earth sphere sits at x = -10 with radius 1)
const TRAIL_POINTS = 400
var flight_end = Vector3.ZERO
var flight_progress = 0.0
var event_index = 0
var liftoff: Node3D = null
var hidden_for_liftoff = []
var cruising = false
var camera: Camera3D = null
var probe_flame: Node3D = null
var trail: MeshInstance3D = null
var trail_mesh: ImmediateMesh = null
var trail_points = []
var flying_to_final_event = false

# The scenery along the way (planets passed, belts) and steering through the belts
var scenery: Node3D = null
var path_height = 4.0
var steer = Vector2.ZERO          # how far the player has steered off the path (sideways, up)
var rocks_hit = {}
var next_sight = 0
var belts_announced = {}
var caption_label: Label
var caption_seconds_left = 0.0
var hit_flash: ColorRect
const STEER_SPEED = 2.2
const STEER_LIMIT = 1.4
const BELT_CROSSING_SECONDS = 14.0   # belts are crossed slowly enough to steer
const ROCK_STRIKE_SCIENCE = 2
const MOST_ROCK_STRIKES = 5      # after this many, the probe has learned its lesson (no more science lost)

# How long the whole trip takes on screen, whatever the destination
const FAST_TRIP_SECONDS = 45.0
const SLOW_TRIP_SECONDS = 180.0

# Arriving: the probe swings into orbit around its target, and landers then go down to the surface
const ORBIT_LAP_SECONDS = 14.0     # one trip around the target
const ORBIT_TILT_DEGREES = 12.0
const DESCENT_SECONDS = 5.0
const SPARKS_SCENE = preload("res://scenes/effects/sparks.tscn")
const SOLAR_WIND_SCENE = preload("res://scenes/effects/solar_wind.tscn")
const RADIO_WAVES_SCENE = preload("res://scenes/effects/radio_waves.tscn")
var arrival_mode = ""             # "", "orbiting", "descending", "landing" (on the ground view) or "landed"
var surface_view: Node3D = null
var hidden_for_surface = []
var orbit_line: MeshInstance3D = null
var orbit_seconds = 0.0
var orbit_mean_anomaly = 0.0
var orbit_semi_major_axis = 1.0
var orbit_periapsis_angle = 0.0
var orbit_angle = PI
var orbit_radius = 1.0
var descent_time = 0.0
var descent_start = Vector3.ZERO
var descent_start_scale = 1.0
var landed_scale = 1.0
const PROBE_HEIGHT = 0.8          # the journey's probe model, in scene units
var landing_spot = Vector3.ZERO
var pending_event = false         # an event's animation is playing; its panel opens when the animation ends
var animation_seconds_left = 0.0
var flame_seconds_left = 0.0
var shake = 0.0
var flicker_seconds_left = 0.0

var total_flight_days = 210.0
var elapsed_flight_days = 0.0
var time_rate_days_per_second = 1.0
var flight_controls: PanelContainer
var mission_clock_label: Label
var mission_status_label: Label
var mission_progress_bar: ProgressBar
var time_mode_label: Label

func _ready():
	event_panel.visible = false
	# Event panels sit low on the screen, so the probe and its animations stay in view above them
	event_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	event_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	event_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	event_panel.custom_minimum_size.x = 520
	continue_button.pressed.connect(_on_continue_pressed)
	set_up_target_planet()
	GameState.build_mission()
	total_flight_days = max(GameState.trip_years() * 365.25, 0.5)
	set_up_cruise_extras()
	set_up_spacecraft_model()
	build_flight_controls()
	build_scenery()
	start_liftoff()

# ---------------------------------------------------------------------------
# Liftoff first
# ---------------------------------------------------------------------------
func start_liftoff():
	var environment_node = null
	for child in get_children():
		if child is WorldEnvironment:
			environment_node = child
		elif child is Node3D and child.visible:
			child.visible = false
			hidden_for_liftoff.append(child)
	liftoff = LaunchLiftoff.new()
	liftoff.name = "Liftoff"
	add_child(liftoff)
	liftoff.finished.connect(_on_liftoff_finished)
	liftoff.start(environment_node)

func _on_liftoff_finished():
	liftoff.queue_free()
	liftoff = null
	for node in hidden_for_liftoff:
		if is_instance_valid(node):
			node.visible = true
	if camera:
		camera.current = true
	cruising = true
	if flight_controls:
		flight_controls.visible = true
	set_flight_progress(0.0)
	place_chase_camera(1.0)
	set_time_mode("fast")
	fly_to(progress_at_event(0))

# ---------------------------------------------------------------------------
# The trip: engine glow, trail and the chase camera
# ---------------------------------------------------------------------------
func set_up_cruise_extras():
	camera = get_node_or_null("Camera3D")
	probe_flame = RocketModel.make_flame()
	probe_flame.position = Vector3(0, -0.46, 0)   # under the rocket's base
	probe_flame.scale = Vector3(0.07, 0.5, 0.07)
	probe_flame.visible = false
	probe.add_child(probe_flame)
	trail_mesh = ImmediateMesh.new()
	trail = MeshInstance3D.new()
	trail.name = "Trail"
	trail.mesh = trail_mesh
	var trail_material = StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.vertex_color_use_as_albedo = true
	trail.material_override = trail_material
	add_child(trail)

# The real NASA spacecraft closest to the design flies the trip. Landers headed for a world with air cross space
# folded inside their entry capsule (heat shield, backshell and cruise stage), like Perseverance did.
func set_up_spacecraft_model():
	var model = null
	var size = PROBE_SIZE
	if has_lander() and not GameState.destination in GameState.AIRLESS_WORLDS and GameState.choices.get("shield", "") in ["shield_heat", "shield_venus"]:
		var capsule = AEROSHELL_SCENE.instantiate()
		capsule.scale = Vector3.ONE * (PROBE_SIZE / 4.5)
		capsule.position.y = 0.425 * capsule.scale.y
		model = Node3D.new()
		model.add_child(capsule)
	else:
		model = SpacecraftLookalike.load_model(SpacecraftLookalike.closest(), size)
	if model == null:
		return   # model files missing: keep the old rocket
	for child in probe.get_children():
		if child is MeshInstance3D:
			child.visible = false
	model.name = "SpacecraftModel"
	probe.add_child(model)
	var box = Spacecraft.model_bounds(model, Transform3D.IDENTITY, null)
	var model_height = box.size.y if box != null else size
	model.position.y -= model_height * 0.5   # centered on the probe's point on the path
	if probe_flame:
		probe_flame.position = Vector3(0, -model_height * 0.5, 0)
		RocketModel.set_flame_vacuum(probe_flame, 1.0)   # out in space

func _process(delta):
	if not cruising:
		return

	# A mission event pauses the simulation so the player can read it and make a decision.
	var belt = scenery.belt_at(flight_progress) if scenery and arrival_mode == "" else {}
	if not event_panel.visible and not pending_event:
		if arrival_mode == "":
			var rate = time_rate_days_per_second
			if not belt.is_empty() and rate > 0.0:
				# Slow down through a belt so there's time to steer
				rate = min(rate, (belt["end"] - belt["start"]) * total_flight_days / BELT_CROSSING_SECONDS)
			elapsed_flight_days = min(
				elapsed_flight_days + delta * rate,
				total_flight_days
			)
			steer_through_belt(delta, belt)
			var new_progress = clamp(elapsed_flight_days / max(total_flight_days, 0.001), 0.0, 1.0)
			set_flight_progress(new_progress)

		if arrival_mode == "" and flight_progress >= 0.999:
			begin_orbit()

		# Events happen at mission-time milestones. Each one plays its animation first, then its panel opens.
		if event_index < GameState.events.size():
			var next_milestone = progress_at_event(event_index)
			if flight_progress >= next_milestone or arrival_mode != "":
				if arrival_mode == "":
					set_flight_progress(next_milestone)
					elapsed_flight_days = total_flight_days * next_milestone
				pending_event = true
				animation_seconds_left = start_event_animation(GameState.events[event_index])

	if pending_event:
		animation_seconds_left -= delta
		if animation_seconds_left <= 0.0:
			pending_event = false
			_show_event()

	if arrival_mode != "":
		update_arrival(delta)
	update_flight_hud()
	if arrival_mode == "":
		announce_sights()
	update_caption(delta)
	update_screen_effects(delta)
	place_chase_camera(1.0 - exp(-3.0 * delta))

	# The engine plume shows during departure, the final approach and any burn an event calls for
	if probe_flame:
		flame_seconds_left -= delta
		probe_flame.visible = (
			(arrival_mode == "" and flight_progress < 0.08)
			or (arrival_mode == "" and flying_to_final_event and flight_progress > 0.85 and flight_progress < 0.999)
			or flame_seconds_left > 0.0
		)
		if probe_flame.visible:
			probe_flame.scale.y = 0.5 * (1.0 + randf_range(-0.08, 0.08))
	update_trail()

func flight_direction(progress):
	var direction = flight_end - FLIGHT_START
	direction.y = cos(progress * PI) * path_height * PI
	return direction.normalized()

# The camera rides behind and a little to the side of the probe, looking ahead toward the destination
func place_chase_camera(blend):
	if camera == null:
		return
	if arrival_mode != "":
		place_arrival_camera(blend)
		return
	var direction = flight_direction(flight_progress)
	var wanted = probe.position - direction * 2.8 + Vector3(0, 1.0, 1.6)
	if scenery and not scenery.belt_at(flight_progress).is_empty():
		wanted = probe.position - direction * 2.4 + Vector3(0, 0.7, 0.5)   # right behind, to see the rocks coming
	camera.position = camera.position.lerp(wanted, clamp(blend, 0.0, 1.0))
	var look_point = probe.position.lerp(target_planet.position, 0.3)
	if camera.position.distance_to(look_point) > 0.01:
		camera.look_at(look_point, Vector3.UP)
	apply_shake()

func place_arrival_camera(blend):
	if arrival_mode in ["landing", "landed"]:
		return   # the landing site has its own camera
	var center = target_planet.position
	if arrival_mode == "orbiting" and orbit_seconds < 5.0:
		# First a wide view of the whole orbit, then ride along with the probe
		var apoapsis = orbit_semi_major_axis * (1.0 + ORBIT_ECCENTRICITY)
		var wide = center + Vector3(-0.35, 0.55, 0.76).normalized() * apoapsis * 2.6
		camera.position = camera.position.lerp(wide, clamp(blend, 0.0, 1.0))
		camera.look_at(center, Vector3.UP)
		apply_shake()
		return
	var outward = (probe.position - center).normalized()
	var forward = -probe.basis.y if arrival_mode != "orbiting" else probe.basis.y
	var side = outward.cross(Vector3.UP).normalized() if abs(outward.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var wanted = probe.position + outward * 1.6 - forward * 1.4 + side * 1.2 + Vector3(0, 0.5, 0)
	var look_point = probe.position.lerp(center, 0.2)
	if arrival_mode == "descending":
		var size = max(probe.scale.x * 2.0, target_radius() * 0.6)
		wanted = probe.position + outward * 1.0 * size + side * 1.8 * size
		look_point = probe.position.lerp(center, 0.15)
	elif arrival_mode == "landed":
		# Down low beside the probe, with the world's horizon curving away behind it
		var size = max(probe.scale.x * 2.5, target_radius() * 0.35)
		wanted = probe.position + outward * 0.45 * size + side * 1.5 * size
		look_point = probe.position + outward * 0.15 * size
	camera.position = camera.position.lerp(wanted, clamp(blend, 0.0, 1.0))
	if camera.position.distance_to(look_point) > 0.01:
		camera.look_at(look_point, Vector3.UP if abs(outward.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD)
	apply_shake()

func apply_shake():
	if shake > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * shake * 0.12
		camera.v_offset = randf_range(-1.0, 1.0) * shake * 0.12
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

# A fading line behind the probe showing the path it has flown
func update_trail():
	if arrival_mode in ["landing", "landed"]:
		return
	if trail_points.is_empty() or trail_points[trail_points.size() - 1].distance_to(probe.position) > 0.04:
		trail_points.append(probe.position)
		if trail_points.size() > TRAIL_POINTS:
			trail_points.pop_front()
	trail_mesh.clear_surfaces()
	if trail_points.size() < 2:
		return
	trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for index in trail_points.size():
		var age = float(index) / (trail_points.size() - 1)
		trail_mesh.surface_set_color(Color(1.0, 0.75, 0.4, 0.15 + 0.7 * age))
		trail_mesh.surface_add_vertex(trail_points[index])
	trail_mesh.surface_end()

func set_up_target_planet():
	var destination = GameState.destination
	var data = SolarSystemData.BODIES.get(destination, {})
	var is_moon_of_planet = data.has("orbit") and data["orbit"].has("satellite")
	if is_moon_of_planet:
		target_planet.material_override = MoonSurfaces.make_material(destination)
		if data.get("irregular", false):
			target_planet.mesh = BeltBuilder.make_rock_mesh(abs(destination.hash()) % 1000, 0.12, false)
	else:
		SpaceTextures.texture_planet(target_planet, destination)

	# Earth (where the probe starts) and the starry sky
	var earth = get_node_or_null("Earth")
	if earth is MeshInstance3D:
		SpaceTextures.texture_planet(earth, "Earth")
	for child in get_children():
		if child is WorldEnvironment:
			SpaceTextures.add_star_sky(child)

	# Scale the planet to its real size compared with Earth
	var planet_radius = SIZE_COMPARED_WITH_EARTH.get(destination, data.get("radius_km", 6371.0) / 6371.0)
	# Tiny worlds like Phobos, Ceres and Makemake are drawn bigger so you can see them
	planet_radius = max(planet_radius, 0.18)
	var sphere_radius = target_planet.mesh.radius if target_planet.mesh is SphereMesh else 1.0
	target_planet.scale = data.get("shape", Vector3.ONE) * (planet_radius / sphere_radius)

	# Big planets sit farther away so they don't swallow the screen, and long trips get a longer path
	# so there's room for everything you pass on the way
	var distance_from_sun = GameState.DESTINATIONS.get(destination, {}).get("distance_from_sun_au", 1.0)
	var extra_length = clamp(log(max(distance_from_sun, 1.0)) / log(2.0) * 8.0, 0.0, 40.0)
	path_height = 4.0 + extra_length * 0.15
	target_planet.position = Vector3(6 + planet_radius + extra_length, 0, 0)
	flight_end = target_planet.position - Vector3(planet_radius + 1.0, 0, 0)

	if destination == "Saturn":
		add_saturn_rings(sphere_radius)
	elif data.has("rings") and not is_moon_of_planet:
		var rings = SpaceTextures.make_rings(data["rings"], sphere_radius)
		# Undo the world's stretched shape (Haumea is egg-shaped) so its ring stays round
		rings.scale = Vector3.ONE / data.get("shape", Vector3.ONE)
		target_planet.add_child(rings)
		# Tip the world over by its real tilt (Uranus lies on its side, so you see its rings face-on like Voyager 2 did)
		target_planet.rotation_degrees.z = {"Uranus": 98.0, "Neptune": 28.0, "Jupiter": 3.0, "Haumea": 30.0}.get(destination, 10.0)
	if is_moon_of_planet:
		add_parent_planet(data["parent"], planet_radius)

# For a moon mission, its planet hangs in the sky behind it, at its real size compared with Earth
func add_parent_planet(parent_name, moon_radius):
	var parent_data = SolarSystemData.BODIES[parent_name]
	var parent_radius = parent_data["radius_km"] / 6371.0
	var parent_planet = MeshInstance3D.new()
	parent_planet.name = "ParentPlanet"
	var sphere = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	parent_planet.mesh = sphere
	SpaceTextures.texture_planet(parent_planet, parent_name)
	parent_planet.scale = Vector3.ONE * parent_radius
	add_child(parent_planet)
	parent_planet.position = target_planet.position + Vector3(parent_radius * 1.2 + moon_radius + 2.0, parent_radius * 0.3, -parent_radius * 2.2 - 5.0)
	if parent_data.has("rings"):
		var rings = SpaceTextures.make_rings(parent_data["rings"], 1.0)
		parent_planet.add_child(rings)
		rings.rotation_degrees.x = 20

func add_saturn_rings(sphere_radius):
	target_planet.add_child(SpaceTextures.make_saturn_rings(sphere_radius))
	# Saturn is tilted about 27 degrees
	target_planet.rotation_degrees.z = 27

# How far along the flight (0 to 1) the probe is when event number "index" happens.
# Trip ("cruise") events are spread along the way; everything else happens once the probe arrives.
# (The events are already sorted by phase, so the cruise events come first.)
func progress_at_event(index):
	var cruise_count = 0
	for event in GameState.events:
		if event.get("phase", "") == "cruise":
			cruise_count += 1
	if index < cruise_count:
		return 0.1 + 0.7 * float(index + 1) / float(cruise_count + 1)
	return 1.0

# A point on the drawn path, and the directions beside and above it
func path_point(progress):
	var point = FLIGHT_START.lerp(flight_end, progress)
	point.y = sin(progress * PI) * path_height   # curved path
	return point

func path_frame(progress):
	var forward = flight_direction(progress)
	var side = forward.cross(Vector3.UP).normalized()
	return {"forward": forward, "side": side, "up": side.cross(forward).normalized()}

func set_flight_progress(new_progress):
	flight_progress = new_progress
	var frame = path_frame(new_progress)
	probe.position = path_point(new_progress) + frame["side"] * steer.x + frame["up"] * steer.y
	# Point the rocket's nose the way it's flying (up at first, level at the top of the curve, then down)
	probe.basis = Basis(Quaternion(Vector3.UP, flight_direction(new_progress)))

func fly_to(target_progress):
	# The probe now coasts through the interval at the selected mission-time rate.
	# target_progress is retained for compatibility with the existing event sequence.
	flying_to_final_event = target_progress >= 0.999   # heading for the arrival: the braking burn comes at the end
	if target_progress <= flight_progress:
		_show_event()

# ---------------------------------------------------------------------------
# Scenery: planets passed, belts to steer through
# ---------------------------------------------------------------------------
func build_scenery():
	scenery = JourneyScenery.new()
	scenery.name = "JourneyScenery"
	add_child(scenery)
	var launch_date = GameState.launch_date if GameState.launch_date > 0.0 else OrbitMath.julian_date_now()
	scenery.set_up(GameState.destination, launch_date, total_flight_days, path_point, path_frame)
	var layer = get_node_or_null("CanvasLayer")
	if layer:
		hit_flash = ColorRect.new()
		hit_flash.color = Color(1.0, 0.3, 0.2, 0.0)
		hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(hit_flash)
		layer.move_child(hit_flash, 0)
		caption_label = Label.new()
		caption_label.add_theme_font_size_override("font_size", 18)
		caption_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		caption_label.add_theme_constant_override("outline_size", 7)
		caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		caption_label.custom_minimum_size = Vector2(470, 0)
		caption_label.offset_left = -235
		caption_label.offset_right = 235
		caption_label.offset_top = 16
		layer.add_child(caption_label)

func show_caption(text, seconds = 5.0):
	if caption_label == null:
		return
	caption_label.text = text
	caption_seconds_left = seconds

func update_caption(delta):
	if caption_label == null:
		return
	caption_seconds_left -= delta
	caption_label.modulate.a = clamp(caption_seconds_left / 0.8, 0.0, 1.0)
	if hit_flash:
		hit_flash.color.a = max(0.0, hit_flash.color.a - delta * 1.5)

# Tells you about each planet as you pass its orbit, and when you enter a belt
func announce_sights():
	if scenery == null:
		return
	while next_sight < scenery.sights.size() and flight_progress >= scenery.sights[next_sight]["progress"] - 0.04:
		var sight = scenery.sights[next_sight]
		var label = SolarSystemData.BODIES[sight["name"]]["label"]
		if sight["near"]:
			show_caption("Flying past %s, %s!" % [label, scenery.distance_text(sight["distance_au"])])
		else:
			show_caption("Crossing %s's orbit. %s itself is %s, so it looks small from here. Planets rarely line up, which is why launch dates matter." % [label, label, scenery.distance_text(sight["distance_au"])], 7.0)
		next_sight += 1
	var belt = scenery.belt_at(flight_progress)
	if not belt.is_empty() and not belts_announced.has(belt["name"]):
		belts_announced[belt["name"]] = true
		if belt["name"] == "Asteroid belt":
			show_caption("Entering the asteroid belt! Steer with WASD or the arrow keys to dodge the rocks.\n(Real asteroids are about a million km apart, so no probe has ever hit one. This belt is packed tight for the challenge.)", 8.0)
		else:
			show_caption("Entering the Kuiper belt: icy leftovers from when the planets formed, out past Neptune. Steer with WASD or the arrow keys!", 7.0)

# Steering inside a belt, and checking for rock strikes. Outside a belt the probe drifts back onto its path.
func steer_through_belt(delta, belt):
	if belt.is_empty():
		steer = steer.move_toward(Vector2.ZERO, delta * 1.5)
		return
	var push = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		push.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		push.x -= 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		push.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		push.y -= 1.0
	steer += push * STEER_SPEED * delta
	if steer.length() > STEER_LIMIT:
		steer = steer.normalized() * STEER_LIMIT
	for index in scenery.dodge_rocks.size():
		if rocks_hit.has(index):
			continue
		var rock = scenery.dodge_rocks[index]
		if probe.position.distance_to(rock[0]) < rock[1] * 1.3 + 0.12:
			rocks_hit[index] = true
			if rocks_hit.size() > MOST_ROCK_STRIKES:
				show_caption("Another rock strike! Luckily it only scraped the probe.", 2.0)
				if hit_flash:
					hit_flash.color.a = 0.3
				continue
			GameState.science -= ROCK_STRIKE_SCIENCE
			GameState.mission_log.append({"title": "Rock strike", "text": "A rock hit the probe in the %s. Lost %d science." % [belt["name"].to_lower(), ROCK_STRIKE_SCIENCE], "ok": false})
			show_caption("Rock strike! Lost %d science." % ROCK_STRIKE_SCIENCE, 2.0)
			if hit_flash:
				hit_flash.color.a = 0.45

# ---------------------------------------------------------------------------
# Mission clock and time controls
# ---------------------------------------------------------------------------

func build_flight_controls():
	var layer = get_node_or_null("CanvasLayer")
	if layer == null:
		push_warning("Flight controls could not be created: CanvasLayer was not found.")
		return

	flight_controls = PanelContainer.new()
	flight_controls.name = "FlightControls"
	flight_controls.visible = false
	flight_controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	flight_controls.offset_left = -330.0
	flight_controls.offset_top = 18.0
	flight_controls.offset_right = -18.0
	flight_controls.offset_bottom = 190.0
	layer.add_child(flight_controls)

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	flight_controls.add_child(column)

	var heading = Label.new()
	heading.text = "MISSION CONTROL"
	heading.add_theme_font_size_override("font_size", 18)
	column.add_child(heading)

	mission_clock_label = Label.new()
	column.add_child(mission_clock_label)

	mission_status_label = Label.new()
	mission_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(mission_status_label)

	mission_progress_bar = ProgressBar.new()
	mission_progress_bar.min_value = 0.0
	mission_progress_bar.max_value = 100.0
	mission_progress_bar.show_percentage = true
	column.add_child(mission_progress_bar)

	time_mode_label = Label.new()
	column.add_child(time_mode_label)

	var buttons = HBoxContainer.new()
	column.add_child(buttons)

	var pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_button.pressed.connect(set_time_mode.bind("pause"))
	buttons.add_child(pause_button)

	var slow_button = Button.new()
	slow_button.text = "Slow"
	slow_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slow_button.pressed.connect(set_time_mode.bind("slow"))
	buttons.add_child(slow_button)

	var fast_button = Button.new()
	fast_button.text = "Fast"
	fast_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fast_button.pressed.connect(set_time_mode.bind("fast"))
	buttons.add_child(fast_button)

	update_flight_hud()


func set_time_mode(mode: String):
	match mode:
		"pause":
			time_rate_days_per_second = 0.0
			time_mode_label.text = "TIME: PAUSED"
		"slow":
			time_rate_days_per_second = total_flight_days / SLOW_TRIP_SECONDS
			time_mode_label.text = "TIME: SLOW  |  " + rate_text(time_rate_days_per_second)
		"fast":
			time_rate_days_per_second = total_flight_days / FAST_TRIP_SECONDS
			time_mode_label.text = "TIME: FAST  |  " + rate_text(time_rate_days_per_second)
		_:
			return

# "2 days / sec", "6 hours / sec" or "45 minutes / sec"
func rate_text(days_per_second):
	if days_per_second >= 1.0:
		if days_per_second >= 10.0:
			return "%d days / sec" % int(round(days_per_second))
		return "%s days / sec" % str(snapped(days_per_second, 0.1))
	if days_per_second * 24.0 >= 1.0:
		return "%s hours / sec" % str(snapped(days_per_second * 24.0, 0.1))
	return "%d minutes / sec" % int(round(days_per_second * 1440.0))


func update_flight_hud():
	if mission_clock_label == null:
		return

	var remaining_days = max(total_flight_days - elapsed_flight_days, 0.0)
	var elapsed_whole_days = int(floor(elapsed_flight_days))
	var remaining_whole_days = int(ceil(remaining_days))
	mission_clock_label.text = "MISSION ELAPSED: Day %d" % elapsed_whole_days

	if remaining_whole_days > 365:
		var years_left = remaining_whole_days / 365.25
		mission_status_label.text = "Destination: %s\nArrival in: %.1f years" % [GameState.destination, years_left]
	elif remaining_days > 0.0:
		mission_status_label.text = "Destination: %s\nArrival in: %d days" % [GameState.destination, max(remaining_whole_days, 1)]
	else:
		mission_status_label.text = "Destination: %s\nArrived!" % GameState.destination

	if flight_progress >= 0.999:
		mission_status_label.text += "\nPhase: At %s" % GameState.destination
	elif flight_progress < 0.08:
		mission_status_label.text += "\nPhase: Departure"
	elif flight_progress < 0.78:
		mission_status_label.text += "\nPhase: Interplanetary cruise"
	elif flight_progress < 0.92:
		mission_status_label.text += "\nPhase: Approach and navigation"
	else:
		mission_status_label.text += "\nPhase: Arrival / braking"

	mission_progress_bar.value = flight_progress * 100.0
	if scenery and not scenery.belt_at(flight_progress).is_empty():
		mission_status_label.text += "\nIn the %s: steer with WASD / arrows" % scenery.belt_at(flight_progress)["name"].to_lower()


# ---------------------------------------------------------------------------
# Arriving: orbit insertion, then (for landers) the trip down to the surface
# ---------------------------------------------------------------------------
# "the Moon", but "Mars"
func world_name():
	var label = SolarSystemData.BODIES.get(GameState.destination, {}).get("label", GameState.destination)
	return "the Moon" if GameState.destination == "Moon" else label

func has_lander():
	return GameState.choices.get("landing", "landing_none") != "landing_none"

func target_radius():
	var sphere_radius = target_planet.mesh.radius if target_planet.mesh is SphereMesh else 1.0
	return sphere_radius * target_planet.scale.x

func begin_orbit():
	arrival_mode = "orbiting"
	steer = Vector2.ZERO
	flight_progress = 1.0
	elapsed_flight_days = total_flight_days
	var center = target_planet.position
	orbit_radius = max(probe.position.distance_to(center), target_radius() + 0.6)
	orbit_angle = atan2(probe.position.z - center.z, probe.position.x - center.x)
	# Arriving at the closest point of a stretched orbit, the way real orbit insertions work
	orbit_semi_major_axis = orbit_radius / (1.0 - ORBIT_ECCENTRICITY)
	orbit_periapsis_angle = orbit_angle
	orbit_mean_anomaly = 0.0
	orbit_seconds = 0.0
	if not GameState.direct_entry():
		draw_orbit_line()
	flame_seconds_left = 2.5    # the braking burn that lets the world's gravity catch the probe
	var label = world_name()
	if GameState.direct_entry():
		# Heat-shield landers dive straight into the air without stopping in orbit first, like Perseverance at Mars
		flame_seconds_left = 0.0
		begin_descent()
		show_caption("Straight in! Your lander hits %s's air behind its heat shield, like Perseverance did." % label, 5.0)
		return
	show_caption(("Braking burn complete: %s's gravity has caught your probe. You're in orbit!" % label).replace(": the", ": The"), 5.0)

func begin_descent():
	arrival_mode = "descending"
	if orbit_line:
		orbit_line.visible = false
	descent_time = 0.0
	descent_start = probe.position
	# The worlds here are drawn small, so the probe shrinks on the way down to look the right size standing on one
	descent_start_scale = probe.scale.x
	landed_scale = clamp(target_radius() * 0.3 / PROBE_HEIGHT, 0.03, 1.0)
	var center = target_planet.position
	var outward = (probe.position - center).normalized()
	var label = world_name()
	if GameState.destination in GameState.NO_SURFACE:
		# Giant planets have no ground: the probe dives into the clouds, like Galileo's probe at Jupiter in 1995
		landing_spot = center + outward * target_radius() * 0.97
		show_caption("Diving into %s's clouds, like the Galileo probe did at Jupiter in 1995" % label, 5.0)
	else:
		landing_spot = center + outward * (target_radius() + 0.46 * landed_scale)   # the probe's base on the ground
		if not GameState.direct_entry():
			show_caption("Going down to the surface of %s..." % label, 4.0)
	if not GameState.destination in GameState.AIRLESS_WORLDS:
		flash(Color(1.0, 0.55, 0.15), 0.35)   # hitting the air: the heat shield glows
		spawn_effect(SPARKS_SCENE, probe.position - outward * 0.3, Vector3.ZERO, Color(1.0, 0.6, 0.3), 0.6)

# Where the probe is on its orbit (relative to the world's center), from Kepler's equation:
# it sweeps out equal areas in equal times, so it races past the world and crawls along the far side.
func orbit_point(mean_anomaly):
	var eccentricity = ORBIT_ECCENTRICITY
	var eccentric_anomaly = mean_anomaly
	for iteration in 6:
		eccentric_anomaly -= (eccentric_anomaly - eccentricity * sin(eccentric_anomaly) - mean_anomaly) / (1.0 - eccentricity * cos(eccentric_anomaly))
	var true_anomaly = 2.0 * atan2(sqrt(1.0 + eccentricity) * sin(eccentric_anomaly * 0.5), sqrt(1.0 - eccentricity) * cos(eccentric_anomaly * 0.5))
	var distance = orbit_semi_major_axis * (1.0 - eccentricity * cos(eccentric_anomaly))
	var angle = orbit_periapsis_angle + true_anomaly
	return Basis(Vector3(1, 0, 0), deg_to_rad(ORBIT_TILT_DEGREES)) * Vector3(cos(angle), 0.0, sin(angle)) * distance

func draw_orbit_line():
	var line_mesh = ImmediateMesh.new()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for step in 181:
		line_mesh.surface_add_vertex(orbit_point(TAU * step / 180.0))
	line_mesh.surface_end()
	orbit_line = MeshInstance3D.new()
	orbit_line.name = "OrbitLine"
	orbit_line.mesh = line_mesh
	var line_material = StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(0.55, 0.85, 1.0, 0.45)
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	orbit_line.material_override = line_material
	orbit_line.position = target_planet.position
	add_child(orbit_line)

func update_arrival(delta):
	var center = target_planet.position
	var tilt = Basis(Vector3(1, 0, 0), deg_to_rad(ORBIT_TILT_DEGREES))
	match arrival_mode:
		"orbiting":
			orbit_seconds += delta
			target_planet.rotate_y(delta * 0.04)   # the world turning below
			orbit_mean_anomaly += delta * TAU / ORBIT_LAP_SECONDS
			var place = orbit_point(orbit_mean_anomaly)
			probe.position = center + place
			var forward = (orbit_point(orbit_mean_anomaly + 0.01) - place).normalized()
			probe.basis = Basis(Quaternion(Vector3.UP, forward))
		"descending":
			descent_time += delta
			var fraction = smoothstep(0.0, 1.0, descent_time / DESCENT_SECONDS)
			probe.position = descent_start.lerp(landing_spot, fraction)
			# Engine toward the ground, braking all the way down (setting the basis also sets the size, so both go together)
			var size = lerp(descent_start_scale, landed_scale, min(1.0, fraction * 1.4))
			probe.basis = Basis(Quaternion(Vector3.UP, (probe.position - center).normalized())).scaled(Vector3.ONE * size)
			flame_seconds_left = 0.1 if fraction < 0.97 else 0.0
			if fraction >= 1.0:
				if not GameState.destination in GameState.NO_SURFACE:
					open_surface_view()
				else:
					arrival_mode = "landed"
					probe.visible = false
					animation_seconds_left = min(animation_seconds_left, 1.0)

# Cut to the landing site: the real lander comes down on that world's ground under its sky
func open_surface_view():
	arrival_mode = "landing"
	surface_view = SURFACE_SCENE.instantiate()
	add_child(surface_view)
	surface_view.set_up(GameState.destination)
	# Only one sky at a time: use the landing site's
	var surface_sky = surface_view.get_node_or_null("WorldEnvironment")
	for child in get_children():
		if child is WorldEnvironment and surface_sky:
			child.environment = surface_sky.environment
		elif child is Node3D and child != surface_view and child.visible:
			child.visible = false
			hidden_for_surface.append(child)
	if surface_sky:
		surface_sky.queue_free()
	surface_view.camera.current = true
	surface_view.touched_down.connect(_on_touched_down)
	if flight_controls:
		flight_controls.visible = false

func _on_touched_down():
	arrival_mode = "landed"
	show_caption("Touchdown! You're on the surface of %s." % world_name(), 5.0)
	if surface_view.can_drive():
		# A rover: drive it around before the mission carries on (the next event waits)
		animation_seconds_left = 100000.0
		await get_tree().create_timer(2.5).timeout
		surface_view.driving_finished.connect(_on_driving_finished)
		surface_view.start_driving()
		show_caption("Your rover is down! Drive it to the glowing science targets.", 5.0)
	else:
		animation_seconds_left = min(animation_seconds_left, 2.0)

func _on_driving_finished(summary):
	var lost_rover = summary.begins_with("The ") or summary.begins_with("Too many") or summary.begins_with("Jupiter")
	GameState.science += surface_view.science_found
	GameState.mission_log.append({"title": "Rover drive", "text": summary, "ok": not lost_rover})
	show_caption(summary, 7.0)
	animation_seconds_left = 3.0

# ---------------------------------------------------------------------------
# Event animations: the general kinds of events get a short animation before their panel opens.
# Returns how many seconds to wait before showing the panel.
# ---------------------------------------------------------------------------
const EVENT_ANIMATIONS = [
	["flare", ["solar flare", "solar storm", "radiation", "cosmic ray"]],
	["hit", ["micrometeoroid", "meteor", "impact", "debris", "rock strike", "ring crossing"]],
	["radio", ["deep space network", "long-distance call", "relay", "transmission", "signal", "antenna"]],
	["glitch", ["software", "bug", "bit flip", "computer", "reaction wheel", "heater", "glitch", "safe mode", "insulation"]],
	["burn", ["course correction", "burn", "engine", "gravity assist", "close dive", "fly lower", "aerobraking"]],
	["quake", ["quake", "creaking", "sinking leg"]],
]

func event_animation_kind(event):
	var words = (event.get("title", "") + " " + event.get("text", "")).to_lower()
	for entry in EVENT_ANIMATIONS:
		for keyword in entry[1]:
			if words.contains(keyword):
				return entry[0]
	return ""

func start_event_animation(event):
	if arrival_mode == "orbiting" and event.get("phase", "") in ["descent", "surface"] and has_lander():
		begin_descent()
		return 60.0   # the panel opens once the lander touches down (see _on_touched_down)
	if event.has("insertion_check"):
		return 60.0 if arrival_mode == "descending" else 3.5   # let the braking burn (or the dive and landing) play first
	match event_animation_kind(event):
		"flare":
			var sun_direction = Vector3(0, -0.7071, -0.7071)   # the way the scene's sunlight travels
			var light = get_node_or_null("DirectionalLight3D")
			if light:
				sun_direction = -light.global_transform.basis.z
			spawn_effect(SOLAR_WIND_SCENE, probe.position - sun_direction * 3.0, -sun_direction)
			flash(Color(1.0, 0.75, 0.3), 0.35)
			return 1.8
		"hit":
			spawn_effect(SPARKS_SCENE, probe.position, Vector3.ZERO)
			flash(Color(1.0, 0.3, 0.2), 0.45)
			shake = 0.8
			return 1.4
		"radio":
			var earth = get_node_or_null("Earth")
			var toward_earth = (earth.global_position - probe.position).normalized() if earth else Vector3.LEFT
			spawn_effect(RADIO_WAVES_SCENE, probe.position, toward_earth)
			return 1.8
		"glitch":
			flicker_seconds_left = 1.2
			return 1.4
		"burn":
			flame_seconds_left = 2.0
			return 1.6
		"quake":
			shake = 1.0
			return 1.4
	return 0.3

# Adds a particle effect at a place, pointing its "up" along a direction, and removes it when it's done
func spawn_effect(scene, place, direction, tint = Color.WHITE, size = 1.0):
	var effect = scene.instantiate()
	add_child(effect)
	effect.global_position = place
	if direction != Vector3.ZERO:
		effect.global_basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	if effect is CPUParticles3D:
		effect.color = tint
		effect.scale_amount_min *= size
		effect.scale_amount_max *= size
		effect.initial_velocity_min *= size
		effect.initial_velocity_max *= size
		effect.restart()
		get_tree().create_timer(effect.lifetime * 2.0 + 0.5).timeout.connect(effect.queue_free)

func flash(color, strength):
	if hit_flash:
		hit_flash.color = Color(color.r, color.g, color.b, strength)

func update_screen_effects(delta):
	shake = max(0.0, shake - delta * 1.2)
	if flicker_seconds_left > 0.0 and hit_flash:
		flicker_seconds_left -= delta
		# The probe's computer glitching: the picture cuts in and out
		hit_flash.color = Color(0.0, 0.02, 0.05, 0.75 if randf() < 0.35 else 0.0)
		if flicker_seconds_left <= 0.0:
			hit_flash.color.a = 0.0

func remove_choice_buttons():
	for button in choice_buttons.get_children():
		button.queue_free()

func _show_event():
	if event_index < 0 or event_index >= GameState.events.size():
		go_to_results()
		return

	var event = GameState.events[event_index]
	remove_choice_buttons()
	event_panel.visible = true
	if event.has("choices"):
		event_title.text = "FLIGHT DECISION  |  " + event["title"]
		event_text.text = event["text"]
		continue_button.visible = false
		for choice_index in event["choices"].size():
			var choice = event["choices"][choice_index]
			var button = Button.new()
			button.text = choice["label"]
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if choice.has("needs") and not GameState.requirement_met(choice["needs"]):
				button.disabled = true
				button.text += "  (needs " + GameState.requirement_part_names(choice["needs"]) + ")"
			button.pressed.connect(_on_choice_pressed.bind(choice_index))
			choice_buttons.add_child(button)
	else:
		var result = GameState.apply_event(event)
		event_title.text = ("SYSTEMS NOMINAL  |  " if result["ok"] else "MISSION ALERT  |  ") + event["title"]
		event_text.text = result["text"]
		continue_button.visible = true

func _on_choice_pressed(choice_index):
	var event = GameState.events[event_index]
	var result = GameState.resolve_choice(event, choice_index)
	remove_choice_buttons()
	event_title.text = ("SYSTEMS NOMINAL  |  " if result["ok"] else "MISSION ALERT  |  ") + event["title"]
	event_text.text = result["text"]
	continue_button.visible = true

func _on_continue_pressed():
	event_panel.visible = false
	event_index += 1
	if GameState.lost or event_index >= GameState.events.size():
		if not GameState.lost and has_lander() and arrival_mode == "orbiting":
			# No landing event came up, but a lander still goes down before the mission ends
			begin_descent()
			var waited = 0.0
			while arrival_mode != "landed" and waited < 30.0:
				waited += get_process_delta_time()
				await get_tree().process_frame
			await get_tree().create_timer(3.0).timeout
			while surface_view and (surface_view.driving or animation_seconds_left > 50000.0):
				await get_tree().process_frame   # driving the rover
			await get_tree().create_timer(2.0).timeout
		go_to_results()
	else:
		fly_to(progress_at_event(event_index))

func go_to_results():
	cruising = false
	if flight_controls:
		flight_controls.visible = false
	GameState.finish_mission()
	get_tree().change_scene_to_file(RESULTS_SCENE)
