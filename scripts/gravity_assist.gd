extends Control

# MINIGAME: GRAVITY-ASSIST PLANNING (res://scenes/gravity_assist.tscn)
# Instead of a huge rocket flying straight to a far world, send the spacecraft past a nearer planet and let that
# planet's gravity bend its path and change its speed, the way Galileo, Cassini and Juno got to Jupiter and
# Saturn on smaller rockets. Pick the flyby planet, then plan the pass: how close to fly, which side to pass on,
# and (if needed) a small engine burn at the closest point. The map shows the orbit it sends you on; it has to
# reach the destination's orbit (the gold ring).
#
# What it does for the mission (GameState.gravity_assist): your rocket only has to reach the flyby planet
# (less launch speed), the trip takes longer, and any burn comes out of your spacecraft's own fuel.
# The physics is in scripts/flyby_physics.gd. Each planning session draws a new arrival (launch window).
#
# Keys: A/D pass height, F switch side, W/S burn, Q/E flyby planet, Space execute, N new window, Esc close.
# The rocket builder opens this with open_planner(); closing it sends closed.

signal closed

const FlybyPhysics = preload("res://scripts/flyby_physics.gd")
const RocketData = preload("res://scripts/rocket_data.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const Career = preload("res://scripts/career.gd")
const SpaceTextures = preload("res://scripts/space_textures.gd")
const TITLE_CARD_SCENE = preload("res://scenes/title_card.tscn")
const AU_KM = 149597870.7
# Launch speed (m/s) to reach each flyby planet, worked out from real launch energies: Cassini (Venus route) needed
# a launch energy of about 16.6 km²/s², Juno (Earth route, with a burn far out to come back) about 31.
const ROUTE_SPEED = {"Venus": 13300, "Earth": 14100, "Mars": 13000, "Jupiter": 15700}
# How the trip's length changes with each route (years; Jupiter flybys shorten trips to the outer planets: New
# Horizons arrived at Pluto about 3 years sooner thanks to Jupiter)
const ROUTE_YEARS = {"Venus": 1.6, "Earth": 2.0, "Mars": 1.0, "Jupiter": -0.25}
const MEDALS = [[85, "GOLD", Color(1.0, 0.82, 0.35), 15], [65, "SILVER", Color(0.8, 0.85, 0.92), 8], [40, "BRONZE", Color(0.85, 0.55, 0.35), 4]]

@onready var map: Control = $Layout/Middle/Map
@onready var closeup: Control = $Layout/Right/Closeup
@onready var goal_label: Label = $Layout/LeftScroll/Left/Goal
@onready var planet_picker: OptionButton = $Layout/LeftScroll/Left/PlanetPicker
@onready var planet_note: Label = $Layout/LeftScroll/Left/PlanetNote
@onready var altitude_label: Label = $Layout/LeftScroll/Left/AltitudeValue
@onready var altitude_slider: HSlider = $Layout/LeftScroll/Left/Altitude
@onready var side_button: Button = $Layout/LeftScroll/Left/SideButton
@onready var burn_label: Label = $Layout/LeftScroll/Left/BurnValue
@onready var burn_slider: HSlider = $Layout/LeftScroll/Left/Burn
@onready var execute_button: Button = $Layout/LeftScroll/Left/Buttons/ExecuteButton
@onready var window_button: Button = $Layout/LeftScroll/Left/Buttons/WindowButton
@onready var readouts: Label = $Layout/Right/Readouts
@onready var result_box: PanelContainer = $Layout/Right/Result
@onready var result_title: Label = $Layout/Right/Result/Column/Title
@onready var result_text: Label = $Layout/Right/Result/Column/Text
@onready var title_label: Label = $Header/Title
@onready var steps_label: Label = $Layout/LeftScroll/Left/Steps
@onready var reach_meter: Control = $Layout/Right/Reach
@onready var keys_row: Control = $Layout/LeftScroll/Left/KeyHints
@onready var closeup_disc: TextureRect = $Layout/Right/Closeup/PlanetDisc
@onready var map_disc: TextureRect = $Layout/Middle/Map/FlybyDisc

var destination = "Jupiter"
var target_radius = 5.2 * AU_KM
var going_inward = false        # Mercury: the flyby has to slow the spacecraft down instead
var options = []
var flyby_planet = "Venus"
var planet = []                 # FLYBY_PLANETS entry
var planet_radius_orbit = 0.0   # km from the Sun
var v_infinity = 6.0            # km/s
var incoming_angle = 0.0        # direction of v∞ coming in, measured from the planet's direction of motion
var side = 1.0
var result_orbit = {}
var reaches = false
var planned = false
var touched_height = false      # (for the step list: has the player set the pass height yet?)
var touched_side = false
var animating = false           # the flyby plays out on the map after Execute

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Header/CloseButton.pressed.connect(close)
	planet_picker.item_selected.connect(func(index): choose_planet(options[index]))
	altitude_slider.value_changed.connect(func(_value): preview())
	burn_slider.value_changed.connect(func(_value): preview())
	side_button.pressed.connect(switch_side)
	altitude_slider.drag_started.connect(func(): touched_height = true)
	window_button.pressed.connect(func(): new_window())
	$Layout/LeftScroll/Left/ClearButton.pressed.connect(clear_plan)
	execute_button.pressed.connect(execute)
	result_box.visible = false

func open_planner():
	get_viewport().gui_release_focus()
	destination = GameState.destination
	target_radius = GameState.DESTINATIONS.get(destination, {}).get("distance_from_sun_au", 5.2) * AU_KM
	going_inward = target_radius < 0.7 * AU_KM
	var candidates = []
	if going_inward:
		candidates = ["Venus", "Earth"]
	elif target_radius > 1.7 * AU_KM:
		candidates = ["Venus", "Earth", "Mars"]
		if target_radius > 6.0 * AU_KM:
			candidates.append("Jupiter")
	# Only routes that ask less of the rocket than flying straight there, through planets that can bend the path
	# far enough on their own (one Venus flyby can't reach Jupiter: Cassini needed Venus twice, then Earth)
	options = []
	var too_weak = []
	for candidate in candidates:
		if ROUTE_SPEED[candidate] >= RocketData.SPEED_NEEDED.get(destination, 0):
			continue
		set_planet_values(candidate)
		if search_window(400):
			options.append(candidate)
		else:
			too_weak.append(candidate)
	planet_picker.clear()
	for option in options:
		planet_picker.add_item("%s flyby   (rocket needs %s m/s instead of %s)" % [option, format_number(ROUTE_SPEED[option]), format_number(RocketData.SPEED_NEEDED.get(destination, 0))])
	var label = SolarSystemData.BODIES.get(destination, {}).get("label", destination)
	title_label.text = "GRAVITY-ASSIST PLANNER  ·  TO %s" % label.to_upper()
	if options.is_empty():
		goal_label.text = "%s is close enough that flying straight there is best. Gravity assists pay off for the far planets (and for slowing down to reach Mercury)." % label
		execute_button.disabled = true
		window_button.disabled = true
		readouts.text = ""
		return
	if going_inward:
		goal_label.text = "Swing past a planet to slow down enough to fall in to %s's orbit (the gold ring), without falling far closer to the Sun." % label
	else:
		goal_label.text = "Swing past a planet to speed up enough to reach %s's orbit (the gold ring), without flying far past it: arriving fast means a bigger braking burn." % label
	if not too_weak.is_empty():
		goal_label.text += " (%s can't do it alone.)" % " or ".join(too_weak)
	choose_planet(options[0])
	UiMotion.reveal_text(title_label, 0.1, 0.7, 0.4)
	UiMotion.stagger([$Layout/LeftScroll, $Layout/Middle, $Layout/Right], 0.1, 0.08, Vector2(0, 20), 0.6)

func close():
	closed.emit()
	queue_free()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func set_planet_values(planet_name):
	flyby_planet = planet_name
	planet = FlybyPhysics.FLYBY_PLANETS[planet_name]
	planet_radius_orbit = planet[0] * AU_KM

func switch_side():
	side = -side
	touched_side = true
	preview()

# Keys: the discrete ones here (they also stop the menus underneath from reacting), held ones in _process
func _input(event):
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			close()
		KEY_F:
			if not animating and not options.is_empty():
				switch_side()
		KEY_SPACE, KEY_ENTER:
			if not animating and not execute_button.disabled:
				execute()
		KEY_N:
			if not animating and not options.is_empty():
				new_window()
		KEY_Q, KEY_E:
			if not animating and options.size() > 1:
				var index = wrapi(options.find(flyby_planet) + (1 if event.keycode == KEY_E else -1), 0, options.size())
				planet_picker.selected = index
				choose_planet(options[index])
		_:
			if not event.keycode in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
				return
	get_viewport().set_input_as_handled()

func _process(delta):
	if options.is_empty() or animating or planet.is_empty():
		return
	var height_keys = (1.0 if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) else 0.0)
	var burn_keys = (1.0 if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) else 0.0) - (1.0 if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) else 0.0)
	var fine = 0.25 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	if height_keys != 0.0:
		touched_height = true
		altitude_slider.value = clamp(altitude_slider.value + height_keys * 0.3 * fine * delta, 0.0, 1.0)
	if burn_keys != 0.0 and burn_slider.editable:
		burn_slider.value = clamp(burn_slider.value + burn_keys * 0.3 * fine * delta, 0.0, burn_slider.max_value)
	keys_row.light_key("A", height_keys < 0.0)
	keys_row.light_key("D", height_keys > 0.0)
	keys_row.light_key("W", burn_keys > 0.0)
	keys_row.light_key("S", burn_keys < 0.0)

func choose_planet(planet_name):
	set_planet_values(planet_name)
	planet_note.text = planet[4]
	var map_texture = SpaceTextures.find_texture(SolarSystemData.BODIES.get(planet_name, {}).get("images", []))
	closeup_disc.texture = map_texture if map_texture else PlaceholderTexture2D.new()
	map_disc.texture = closeup_disc.texture
	closeup.planet_disc = closeup_disc
	map.planet_disc = map_disc
	map.flyby_planet = planet_name
	map.flyby_radius_km = planet_radius_orbit
	map.target_radius_km = target_radius
	map.target_name = SolarSystemData.BODIES.get(destination, {}).get("label", destination)
	map.span_km = max(target_radius, planet_radius_orbit) * 1.12
	closeup.planet_radius_km = planet[2]
	closeup.planet_color = SolarSystemData.BODIES.get(planet_name, {}).get("color", Color(0.8, 0.75, 0.6))
	# The closest pass: from the lowest safe height up to far away (a log scale, so both ends are easy to set)
	altitude_slider.min_value = 0.0
	altitude_slider.max_value = 1.0
	altitude_slider.step = 0.001
	var most_burn = clamp(GameState.probe_speed_change_km_s() - GameState.base_arrival_burn_km_s(), 0.0, 1.5)
	burn_slider.max_value = snapped(max(most_burn, 0.0), 0.01)
	burn_slider.step = 0.01
	burn_slider.editable = most_burn > 0.0
	new_window()

func altitude_km():
	var lowest = planet[3]
	var highest = planet[2] * (40.0 if flyby_planet == "Jupiter" else 12.0)
	return lowest * pow(highest / lowest, altitude_slider.value)

# A new arrival at the flyby planet (a different launch window): a v∞ and approach direction that can reach the
# destination with a well-planned pass, but not without one
func new_window():
	planned = false
	result_box.visible = false
	execute_button.disabled = false
	execute_button.text = "Execute flyby"
	search_window(400)
	side = 1.0 if randf() < 0.5 else -1.0
	altitude_slider.value = 0.6
	burn_slider.value = 0.0
	preview()

# Draws arrivals until one needs a planned pass to work: flying straight on misses, but the best pass reaches
# (with some spare on easier difficulties). Returns false if none turned up (this planet is too weak for the trip).
func search_window(attempts):
	var low = {"Venus": 5.0, "Earth": 6.5, "Mars": 4.0, "Jupiter": 8.0}[flyby_planet]
	var high = {"Venus": 9.0, "Earth": 10.0, "Mars": 6.5, "Jupiter": 12.0}[flyby_planet]
	var margin = [1.12, 1.06, 1.02][clamp(GameState.difficulty, 0, 2)]
	for attempt in attempts:
		v_infinity = randf_range(low, high)
		incoming_angle = randf_range(-PI, PI)
		if not reaches_target(outcome(0.0, 0.0, 1.0, planet[3])) and reaches_target(best_possible(), margin):
			return true
	return false

# The best orbit any pass could give (closest safe pass, either side, no burn)
func best_possible():
	var best = {}
	for turn_side in [1.0, -1.0]:
		var bend = FlybyPhysics.bend_angle(v_infinity, planet[2] + planet[3], planet[1])
		var orbit = outcome(bend, 0.0, turn_side, planet[3])
		if best.is_empty() or better(orbit, best):
			best = orbit
	return best

func better(orbit, other):
	if going_inward:
		return orbit["periapsis"] < other["periapsis"]
	return orbit["apoapsis"] > other["apoapsis"]

func reaches_target(orbit, margin := 1.0):
	if orbit.is_empty():
		return false
	if going_inward:
		return orbit["periapsis"] <= target_radius / margin
	return orbit["escapes"] or orbit["apoapsis"] >= target_radius * margin

# The orbit around the Sun after a pass that bends v∞ by bend (radians) toward turn_side, with a burn (km/s)
func outcome(bend, burn, turn_side, altitude := -1.0):
	var planet_speed = FlybyPhysics.circular_speed(planet_radius_orbit)
	var forward = Vector2(0, 1)    # the planet moves "up" at the right of the Sun on the map
	var outward = Vector2(1, 0)
	var direction_in = forward.rotated(-incoming_angle)
	var direction_out = direction_in.rotated(bend * turn_side)
	var closest = planet[2] + (altitude if altitude >= 0.0 else altitude_km())
	var v_out = FlybyPhysics.v_infinity_after_burn(v_infinity, closest, planet[1], burn) if burn > 0.0 else v_infinity
	var velocity = forward * planet_speed + direction_out * v_out
	var orbit = FlybyPhysics.sun_orbit(outward * planet_radius_orbit, velocity)
	orbit["direction_in"] = direction_in
	orbit["direction_out"] = direction_out
	orbit["speed_before"] = (forward * planet_speed + direction_in * v_infinity).length()
	orbit["speed_after"] = velocity.length()
	return orbit

func preview():
	if planet.is_empty():
		return
	var closest = planet[2] + altitude_km()
	var bend = FlybyPhysics.bend_angle(v_infinity, closest, planet[1])
	result_orbit = outcome(bend, burn_slider.value, side)
	reaches = reaches_target(result_orbit)
	# The map: the path in (backwards from the planet) and the path out
	var planet_speed = FlybyPhysics.circular_speed(planet_radius_orbit)
	var incoming_orbit = FlybyPhysics.sun_orbit(Vector2(planet_radius_orbit, 0), Vector2(0, planet_speed) + result_orbit["direction_in"] * v_infinity)
	var backwards = incoming_orbit.duplicate()
	backwards["angular_momentum"] = -incoming_orbit["angular_momentum"]
	map.path_in = FlybyPhysics.orbit_points(backwards, 0.0, PI * 0.8, 80, map.span_km * 1.2)
	map.path_out = FlybyPhysics.orbit_points(result_orbit, 0.0, TAU * 0.98, 160, map.span_km * 1.2)
	map.reaches = reaches
	closeup.closest_km = closest
	closeup.incoming_direction = result_orbit["direction_in"]
	closeup.outgoing_direction = result_orbit["direction_out"]
	closeup.planet_motion = Vector2(0, 1)
	altitude_label.text = "Closest pass: %s km above %s" % [format_number(altitude_km()), "the cloud tops" if flyby_planet in ["Venus", "Jupiter"] else "the ground"]
	side_button.text = "Swing: %s  (F to switch)" % ("counterclockwise" if side > 0 else "clockwise")
	burn_label.text = "Engine burn at the closest point: %.2f km/s%s" % [burn_slider.value, "" if burn_slider.editable else "  (no spare fuel)"]
	var lines = [
		"ARRIVAL SPEED (v∞)   %.2f km/s" % v_infinity,
		"BEND ANGLE (δ)       %.1f°" % rad_to_deg(bend),
		"SPEED FROM THE SUN   %.2f → %.2f km/s" % [result_orbit["speed_before"], result_orbit["speed_after"]],
		"CHANGE               %s%.2f km/s" % ["+" if result_orbit["speed_after"] >= result_orbit["speed_before"] else "", result_orbit["speed_after"] - result_orbit["speed_before"]],
	]
	if going_inward:
		lines.append("CLOSEST TO THE SUN   %.2f AU (need %.2f)" % [result_orbit["periapsis"] / AU_KM, target_radius / AU_KM])
	else:
		lines.append("FARTHEST FROM SUN    %s (need %.2f AU)" % ["escapes the Sun" if result_orbit["escapes"] else "%.2f AU" % (result_orbit["apoapsis"] / AU_KM), target_radius / AU_KM])
	if reaches:
		var past = overshoot()
		lines.append("ON TARGET            %s" % ("yes" if past <= 0.25 else "%d%% past (arrives fast)" % int(round(past * 100.0)) if past < 8.0 else "far past it"))
	lines.append("")
	lines.append("REACHES %s" % map.target_name.to_upper() if reaches else "FALLS SHORT: try the other side, a closer pass, or a burn")
	readouts.text = "\n".join(lines)
	# "Does it reach?" and the step list
	reach_meter.target_au = target_radius / AU_KM
	reach_meter.start_au = planet_radius_orbit / AU_KM
	reach_meter.going_inward = going_inward
	reach_meter.escapes = result_orbit["escapes"]
	reach_meter.reach_au = (result_orbit["periapsis"] if going_inward else (result_orbit["apoapsis"] if not result_orbit["escapes"] else target_radius * 2.0)) / AU_KM
	reach_meter.reaches = reaches
	reach_meter.on_target = reaches and overshoot() <= 0.25
	update_steps()
	readouts.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8) if reaches else Color(1.0, 0.8, 0.75))

# The step list on the left: what to do next, ticked off as you go
func update_steps():
	var label = map.target_name
	var steps = [
		[true, "Pick a planet (Q E)"],
		[touched_height, "Set the pass height (A D)"],
		[touched_side, "Pick the swing side (F)"],
		[reaches, "Reach %s's gold ring" % label],
		[reaches and overshoot() <= 0.25, "Don't overshoot it much"],
		[planned, "Execute (Space)"],
	]
	var lines = []
	var current_marked = false
	for index in steps.size():
		var done = steps[index][0]
		var marker = "✓" if done else ("▶" if not current_marked else "·")
		if not done and not current_marked:
			current_marked = true
		lines.append("%s  %s" % [marker, steps[index][1]])
	steps_label.text = "\n".join(lines)

# How far past the destination's orbit the new orbit goes (0 = just reaches it). Overshooting means arriving fast,
# so the spacecraft needs a bigger braking burn. Escaping the solar system is fine for the far worlds (New
# Horizons did, on its way to Pluto).
func overshoot():
	if going_inward:
		return target_radius / max(result_orbit["periapsis"], 1.0) - 1.0
	if result_orbit["escapes"]:
		return 0.0 if target_radius > 25.0 * AU_KM else 9.0
	return result_orbit["apoapsis"] / target_radius - 1.0

# The score: reaching the destination 60, saving the spacecraft's fuel 25, landing on target (not far past) 15
func plan_score():
	if not reaches:
		var share = target_radius / max(result_orbit["periapsis"], 1.0) if going_inward else result_orbit["apoapsis"] / target_radius
		return {"reach": int(round(30.0 * clamp(share, 0.0, 1.0))), "fuel": 0, "accuracy": 0}
	var fuel = 25
	if burn_slider.value > 0.0:
		fuel = int(round(25.0 * (1.0 - clamp(burn_slider.value / max(burn_slider.max_value, 0.01), 0.0, 1.0)) * 0.8))
	var accuracy = int(round(15.0 * clamp(1.0 - (overshoot() - 0.25) / 1.25, 0.0, 1.0)))
	return {"reach": 60, "fuel": fuel, "accuracy": accuracy}

func clear_plan():
	GameState.gravity_assist = {}
	result_title.text = "DIRECT ROUTE"
	result_title.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	result_text.text = "No gravity assist: your rocket has to throw the spacecraft all the way, %s m/s." % format_number(RocketData.SPEED_NEEDED.get(destination, 0))
	result_box.visible = true
	UiMotion.pop_in(result_box, 0.0, 0.4)

# The flyby plays out: the spacecraft comes in along its path, swings past the planet (the close-up), and heads
# off on its new orbit toward the gold ring
func play_flyby():
	animating = true
	execute_button.disabled = true
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_effect("whoosh", -6.0)
	map.travel = 0.0
	closeup.travel = 0.0
	var motion = create_tween()
	motion.tween_property(map, "travel", 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	motion.tween_property(closeup, "travel", 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(map, "travel", 2.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await motion.finished
	var card = TITLE_CARD_SCENE.instantiate()
	add_child(card)
	card.play("%s FLYBY" % flyby_planet.to_upper(), ("Reaches %s" % map.target_name) if reaches else "Falls short of %s" % map.target_name,
		Color(0.5, 1.0, 0.7) if reaches else Color(1.0, 0.55, 0.45), 1.4)
	animating = false
	execute_button.disabled = false
	map.travel = -1.0
	closeup.travel = -1.0

# Lock in the plan, score it, and tell the mission
func execute():
	if planned:
		new_window()
		return
	planned = true
	await play_flyby()
	var parts = plan_score()
	var score = parts["reach"] + parts["fuel"] + parts["accuracy"]
	var medal = null
	for entry in MEDALS:
		if score >= entry[0]:
			medal = entry
			break
	# Tell the mission: the rocket only has to reach the flyby planet; the trip gets longer; the burn uses the
	# spacecraft's own fuel
	if reaches:
		GameState.gravity_assist = {
			"destination": destination, "planet": flyby_planet, "launch_speed_needed": ROUTE_SPEED[flyby_planet],
			"extra_years": ROUTE_YEARS[flyby_planet] if ROUTE_YEARS[flyby_planet] > 0.0 else GameState.DESTINATIONS[destination]["trip_years"] * ROUTE_YEARS[flyby_planet],
			"probe_burn_km_s": burn_slider.value, "score": score,
		}
	# (a plan that misses doesn't replace an earlier one that worked)
	# Research points for a medal beating your best on this destination
	var plans = GameState.career.get("assist_plans", {})
	var previous_best = plans.get(destination, 0)
	var research = 0
	if medal and score > previous_best:
		var previous_points = 0
		for entry in MEDALS:
			if previous_best >= entry[0]:
				previous_points = entry[3]
				break
		research = max(medal[3] - previous_points, 0)
	plans[destination] = max(previous_best, score)
	GameState.career["assist_plans"] = plans
	GameState.career["research"] = GameState.career.get("research", 0) + research
	Career.save_data(GameState.career)
	result_title.text = ((medal[1] + " PLAN  ·  %d / 100") % score) if medal and reaches else "NO GOOD  ·  %d / 100" % score
	result_title.add_theme_color_override("font_color", medal[2] if medal and reaches else Color(1.0, 0.5, 0.45))
	var breakdown = "Reaching %s %d/60 · fuel saved %d/25 · on target %d/15" % [map.target_name, parts["reach"], parts["fuel"], parts["accuracy"]]
	if reaches:
		result_text.text = breakdown + "\nYour rocket now only needs %s m/s (instead of %s), and the trip takes %s.%s\n%s" % [
			format_number(ROUTE_SPEED[flyby_planet]), format_number(RocketData.SPEED_NEEDED.get(destination, 0)),
			("%.1f years longer" % GameState.gravity_assist["extra_years"]) if GameState.gravity_assist["extra_years"] > 0.0 else ("%.1f years less" % -GameState.gravity_assist["extra_years"]),
			("  The %.2f km/s burn comes out of your spacecraft's fuel." % burn_slider.value) if burn_slider.value > 0.0 else "",
			("+%d research points!" % research) if research > 0 else "Best plan for this destination: %d." % max(previous_best, score)]
	else:
		result_text.text = breakdown + "\nThis pass doesn't reach %s. %s" % [map.target_name,
			"Your earlier %s plan still stands." % GameState.gravity_assist["planet"] if GameState.assist_planned() else "The mission keeps the direct route. Try another plan or window."]
	execute_button.text = "Try another window"
	result_box.visible = true
	UiMotion.pop_in(result_box, 0.0, 0.5)
	UiMotion.stamp(result_title, 0.25)
	if medal and reaches and medal[1] == "GOLD":
		GameState.award_achievement("gold_plan")
	if research > 0:
		GameState.show_toast("%s plan" % medal[1].capitalize(), "%s flyby to %s. +%d research points." % [flyby_planet, map.target_name, research], "research")

static func format_number(number):
	var digits = str(int(round(number)))
	var result = ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return digits + result
