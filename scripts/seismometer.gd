extends Control

# MINIGAME: SEISMIC STATION (res://scenes/seismometer.tscn)
# On Mars and the Moon, one of the rover's targets is a good spot for a seismometer, the instrument that listens
# for quakes. Opened from surface_view.gd like the Sample Lab.
#
# Real seismometers have listened on both: the Apollo astronauts set up seismometers that recorded thousands of
# moonquakes from 1969 to 1977, and NASA's InSight lander recorded more than 1,300 marsquakes from 2018 to 2022.
#
# 1. LEVEL: a seismometer must stand perfectly level. Adjust its legs (A D, W S; Shift for fine) until the bubble
#    sits in the green circle and hold it there. Apollo astronauts did this by hand, watching a bubble level;
#    InSight's SEIS leveled itself on motorized legs. On Mars, then lower the wind shield (SPACE): InSight covered
#    SEIS with a dome because the wind shook it.
# 2. LISTEN: the seismogram comes in (sped up). A quake sends two kinds of waves: P waves (pressure waves, the
#    fastest, so they arrive first) and S waves (shear waves, slower and usually bigger). Press SPACE when the P
#    wave arrives, and again for the S wave. Afterwards, fine-tune your picks: 1 or 2 selects a pick, A and D move it.
# 3. LOCATE: the gap between the P and S arrivals tells you how far away the quake was. Both waves start together,
#    so the farther they travel, the more the slower S wave falls behind:
#        distance = (S − P time) × Vp × Vs / (Vp − Vs)
#    Wave speeds (approximate, from models of the upper mantle): Mars Vp 7.5, Vs 4.2 km/s; the Moon Vp 7.7,
#    Vs 4.45 km/s. That's about 9.5 km (Mars) or 10.5 km (Moon) for every second of S − P time.
#    Simplified: one straight path through a uniform mantle, one quake, and the recording is sped up.
#
# SCORE (0-100): leveling 20, P pick 30, S pick 30, distance 20. Gold 85, silver 65, bronze 40, research points
# for each medal, best score kept. Sends finished({"science", "score", "medal", "distance_error"}).

signal finished(result)

const Career = preload("res://scripts/career.gd")
const SPEEDS = {"Mars": [7.5, 4.2], "Moon": [7.7, 4.45]}    # km/s: P and S waves (approximate)
const LEVEL_LIMIT = [0.5, 0.3, 0.2]   # degrees, by difficulty
const LEVEL_HOLD = 1.5                # seconds to hold it level
const LEG_SPEED = 0.6                 # degrees per second while a key is held (Shift: a quarter)
const RECORD_SECONDS = 26.0           # how long the recording takes to come in on screen
const PICK_SPEED = 4.0                # seconds of recording per second while A or D is held
const SAMPLE_RATE = 20.0
const MEDALS = [[85, "GOLD", Color(1.0, 0.82, 0.35), 6], [65, "SILVER", Color(0.8, 0.85, 0.92), 4], [40, "BRONZE", Color(0.85, 0.55, 0.35), 1]]
const FACTS = {
	"Mars": "InSight recorded more than 1,300 marsquakes between 2018 and 2022, many from Cerberus Fossae, a young volcanic region. The way their waves bent and bounced showed Mars has a crust, a mantle and a large liquid core.",
	"Moon": "The Apollo seismometers listened from 1969 to 1977. Moonquakes 'ring' for an hour or more, because the Moon's dry, shattered crust scatters the waves around like the inside of a bell.",
}

@onready var title_label: Label = $Header/Title
@onready var stage_label: Label = $Header/Stage
@onready var view: Control = $Body/View
@onready var steps_label: Label = $Body/Side/Column/Steps
@onready var status_label: Label = $Body/Side/Column/Status
@onready var readout_label: Label = $Body/Side/Column/Readout
@onready var keys_row: Control = $Body/Side/Column/KeyHints
@onready var action_button: Button = $Body/Side/Column/ActionButton
@onready var result_label: Label = $Body/Side/Column/Result
@onready var continue_button: Button = $Body/Side/Column/ContinueButton

var world = "Mars"
var stage = "level"           # "level", "record", "pick", "done"
var level_seconds = 0.0       # how long it has been held level
var leveled = false           # held level long enough: the legs lock
var level_time = 0.0          # how long leveling took in all
var settle = Vector2.ZERO     # the ground slowly settling under the feet (degrees per second)
var true_distance = 0.0       # km
var p_arrival = 0.0           # seconds into the recording
var s_arrival = 0.0
var factor = 9.5              # km per second of S − P time
var score = 0
var medal_name = ""
var science = 0
var distance_error = 1.0
var training = false          # opened from the career screen's Training tab (research only for beating your best medal)
var inputs_override = {}      # (the automatic tests use this instead of the keyboard)

func _ready():
	continue_button.visible = false
	result_label.visible = false
	action_button.pressed.connect(_on_action_pressed)
	continue_button.pressed.connect(_on_continue_pressed)

func held(key):
	if inputs_override.has(key):
		return inputs_override[key]
	return Input.is_key_pressed(key)

func start(target_name, world_name):
	get_viewport().gui_release_focus()
	if training:
		continue_button.text = "Done"
		# In training you can leave any time
		var close_button = Button.new()
		close_button.text = "Close (Esc)"
		close_button.focus_mode = Control.FOCUS_NONE
		close_button.custom_minimum_size = Vector2(110, 34)
		close_button.pressed.connect(queue_free)
		$Header.add_child(close_button)
	world = world_name if SPEEDS.has(world_name) else "Mars"
	title_label.text = "SEISMIC STATION  ·  %s" % target_name.to_upper()
	var speeds = SPEEDS[world]
	factor = speeds[0] * speeds[1] / (speeds[0] - speeds[1])
	view.mode = "level"
	view.has_wind = world == "Mars"
	view.level_limit = LEVEL_LIMIT[clamp(GameState.difficulty, 0, 2)]
	var angle = randf() * TAU
	view.tilt = Vector2(cos(angle), sin(angle)) * randf_range(2.0, 4.5)
	settle = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * 0.06
	# The quake: somewhere a few hundred kilometers away
	true_distance = randf_range(260.0, 900.0)
	p_arrival = randf_range(18.0, 28.0)
	s_arrival = p_arrival + true_distance / factor
	view.total_seconds = ceil((s_arrival + (90.0 if world == "Moon" else 60.0)) / 10.0) * 10.0
	keys_row.hints = [["A D", "tilt left / right"], ["W S", "tilt front / back"], ["Shift", "fine"]]
	action_button.visible = world == "Mars"
	action_button.disabled = true
	action_button.text = "Lower the wind shield (SPACE)"
	update_steps()
	UiMotion.reveal_text(title_label, 0.1, 0.6, 0.4)
	UiMotion.slide_in($Body/Side, 0.15, Vector2(30, 0), 0.5)

# Every key belongs to the minigame while it's open; the one-press keys are handled here
func _input(event):
	if not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if training and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		return
	if event.pressed and not event.echo:
		handle_key(event.keycode)

func handle_key(keycode):
	match stage:
		"level":
			if keycode == KEY_SPACE and leveled:
				_on_action_pressed()
		"record":
			if keycode == KEY_SPACE:
				if view.p_pick < 0.0:
					view.p_pick = view.shown_seconds
					view.selected = "p"
					play_sound("select")
				elif view.s_pick < 0.0:
					view.s_pick = view.shown_seconds
					view.selected = "s"
					play_sound("select")
		"pick":
			if keycode == KEY_1:
				view.selected = "p"
			elif keycode == KEY_2:
				view.selected = "s"
			elif keycode == KEY_SPACE or keycode == KEY_ENTER:
				_on_action_pressed()

func is_level():
	return view.tilt.length() <= view.level_limit

func _process(delta):
	match stage:
		"level":
			if leveled:
				update_readout()
				return
			level_time += delta
			var rate = LEG_SPEED * (0.25 if held(KEY_SHIFT) else 1.0)
			var adjust = Vector2.ZERO
			if held(KEY_A):
				adjust.x += 1.0
			if held(KEY_D):
				adjust.x -= 1.0
			if held(KEY_W):
				adjust.y -= 1.0
			if held(KEY_S):
				adjust.y += 1.0
			view.tilt += adjust * rate * delta + settle * delta
			level_seconds = level_seconds + delta if is_level() and adjust == Vector2.ZERO else (level_seconds if is_level() else 0.0)
			if is_level() and level_seconds >= LEVEL_HOLD:
				leveled = true
				play_sound("confirm")
				if world == "Mars":
					action_button.disabled = false
					status_label.text = "Level! Now lower the wind shield over it (SPACE)."
				else:
					begin_recording()
			elif is_level():
				status_label.text = "Level... hold it there (%.1f s)." % max(LEVEL_HOLD - level_seconds, 0.0)
			else:
				status_label.text = "Tilted %.2f°. Move the bubble into the green circle: the bubble floats to the high side." % view.tilt.length()
		"record":
			view.shown_seconds = min(view.shown_seconds + delta * view.total_seconds / RECORD_SECONDS, view.total_seconds)
			status_label.text = "Recording... Press SPACE when the %s wave arrives." % ("P" if view.p_pick < 0.0 else ("S" if view.s_pick < 0.0 else "(both picked)"))
			if view.shown_seconds >= view.total_seconds:
				begin_picking()
		"pick":
			var move = (1.0 if held(KEY_D) else 0.0) - (1.0 if held(KEY_A) else 0.0)
			if move != 0.0:
				var key = "p_pick" if view.selected == "p" else "s_pick"
				var value = view.get(key)
				if value < 0.0:
					value = view.shown_seconds * (0.3 if view.selected == "p" else 0.6)
				view.set(key, clamp(value + move * PICK_SPEED * delta, 0.0, view.total_seconds))
			action_button.disabled = view.p_pick < 0.0 or view.s_pick < 0.0 or view.s_pick <= view.p_pick
	update_readout()

func update_readout():
	var lines = []
	if view.p_pick >= 0.0:
		lines.append("P pick   %.1f s" % view.p_pick)
	if view.s_pick >= 0.0:
		lines.append("S pick   %.1f s" % view.s_pick)
	if view.p_pick >= 0.0 and view.s_pick > view.p_pick:
		var gap = view.s_pick - view.p_pick
		lines.append("S − P    %.1f s" % gap)
		lines.append("Distance = %.1f s × %.1f km/s ≈ %d km" % [gap, factor, int(round(gap * factor))])
	readout_label.text = "\n".join(lines)

func update_steps():
	var names = [["level", "Level the seismometer" + (" and lower the wind shield" if world == "Mars" else "")], ["record", "Pick the P and S waves as they arrive"], ["pick", "Fine-tune the picks, then locate the quake"], ["done", "How far away was it?"]]
	var order = ["level", "record", "pick", "done"]
	var now = order.find(stage)
	var lines = []
	for index in names.size():
		lines.append("%s  %s" % ["✓" if index < now else ("▶" if index == now else "·"), names[index][1]])
	steps_label.text = "\n".join(lines)

func _on_action_pressed():
	match stage:
		"level":
			if leveled:
				view.shield_down = true
				play_sound("confirm")
				begin_recording()
		"pick":
			if view.p_pick >= 0.0 and view.s_pick > view.p_pick:
				locate()

# The quake's recording: background noise (worse if the instrument isn't level, and from the wind on Mars without
# the shield), then the P wave (quick, small wiggles) and the S wave (slower, bigger), each fading away; the Moon's
# fade very slowly (they "ring")
func begin_recording():
	stage = "record"
	view.mode = "trace"
	var count = int(view.total_seconds * SAMPLE_RATE)
	var samples = PackedFloat32Array()
	samples.resize(count)
	var noise = 0.06 * (1.0 + view.tilt.length() * 3.0) * (1.0 if world == "Moon" or view.shield_down else 2.5)
	var ring = 80.0 if world == "Moon" else 18.0
	var phases = [randf() * TAU, randf() * TAU, randf() * TAU]
	for index in count:
		var time = index / SAMPLE_RATE
		var value = noise * (0.5 * sin(time * 9.1 + phases[0]) + 0.3 * sin(time * 15.7 + phases[1]) + 0.4 * sin(time * 4.3 + phases[2]) + randf_range(-0.6, 0.6))
		if time >= p_arrival:
			var since = time - p_arrival
			value += 0.35 * min(since / 0.6, 1.0) * exp(-since / (ring * 0.5)) * sin(TAU * 1.6 * since) * (0.8 + 0.2 * randf())
		if time >= s_arrival:
			var since = time - s_arrival
			value += 1.0 * min(since / 1.5, 1.0) * exp(-since / ring) * sin(TAU * 0.7 * since) * (0.8 + 0.2 * randf())
		samples[index] = value
	view.samples = samples
	view.sample_rate = SAMPLE_RATE
	view.shown_seconds = 0.0
	action_button.visible = false
	keys_row.hints = [["Space", "pick P, then S"]]
	update_steps()

func begin_picking():
	stage = "pick"
	status_label.text = "Recording done. Fine-tune your picks: 1 or 2 selects P or S, A and D move it. Then locate the quake."
	keys_row.hints = [["1 2", "select P / S"], ["A D", "move pick"], ["Space", "locate"]]
	action_button.visible = true
	action_button.text = "Locate the quake  ›"
	update_steps()

func locate():
	stage = "done"
	update_steps()
	var gap = view.s_pick - view.p_pick
	var estimate = gap * factor
	distance_error = abs(estimate - true_distance) / true_distance
	view.true_p = p_arrival
	view.true_s = s_arrival
	var p_error = abs(view.p_pick - p_arrival)
	var s_error = abs(view.s_pick - s_arrival)
	var level_points = int(round(20.0 * clamp(1.0 - (level_time - 6.0) / 30.0, 0.3, 1.0))) if view.shield_down or world == "Moon" else 10
	var p_points = int(round(30.0 * clamp(1.0 - (p_error - 0.5) / 5.0, 0.0, 1.0)))
	var s_points = int(round(30.0 * clamp(1.0 - (s_error - 0.8) / 6.0, 0.0, 1.0)))
	var distance_points = int(round(20.0 * clamp(1.0 - (distance_error - 0.03) / 0.3, 0.0, 1.0)))
	score = clamp(level_points + p_points + s_points + distance_points, 0, 100)
	science = 3 + int(round(score / 10.0))
	var medal = null
	for entry in MEDALS:
		if score >= entry[0]:
			medal = entry
			break
	var science_text = "" if training else " · +%d science" % science
	var reward = "%d / 100%s" % [score, science_text]
	if medal:
		medal_name = medal[1]
		var bests = GameState.career.get("seismic_best", {})
		var research = research_for(medal, bests.get(world, 0))
		GameState.career["research"] = GameState.career.get("research", 0) + research
		var new_best = score > bests.get(world, -1)
		bests[world] = max(bests.get(world, 0), score)
		GameState.career["seismic_best"] = bests
		Career.save_data(GameState.career)
		if medal[1] == "GOLD":
			GameState.note_gold_medal()
		reward = "%s · %d / 100%s%s · +%d research points" % [medal[1], score, " (new best!)" if new_best else "", science_text, research]
		if research > 0:
			GameState.show_toast("%s seismology" % medal[1].capitalize(), "+%d research points." % research, "research")
	if distance_error <= 0.1:
		GameState.award_achievement("seismologist")
	result_label.text = "Your estimate: %d km. The quake was really %d km away (%d%% off).\nP pick %.1f s off, S pick %.1f s off. Level %d/20 · P %d/30 · S %d/30 · distance %d/20\n%s\n\n%s" % [
		int(round(estimate)), int(round(true_distance)), int(round(distance_error * 100.0)), p_error, s_error, level_points, p_points, s_points, distance_points, reward, FACTS[world]]
	result_label.visible = true
	status_label.text = "The dashed lines show when the waves really arrived."
	action_button.visible = false
	continue_button.visible = true
	UiMotion.slide_in(result_label, 0.0, Vector2(0, 12), 0.4)
	play_sound("confirm" if distance_error <= 0.2 else "glitch")
	print("SEISMIC %s" % [{"world": world, "true_km": true_distance, "estimate_km": estimate, "p_error": p_error, "s_error": s_error, "score": score}])

# On a mission every medal earns its research points; in training only beating your best medal does (like the
# other simulators), so the same site can't be farmed
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
	finished.emit({"science": science, "score": score, "medal": medal_name, "distance_error": distance_error})
	queue_free()

func play_sound(sound_name):
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_effect(sound_name, -6.0)
