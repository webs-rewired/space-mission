extends Control

# MINIGAME: ORBITAL INSERTION (res://scenes/orbital_insertion.tscn)
# When the spacecraft arrives at its world it's going too fast for gravity to keep it: it's falling past on a
# hyperbola. You fire the engine against your motion as you swing past the closest point, so the world's
# gravity can catch you, and try to end up in the target orbit (the gold band) with fuel to spare.
#
# Real physics (scripts/orbit_physics.gd): the world's real GM, a real hyperbolic arrival, your spacecraft's
# real speed-change budget from the probe builder (the rocket equation: engine Isp, propellant, mass), and
# the Oberth effect for free (a burn at the closest point, where you're fastest, does the most).
# Simplified for the game, and said so on screen: the burn runs sped up (real insertion burns take 30 to 40
# minutes), the orbit is drawn flat (no inclination), and only the world's gravity counts.
#
# launch.gd opens this at the "Braking into orbit" event and waits for finished(result):
#   {"captured", "rating" ("excellent", "good", "rough", "missed"), "periapsis_km", "apoapsis_km",
#    "speed_change_used", "speed_change_available", "autopilot"}

signal finished(result)

const OrbitPhysics = preload("res://scripts/orbit_physics.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const SpaceTextures = preload("res://scripts/space_textures.gd")
const OrbitScience = preload("res://scripts/orbit_science.gd")
const OrbitView = preload("res://scripts/orbit_view.gd")
const SECONDS_FOR_PASS = 5.0        # real seconds to swing through the 60 degrees around the closest point
const BURN_SECONDS_FOR_NEEDED = 3.2 # real seconds of burning to change speed by the amount this world needs
const AIR_HEIGHT_KM = {"Mars": 125.0, "Venus": 250.0, "Titan": 700.0, "Jupiter": 1000.0, "Saturn": 1000.0, "Uranus": 1000.0, "Neptune": 1000.0, "Pluto": 100.0, "Triton": 50.0}

@onready var view: Control = $View
@onready var title_label: Label = $Panel/Column/Title
@onready var goal_label: Label = $Panel/Column/Goal
@onready var readouts: Label = $Panel/Column/Readouts
@onready var status_label: Label = $Panel/Column/Status
@onready var fuel_bar: ProgressBar = $Panel/Column/FuelRow/FuelBar
@onready var fuel_label: Label = $Panel/Column/FuelRow/FuelText
@onready var burn_button: Button = $Panel/Column/Buttons/BurnButton
@onready var autopilot_button: Button = $Panel/Column/Buttons/AutopilotButton
@onready var note_label: Label = $Panel/Column/Note
@onready var result_panel: PanelContainer = $ResultPanel
@onready var result_title: Label = $ResultPanel/Column/ResultTitle
@onready var result_text: Label = $ResultPanel/Column/ResultText
@onready var continue_button: Button = $ResultPanel/Column/ContinueButton

var mu = 42828.0
var world_radius = 3389.5
var target_periapsis = 3700.0
var target_apoapsis = 10000.0      # the farthest point of the planned orbit (what the planned burn gives)
var state = {"position": Vector2.ZERO, "velocity": Vector2.ZERO}
var speed_change_available = 1.0
var speed_change_used = 0.0
var burn_rate = 0.3                 # km/s of speed change per real second of burning
var warp_at_closest = 100.0         # sim seconds per real second at the closest point
var safety_floor = 3500.0           # the flight computer won't let the periapsis drop below this
var burning_by_key = false
var burning_by_button = false
var autopilot = false
var finished_flying = false
var passed_closest = false
var trail_timer = 0.0
var orbit = {}

func _ready():
	result_panel.visible = false
	burn_button.button_down.connect(func(): burning_by_button = true)
	burn_button.button_up.connect(func(): burning_by_button = false)
	autopilot_button.pressed.connect(func():
		autopilot = true
		autopilot_button.disabled = true
		autopilot_button.text = "Autopilot flying")
	continue_button.pressed.connect(_on_continue_pressed)

func start():
	get_viewport().gui_release_focus()
	var destination = GameState.destination
	var data = SolarSystemData.BODIES.get(destination, {})
	world_radius = data.get("radius_km", 1000.0)
	mu = OrbitScience.WORLDS.get(destination, {}).get("gm", data.get("mass_earths", 0.1) * OrbitPhysics.EARTH_MU)
	var altitude = OrbitScience.WORLDS.get(destination, {}).get("altitude", clamp(world_radius * 0.15, 100.0, 3000.0))
	target_periapsis = world_radius + altitude
	var air = AIR_HEIGHT_KM.get(destination, 0.0)
	safety_floor = world_radius + max(air, altitude * 0.3)
	speed_change_available = GameState.probe_speed_change_km_s()
	var needed = GameState.arrival_burn_needed_km_s()
	var arrival = OrbitPhysics.approach(mu, target_periapsis, needed, target_periapsis * 9.0)
	state["position"] = arrival["position"]
	state["velocity"] = arrival["velocity"]
	target_apoapsis = arrival["target_apoapsis"]
	burn_rate = max(needed, 0.25) / BURN_SECONDS_FOR_NEEDED
	var speed_at_closest = sqrt(arrival["speed_at_infinity"] * arrival["speed_at_infinity"] + 2.0 * mu / target_periapsis)
	warp_at_closest = (PI / 3.0) / (speed_at_closest / target_periapsis) / SECONDS_FOR_PASS
	# The view and the words
	view.world_radius = world_radius
	view.air_height = air
	view.target_periapsis = target_periapsis
	view.target_high = min(target_apoapsis, target_periapsis * 8.0)
	var map = SpaceTextures.find_texture(data.get("images", [])) if data.get("images", []).size() > 0 else null
	view.planet_disk.texture = map if map else PlaceholderTexture2D.new()
	view.planet_disk.material.set_shader_parameter("has_map", map != null)
	view.planet_disk.material.set_shader_parameter("tint", Color.WHITE if map else data.get("color", Color(0.6, 0.6, 0.6)))
	title_label.text = "ORBIT INSERTION  ·  %s" % data.get("label", destination).to_upper()
	goal_label.text = "You're falling past %s too fast for its gravity to keep you. Fire the engine against your motion as you swing past the closest point, so gravity can catch you. Aim for an orbit inside the gold rings, with fuel to spare." % data.get("label", destination)
	note_label.text = "Real numbers: %s's gravity (GM %s km³/s²) and your spacecraft's %.2f km/s of speed change. Sped up for the game: the real thing would be %s, and the orbit is drawn flat." % [data.get("label", destination), OrbitView.format_km(mu), speed_change_available, GameState.arrival_burn_time_text()]
	# The panel slides in and the title rises (scripts/ui_motion.gd)
	UiMotion.slide_in($Panel, 0.1, Vector2(40, 0), 0.6)
	UiMotion.reveal_text(title_label, 0.2, 0.7, 0.4)

func _input(event):
	if event is InputEventKey and event.keycode == KEY_SPACE and not event.echo:
		burning_by_key = event.pressed
		get_viewport().set_input_as_handled()

func _process(delta):
	if finished_flying or mu <= 0.0:
		return
	var distance = state["position"].length()
	var warp = warp_at_closest * clamp(pow(distance / target_periapsis, 1.5), 1.0, 80.0)
	var sim_seconds = delta * warp
	orbit = OrbitPhysics.orbit_of(state["position"], state["velocity"], mu)
	# Where it is compared with the closest point of its path: negative before, positive after
	var angle_from_closest = wrapf(atan2(state["position"].y, state["position"].x) - orbit["periapsis_angle"], -PI, PI) * sign(orbit["angular_momentum"])
	if angle_from_closest > 0.05:
		passed_closest = true
	var wants_burn = burning_by_key or burning_by_button
	if autopilot:
		# The autopilot burns around the closest point until the orbit is a tight one (or the fuel runs out)
		wants_burn = abs(angle_from_closest) < 0.55 and (not orbit["captured"] or orbit["apoapsis"] > target_apoapsis)
	var thrust = Vector2.ZERO
	var burning = wants_burn and speed_change_used < speed_change_available
	if burning:
		var change = min(burn_rate * delta, speed_change_available - speed_change_used)
		var new_velocity = state["velocity"] - state["velocity"].normalized() * change
		# The flight computer refuses a burn that would drop the closest point into the air or the ground
		var after = OrbitPhysics.orbit_of(state["position"], new_velocity, mu)
		if after["periapsis"] < safety_floor and (passed_closest or after["periapsis"] < orbit["periapsis"]):
			burning = false
			view.interlock_warning = 1.0
		else:
			state["velocity"] = new_velocity
			speed_change_used += change
	OrbitPhysics.step(state, mu, sim_seconds, thrust)
	view.interlock_warning = max(view.interlock_warning - delta, 0.0)
	trail_timer -= delta
	if trail_timer <= 0.0:
		trail_timer = 0.05
		view.trail.append(state["position"])
		if view.trail.size() > 400:
			view.trail.remove_at(0)
	# Zoom to fit the spacecraft and the target orbit
	var wanted_span = max(distance, target_periapsis * 2.2) * 1.25
	view.km_per_pixel = lerp(view.km_per_pixel, wanted_span / (min(view.size.x, view.size.y) * 0.5), min(1.0, delta * 3.0))
	view.craft_position = state["position"]
	view.craft_velocity = state["velocity"]
	view.orbit = orbit
	view.burning = burning
	update_readouts(distance, burning)
	# Done once it has swung well past the closest point, or is heading away far out
	var moving_out = state["position"].dot(state["velocity"]) > 0.0
	if passed_closest and not burning and (angle_from_closest > 1.7 or (moving_out and distance > target_periapsis * 5.0)):
		finish()

func update_readouts(distance, burning):
	var speed = state["velocity"].length()
	var escape_speed = sqrt(2.0 * mu / distance)
	var lines = []
	lines.append("ALTITUDE        %s km" % OrbitView.format_km(distance - world_radius))
	lines.append("SPEED           %.2f km/s" % speed)
	lines.append("ESCAPE SPEED    %.2f km/s here" % escape_speed)
	lines.append("CLOSEST POINT   %s km up" % OrbitView.format_km(orbit["periapsis"] - world_radius))
	lines.append("FARTHEST POINT  %s" % ("%s km up" % OrbitView.format_km(orbit["apoapsis"] - world_radius) if orbit["captured"] else "none: escaping"))
	lines.append("ECCENTRICITY    %.3f" % orbit["eccentricity"])
	readouts.text = "\n".join(lines)
	fuel_bar.value = 100.0 * (1.0 - speed_change_used / max(speed_change_available, 0.001))
	fuel_label.text = "%.2f of %.2f km/s left" % [speed_change_available - speed_change_used, speed_change_available]
	if orbit["captured"]:
		status_label.text = "CAPTURED by gravity" + ("  ·  burning" if burning else "")
		status_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	else:
		status_label.text = "ESCAPING: you'll fly past" + ("  ·  burning" if burning else "")
		status_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))

# How it went, and what it means for the mission
func finish():
	finished_flying = true
	var periapsis_height = orbit["periapsis"] - world_radius
	var rating = "missed"
	if orbit["captured"]:
		if orbit["apoapsis"] <= target_apoapsis * 1.35 and abs(orbit["periapsis"] - target_periapsis) <= (target_periapsis - world_radius) * 0.6:
			rating = "excellent"
		elif orbit["apoapsis"] <= target_apoapsis * 4.0:
			rating = "good"
		else:
			rating = "rough"
	var words = {
		"excellent": ["A PERFECT INSERTION", "Right into the planned orbit: your instruments get the close passes the mission was designed for."],
		"good": ["IN ORBIT", "Gravity caught you in a stretched orbit. Good enough for science."],
		"rough": ["BARELY CAPTURED", "Gravity only just caught you, in a huge looping orbit: you'll spend most of the time far away."],
		"missed": ["FLEW PAST", "Not enough speed was taken off, so the spacecraft escaped, like New Horizons at Pluto. It grabs what science it can on the way past."],
	}[rating]
	result_title.text = words[0]
	var numbers = "Closest point %s km up" % OrbitView.format_km(periapsis_height)
	if orbit["captured"]:
		numbers += ", farthest %s km up." % OrbitView.format_km(orbit["apoapsis"] - world_radius)
	else:
		numbers += "."
	result_text.text = "%s\n%s\nUsed %.2f of %.2f km/s.%s" % [words[1], numbers, speed_change_used, speed_change_available, "  (Autopilot)" if autopilot else ""]
	result_title.add_theme_color_override("font_color", {"excellent": Color(0.45, 1.0, 0.6), "good": Color(0.55, 0.85, 1.0), "rough": Color(1.0, 0.82, 0.4), "missed": Color(1.0, 0.5, 0.45)}[rating])
	result_panel.visible = true
	UiMotion.pop_in(result_panel, 0.1, 0.5)
	UiMotion.reveal_text(result_title, 0.25, 0.6, 0.4)
	set_meta("result", {"captured": orbit["captured"], "rating": rating, "periapsis_km": periapsis_height, "apoapsis_km": orbit["apoapsis"] - world_radius,
		"speed_change_used": speed_change_used, "speed_change_available": speed_change_available, "autopilot": autopilot})

func _on_continue_pressed():
	finished.emit(get_meta("result"))
	queue_free()
