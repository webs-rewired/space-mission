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

# How long the whole trip takes on screen, whatever the destination
const FAST_TRIP_SECONDS = 45.0
const SLOW_TRIP_SECONDS = 180.0

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
	continue_button.pressed.connect(_on_continue_pressed)
	set_up_target_planet()
	GameState.build_mission()
	total_flight_days = max(GameState.trip_years() * 365.25, 0.5)
	set_up_cruise_extras()
	build_flight_controls()
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

func _process(delta):
	if not cruising:
		return

	# A mission event pauses the simulation so the player can read it and make a decision.
	if not event_panel.visible:
		elapsed_flight_days = min(
			elapsed_flight_days + delta * time_rate_days_per_second,
			total_flight_days
		)
		var new_progress = clamp(elapsed_flight_days / max(total_flight_days, 0.001), 0.0, 1.0)
		set_flight_progress(new_progress)

		# Events happen at mission-time milestones, rather than after a fixed 1.5-second tween.
		if event_index < GameState.events.size():
			var next_milestone = progress_at_event(event_index)
			if flight_progress >= next_milestone:
				set_flight_progress(next_milestone)
				elapsed_flight_days = total_flight_days * next_milestone
				_show_event()

	update_flight_hud()
	place_chase_camera(1.0 - exp(-3.0 * delta))

	# The engine plume is shown during departure and final approach burns.
	if probe_flame:
		probe_flame.visible = (
			flight_progress < 0.08
			or (flying_to_final_event and flight_progress > 0.85 and flight_progress < 0.999)
		)
		if probe_flame.visible:
			probe_flame.scale.y = 0.5 * (1.0 + randf_range(-0.08, 0.08))
	update_trail()

func flight_direction(progress):
	var direction = flight_end - FLIGHT_START
	direction.y = cos(progress * PI) * 4.0 * PI
	return direction.normalized()

# The camera rides behind and a little to the side of the probe, looking ahead toward the destination
func place_chase_camera(blend):
	if camera == null:
		return
	var direction = flight_direction(flight_progress)
	var wanted = probe.position - direction * 2.8 + Vector3(0, 1.0, 1.6)
	camera.position = camera.position.lerp(wanted, clamp(blend, 0.0, 1.0))
	var look_point = probe.position.lerp(target_planet.position, 0.3)
	if camera.position.distance_to(look_point) > 0.01:
		camera.look_at(look_point, Vector3.UP)

# A fading line behind the probe showing the path it has flown
func update_trail():
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

	# Big planets sit farther away so they don't swallow the screen
	target_planet.position = Vector3(6 + planet_radius, 0, 0)
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

func set_flight_progress(new_progress):
	flight_progress = new_progress
	var probe_position = FLIGHT_START.lerp(flight_end, new_progress)
	probe_position.y = sin(new_progress * PI) * 4.0   # curved path
	probe.position = probe_position
	# Point the rocket's nose the way it's flying (up at first, level at the top of the curve, then down)
	probe.basis = Basis(Quaternion(Vector3.UP, flight_direction(new_progress)))

func fly_to(target_progress):
	# The probe now coasts through the interval at the selected mission-time rate.
	# target_progress is retained for compatibility with the existing event sequence.
	flying_to_final_event = target_progress >= 0.999   # heading for the arrival: the braking burn comes at the end
	if target_progress <= flight_progress:
		_show_event()

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
		go_to_results()
	else:
		fly_to(progress_at_event(event_index))

func go_to_results():
	cruising = false
	if flight_controls:
		flight_controls.visible = false
	GameState.finish_mission()
	get_tree().change_scene_to_file(RESULTS_SCENE)
