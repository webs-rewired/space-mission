extends Control

# MINIGAME: DOCKING TRAINER (res://scenes/docking.tscn)
# Fly a spacecraft the last few dozen meters to one of the Space Station's docking ports, looking through the
# docking camera, the way Crew Dragon and Starliner crews practice it (and can take over from the computer).
# Orbital mechanics is on (scripts/docking_physics.gd), and the two ports behave differently:
#   forward port (V-bar approach, from in front): moving in, the spacecraft slowly sinks toward Earth
#   zenith port (R-bar approach, from above): tides push it away upward, and coming down makes it drift forward
# The physics runs in the station's orbit frame; the screen shows everything in the port's frame (right, up, range).
#
# Translation (moving): W/S up and down, A/D left and right, E toward the port, Q away from it
# Rotation (turning):   arrow keys pitch and yaw, Z/C roll
# Hold Shift for fine control (a quarter of the push). R toggles rate hold (the computer stops the turning).
# PILOT ASSIST (P, on for Cadet and Standard): the flight computer keeps the spacecraft lined up (pitch, yaw and
# roll held at zero, like Crew Dragon's attitude hold), so the pilot only moves it: W A S D to center, E and Q
# for speed. The status line names the exact key to press next.
#
# To dock, touch the port slowly, centered and lined up. Scoring: docked 50, contact speed 15, centering 15,
# lined up 10, propellant left 10. Medals, personal best and research points like the other minigames.
# Opened from the career screen's Training tab; closing it sends closed. A failed docking only ends the attempt.
#
# SAMPLE RETURN (start_sample_return): on a landing mission with the Sample return part, the ascent stage carrying
# your rock samples has to dock with your orbiter around that world, like China's Chang'e 5 did at the Moon in
# 2020. The same flying, around the destination instead of Earth, with two approaches' worth of propellant.
# Sends sample_return_finished({"docked", "score"}) when it's over.

signal closed
signal sample_return_finished(result)

const DockingPhysics = preload("res://scripts/docking_physics.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const SpaceTextures = preload("res://scripts/space_textures.gd")
const OrbitScience = preload("res://scripts/orbit_science.gd")
const OrbitPhysics = preload("res://scripts/orbit_physics.gd")
const EARTH_TEXTURE = preload("res://assets/textures/2k_earth_daymap.jpg")
const WORLD_SCALE = 2.0         # meters in the 3D view for each real kilometer of the world below (500× smaller)
const AIR_COLORS = {"Earth": Color(0.35, 0.6, 1.0, 0.22), "Mars": Color(0.85, 0.6, 0.45, 0.12), "Titan": Color(0.95, 0.65, 0.3, 0.35), "Venus": Color(1.0, 0.9, 0.6, 0.3)}
const Career = preload("res://scripts/career.gd")
const MEDALS = [[85, "GOLD", Color(1.0, 0.82, 0.35), 15], [65, "SILVER", Color(0.8, 0.85, 0.92), 8], [40, "BRONZE", Color(0.85, 0.55, 0.35), 4]]

# The thrusters (game numbers: a spacecraft of about 12 tonnes on its small maneuvering thrusters)
const PUSH = 0.05               # m/s² while a translation key is held
const TURN = 0.8                # degrees/s² while a rotation key is held
const FINE_SHARE = 0.25         # Shift: a quarter of the push, for the last few meters
const TURN_PROPELLANT = 0.01    # propellant (in m/s of push) for each degree/s of turning
# What the docking ring can accept at contact (game limits for a gentle docking, rounded)
const SLOWEST_CONTACT = 0.02    # m/s: slower than this doesn't push the capture latches home
const FASTEST_CONTACT = 0.15    # m/s: faster bounces off the ring
const FASTEST_SIDEWAYS = 0.05   # m/s sideways at contact
const CAPTURE_OFFSETS = [0.25, 0.2, 0.15]   # m from the docking axis, by difficulty (tighter on Veteran)
const CAPTURE_ANGLES = [5.0, 4.0, 3.0]      # degrees of pitch, yaw or roll, by difficulty
const PORT_STRUCTURE = 0.9      # m: farther off than the ring but within this, the spacecraft hits the port
const STATION_RADIUS = 2.4      # m: within this of the docking axis at the port, it hits the station itself
const TIME_LIMIT = 420.0        # seconds
const FARTHEST = 140.0          # m: drifting away farther than this ends the attempt
const FAST_FORWARD_CLOSEST = 6.0   # m: fast-forward switches off this close to the port
const CAMERA_SETBACK = 0.8      # m from the docking ring back to the docking camera
# The ports: the station scene in docking.tscn, and how to describe the approach
const TARGETS = {
	"forward": {"title": "Forward port (V-bar)", "station": "StationForward", "where": "in front of the station's forward port",
		"lesson": "You and the station are both in orbit. Coming in from in front, you're a little slower than the station, so you slowly sink toward Earth (the Clohessy-Wiltshire equations NASA plans rendezvous with). Keep nudging up."},
	"zenith": {"title": "Zenith port (R-bar)", "station": "StationZenith", "where": "above the station's zenith port, with Earth below",
		"lesson": "Above the station, tides in Earth's gravity slowly push you farther up, and moving down toward the port makes you drift forward (the Coriolis term in the Clohessy-Wiltshire equations). Keep braking and nudging back."},
	"orbiter": {"title": "Sample return", "station": "Orbiter", "where": "in front of your orbiter",
		"lesson": "Your ascent stage is carrying the samples. Dock with the orbiter and they ride home; miss, and they stay behind. Orbital mechanics still pulls you off course, at this world's own orbital rate."},
}

@onready var camera: Camera3D = $View/Viewport/World/Camera
@onready var earth: Node3D = $View/Viewport/World/Earth
@onready var reticle: Control = $Reticle
@onready var readouts: Label = $Left/Column/Readouts
@onready var status_label: Label = $Status
@onready var assist_button: Button = $Bottom/AssistButton
@onready var restart_button: Button = $Bottom/RestartButton
@onready var result_box: PanelContainer = $Result
@onready var result_title: Label = $Result/Column/Title
@onready var result_text: Label = $Result/Column/Text
@onready var again_button: Button = $Result/Column/Buttons/AgainButton
@onready var done_button: Button = $Result/Column/Buttons/DoneButton
@onready var limits_label: Label = $Right/Column/Limits
@onready var lesson_label: Label = $Right/Column/Lesson
@onready var target_picker: OptionButton = $Bottom/TargetPicker
@onready var checklist_label: Label = $Right/Column/Checklist
@onready var keys_row: Control = $Right/Column/KeyHints

var physics = DockingPhysics.new()
var attitude = Vector3.ZERO        # pitch, yaw, roll in degrees
var attitude_rate = Vector3.ZERO   # degrees per second
var propellant_budget = 4.0        # m/s of push the thrusters can give
var propellant_used = 0.0
var rate_hold = false
var running = false
var finished = false
var clock = 0.0
var thruster_sound_wait = 0.0
var last_warning = ""
var inputs_override = {}           # (the automatic tests fly with this instead of the keyboard)
var forecast_wait = 0
var time_scale = 1.0               # (the automatic tests run the clock faster)
var fast_forward = false
var predicted_contact = Vector3.ZERO
var target = "forward"
var capture_offset = 0.2           # this attempt's limits (from CAPTURE_OFFSETS and CAPTURE_ANGLES)
var capture_angle = 4.0
var base = Basis.IDENTITY          # the docking camera's direction when lined up with the port (3D world)
var sample_return = false          # flying the sample-return ascent stage on a mission (not the trainer)
var return_world = "Moon"
var attempts_left = 2
var reported = false               # (sample return: the result has been sent)
var return_result = {"docked": false, "score": 0}
var current_step = ""              # what to do next, for the status line
var pilot_assist = true            # the computer holds the attitude (lined up); the pilot only translates
var assist_chosen = false          # the pilot switched assist on or off: keep that choice for the next attempt
const ASSIST_HINTS = [["W A S D", "center"], ["E", "move in"], ["Q", "slow down"], ["Shift", "fine"], ["P", "assist off"], ["T", "fast-forward"]]
const MANUAL_HINTS = [["W A S D", "move"], ["E", "in"], ["Q", "out"], ["← → ↑ ↓", "turn"], ["Z C", "roll"], ["Shift", "fine"], ["R", "rate hold"], ["P", "assist on"], ["T", "fast-forward"]]

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Header/CloseButton.pressed.connect(close)
	restart_button.pressed.connect(start)
	again_button.pressed.connect(start)
	done_button.pressed.connect(close)
	assist_button.pressed.connect(func():
		assist_chosen = true
		set_pilot_assist(not pilot_assist))
	for target_id in TARGETS:
		target_picker.add_item(TARGETS[target_id]["title"])
	target_picker.item_selected.connect(func(index):
		target = TARGETS.keys()[index]
		start())
	get_viewport().gui_release_focus()
	start()
	UiMotion.reveal_text($Header/Title, 0.1, 0.7, 0.4)
	UiMotion.stagger([$Left, $Right], 0.2, 0.1, Vector2(0, 16), 0.6)

func close():
	if sample_return and not reported:
		reported = true
		sample_return_finished.emit(return_result)
	closed.emit()
	queue_free()

# A mission's sample return: dock the ascent stage with the orbiter around this world
func start_sample_return(world):
	sample_return = true
	return_world = world
	target = "orbiter"
	attempts_left = 2
	target_picker.visible = false
	restart_button.visible = false
	start()

# The 3D world has y up and the station flying toward +z; the orbit frame has x up (away from Earth), y forward,
# z sideways. The port frame is right, up and range (out along the docking axis) as the docking camera sees them.
func hill_to_world(vector):
	return Vector3(vector.z, vector.x, vector.y)

func world_to_hill(vector):
	return Vector3(vector.y, vector.z, vector.x)

func to_port_frame(hill_vector):
	var world = hill_to_world(hill_vector)
	return Vector3(world.dot(base.x), world.dot(base.y), world.dot(base.z))

func from_port_frame(port_vector):
	return world_to_hill(base.x * port_vector.x + base.y * port_vector.y + base.z * port_vector.z)

func port_position():
	return to_port_frame(physics.position)

func port_velocity():
	return to_port_frame(physics.velocity)

func set_up_target():
	for target_id in TARGETS:
		get_node("View/Viewport/World/" + TARGETS[target_id]["station"]).visible = target_id == target
	set_up_world(return_world if target == "orbiter" else "Earth")
	if target == "zenith":
		# Looking straight down at the port, with the station's direction of flight at the top of the picture
		base = Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
	else:
		base = Basis.IDENTITY
	lesson_label.text = TARGETS[target]["lesson"]
	if target == "orbiter":
		$Header/Title.text = "SAMPLE RETURN  ·  DOCK WITH YOUR ORBITER AT %s" % SolarSystemData.BODIES.get(return_world, {}).get("label", return_world).to_upper()
	else:
		$Header/Title.text = "DOCKING TRAINER  ·  SPACE STATION %s" % TARGETS[target]["title"].to_upper()
		target_picker.selected = TARGETS.keys().find(target)

# The world below: Earth under the Space Station, or the mission's destination under the orbiter. It's drawn 500
# times smaller and 500 times closer, so it fills the same part of the sky, and the orbital rate (for the
# Clohessy-Wiltshire drift) is the real one for a low orbit there.
func set_up_world(world):
	var data = SolarSystemData.BODIES.get(world, {})
	var radius_km = 6371.0 if world == "Earth" else data.get("radius_km", 1737.0)
	var altitude_km = 420.0 if world == "Earth" else clamp(radius_km * 0.06, 15.0, 400.0)
	var surface: MeshInstance3D = earth.get_node("Surface")
	var clouds: MeshInstance3D = earth.get_node("Clouds")
	var air: MeshInstance3D = $View/Viewport/World/Air
	# (the meshes and materials are copied first, so changing them never leaks into the next time the scene opens)
	surface.mesh = surface.mesh.duplicate()
	surface.mesh.radius = radius_km * WORLD_SCALE
	surface.mesh.height = radius_km * WORLD_SCALE * 2.0
	var material = surface.get_surface_override_material(0).duplicate()
	var map = EARTH_TEXTURE if world == "Earth" else SpaceTextures.find_texture(data.get("images", []))
	material.albedo_texture = map
	material.albedo_color = Color.WHITE if map else data.get("color", Color(0.6, 0.6, 0.6))
	surface.set_surface_override_material(0, material)
	clouds.visible = world == "Earth"
	earth.position = Vector3(0, -(radius_km + altitude_km) * WORLD_SCALE, 0)
	air.visible = AIR_COLORS.has(world)
	if air.visible:
		air.mesh = air.mesh.duplicate()
		air.mesh.radius = (radius_km + min(100.0, radius_km * 0.03)) * WORLD_SCALE
		air.mesh.height = air.mesh.radius * 2.0
		var air_material = air.get_surface_override_material(0).duplicate()
		air_material.albedo_color = AIR_COLORS[world]
		air.set_surface_override_material(0, air_material)
		air.position = earth.position
	camera.far = (radius_km + altitude_km) * WORLD_SCALE * 3.0
	if world == "Earth":
		physics.mean_motion = DockingPhysics.MEAN_MOTION
	else:
		var mu = OrbitScience.WORLDS.get(world, {}).get("gm", data.get("mass_earths", 0.0123) * OrbitPhysics.EARTH_MU)
		var orbit_radius = radius_km + altitude_km
		physics.mean_motion = sqrt(mu / (orbit_radius * orbit_radius * orbit_radius))

# A new approach: a hold point on the docking axis, a little off it and a little crooked
func start():
	set_up_target()
	var difficulty = clamp(GameState.difficulty, 0, 2)
	var distance = [20.0, 30.0, 40.0][difficulty] * (0.7 if sample_return else 1.0)
	var offset = [0.8, 1.8, 3.0][difficulty]
	var tilt = [2.0, 4.0, 6.0][difficulty]
	var spin = [0.0, 0.1, 0.25][difficulty]
	propellant_budget = [9.0, 6.0, 4.5][difficulty] * (1.3 if GameState.has_upgrade("rcs_upgrade") else 1.0)
	if sample_return:
		GameState.note_tech("rcs_upgrade", "30% more propellant for the sample-return docking")
	capture_offset = CAPTURE_OFFSETS[difficulty]
	capture_angle = CAPTURE_ANGLES[difficulty]
	limits_label.text = "Touch the port at %d to %d cm/s, within %d cm of the center, lined up within %d°.\nSideways speed under %d cm/s." % [
		int(SLOWEST_CONTACT * 100), int(FASTEST_CONTACT * 100), int(round(capture_offset * 100)), int(capture_angle), int(FASTEST_SIDEWAYS * 100)]
	reticle.angle_limit = capture_angle
	reticle.offset_limit = capture_offset
	set_rate_hold(difficulty < 2)
	set_pilot_assist(pilot_assist if assist_chosen else difficulty < 2)
	reticle.show_prediction = difficulty < 2
	physics.set_state(from_port_frame(Vector3(randf_range(-offset, offset), randf_range(-offset, offset), distance)),
		from_port_frame(Vector3(randf_range(-0.01, 0.01), randf_range(-0.01, 0.01), 0.0)))
	attitude = Vector3(randf_range(-tilt, tilt), randf_range(-tilt, tilt), randf_range(-tilt, tilt))
	attitude_rate = Vector3(randf_range(-spin, spin), randf_range(-spin, spin), randf_range(-spin, spin))
	propellant_used = 0.0
	clock = 0.0
	fast_forward = false
	running = true
	finished = false
	again_button.visible = true
	if not sample_return:
		again_button.text = "Fly again"
		done_button.text = "Done"
	last_warning = ""
	result_box.visible = false
	status_label.text = "Holding %d m %s. Follow the checklist on the right." % [int(distance), TARGETS[target]["where"]]
	if sample_return:
		status_label.text = "The ascent stage is up, %d m %s. Dock gently and the samples go home." % [int(distance), TARGETS[target]["where"]]
	update_view()

func set_rate_hold(on):
	rate_hold = on

# Pilot assist: the computer flies the attitude, the pilot flies the position (see the top of this file)
func set_pilot_assist(on):
	pilot_assist = on
	assist_button.text = "Pilot assist: %s (P)" % ("ON" if on else "OFF")
	keys_row.hints = ASSIST_HINTS if on else MANUAL_HINTS

# Every key belongs to the trainer while it's open (the flying keys are read with Input.is_key_pressed; this only
# stops the menus underneath from reacting to them, like arrow keys moving their focus)
func _input(event):
	if not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		close()
	elif event.keycode == KEY_R and running:
		set_rate_hold(not rate_hold)
	elif event.keycode == KEY_P and running:
		assist_chosen = true
		set_pilot_assist(not pilot_assist)
	elif event.keycode == KEY_T and running:
		fast_forward = not fast_forward and port_position().z >= FAST_FORWARD_CLOSEST

func held(key):
	if inputs_override.has(key):
		return inputs_override[key]
	return Input.is_key_pressed(key)

func _process(delta):
	if not running:
		return
	delta = min(delta, 0.05) * time_scale
	# Fast-forward (T) only while still far from the port
	if fast_forward and port_position().z < FAST_FORWARD_CLOSEST:
		fast_forward = false
	if fast_forward:
		delta *= 3.0
	clock += delta
	var share = FINE_SHARE if held(KEY_SHIFT) else 1.0
	var out_of_propellant = propellant_used >= propellant_budget
	# Translation, in the spacecraft's own directions (right, up, toward the port)
	var push = Vector3.ZERO
	if not out_of_propellant:
		push.x = (1.0 if held(KEY_D) else 0.0) - (1.0 if held(KEY_A) else 0.0)
		push.y = (1.0 if held(KEY_W) else 0.0) - (1.0 if held(KEY_S) else 0.0)
		push.z = (1.0 if held(KEY_Q) else 0.0) - (1.0 if held(KEY_E) else 0.0)   # the camera looks along -z
	var push_world = (base * camera_basis()) * (push * PUSH * share)
	var push_station = world_to_hill(push_world)
	propellant_used += push_world.length() * delta
	# Rotation
	var turn = Vector3.ZERO
	if not out_of_propellant and not pilot_assist:
		turn.x = (1.0 if held(KEY_UP) else 0.0) - (1.0 if held(KEY_DOWN) else 0.0)
		turn.y = (1.0 if held(KEY_LEFT) else 0.0) - (1.0 if held(KEY_RIGHT) else 0.0)
		turn.z = (1.0 if held(KEY_Z) else 0.0) - (1.0 if held(KEY_C) else 0.0)
	var turn_rate_change = turn * TURN * share * delta
	if pilot_assist and not out_of_propellant:
		# The computer turns the spacecraft back to lined up and holds it there: a turn rate that shrinks as the
		# angle shrinks, reached with no more than a held key's worth of thrust
		for axis in 3:
			var wanted_rate = clamp(-attitude[axis] * 0.6, -1.5, 1.5)
			turn_rate_change[axis] = clamp(wanted_rate - attitude_rate[axis], -TURN * delta, TURN * delta)
	elif rate_hold and not out_of_propellant:
		# The computer fires against any turning you aren't commanding (about as hard as a held key) until it stops
		for axis in 3:
			if turn[axis] == 0.0:
				turn_rate_change[axis] += clamp(-attitude_rate[axis], -TURN * delta, TURN * delta)
	attitude_rate += turn_rate_change
	propellant_used += (abs(turn_rate_change.x) + abs(turn_rate_change.y) + abs(turn_rate_change.z)) * TURN_PROPELLANT
	attitude += attitude_rate * delta
	physics.step(delta, push_station)
	# Thruster sound while firing (a puff every quarter second)
	thruster_sound_wait -= delta
	if (push != Vector3.ZERO or turn != Vector3.ZERO) and thruster_sound_wait <= 0.0:
		thruster_sound_wait = 0.25
		var audio = get_node_or_null("/root/AudioManager")
		if audio:
			audio.play_effect("thruster", -20.0 if share < 1.0 else -14.0, randf_range(1.4, 1.8))
	earth.rotate_x(-physics.mean_motion * delta)
	if port_position().z <= 0.0:
		contact()
		return
	if port_position().z > FARTHEST:
		end_attempt("DRIFTED AWAY", "The spacecraft drifted %d m from the station. Mission control called off the approach." % int(FARTHEST))
		return
	if clock > TIME_LIMIT:
		end_attempt("OUT OF TIME", "The approach took longer than %d minutes. Real dockings follow a timeline planned around the station's orbit, so mission control waved this one off." % int(TIME_LIMIT / 60.0))
		return
	update_view()

func camera_basis():
	return Basis.from_euler(Vector3(deg_to_rad(attitude.x), deg_to_rad(attitude.y), deg_to_rad(attitude.z)))

func lateral_offset():
	var place = port_position()
	return Vector2(place.x, place.y)   # right, up (meters)

func update_view():
	var place = port_position()
	camera.basis = base * camera_basis()
	# (the camera sits a little behind the spacecraft's docking ring, looking past it)
	camera.position = hill_to_world(physics.position) + camera.basis.z * CAMERA_SETBACK
	reticle.pitch = attitude.x
	reticle.yaw = attitude.y
	reticle.roll = attitude.z
	# The port and its capture zone in the camera view, and the predicted contact point: coast forward with no
	# thrust until the spacecraft reaches the port plane (worked out a few times a second)
	reticle.port_visible = not camera.is_position_behind(Vector3.ZERO)
	reticle.port_on_screen = camera.unproject_position(Vector3.ZERO)
	var focal_pixels = (reticle.size.y / 2.0) / tan(deg_to_rad(camera.fov / 2.0))
	reticle.capture_radius_pixels = focal_pixels * capture_offset / max(place.z + CAMERA_SETBACK, 0.3)
	forecast_wait -= 1
	if forecast_wait <= 0:
		forecast_wait = 6
		var forecast = DockingPhysics.new()
		forecast.mean_motion = physics.mean_motion
		forecast.set_state(physics.position, physics.velocity)
		var seconds = 0.0
		while to_port_frame(forecast.position).z > 0.0 and seconds < 900.0 and to_port_frame(forecast.velocity).z < 0.0:
			forecast.step(0.5, Vector3.ZERO, 0.5)
			seconds += 0.5
		var contact_place = hill_to_world(forecast.position)
		reticle.prediction_valid = to_port_frame(forecast.position).z <= 0.0
		predicted_contact = contact_place - base.z * contact_place.dot(base.z)
	reticle.predicted_on_screen = camera.unproject_position(predicted_contact)
	var speed = port_velocity()
	var closing = -speed.z
	var offset = lateral_offset()
	var drift = to_port_frame(physics.natural_acceleration()) * 1000.0
	var lines = [
		"RANGE          %.2f m" % place.z,
		"CLOSING RATE   %+.3f m/s" % closing,
		"SIDEWAYS       %.2f m %s   %+.3f m/s" % [abs(offset.x), "right" if offset.x >= 0.0 else "left", speed.x],
		"UP / DOWN      %.2f m %s   %+.3f m/s" % [abs(offset.y), "up" if offset.y >= 0.0 else "down", speed.y],
		"ORBITAL DRIFT  %+.2f up  %+.2f right mm/s²" % [drift.y, drift.x],
		"",
		"RCS PROPELLANT %d%%" % int(round(100.0 * max(propellant_budget - propellant_used, 0.0) / propellant_budget)),
		"ATTITUDE       %s" % ("held by the computer" if pilot_assist else ("rate hold" if rate_hold else "manual")),
		"TIME           %d:%02d%s" % [int(clock) / 60, int(clock) % 60, "   ×3 (T)" if fast_forward else ""],
	]
	readouts.text = "\n".join(lines)
	# Warnings
	var warning = ""
	if propellant_used >= propellant_budget:
		warning = "RCS propellant gone: the spacecraft can only coast now."
	elif place.z < 10.0 and closing > FASTEST_CONTACT * 1.3:
		warning = "Too fast! Slow down before contact (Q)."
	elif place.z < 6.0 and offset.length() > capture_offset * 2.5:
		warning = "Off center: line up with the target before contact."
	elif closing < -0.02:
		warning = "Backing away from the station."
	update_checklist(place, closing, offset)
	if warning != "":
		status_label.text = warning
		if warning != last_warning:
			reticle.flash = 0.6
	else:
		status_label.text = current_step
	last_warning = warning
	# The keys light up while held
	for pair in [["W", KEY_W], ["A", KEY_A], ["S", KEY_S], ["D", KEY_D], ["E", KEY_E], ["Q", KEY_Q], ["Z", KEY_Z], ["C", KEY_C], ["Shift", KEY_SHIFT]]:
		keys_row.light_key(pair[0], held(pair[1]))
	keys_row.light_key("←", held(KEY_LEFT))
	keys_row.light_key("→", held(KEY_RIGHT))
	keys_row.light_key("↑", held(KEY_UP))
	keys_row.light_key("↓", held(KEY_DOWN))

# The checklist on the right: what a pilot does, in order, ticked off as each one is true right now. The first
# one that isn't done is the next thing to do, and the status line at the bottom says exactly how.
func update_checklist(place, closing, offset):
	var angle = max(abs(attitude.x), abs(attitude.y), abs(attitude.z))
	var speed = port_velocity()
	var centered = offset.length() <= max(capture_offset * 2.0, min(0.6, place.z * 0.05))
	var moving_in = closing >= 0.05 or (place.z <= 5.0 and closing >= SLOWEST_CONTACT) or place.z < 1.0
	var move_in_text = "Move in: tap E (closing at %.2f m/s; aim for about 0.15)." % closing
	if closing > 0.2:
		move_in_text = "A little fast: tap Q (closing at %.2f m/s; aim for about 0.15)." % closing
	var slow_text = "Coming in nicely at %.2f m/s. When the range reaches 5 m, slow down to 0.03 to 0.10 m/s." % closing
	if place.z <= 5.0:
		slow_text = ("Slow down: tap Q (closing at %.2f m/s; aim for 0.03 to 0.10)." % closing) if closing > 0.10 else ("Too slow to latch: tap E once (closing at %.3f m/s)." % closing)
	var steps = [
		["Stop the spin", attitude_rate.length() < 0.15, "Pilot assist is stopping the spin..." if pilot_assist else "Stop the spin: press R for rate hold (or tap the arrow keys against the turn)."],
		["Line up (gauges green)", angle <= capture_angle * 0.8, "Pilot assist is lining you up..." if pilot_assist else "Line up: arrow keys and Z/C until the pitch, yaw and roll gauges turn green."],
		["Center on the target", centered, "Center: %s Put the orange cross on the black cross." % centering_advice(offset, speed)],
		["Move in at 0.10 to 0.20 m/s", moving_in, move_in_text],
		["Slow down inside 5 m", place.z <= 5.0 and closing >= SLOWEST_CONTACT and closing <= 0.10, slow_text],
		["Touch the port", false, "Nearly there: %s" % centering_advice(offset, speed)],
	]
	var lines = []
	current_step = ""
	for step in steps:
		var marker = "✓"
		if not step[1]:
			marker = "▶" if current_step == "" else "·"
			if current_step == "":
				current_step = step[2]
		lines.append("%s  %s" % [marker, step[0]])
	checklist_label.text = "\n".join(lines)

# Which keys move the spacecraft toward the docking axis right now: drift in at a speed that shrinks as the
# offset shrinks (8 cm/s for each meter off, at most 10 cm/s), and coast once it's already drifting that way
func centering_advice(offset, speed):
	var wanted = Vector2(clamp(-offset.x * 0.08, -0.1, 0.1), clamp(-offset.y * 0.08, -0.1, 0.1))
	var error = wanted - Vector2(speed.x, speed.y)
	var keys = []
	if abs(error.x) > 0.008:
		keys.append("D (right)" if error.x > 0.0 else "A (left)")
	if abs(error.y) > 0.008:
		keys.append("W (up)" if error.y > 0.0 else "S (down)")
	if keys.is_empty():
		return "drifting the right way, so let it coast."
	return "tap %s." % " and ".join(keys)

# The spacecraft's docking ring reaches the port
func contact():
	running = false
	var offset = lateral_offset().length()
	var speed = port_velocity()
	var closing = -speed.z
	var sideways = Vector2(speed.x, speed.y).length()
	var angle = max(abs(attitude.x), abs(attitude.y), abs(attitude.z))
	update_view()
	var audio = get_node_or_null("/root/AudioManager")
	if offset > STATION_RADIUS:
		end_attempt("MISSED THE PORT", "The spacecraft passed %.1f m off the docking axis, beside the station instead of onto the port." % offset)
		return
	if offset > PORT_STRUCTURE:
		if audio:
			audio.play_effect("crash", -4.0)
		end_attempt("COLLISION", "The spacecraft hit the station %.2f m off center, outside the docking ring. In real life this is what the abort rules exist to prevent." % offset)
		return
	var problems = []
	if offset > capture_offset:
		problems.append("%d cm off center (the ring takes %d)" % [int(round(offset * 100)), int(round(capture_offset * 100))])
	if angle > capture_angle:
		problems.append("%.1f° crooked (the ring takes %d°)" % [angle, int(capture_angle)])
	if closing > FASTEST_CONTACT:
		problems.append("%.2f m/s, too fast (under %.2f)" % [closing, FASTEST_CONTACT])
	elif closing < SLOWEST_CONTACT:
		problems.append("%.3f m/s, too slow to push the latches home" % closing)
	if sideways > FASTEST_SIDEWAYS:
		problems.append("sliding sideways at %.2f m/s" % sideways)
	if audio:
		audio.play_effect("clank", -4.0)
	if not problems.is_empty():
		end_attempt("NO CAPTURE", "The rings touched but didn't latch: %s. The spacecraft bounced back off the port." % ", ".join(problems))
		return
	# Docked: score it
	var speed_points = 15.0
	if closing < 0.03:
		speed_points *= (closing - SLOWEST_CONTACT) / 0.01
	elif closing > 0.10:
		speed_points *= 1.0 - (closing - 0.10) / (FASTEST_CONTACT - 0.10)
	var centering_points = 15.0 * (1.0 - offset / capture_offset)
	var lined_up_points = 10.0 * (1.0 - angle / capture_angle)
	var left_share = max(propellant_budget - propellant_used, 0.0) / propellant_budget
	var propellant_points = 10.0 * clamp((left_share - 0.2) / 0.5, 0.0, 1.0)
	var parts = {"docked": 50, "speed": int(round(clamp(speed_points, 0.0, 15.0))), "centering": int(round(clamp(centering_points, 0.0, 15.0))),
		"lined_up": int(round(clamp(lined_up_points, 0.0, 10.0))), "propellant": int(round(propellant_points))}
	var score = parts["docked"] + parts["speed"] + parts["centering"] + parts["lined_up"] + parts["propellant"]
	if audio:
		audio.play_effect("latch", -2.0, 1.0, 0.5)
		audio.play_effect("jingle_success", -6.0, 1.0, 1.2)
	var medal = null
	for entry in MEDALS:
		if score >= entry[0]:
			medal = entry
			break
	if sample_return:
		finish_sample_return(score, medal, closing, offset, angle)
		return
	var research = record_best(score, medal)
	if medal and medal[1] == "GOLD":
		GameState.award_achievement("ace_pilot")
	result_title.text = ("%s · DOCKED · %d / 100" % [medal[1], score]) if medal else "DOCKED · %d / 100" % score
	result_title.add_theme_color_override("font_color", medal[2] if medal else Color(0.75, 0.9, 1.0))
	result_text.text = "Soft capture, then hard capture: the latches pulled the rings together.\nContact at %.3f m/s, %d cm off center, %.1f° off, after %d:%02d.\n\nSpeed %d/15 · centered %d/15 · lined up %d/10 · propellant %d/10%s" % [
		closing, int(round(offset * 100)), angle, int(clock) / 60, int(clock) % 60,
		parts["speed"], parts["centering"], parts["lined_up"], parts["propellant"],
		("\n+%d research points!" % research) if research > 0 else "\nYour best: %d." % GameState.career.get("docking_best", score)]
	show_result()
	if research > 0:
		GameState.show_toast("%s docking" % medal[1].capitalize(), "Docked at the Space Station. +%d research points." % research, "research")
	print("DOCKING %s" % [{"score": score, "parts": parts, "closing": closing, "offset": offset, "angle": angle, "seconds": clock}])

func end_attempt(title, text):
	running = false
	finished = true
	result_title.text = title
	result_title.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	if sample_return:
		attempts_left -= 1
		if attempts_left > 0:
			result_text.text = text + "\n\nThe ascent stage backed off safely and has propellant for one more approach."
			again_button.text = "Try again (last approach)"
			done_button.text = "Give up on the samples"
		else:
			result_text.text = text + "\n\nThat was the last of the ascent stage's propellant. The samples drift away in orbit, but the rest of your mission carries on."
			again_button.visible = false
			done_button.text = "Continue the mission"
	else:
		result_text.text = text + "\n\nNo harm done: this is the trainer. Try again?"
	reticle.flash = 1.0
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_effect("jingle_failure", -6.0, 1.0, 0.4)
	show_result()
	print("DOCKING FAILED %s: %s" % [title, text])

func show_result():
	finished = true
	status_label.text = ""
	result_box.visible = true
	UiMotion.pop_in(result_box, 0.0, 0.5)
	UiMotion.stamp(result_title, 0.25)

# Sample return docked: the samples move into the orbiter's return capsule
func finish_sample_return(score, medal, closing, offset, angle):
	if medal and medal[1] == "GOLD":
		GameState.note_gold_medal()
	result_title.text = "SAMPLES SECURED  ·  %d / 100" % score
	result_title.add_theme_color_override("font_color", medal[2] if medal else Color(0.5, 1.0, 0.7))
	result_text.text = "Capture! The canister is inside the orbiter's return capsule, heading home.\nContact at %.3f m/s, %d cm off center, %.1f° off.\nA gentler, cleaner docking keeps more of the samples in perfect condition: the better your score, the more science they're worth." % [closing, int(round(offset * 100)), angle]
	again_button.visible = false
	done_button.text = "Bring them home"
	return_result = {"docked": true, "score": score}
	show_result()

# Personal best and research points (only for beating your best medal)
func record_best(score, medal):
	var previous_best = GameState.career.get("docking_best", 0)
	var research = 0
	if medal and score > previous_best:
		var previous_points = 0
		for entry in MEDALS:
			if previous_best >= entry[0]:
				previous_points = entry[3]
				break
		research = max(medal[3] - previous_points, 0)
	GameState.career["docking_best"] = max(previous_best, score)
	var by_target = GameState.career.get("docking_targets", {})
	by_target[target] = max(by_target.get(target, 0), score)
	GameState.career["docking_targets"] = by_target
	GameState.career["research"] = GameState.career.get("research", 0) + research
	Career.save_data(GameState.career)
	return research
