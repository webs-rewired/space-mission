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
const ATMOSPHERE_SHADER = preload("res://shaders/atmosphere_glow.gdshader")
const PROBE_MARKER = preload("res://assets/ui/probe_marker.png")
const ROCK_STRIKE_SCIENCE = 2
const MOST_ROCK_STRIKES = 5      # after this many, the probe has learned its lesson (no more science lost)
const PROBE_HIT_RADIUS = 0.2     # how close a rock's edge has to come to the middle of the spacecraft to count as a hit
const ROCK_HIT_SHARE = 0.55      # a rock's solid part, compared with its drawn size
var control_banner: Label        # "MANUAL CONTROL" across the top while you're steering through a belt
var belt_now = ""
# While a mission event is waiting for you, the probe doesn't just freeze: it wobbles off its heading with an
# amber caution light pulsing, and the screen gets a pulsing caution frame, like a master caution alarm.
var alert_strength = 0.0
var alert_steady_basis = Basis.IDENTITY
var alert_light: OmniLight3D = null
var alert_frame: Panel = null
var abort_button: Button = null
var abort_dialog: ConfirmationDialog = null

# How long the whole trip takes on screen, whatever the destination
const FAST_TRIP_SECONDS = 45.0
const SLOW_TRIP_SECONDS = 180.0

# Arriving: the probe swings into orbit around its target, and landers then go down to the surface
const ORBIT_LAP_SECONDS = 14.0     # one trip around the target
const ORBIT_TILT_DEGREES = 12.0
const MAPPING_ORBIT_TILT_DEGREES = 86.0   # orbiters fly over the poles, so the world turns under them and every part gets mapped
const ORBIT_SCIENCE_SCENE = preload("res://scenes/orbit_science.tscn")
const FIRST_ORBIT_EVENT_SECONDS = 12.0
const ORBIT_EVENT_SPACING_SECONDS = 25.0
var orbit_tilt_degrees = ORBIT_TILT_DEGREES
var orbit_science: Node3D = null    # science from orbit, for probes with no lander
var next_orbit_event_seconds = FIRST_ORBIT_EVENT_SECONDS
var orbit_wide_view = false
var arrival_camera_offset = Vector3.ZERO   # where the camera sits compared with the spacecraft, kept from frame to frame
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
# Scale: one scene unit is Earth's radius (6,371 km), and planets are their true sizes compared with each other.
# A real spacecraft (about 10 m) would be far smaller than a pixel next to a planet, so the spacecraft is drawn
# bigger than real, and how much bigger depends on where it is: out in empty space it's drawn big enough to see,
# and near a planet or moon it shrinks to about 1 % of that world's size, so the world looms huge behind it.
# The camera keeps the same distance from the spacecraft compared with its size, so it always stays in view.
const NEAR_PLANET_SIZE = 0.012    # the spacecraft's drawn size near a world, compared with that world's radius
const FULL_SIZE_DISTANCE = 4.0    # from this far from a world's surface (scene units), it's drawn at full size
var display_scale = 1.0           # how big the spacecraft is drawn right now (1 = PROBE_SIZE)
var probe_marker: MeshInstance3D = null   # a small glowing dot that marks the spacecraft when it's too small to see
var landing_spot = Vector3.ZERO
var pending_event = false         # an event's animation is playing; its panel opens when the animation ends
var animation_seconds_left = 0.0
# The landing site and the rover. Landing events happen during the landing, and surface events while you drive.
const FIRST_SURFACE_EVENT_DRIVE_SECONDS = 15.0
const SURFACE_EVENT_SPACING_DRIVE_SECONDS = 25.0
var rover_state = ""              # "" (no rover yet), "waiting" (just landed), "driving" or "done"
var seconds_since_touchdown = 0.0
var seconds_since_last_event = 0.0
var next_surface_event_drive_seconds = FIRST_SURFACE_EVENT_DRIVE_SECONDS
var finishing = false
var approach_start = Vector3.ZERO
var approach_seconds = 0.0
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
	build_abort_button()
	build_scenery()
	start_liftoff()
	warm_up_effects()

# The first time Godot draws a new kind of effect it has to build its shaders, which can freeze the game for a
# moment (sparks from a rock strike, the solar wind, radio waves). Drawing each one once right in front of the
# camera now, while the loading screen still covers the picture, gets that done before you can see it.
func warm_up_effects():
	await get_tree().process_frame
	var view_camera = get_viewport().get_camera_3d()
	if view_camera == null:
		return
	var warmed = []
	for scene in [SPARKS_SCENE, SOLAR_WIND_SCENE, RADIO_WAVES_SCENE]:
		var effect = scene.instantiate()
		add_child(effect)
		effect.global_position = view_camera.global_position - view_camera.global_basis.z * 3.0
		if effect is GPUParticles3D or effect is CPUParticles3D:
			effect.emitting = true
		warmed.append(effect)
	for frame in 4:
		await get_tree().process_frame
	for effect in warmed:
		if is_instance_valid(effect):
			effect.queue_free()

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
	if audio():
		audio().play_music("music_cruise", 4.0)   # space itself is silent, so the trip gets music
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
	probe_marker = MeshInstance3D.new()
	var dot = QuadMesh.new()
	dot.size = Vector2(0.05, 0.05)
	probe_marker.mesh = dot
	var dot_material = StandardMaterial3D.new()
	dot_material.albedo_texture = PROBE_MARKER   # a ring with a tiny spacecraft in it
	dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot_material.fixed_size = true          # the same size on screen however far away
	dot_material.no_depth_test = true
	dot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot_material.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
	probe_marker.material_override = dot_material
	probe_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	probe_marker.visible = false
	probe.add_child(probe_marker)
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

		# Each event waits for its moment (see next_event_ready). It plays its animation first, then its panel opens.
		if event_index < GameState.events.size() and next_event_ready(GameState.events[event_index]):
			if arrival_mode == "":
				var next_milestone = progress_at_event(event_index)
				set_flight_progress(next_milestone)
				elapsed_flight_days = total_flight_days * next_milestone
			pending_event = true
			alert_steady_basis = probe.basis.orthonormalized()
			animation_seconds_left = start_event_animation(GameState.events[event_index])

		# On the ground: the rover sets off once the touchdown checks are done
		if surface_view and surface_view.landed and not pending_event:
			seconds_since_touchdown += delta
			seconds_since_last_event += delta
			if rover_state == "waiting" and seconds_since_touchdown >= 2.5 and surface_view.rover_ready and not next_event_has_phase("descent"):
				start_rover()

	if pending_event:
		animation_seconds_left -= delta
		if animation_seconds_left <= 0.0:
			pending_event = false
			_show_event()

	if arrival_mode != "":
		update_arrival(delta)
	update_display_scale()
	orient_probe(probe.basis)
	update_alert(delta)
	if probe_marker and camera:
		probe_marker.visible = probe.visible and camera.global_position.distance_to(probe.global_position) > display_scale * 12.0
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

# The "something needs your attention" animation (see alert_strength above)
func update_alert(delta):
	var waiting_for_player = (pending_event or event_panel.visible) and surface_view == null
	alert_strength = move_toward(alert_strength, 1.0 if waiting_for_player else 0.0, delta * (1.5 if waiting_for_player else 3.0))
	var seconds = Time.get_ticks_msec() / 1000.0
	var pulse = 0.5 + 0.5 * sin(seconds * 7.0)
	if alert_frame:
		alert_frame.visible = alert_strength > 0.01
		alert_frame.modulate.a = alert_strength * (0.35 + 0.65 * pulse)
	if alert_light == null:
		alert_light = OmniLight3D.new()
		alert_light.light_color = Color(1.0, 0.6, 0.15)
		alert_light.shadow_enabled = false
		add_child(alert_light)
	alert_light.visible = alert_strength > 0.01 and probe.visible
	if alert_strength <= 0.0:
		return
	alert_light.position = probe.position + (camera.global_position - probe.position).normalized() * display_scale * 0.9
	alert_light.omni_range = display_scale * 4.0
	alert_light.light_energy = alert_strength * pulse * 2.5
	# The probe drifts off its heading: a slow roll and a nodding wobble
	var steady = alert_steady_basis if arrival_mode == "" and waiting_for_player else probe.basis.orthonormalized()
	var wobble = Basis(Vector3.UP, sin(seconds * 0.8) * 0.6 * alert_strength) * Basis(Vector3.RIGHT, sin(seconds * 1.4) * 0.22 * alert_strength) * Basis(Vector3.FORWARD, cos(seconds * 1.1) * 0.15 * alert_strength)
	orient_probe(steady * wobble)

# What a decision's result looks and sounds like: a calm green pulse, or a red jolt with sparks
func show_result_feedback(went_well):
	if went_well:
		flash(Color(0.3, 1.0, 0.6), 0.22)
		play_sound("confirm", -6.0)
		return
	flash(Color(1.0, 0.2, 0.15), 0.5)
	play_sound("error", -2.0)
	shake = max(shake, 0.7)
	if surface_view:
		surface_view.shake = max(surface_view.shake, 0.6)
	elif probe.visible:
		spawn_effect(SPARKS_SCENE, probe.position, Vector3.ZERO, Color(1.0, 0.7, 0.4), display_scale)

# ---------------------------------------------------------------------------
# Abort mission: a button in the corner of the screen from liftoff onward. It asks first, then goes back to the
# solar system.
# ---------------------------------------------------------------------------
func build_abort_button():
	var layer = get_node_or_null("CanvasLayer")
	if layer == null:
		return
	alert_frame = Panel.new()
	var frame_style = StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 0)
	frame_style.border_color = Color(1.0, 0.62, 0.15, 0.9)
	frame_style.set_border_width_all(7)
	alert_frame.add_theme_stylebox_override("panel", frame_style)
	alert_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	alert_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_frame.visible = false
	layer.add_child(alert_frame)

	var top_layer = CanvasLayer.new()
	top_layer.name = "AbortLayer"
	top_layer.layer = 20   # above the launch, landing and orbit screens
	add_child(top_layer)
	abort_button = Button.new()
	abort_button.text = "Abort mission"
	abort_button.focus_mode = Control.FOCUS_NONE
	abort_button.tooltip_text = "End this mission and go back to the solar system"
	abort_button.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	abort_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 14)
	abort_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	abort_button.pressed.connect(_on_abort_pressed)
	top_layer.add_child(abort_button)
	abort_dialog = ConfirmationDialog.new()
	abort_dialog.title = "Abort mission?"
	abort_dialog.dialog_text = "End this mission and go back to the solar system?\nThe spacecraft and its science will be lost."
	abort_dialog.ok_button_text = "Abort mission"
	abort_dialog.cancel_button_text = "Keep flying"
	abort_dialog.confirmed.connect(abort_mission)
	abort_dialog.canceled.connect(_on_abort_cancelled)
	top_layer.add_child(abort_dialog)

func _on_abort_pressed():
	get_tree().paused = true   # everything waits while you decide
	abort_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	abort_dialog.popup_centered()

func _on_abort_cancelled():
	get_tree().paused = false

func abort_mission():
	get_tree().paused = false
	cruising = false
	if audio():
		audio().cancel_delayed_sounds()
		audio().stop_engine(0.3)
		audio().stop_voice()
		audio().stop_ambience(0.3)
		audio().set_air(1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.go_to_scene("res://scenes/solar_system.tscn")

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
	var size = display_scale
	var wanted = probe.position + (-direction * 2.8 + Vector3(0, 1.0, 1.6)) * size
	if scenery and not scenery.belt_at(flight_progress).is_empty():
		wanted = probe.position + (-direction * 2.4 + Vector3(0, 0.7, 0.5)) * size   # right behind, to see the rocks coming
	camera.position = camera.position.lerp(wanted, clamp(blend, 0.0, 1.0))
	var look_point = probe.position + (target_planet.position - probe.position).normalized() * min(probe.position.distance_to(target_planet.position) * 0.3, 3.0 * size + probe.position.distance_to(target_planet.position) * 0.3 * size)
	if camera.position.distance_to(look_point) > 0.000001:
		camera.look_at(look_point, Vector3.UP)
	apply_shake()

func place_arrival_camera(blend):
	if arrival_mode in ["landing", "landed"]:
		return   # the landing site has its own camera
	var center = target_planet.position
	if arrival_mode == "orbiting" and (orbit_seconds < 5.0 or orbit_wide_view):
		# First a wide view of the whole orbit, then ride along with the probe
		var apoapsis = orbit_semi_major_axis * (1.0 + ORBIT_ECCENTRICITY)
		var wide = center + Vector3(-0.35, 0.55, 0.76).normalized() * apoapsis * 2.6
		camera.position = camera.position.lerp(wide, clamp(blend, 0.0, 1.0))
		camera.look_at(center, Vector3.UP)
		arrival_camera_offset = camera.position - probe.position
		apply_shake()
		return
	var outward = (probe.position - center).normalized()
	var forward = (-probe.basis.y if arrival_mode != "orbiting" else probe.basis.y).normalized()
	var side = outward.cross(Vector3.UP).normalized() if abs(outward.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var size = display_scale
	var wanted = probe.position + (outward * 1.1 - forward * 2.2 + side * 1.0) * size
	var look_point = probe.position + (center - probe.position).normalized() * size * 2.0
	if arrival_mode == "descending":
		# Following the lander down, with the ground coming up to meet it
		wanted = probe.position + (outward * 1.4 + side * 2.6) * size * 2.0
		look_point = probe.position + (center - probe.position).normalized() * size * 3.0
	# Glide toward the wanted spot measured from the spacecraft (it moves fast in orbit, and the camera has to keep up)
	arrival_camera_offset = arrival_camera_offset.lerp(wanted - probe.position, clamp(blend, 0.0, 1.0))
	camera.position = probe.position + arrival_camera_offset
	# Gliding in from the wide view could take the camera right through the world: jump instead
	if camera.position.distance_to(center) < target_radius() * 1.03:
		camera.position = wanted
		arrival_camera_offset = wanted - probe.position
	if camera.position.distance_to(look_point) > 0.000001:
		camera.look_at(look_point, Vector3.UP if abs(outward.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD)
	apply_shake()

func apply_shake():
	if shake > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * shake * 0.12 * display_scale
		camera.v_offset = randf_range(-1.0, 1.0) * shake * 0.12 * display_scale
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
	flight_end = target_planet.position - Vector3(planet_radius * 1.12, 0, 0)   # arriving at a low orbit's height

	add_target_atmosphere(data, sphere_radius)
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

# Worlds with air get a glowing edge (the same colors as in the solar system view). Titan also gets the thin blue
# haze layer that floats above its orange smog.
func add_target_atmosphere(data, sphere_radius):
	if not data.has("atmosphere"):
		return
	var shell_mesh = SphereMesh.new()
	shell_mesh.radius = sphere_radius * 1.03
	shell_mesh.height = sphere_radius * 2.06
	var shell = MeshInstance3D.new()
	shell.name = "Atmosphere"
	shell.mesh = shell_mesh
	var glow = ShaderMaterial.new()
	glow.shader = ATMOSPHERE_SHADER
	glow.set_shader_parameter("glow_color", data["atmosphere"][0])
	glow.set_shader_parameter("strength", data["atmosphere"][1])
	glow.set_shader_parameter("outer_amount", 0.5 if GameState.destination == "Titan" else 0.0)
	var sun = get_node_or_null("DirectionalLight3D")
	if sun:
		glow.set_shader_parameter("sun_direction", sun.global_transform.basis.z)
	shell.material_override = glow
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target_planet.add_child(shell)

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

# How big to draw the spacecraft right now: smaller the closer it is to a world (see NEAR_PLANET_SIZE)
func update_display_scale():
	var wanted = 1.0
	var worlds = [target_planet]
	var earth = get_node_or_null("Earth")
	if earth and earth.visible:
		worlds.append(earth)
	for world in worlds:
		if not world is Node3D:
			continue
		var radius = world.scale.x * (world.mesh.radius if world is MeshInstance3D and world.mesh is SphereMesh else 1.0)
		var above_surface = max(probe.position.distance_to(world.position) - radius, 0.0)
		var near_size = radius * NEAR_PLANET_SIZE / PROBE_SIZE
		wanted = min(wanted, lerp(near_size, 1.0, clamp(above_surface / FULL_SIZE_DISTANCE, 0.0, 1.0)))
	if arrival_mode in ["orbiting", "descending", "approaching"]:
		wanted = min(wanted, target_radius() * NEAR_PLANET_SIZE / PROBE_SIZE)
	display_scale = clamp(wanted, 0.002, 1.0)
	if camera:
		camera.near = clamp(display_scale * 0.05, 0.0002, 0.05)

# Turns the spacecraft (setting its basis would also reset its size, so the size goes back on each time)
func orient_probe(new_basis):
	probe.basis = new_basis.orthonormalized().scaled(Vector3.ONE * display_scale)

func set_flight_progress(new_progress):
	flight_progress = new_progress
	var frame = path_frame(new_progress)
	probe.position = path_point(new_progress) + frame["side"] * steer.x + frame["up"] * steer.y
	# Point the rocket's nose the way it's flying (up at first, level at the top of the curve, then down)
	orient_probe(Basis(Quaternion(Vector3.UP, flight_direction(new_progress))))

func fly_to(target_progress):
	# The probe now coasts through the interval at the selected mission-time rate.
	# target_progress is retained for compatibility with the existing event sequence.
	flying_to_final_event = target_progress >= 0.999   # heading for the arrival: the braking burn comes at the end

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
		control_banner = Label.new()
		control_banner.theme_type_variation = "TitleLabel"
		control_banner.text = "MANUAL CONTROL\nSteer with WASD or the arrow keys to dodge the rocks"
		control_banner.add_theme_font_size_override("font_size", 22)
		control_banner.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
		control_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		control_banner.add_theme_constant_override("outline_size", 8)
		control_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		control_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		control_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
		control_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
		control_banner.offset_bottom = -36
		control_banner.visible = false
		layer.add_child(control_banner)

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
			show_caption("Entering the asteroid belt. You have control!\n(Real asteroids are about a million km apart, so no probe has ever hit one. A few are near your path here for the challenge.)", 8.0)
		else:
			show_caption("Entering the Kuiper belt: icy leftovers from when the planets formed, out past Neptune. You have control!", 7.0)

# Steering inside a belt, and checking for rock strikes. Outside a belt the probe drifts back onto its path.
func steer_through_belt(delta, belt):
	var belt_name = belt.get("name", "")
	if belt_name != belt_now:
		# Going in or out of a belt: tell the player clearly who is flying
		if belt_name != "":
			play_sound("alarm", -8.0)
		elif belt_now != "":
			show_caption("%s cleared. The autopilot has the controls again." % belt_now, 4.0)
			play_sound("confirm", -8.0)
		belt_now = belt_name
	scenery.probe_progress = flight_progress
	if control_banner:
		control_banner.visible = belt_name != "" and not event_panel.visible
		control_banner.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
	if belt.is_empty():
		steer = steer.move_toward(Vector2.ZERO, delta * 1.5)
		return
	steer += steering_keys_push() * STEER_SPEED * delta
	if steer.length() > STEER_LIMIT:
		steer = steer.normalized() * STEER_LIMIT
	for index in scenery.dodge_rocks.size():
		if rocks_hit.has(index):
			continue
		var rock = scenery.dodge_rocks[index]
		if probe.position.distance_to(rock[0]) < rock[1] * ROCK_HIT_SHARE + PROBE_HIT_RADIUS:
			rocks_hit[index] = true
			scenery.break_rock(index)
			spawn_effect(SPARKS_SCENE, probe.position, (rock[0] - probe.position).normalized(), Color(1.0, 0.8, 0.5), 0.5)
			shake = max(shake, 0.6)
			if rocks_hit.size() > MOST_ROCK_STRIKES:
				show_caption("Another rock strike! Luckily it only scraped the probe.", 2.0)
				play_sound("impact", -8.0)
				if hit_flash:
					hit_flash.color.a = 0.3
				continue
			GameState.science -= ROCK_STRIKE_SCIENCE
			GameState.mission_log.append({"title": "Rock strike", "text": "A rock hit the probe in the %s. Lost %d science." % [belt["name"].replace("Asteroid", "asteroid"), ROCK_STRIKE_SCIENCE], "ok": false})
			show_caption("Rock strike! Lost %d science." % ROCK_STRIKE_SCIENCE, 2.0)
			play_sound("impact", -2.0)
			if hit_flash:
				hit_flash.color.a = 0.45

# Which way the steering keys push the probe, as (along the path's side, along the path's up).
# The keys work the way you see it on screen: A or Left moves the probe to the left of the picture, D or Right to
# the right, W or Up moves it up and S or Down moves it down, wherever the camera happens to be looking from.
func steering_keys_push():
	var screen_push = Vector2.ZERO   # x: right on screen, y: up on screen
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		screen_push.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		screen_push.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		screen_push.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		screen_push.y -= 1.0
	if screen_push == Vector2.ZERO:
		return Vector2.ZERO
	var frame = path_frame(flight_progress)
	var plain_push = Vector2(screen_push.x, screen_push.y)   # side is to the right when looking along the path
	if camera == null:
		return plain_push
	var wanted_direction = camera.global_basis.x * screen_push.x + camera.global_basis.y * screen_push.y
	var path_push = Vector2(wanted_direction.dot(frame["side"]), wanted_direction.dot(frame["up"]))
	# If the camera looks at the path from straight beside it, left and right on screen run along the path (which
	# the player can't steer), so fall back to steering as if the camera were behind the probe
	if path_push.length() < 0.35:
		return plain_push
	return path_push.normalized() * min(screen_push.length(), 1.0)

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
	flight_controls.offset_left = -350.0
	flight_controls.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # if anything is wider, it grows to the left, not off the screen
	flight_controls.offset_top = 18.0
	flight_controls.offset_right = -18.0
	flight_controls.offset_bottom = 190.0
	layer.add_child(flight_controls)

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	flight_controls.add_child(column)

	var heading = Label.new()
	heading.text = "MISSION CONTROL"
	heading.theme_type_variation = "TitleLabel"   # (fonts: assets/ui/orbit_lab_theme.tres)
	heading.add_theme_font_size_override("font_size", 22)
	column.add_child(heading)

	mission_clock_label = Label.new()
	mission_clock_label.theme_type_variation = "DataLabel"
	column.add_child(mission_clock_label)

	mission_status_label = Label.new()
	mission_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(mission_status_label)

	mission_progress_bar = ProgressBar.new()
	mission_progress_bar.min_value = 0.0
	mission_progress_bar.max_value = 100.0
	mission_progress_bar.show_percentage = true
	mission_progress_bar.visible = false   # (the timeline below shows the same thing, with more in it)
	column.add_child(mission_progress_bar)

	# The mission timeline: launch on the left, arrival on the right, the belts and planets passed along the way
	mission_timeline = Control.new()
	mission_timeline.custom_minimum_size = Vector2(0, 34)
	mission_timeline.draw.connect(draw_mission_timeline)
	mission_timeline.tooltip_text = "Mission timeline: launch on the left, arrival on the right.\nAmber bands: asteroid or Kuiper belt. Blue ticks: planets passed. Gold diamonds: events."
	column.add_child(mission_timeline)

	# Live readouts, worked out from the real route: distance, speed, sunlight, radio delay and which Deep Space
	# Network dish is listening
	telemetry_label = Label.new()
	telemetry_label.theme_type_variation = "DataLabel"
	telemetry_label.add_theme_font_size_override("font_size", 13)
	telemetry_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	column.add_child(telemetry_label)

	time_mode_label = Label.new()
	time_mode_label.theme_type_variation = "DataLabel"
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
	update_telemetry()
	if mission_timeline:
		mission_timeline.queue_redraw()
	if scenery and not scenery.belt_at(flight_progress).is_empty():
		mission_status_label.text += "\nIn the %s: YOU have control" % scenery.belt_at(flight_progress)["name"].replace("Asteroid", "asteroid")


# ---------------------------------------------------------------------------
# Live telemetry and the mission timeline
# ---------------------------------------------------------------------------
# NASA's Deep Space Network: three sites about 120 degrees apart around the world, so as Earth turns one of them
# can always see the spacecraft. [name, east longitude in degrees]
const DEEP_SPACE_NETWORK = [["Goldstone, California", -116.89], ["Madrid, Spain", -4.25], ["Canberra, Australia", 148.98]]
const KILOMETERS_PER_AU = 149597870.7
const LIGHT_SECONDS_PER_AU = 499.005
const EARTH_TILT_DEGREES = 23.4393
var mission_timeline: Control = null
var telemetry_label: Label = null
var last_probe_km = []
var last_probe_days = 0.0
var probe_speed_km_s = 0.0

func update_telemetry():
	if telemetry_label == null:
		return
	if scenery == null or scenery.route_km.is_empty() or arrival_mode != "":
		telemetry_label.visible = false
		return
	telemetry_label.visible = true
	var now = scenery.route_launch_date + elapsed_flight_days
	var here = scenery.probe_km(flight_progress)
	var earth = scenery.body_km("Earth", now)
	var from_earth = Vector3(here[0] - earth[0], here[1] - earth[1], here[2] - earth[2])
	var sun_distance_au = Vector3(here[0], here[1], here[2]).length() / KILOMETERS_PER_AU
	var earth_distance_au = from_earth.length() / KILOMETERS_PER_AU
	# Speed around the Sun, from how far it moved since the last update
	if not last_probe_km.is_empty() and elapsed_flight_days - last_probe_days > 0.0001:
		var moved = Vector3(here[0] - last_probe_km[0], here[1] - last_probe_km[1], here[2] - last_probe_km[2]).length()
		var measured = moved / ((elapsed_flight_days - last_probe_days) * 86400.0)
		probe_speed_km_s = measured if probe_speed_km_s == 0.0 else lerp(probe_speed_km_s, measured, 0.2)
	last_probe_km = here
	last_probe_days = elapsed_flight_days
	var delay_seconds = earth_distance_au * LIGHT_SECONDS_PER_AU
	var lines = []
	lines.append("From Earth  %s" % distance_text(earth_distance_au))
	lines.append("From Sun    %.2f AU, %s sunlight" % [sun_distance_au, sunlight_text(sun_distance_au)])
	if probe_speed_km_s > 0.0:
		lines.append("Speed       %.1f km/s (around Sun)" % probe_speed_km_s)
	lines.append("Signal      %s each way" % delay_text(delay_seconds))
	lines.append("DSN         %s" % listening_station(from_earth, now))
	telemetry_label.text = "\n".join(lines)

func distance_text(au):
	var kilometers = au * KILOMETERS_PER_AU
	if kilometers < 2000000.0:
		return "%s km" % format_thousands(int(kilometers))
	if kilometers < 1000000000.0:
		return "%.2f AU, %d million km" % [au, int(kilometers / 1000000.0)]
	return "%.1f AU, %.1f billion km" % [au, kilometers / 1000000000.0]

func sunlight_text(au):
	var share = 1.0 / (au * au)
	return "%d%%" % int(round(share * 100.0)) if share >= 0.1 else "%.1f%%" % (share * 100.0)

func delay_text(seconds):
	if seconds < 90.0:
		return "%.1f s" % seconds
	if seconds < 5400.0:
		return "%.1f min" % (seconds / 60.0)
	return "%.1f hours" % (seconds / 3600.0)

func format_thousands(number):
	var text = str(number)
	var grouped = ""
	while text.length() > 3:
		grouped = "," + text.substr(text.length() - 3) + grouped
		text = text.substr(0, text.length() - 3)
	return text + grouped

# Which of the three Deep Space Network sites has the spacecraft overhead right now: the one where the
# spacecraft's direction in the sky is closest to due south (smallest hour angle), as Earth turns
func listening_station(from_earth, julian_date):
	if time_rate_days_per_second > 0.5:
		return "3 sites taking turns"   # (at this speed Earth spins too fast to say which)
	var tilt = deg_to_rad(EARTH_TILT_DEGREES)
	# Ecliptic to Earth's equator (route coordinates are ecliptic, in km)
	var equator_x = from_earth.x
	var equator_y = from_earth.y * cos(tilt) - from_earth.z * sin(tilt)
	var right_ascension = rad_to_deg(atan2(equator_y, equator_x))
	var sidereal_degrees = 280.46061837 + 360.98564736629 * (julian_date - 2451545.0)
	var best = DEEP_SPACE_NETWORK[0]
	var best_angle = 999.0
	for site in DEEP_SPACE_NETWORK:
		var hour_angle = abs(wrapf(sidereal_degrees + site[1] - right_ascension, -180.0, 180.0))
		if hour_angle < best_angle:
			best_angle = hour_angle
			best = site
	return "%s (70 m)" % best[0]

func draw_mission_timeline():
	var size = mission_timeline.size
	var top = 8.0
	var height = 10.0
	mission_timeline.draw_rect(Rect2(0, top, size.x, height), Color(0.12, 0.16, 0.24))
	if scenery:
		for belt in scenery.belts:
			mission_timeline.draw_rect(Rect2(size.x * belt["start"], top, size.x * (belt["end"] - belt["start"]), height), Color(1.0, 0.7, 0.25, 0.55))
		for sight in scenery.sights:
			var x = size.x * sight["progress"]
			mission_timeline.draw_line(Vector2(x, top - 4), Vector2(x, top + height + 4), Color(0.5, 0.8, 1.0), 2.0)
	# Cruise events: where the decisions come up (done ones bright, coming ones dim)
	for index in GameState.events.size():
		if GameState.events[index].get("phase", "cruise") != "cruise":
			continue
		var at = progress_at_event(index)
		if at >= 0.0 and at <= 1.0:
			var x = size.x * at
			var shade = Color(1.0, 0.85, 0.35) if index < event_index else Color(1.0, 0.85, 0.35, 0.35)
			mission_timeline.draw_colored_polygon(PackedVector2Array([Vector2(x, top - 1), Vector2(x + 4, top + height / 2), Vector2(x, top + height + 1), Vector2(x - 4, top + height / 2)]), shade)
	# Done so far, and where the probe is now
	mission_timeline.draw_rect(Rect2(0, top, size.x * flight_progress, height), Color(0.45, 0.85, 1.0, 0.55))
	var now_x = size.x * flight_progress
	mission_timeline.draw_circle(Vector2(now_x, top + height / 2), 5.0, Color.WHITE)
	var font = mission_timeline.get_theme_default_font()
	mission_timeline.draw_string(font, Vector2(0, top + height + 15), "LAUNCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.66, 0.75))
	mission_timeline.draw_string(font, Vector2(size.x - 80, top + height + 15), world_name().to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, 80, 10, Color(0.6, 0.66, 0.75))

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
	orbit_radius = max(probe.position.distance_to(center), target_radius() * 1.12)
	orbit_angle = atan2(probe.position.z - center.z, probe.position.x - center.x)
	# Arriving at the closest point of a stretched orbit, the way real orbit insertions work
	orbit_semi_major_axis = orbit_radius / (1.0 - ORBIT_ECCENTRICITY)
	orbit_periapsis_angle = orbit_angle
	orbit_mean_anomaly = 0.0
	orbit_seconds = 0.0
	if not has_lander():
		orbit_tilt_degrees = MAPPING_ORBIT_TILT_DEGREES
	if not GameState.direct_entry():
		draw_orbit_line()
	flame_seconds_left = 2.5    # the braking burn that lets the world's gravity catch the probe
	var label = world_name()
	if GameState.direct_entry():
		# Heat-shield landers dive straight into the air without stopping in orbit first, like Perseverance at Mars.
		# They coast in on the final approach while the arrival checks happen, then hit the air.
		flame_seconds_left = 0.0
		arrival_mode = "approaching"
		approach_start = probe.position
		approach_seconds = 0.0
		show_caption("Final approach: your lander is lined up to hit %s's air behind its heat shield, with no stop in orbit." % label, 5.0)
		return
	show_caption(("Braking burn complete: %s's gravity has caught your probe. You're in orbit!" % label).replace(": the", ": The"), 5.0)
	play_sound("thruster", -6.0)
	if not has_lander():
		start_orbit_science()   # an orbiter's real work starts now: mapping the world below
	if audio() and GameState.destination in ["Jupiter", "Io", "Europa", "Ganymede", "Callisto"] and audio().has_sound("jupiter_radio"):
		audio().play_ambience("jupiter_radio", -8.0)
		await get_tree().create_timer(5.5).timeout
		show_caption("That eerie sound is real: radio waves NASA's Juno recorded near Ganymede, turned into sound.", 6.0)

func begin_descent():
	arrival_mode = "descending"
	if orbit_line:
		orbit_line.visible = false
	descent_time = 0.0
	descent_start = probe.position
	# The worlds here are drawn small, so the probe shrinks on the way down to look the right size standing on one
	descent_start_scale = display_scale
	landed_scale = display_scale
	var center = target_planet.position
	var outward = (probe.position - center).normalized()
	var label = world_name()
	if GameState.destination in GameState.NO_SURFACE:
		# Giant planets have no ground: the probe dives into the clouds, like Galileo's probe at Jupiter in 1995
		landing_spot = center + outward * target_radius() * 0.97
		show_caption("Diving into %s's clouds, like the Galileo probe did at Jupiter in 1995" % label, 5.0)
	else:
		landing_spot = center + outward * (target_radius() + 0.46 * landed_scale)   # the probe's base on the ground
		if GameState.direct_entry():
			show_caption("Straight in! Your lander hits %s's air behind its heat shield, like Perseverance did." % label, 5.0)
		else:
			show_caption("Going down to the surface of %s..." % label, 4.0)
	if not GameState.destination in GameState.AIRLESS_WORLDS:
		flash(Color(1.0, 0.55, 0.15), 0.35)   # hitting the air: the heat shield glows
		spawn_effect(SPARKS_SCENE, probe.position - outward * 0.3 * display_scale, Vector3.ZERO, Color(1.0, 0.6, 0.3), 0.6 * display_scale)

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
	return Basis(Vector3(1, 0, 0), deg_to_rad(orbit_tilt_degrees)) * Vector3(cos(angle), 0.0, sin(angle)) * distance

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
	var tilt = Basis(Vector3(1, 0, 0), deg_to_rad(orbit_tilt_degrees))
	match arrival_mode:
		"approaching":
			# Coasting in toward the world, heat shield first
			approach_seconds += delta
			var outward = (approach_start - center).normalized()
			var close_in = center + outward * target_radius() * 1.8
			probe.position = approach_start.lerp(close_in, 1.0 - exp(-approach_seconds * 0.12))
			orient_probe(Basis(Quaternion(Vector3.UP, outward)))
		"orbiting":
			orbit_seconds += delta
			target_planet.rotate_y(delta * 0.04)   # the world turning below
			orbit_mean_anomaly += delta * TAU / ORBIT_LAP_SECONDS
			var place = orbit_point(orbit_mean_anomaly)
			probe.position = center + place
			var forward = (orbit_point(orbit_mean_anomaly + 0.01) - place).normalized()
			orient_probe(Basis(Quaternion(Vector3.UP, forward)))
		"descending":
			descent_time += delta
			var fraction = smoothstep(0.0, 1.0, descent_time / DESCENT_SECONDS)
			probe.position = descent_start.lerp(landing_spot, fraction)
			# Engine toward the ground, braking all the way down
			orient_probe(Basis(Quaternion(Vector3.UP, (probe.position - center).normalized())))
			flame_seconds_left = 0.1 if fraction < 0.97 else 0.0
			if fraction >= 1.0:
				if not GameState.destination in GameState.NO_SURFACE:
					open_surface_view()
				else:
					arrival_mode = "landed"
					probe.visible = false

# Cut to the landing site: the real lander comes down on that world's ground under its sky
func open_surface_view():
	arrival_mode = "landing"
	if audio():
		audio().stop_music(4.0)
		audio().stop_ambience(2.0)
	surface_view = SURFACE_SCENE.instantiate()
	add_child(surface_view)
	# Saturn has no ground: its landers go down to its moon Titan, like ESA's Huygens did
	surface_view.set_up("Titan" if GameState.destination == "Saturn" else GameState.destination)
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
	surface_view.crash_landing = landing_will_fail()
	if flight_controls:
		flight_controls.visible = false

# ---------------------------------------------------------------------------
# Science from orbit (probes with no lander): mapping, pictures and data, until you end the orbit mission
# ---------------------------------------------------------------------------
func start_orbit_science():
	if orbit_science:
		return
	orbit_science = ORBIT_SCIENCE_SCENE.instantiate()
	add_child(orbit_science)
	orbit_science.start(self)
	orbit_science.finished.connect(_on_orbit_science_finished)
	next_orbit_event_seconds = FIRST_ORBIT_EVENT_SECONDS

func _on_orbit_science_finished(summary, points):
	GameState.science += points
	GameState.mission_log.append({"title": "Science from orbit", "text": summary, "ok": true})
	show_caption(summary, 7.0)

func orbit_science_running():
	return orbit_science != null and is_instance_valid(orbit_science) and orbit_science.running

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C and orbit_science_running():
		orbit_wide_view = not orbit_wide_view

# A landing check that the design fails (like no heat shield at Mars) means the lander comes down too hard
func landing_will_fail():
	for index in range(event_index, GameState.events.size()):
		var event = GameState.events[index]
		if event.get("phase", "") == "descent" and event.has("check") and event.get("fatal", false) and not GameState.requirement_met(event["pass_if"]):
			return true
	return GameState.lost

func next_event_has_phase(phase):
	return event_index < GameState.events.size() and GameState.events[event_index].get("phase", "") == phase

func _on_touched_down():
	arrival_mode = "landed"
	seconds_since_touchdown = 0.0
	seconds_since_last_event = 0.0
	if surface_view.crash_landing:
		show_caption("Impact! The lander hit the ground far too fast.", 5.0)
		rover_state = "done"
		return
	show_caption("Touchdown! You're on the surface of %s." % world_name(), 5.0)
	# A rover sets off once the touchdown checks are done (see _process)
	rover_state = "waiting" if surface_view.can_drive() else "done"

func start_rover():
	rover_state = "driving"
	next_surface_event_drive_seconds = FIRST_SURFACE_EVENT_DRIVE_SECONDS
	surface_view.driving_finished.connect(_on_driving_finished)
	surface_view.start_driving()
	show_caption("Your rover is down! Drive it to the glowing science targets.", 5.0)

func _on_driving_finished(summary):
	rover_state = "done"
	seconds_since_last_event = 0.0
	var lost_rover = summary.begins_with("The ") or summary.begins_with("Too many") or summary.begins_with("Jupiter")
	GameState.science += surface_view.science_found
	GameState.mission_log.append({"title": "Rover drive", "text": summary, "ok": not lost_rover})
	show_caption(summary, 7.0)

# Each event waits for its moment: trip events for their point along the way, arrival and orbit events for the
# arrival, landing events for the landing itself (decisions on the way down, checks at touchdown), and surface events
# for time on the ground: every so often while you drive, or one after another if there's no rover.
func next_event_ready(event):
	var phase = event.get("phase", "cruise")
	if arrival_mode == "":
		return phase == "cruise" and flight_progress >= progress_at_event(event_index)
	if phase == "orbit" and orbit_science_running():
		return orbit_science.science_seconds >= next_orbit_event_seconds   # every so often while mapping
	if phase in ["descent", "surface"] and has_lander():
		if arrival_mode in ["orbiting", "approaching"]:
			begin_descent()   # time to go down
			return false
		if surface_view == null:
			return arrival_mode == "landed"   # a giant planet: the probe has dived into its clouds
		if phase == "descent":
			if event.has("check"):
				return surface_view.landed
			return surface_view.reached_decision_point or surface_view.landed
		if not surface_view.landed or rover_state == "waiting":
			return false
		if rover_state == "driving":
			return surface_view.drive_seconds >= next_surface_event_drive_seconds
		return seconds_since_last_event >= 2.5
	return arrival_mode in ["orbiting", "approaching", "landed"]

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
	["dust", ["dust devil", "dust storm", "dust"]],
]

# Extra animations that only happen at a landing site (checked first there)
const SURFACE_EVENT_ANIMATIONS = [
	["storm", ["dust storm"]],
	["night", ["lunar night", "freezing night", "nightfall", "eclipse", "four-hour day"]],
	["drill", ["drill", "sampling", "a sample", "scoop", "robotic arm"]],
]

func event_animation_kind(event):
	var words = (event.get("title", "") + " " + event.get("text", "")).to_lower()
	if surface_view:
		for entry in SURFACE_EVENT_ANIMATIONS:
			for keyword in entry[1]:
				if words.contains(keyword):
					return entry[0]
	for entry in EVENT_ANIMATIONS:
		for keyword in entry[1]:
			if words.contains(keyword):
				return entry[0]
	return ""

func start_event_animation(event):
	if event.has("insertion_check"):
		return 3.5 if arrival_mode == "orbiting" else 1.0   # let the braking burn play first
	var kind = event_animation_kind(event)
	if surface_view:
		# At the landing site: the shaking, dust and sounds happen there
		match kind:
			"flare":
				flash(Color(1.0, 0.75, 0.3), 0.3)
				play_sound("alarm", -4.0)
			"glitch":
				flicker_seconds_left = 1.2
				play_sound("glitch", -4.0)
			"radio":
				play_sound("static", -6.0)
		return surface_view.play_event_effect(kind)
	match kind:
		"flare":
			var sun_direction = Vector3(0, -0.7071, -0.7071)   # the way the scene's sunlight travels
			var light = get_node_or_null("DirectionalLight3D")
			if light:
				sun_direction = -light.global_transform.basis.z
			spawn_effect(SOLAR_WIND_SCENE, probe.position - sun_direction * 3.0 * display_scale, -sun_direction, Color.WHITE, display_scale)
			flash(Color(1.0, 0.75, 0.3), 0.35)
			play_sound("alarm", -4.0)
			return 1.8
		"hit":
			spawn_effect(SPARKS_SCENE, probe.position, Vector3.ZERO, Color.WHITE, display_scale)
			flash(Color(1.0, 0.3, 0.2), 0.45)
			shake = 0.8
			play_sound("impact", 0.0)
			return 1.4
		"radio":
			var earth = get_node_or_null("Earth")
			var toward_earth = (earth.global_position - probe.position).normalized() if earth else Vector3.LEFT
			spawn_effect(RADIO_WAVES_SCENE, probe.position, toward_earth, Color.WHITE, display_scale)
			play_sound("static", -6.0)
			return 1.8
		"glitch":
			flicker_seconds_left = 1.2
			play_sound("glitch", -4.0)
			return 1.4
		"burn":
			flame_seconds_left = 2.0
			play_sound("thruster", -8.0)
			return 1.6
		"quake":
			shake = 1.0
			# A real marsquake that NASA's InSight lander felt (sped up so we can hear it)
			play_sound("marsquake" if GameState.destination == "Mars" else "thump", 0.0)
			return 1.4
	# Anything else: a caution tone while the probe starts to wobble (see update_alert)
	play_sound("alarm", -10.0)
	return 1.0

# Adds a particle effect at a place, pointing its "up" along a direction, and removes it when it's done
func spawn_effect(scene, place, direction, tint = Color.WHITE, size = 1.0):
	var effect = scene.instantiate()
	add_child(effect)
	effect.global_position = place
	if direction != Vector3.ZERO:
		effect.global_basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	if effect is CPUParticles3D:
		effect.color = tint
		effect.emission_sphere_radius *= size
		effect.emission_box_extents *= size
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
	if surface_view:
		surface_view.paused = true   # the landing (or the rover) waits for your decision
	if orbit_science_running():
		orbit_science.paused = true
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
		show_result_feedback(result["ok"])

func _on_choice_pressed(choice_index):
	var event = GameState.events[event_index]
	var result = GameState.resolve_choice(event, choice_index)
	if GameState.lost and surface_view and not surface_view.landed:
		surface_view.crash_landing = true   # that decision on the way down ends in a crash
	remove_choice_buttons()
	event_title.text = ("SYSTEMS NOMINAL  |  " if result["ok"] else "MISSION ALERT  |  ") + event["title"]
	event_text.text = result["text"]
	continue_button.visible = true
	show_result_feedback(result["ok"])

func _on_continue_pressed():
	event_panel.visible = false
	event_index += 1
	seconds_since_last_event = 0.0
	if orbit_science_running():
		orbit_science.paused = false
		next_orbit_event_seconds = orbit_science.science_seconds + ORBIT_EVENT_SPACING_SECONDS
	if surface_view:
		surface_view.paused = false
		if rover_state == "driving":
			next_surface_event_drive_seconds = surface_view.drive_seconds + SURFACE_EVENT_SPACING_DRIVE_SECONDS
	if GameState.lost:
		if surface_view and not surface_view.landed:
			# Watch the crash first
			surface_view.crash_landing = true
			var waited = 0.0
			while not surface_view.landed and waited < 30.0:
				waited += get_process_delta_time()
				await get_tree().process_frame
			await get_tree().create_timer(2.5).timeout
		go_to_results()
	elif event_index >= GameState.events.size():
		finish_mission()
	else:
		fly_to(progress_at_event(event_index))

# Every event is done. A lander still goes down first, and a rover keeps driving until you press "Done driving".
func finish_mission():
	if finishing:
		return
	finishing = true
	if has_lander() and arrival_mode in ["orbiting", "approaching"]:
		begin_descent()
	var waited = 0.0
	while has_lander() and arrival_mode != "landed" and waited < 60.0:
		waited += get_process_delta_time()
		await get_tree().process_frame
	while rover_state in ["waiting", "driving"] or orbit_science_running():
		await get_tree().process_frame   # driving the rover, or doing science from orbit
	await get_tree().create_timer(2.5 if has_lander() else 0.5).timeout
	go_to_results()

func audio():
	return get_node_or_null("/root/AudioManager")

func play_sound(sound_name, volume_db = 0.0):
	if audio():
		audio().play_effect(sound_name, volume_db)

func go_to_results():
	if not cruising:
		return
	cruising = false
	if surface_view and surface_view.driving:
		surface_view.end_driving("")
	if orbit_science_running() and not GameState.lost:
		orbit_science.end_mission()
	if audio():
		audio().stop_engine(0.5)
		audio().stop_ambience(1.5)
	if GameState.lost and audio():
		audio().play_voice("houston_problem")   # Apollo 13: "Houston, we've had a problem"
		await get_tree().create_timer(3.5).timeout
	if flight_controls:
		flight_controls.visible = false
	GameState.finish_mission()
	GameState.go_to_scene(RESULTS_SCENE)
