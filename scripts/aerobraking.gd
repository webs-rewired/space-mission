extends Control

# MINIGAME: AEROBRAKING (res://scenes/aerobraking.tscn)
# An orbiter arriving at Mars or Venus is caught in a long, stretched orbit. Burning the engine all the way down to
# a low mapping orbit would take a lot of propellant, so real orbiters dip into the very top of the atmosphere at
# their lowest point on each orbit and let the air drag them slower, a little at a time: aerobraking.
# Magellan did it first, at Venus in 1993, over about 70 days; Mars Global Surveyor, Mars Odyssey and Mars
# Reconnaissance Orbiter (2006, about five months) did it at Mars.
#
# HOW IT PLAYS: the navigators choose the lowest point of the orbit (the periapsis altitude) and the spacecraft flies
# a week of orbits there (4 days at Venus). Lower means denser air: more braking each pass, but more heating of the
# solar panels. The air changes from day to day, and at Mars a dust storm can warm and puff up the upper air within
# days (one did, during Mars Global Surveyor's aerobraking in 1997). Heat a pass past the limit and the spacecraft
# protects itself (safe mode and a "pop-up" burn to a higher periapsis), losing days. Bring the farthest point (the
# apoapsis) down to the mapping orbit before the deadline (solar conjunction at Mars, when the Sun blocks the radio
# link) without overheating three times.
#
# THE MODEL (approximate, for the game):
#   air density at the periapsis   ρ = ρref · exp(−(h − href) / H) · weather    (H is the upper atmosphere's scale height)
#   braking on each pass          Δv = K · ρ · v      (drag ∝ ρv², over a pass that lasts ∝ 1/v)
#   heating on each pass          heat ∝ ρ · v³       (100% = the solar panels' limit)
# and after each pass the orbit is worked out exactly from the slower speed at the periapsis (vis-viva):
#   v² = μ (2/r − 1/a)
# Real orbits, gravity and sizes; the density scale, K and the weather are tuned so it takes about as long as the
# real campaigns did.
#
# SCORE (0-100): reaching the mapping orbit 50, days to spare up to 25, no overheats 25 (−10 each). Gold 85, silver
# 65, bronze 40, research points for each medal (in training: only for beating your best medal).
# Sends finished({"science", "score", "medal", "done", "days"}).

signal finished(result)

const Career = preload("res://scripts/career.gd")
const WORLDS = {
	"Mars": {"radius": 3389.5, "gm": 42828.0, "scale_height": 8.0, "reference_altitude": 110.0, "start_apoapsis": 40000.0,
		"start_periapsis": 300.0, "target_apoapsis": 500.0, "days": 150.0, "step_days": 7.0, "drag": 0.9, "dust": true, "weather_change": 0.1,
		"deadline": "solar conjunction (the Sun will block the radio link)", "color": Color(0.78, 0.42, 0.28), "air": Color(0.95, 0.6, 0.4),
		"real": "Mars Reconnaissance Orbiter aerobraked like this from March to August 2006, dipping into the upper air hundreds of times."},
	"Venus": {"radius": 6051.8, "gm": 324859.0, "scale_height": 4.5, "reference_altitude": 135.0, "start_apoapsis": 8500.0,
		"start_periapsis": 300.0, "target_apoapsis": 600.0, "days": 75.0, "step_days": 4.0, "drag": 0.28, "dust": false, "weather_change": 0.2,
		"deadline": "the start of the radar mapping cycle", "color": Color(0.9, 0.78, 0.5), "air": Color(1.0, 0.9, 0.6),
		"real": "NASA's Magellan was the first spacecraft ever to aerobrake, at Venus in 1993, lowering its orbit over about 70 days."},
}
const PERIAPSIS_SPEED = 6.0          # km per second while W or S is held (Shift: a quarter)
const MOST_OVERHEATS = 3
const POP_UP_KM = 6.0                # a safe-mode "pop-up" burn raises the periapsis this much
const SAFE_MODE_DAYS = 2.0
const MEDALS = [[85, "GOLD", Color(1.0, 0.82, 0.35), 6], [65, "SILVER", Color(0.8, 0.85, 0.92), 4], [40, "BRONZE", Color(0.85, 0.55, 0.35), 1]]

@onready var title_label: Label = $Header/Title
@onready var view: Control = $Body/View
@onready var brief_label: Label = $Body/Side/Column/Brief
@onready var readout_label: Label = $Body/Side/Column/Readout
@onready var periapsis_label: Label = $Body/Side/Column/Periapsis
@onready var forecast_label: Label = $Body/Side/Column/Forecast
@onready var status_label: Label = $Body/Side/Column/Status
@onready var fly_button: Button = $Body/Side/Column/FlyButton
@onready var result_label: Label = $Body/Side/Column/Result
@onready var continue_button: Button = $Body/Side/Column/ContinueButton

var world = "Mars"
var planet = {}
var apoapsis = 40000.0           # km above the surface
var periapsis = 300.0
var periapsis_setting = 120.0    # what the navigators have chosen for the next step
var day = 0.0
var weather = 1.0                # today's air density compared with normal
var storm_days_left = 0.0
var storm_strength = 1.0
var storm_age = 0.0              # days since the dust storm started (it takes about 3 days to reach full strength)
var overheats = 0
var passes = 0
var braking_done = 0.0           # km/s of braking done by the air
var reference_speed = 1.0        # the speed at the periapsis on the first dipping orbit (heating is 100% there)
var history = []                 # each step: {"heat", "apoapsis", "day", "overheat"}
var storm_warning = false        # a dust storm started during the last step (said once, after it)
var state = "planning"           # "planning", "flying", "done"
var score = 0
var medal_name = ""
var science = 0
var finished_ok = false
var training = false             # opened from the Training tab (research only for beating your best medal)
var inputs_override = {}         # (the automatic tests use this instead of the keyboard)

func _ready():
	continue_button.visible = false
	result_label.visible = false
	fly_button.pressed.connect(fly_step)
	continue_button.pressed.connect(_on_continue_pressed)

func held(key):
	if inputs_override.has(key):
		return inputs_override[key]
	return Input.is_key_pressed(key)

func start(world_name):
	get_viewport().gui_release_focus()
	world = world_name if WORLDS.has(world_name) else "Mars"
	planet = WORLDS[world]
	if training:
		continue_button.text = "Done"
		var close_button = Button.new()
		close_button.text = "Close (Esc)"
		close_button.focus_mode = Control.FOCUS_NONE
		close_button.custom_minimum_size = Vector2(110, 34)
		close_button.pressed.connect(queue_free)
		$Header.add_child(close_button)
	title_label.text = "AEROBRAKING  ·  %s" % world.to_upper()
	apoapsis = planet["start_apoapsis"]
	periapsis = planet["start_periapsis"]
	periapsis_setting = planet["reference_altitude"] + 1.5 * planet["scale_height"]   # (a safe, slow start: about 22% heating)
	reference_speed = periapsis_speed(planet["start_apoapsis"], planet["reference_altitude"])
	brief_label.text = "You're in a long orbit, %s km at the far end. Dip into the top of the air at the low end of each orbit and let drag shrink it to %s km, before %s. %s" % [
		format_km(apoapsis), format_km(planet["target_apoapsis"]), planet["deadline"], planet["real"]]
	view.set_up(planet)
	fly_button.text = "Fly %d days of orbits (SPACE)" % int(planet["step_days"])
	update_screen()
	UiMotion.reveal_text(title_label, 0.1, 0.6, 0.4)
	UiMotion.slide_in($Body/Side, 0.15, Vector2(30, 0), 0.5)

static func format_km(value):
	var whole = str(int(round(value)))
	var grouped = ""
	for index in whole.length():
		if index > 0 and (whole.length() - index) % 3 == 0:
			grouped += ","
		grouped += whole[index]
	return grouped

# ---------------------------------------------------------------------------
# The orbit
# ---------------------------------------------------------------------------
func periapsis_speed(apoapsis_km, periapsis_km):
	var near = planet["radius"] + periapsis_km
	var far = planet["radius"] + apoapsis_km
	return sqrt(planet["gm"] * (2.0 / near - 2.0 / (near + far)))

func period_hours(apoapsis_km, periapsis_km):
	var semi_major = (2.0 * planet["radius"] + apoapsis_km + periapsis_km) / 2.0
	return TAU * sqrt(pow(semi_major, 3) / planet["gm"]) / 3600.0

func density_share(altitude_km, weather_now):
	return exp(-(altitude_km - planet["reference_altitude"]) / planet["scale_height"]) * weather_now

# Heating on a pass, in % of the solar panels' limit
func heating(apoapsis_km, periapsis_km, weather_now):
	return 100.0 * density_share(periapsis_km, weather_now) * pow(periapsis_speed(apoapsis_km, periapsis_km) / reference_speed, 3)

# The day's air: it wanders from day to day (Venus's upper air changes more than Mars's, as Venus Express found),
# and at Mars a dust storm can puff the upper air up for a couple of weeks, building over about three days
func next_weather():
	weather = exp(log(weather) * 0.7 + randf_range(-planet["weather_change"], planet["weather_change"]))
	if planet["dust"]:
		if storm_days_left <= 0.0 and randf() < 0.012:
			storm_days_left = randf_range(10.0, 20.0)
			storm_strength = randf_range(1.7, 2.4)
			storm_age = 0.0
			storm_warning = true
		if storm_days_left > 0.0:
			storm_days_left -= 1.0
			storm_age += 1.0
	return forecast()

func forecast():
	if storm_days_left <= 0.0:
		return weather
	return weather * (1.0 + (storm_strength - 1.0) * min(storm_age / 3.0, 1.0))

# ---------------------------------------------------------------------------
# Playing
# ---------------------------------------------------------------------------
func _input(event):
	if not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if training and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		return
	if event.pressed and not event.echo and event.keycode == KEY_SPACE and state == "planning":
		fly_step()

func _process(delta):
	if state != "planning":
		return
	var change = (1.0 if held(KEY_W) else 0.0) - (1.0 if held(KEY_S) else 0.0)
	if change != 0.0:
		periapsis_setting = clamp(periapsis_setting + change * PERIAPSIS_SPEED * (0.25 if held(KEY_SHIFT) else 1.0) * min(delta, 0.05), planet["reference_altitude"] - 25.0, planet["reference_altitude"] + 80.0)
		update_screen()

# One step: the navigators' small burns at the far end put the periapsis where it was set, then the spacecraft flies
# a few days of orbits, each pass braking it a little (and heating it), with the weather changing every day
func fly_step():
	if state != "planning":
		return
	state = "flying"
	fly_button.disabled = true
	periapsis = periapsis_setting
	var step_end = day + planet["step_days"]
	var peak = 0.0
	var overheated = false
	var day_clock = 0.0
	var today = next_weather()
	var passes_before = passes
	var apoapsis_before = apoapsis
	while day < step_end and apoapsis > planet["target_apoapsis"]:
		var speed = periapsis_speed(apoapsis, periapsis)
		var heat = heating(apoapsis, periapsis, today)
		peak = max(peak, heat)
		if heat > 100.0:
			# Too hot: safe mode, and a pop-up burn to a higher, safer periapsis; days are lost recovering
			overheated = true
			overheats += 1
			periapsis += POP_UP_KM
			periapsis_setting = periapsis
			day += SAFE_MODE_DAYS
			break
		var braking = planet["drag"] * density_share(periapsis, today) * speed / 1000.0
		braking_done += braking
		var near = planet["radius"] + periapsis
		var slower = speed - braking
		var semi_major = 1.0 / (2.0 / near - slower * slower / planet["gm"])
		apoapsis = max(2.0 * semi_major - near - planet["radius"], periapsis)
		passes += 1
		var hours = period_hours(apoapsis, periapsis)
		day += hours / 24.0
		day_clock += hours / 24.0
		if day_clock >= 1.0:
			day_clock -= 1.0
			today = next_weather()
	history.append({"heat": peak, "apoapsis": apoapsis, "day": day, "overheat": overheated})
	view.history = history
	await view.animate_step(apoapsis_before, apoapsis, periapsis, passes - passes_before, peak, overheated)
	if overheated:
		play_sound("error")
		status_label.text = "OVERHEAT %d of %d: a pass went past the solar panels' limit. Safe mode and a pop-up burn to %d km; %d days lost." % [overheats, MOST_OVERHEATS, int(round(periapsis)), int(SAFE_MODE_DAYS)]
	elif storm_warning:
		storm_warning = false
		play_sound("error")
		status_label.text = "A dust storm is building on Mars! It heats the air and the upper atmosphere swells: expect up to twice the density at the low point. Raise it."
	else:
		status_label.text = "%d passes, hottest at %d%% of the limit. The far end came down from %s to %s km." % [passes - passes_before, int(round(peak)), format_km(apoapsis_before), format_km(apoapsis)]
		play_sound("select")
	if apoapsis <= planet["target_apoapsis"]:
		finish(true)
	elif overheats >= MOST_OVERHEATS:
		finish(false, "Three overheats: the team stopped aerobraking to protect the spacecraft and finished the job with the engine.")
	elif day >= planet["days"]:
		finish(false, "Out of time: %s has come. The rest of the way down is done with the engine, using propellant meant for later." % planet["deadline"].split(" (")[0])
	else:
		state = "planning"
		fly_button.disabled = false
	update_screen()

func update_screen():
	var heat_now = heating(apoapsis, periapsis_setting, forecast())
	var days_left = max(planet["days"] - day, 0.0)
	readout_label.text = "DAY            %d of %d\nFAR END        %s km  (goal %s km)\nORBIT PERIOD   %.1f hours\nAIR BRAKING    %d m/s so far\nOVERHEATS      %d of %d" % [
		int(day), int(planet["days"]), format_km(apoapsis), format_km(planet["target_apoapsis"]), period_hours(apoapsis, periapsis_setting), int(round(braking_done * 1000.0)), overheats, MOST_OVERHEATS]
	periapsis_label.text = "LOW POINT  %d km" % int(round(periapsis_setting))
	var storm = storm_days_left > 0.0
	var risk = "safe" if heat_now < 75.0 else ("close to the limit" if heat_now < 95.0 else "TOO HOT")
	forecast_label.text = "Air today: %.1f× normal%s\nExpected heating there: %d%% (%s). The air changes every day, so leave a margin." % [
		forecast(), "  (DUST STORM)" if storm else "", int(round(heat_now)), risk]
	forecast_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7) if heat_now < 75.0 else (Color(1.0, 0.85, 0.4) if heat_now < 95.0 else Color(1.0, 0.45, 0.4)))
	view.apoapsis = apoapsis
	view.periapsis = periapsis_setting if state == "planning" else periapsis
	view.heat_preview = heat_now
	view.days_left = days_left

func finish(reached, reason := ""):
	state = "done"
	finished_ok = reached
	fly_button.visible = false
	var spare = max(planet["days"] - day, 0.0)
	if reached:
		score = 50 + int(round(min(spare / planet["days"] * 100.0, 25.0))) + max(25 - 10 * overheats, 0)
	else:
		var progress = clamp((planet["start_apoapsis"] - apoapsis) / (planet["start_apoapsis"] - planet["target_apoapsis"]), 0.0, 1.0)
		score = int(round(10.0 + progress * 30.0)) + max(15 - 10 * overheats, 0)
	score = clamp(score, 0, 100)
	science = (8 if reached else 3) + int(round(score / 20.0))
	var medal = null
	for entry in MEDALS:
		if score >= entry[0]:
			medal = entry
			break
	var science_text = "" if training else " · +%d science" % science
	var reward = "%d / 100%s" % [score, science_text]
	if medal:
		medal_name = medal[1]
		var bests = GameState.career.get("aerobraking_best", {})
		var research = research_for(medal, bests.get(world, 0))
		GameState.career["research"] = GameState.career.get("research", 0) + research
		var new_best = score > bests.get(world, -1)
		bests[world] = max(bests.get(world, 0), score)
		GameState.career["aerobraking_best"] = bests
		Career.save_data(GameState.career)
		if medal[1] == "GOLD":
			GameState.note_gold_medal()
		reward = "%s · %d / 100%s%s · +%d research points" % [medal[1], score, " (new best!)" if new_best else "", science_text, research]
		if research > 0:
			GameState.show_toast("%s aerobraking" % medal[1].capitalize(), "+%d research points." % research, "research")
	if reached and overheats == 0:
		GameState.award_achievement("air_surfer")
	var opening = "Mapping orbit reached on day %d after %d passes through the air! Drag did %d m/s of braking for free: propellant that would have been burned is saved for the science mission." % [int(day), passes, int(round(braking_done * 1000.0))] if reached else reason
	result_label.text = "%s\n\n%s" % [opening, reward]
	result_label.visible = true
	continue_button.visible = true
	UiMotion.slide_in(result_label, 0.0, Vector2(0, 12), 0.4)
	play_sound("confirm" if reached else "glitch")
	print("AEROBRAKING %s" % [{"world": world, "reached": reached, "day": day, "passes": passes, "overheats": overheats, "score": score}])

# On a mission every medal earns its research points; in training only beating your best medal does
func research_for(medal, previous_best):
	if not training:
		return medal[3]
	var previous_points = 0
	for entry in MEDALS:
		if previous_best >= entry[0]:
			previous_points = entry[3]
			break
	return max(medal[3] - previous_points, 0)

func _on_continue_pressed():
	finished.emit({"science": science, "score": score, "medal": medal_name, "done": finished_ok, "days": day})
	queue_free()

func play_sound(sound_name):
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_effect(sound_name, -6.0)
