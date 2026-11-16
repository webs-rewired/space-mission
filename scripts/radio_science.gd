extends Control

# MINIGAME: RADIO SCIENCE (res://scenes/radio_science.tscn)
# Science with nothing but the spacecraft's radio. Two kinds, by world (scripts/radio_science_data.gd):
#   OCCULTATION (worlds with air): the spacecraft slips behind the world as seen from Earth, and its signal passes
#     through the atmosphere on the way. The air bends it, shifting its frequency more and more as the signal dips into
#     denser air, and fading it, until the world itself cuts it off.
#   GRAVITY (airless worlds): flying over heavier or lighter patches, the spacecraft speeds up or slows down by
#     millimeters per second, and the frequency wiggles.
# Either way, the job is the same as in a Deep Space Network control room: keep the receiver locked on the signal
# (A and D tune it; Shift for fine tuning) as it drifts. Every stretch you stay locked on becomes a data point. Then
# the data turns into a profile of the air (or a map of the gravity), and you read off what real missions found.
#
# Simplified for the game: the shift and fading follow the real shape (they grow with the air's density, or with the
# extra mass below), but in made-up display units, and the pass is sped up to about 40 seconds.
#
# SCORE (0-100): the share of the pass you stayed locked on, 60; the question, 40. Gold 85, silver 65, bronze 40,
# research points for each medal (in training: only for beating your best medal).
# Sends finished({"science", "score", "medal", "coverage"}).

signal finished(result)

const Data = preload("res://scripts/radio_science_data.gd")
const Career = preload("res://scripts/career.gd")
const PASS_SECONDS = 40.0
const BINS = 40
const LOCK_WIDTH = [0.2, 0.15, 0.11]          # how wide the receiver's window is (the display is 2 wide), by difficulty
const TUNE_SPEED = 1.1                        # display widths per second while A or D is held (Shift: a third)
const MEDALS = [[85, "GOLD", Color(1.0, 0.82, 0.35), 6], [65, "SILVER", Color(0.8, 0.85, 0.92), 4], [40, "BRONZE", Color(0.85, 0.55, 0.35), 1]]

@onready var title_label: Label = $Header/Title
@onready var view: Control = $Body/View
@onready var brief_label: Label = $Body/Side/Column/Brief
@onready var readout_label: Label = $Body/Side/Column/Readout
@onready var status_label: Label = $Body/Side/Column/Status
@onready var keys_row: Control = $Body/Side/Column/KeyHints
@onready var start_button: Button = $Body/Side/Column/StartButton
@onready var question_label: Label = $Body/Side/Column/Question
@onready var answer_buttons: VBoxContainer = $Body/Side/Column/Answers
@onready var result_label: Label = $Body/Side/Column/Result
@onready var continue_button: Button = $Body/Side/Column/ContinueButton

var world = "Mars"
var info = {}
var state = "ready"           # "ready", "tracking", "question", "done"
var clock = 0.0               # seconds into the pass
var receiver = 0.0            # where the receiver is tuned (−1 to 1)
var lock_width = 0.15
var bin_locked = []           # seconds locked in each bin
var bin_total = []
var drift_phase = 0.0
var drift_rate = 0.0
var coverage = 0.0
var score = 0
var medal_name = ""
var science = 0
var training = false          # opened from the Training tab (research only for beating your best medal)
var inputs_override = {}      # (the automatic tests use this instead of the keyboard)

func _ready():
	continue_button.visible = false
	result_label.visible = false
	question_label.visible = false
	start_button.pressed.connect(begin_pass)
	continue_button.pressed.connect(_on_continue_pressed)

func held(key):
	if inputs_override.has(key):
		return inputs_override[key]
	return Input.is_key_pressed(key)

func start(world_name):
	get_viewport().gui_release_focus()
	world = world_name if Data.has_world(world_name) else "Mars"
	info = Data.WORLDS[world]
	if training:
		continue_button.text = "Done"
		var close_button = Button.new()
		close_button.text = "Close (Esc)"
		close_button.focus_mode = Control.FOCUS_NONE
		close_button.custom_minimum_size = Vector2(110, 34)
		close_button.pressed.connect(queue_free)
		$Header.add_child(close_button)
	var occultation = info["mode"] == "occultation"
	var named = "the Moon" if world == "Moon" else world
	title_label.text = ("RADIO OCCULTATION  ·  %s" if occultation else "GRAVITY SCIENCE  ·  %s") % world.to_upper()
	if occultation:
		brief_label.text = "Your spacecraft is about to pass behind %s, seen from Earth. Its radio signal will travel through the air on the way, bending more and fading as it goes deeper. Keep the receiver locked on it to measure the air at every height, like %s." % [named, info["mission"]]
	else:
		brief_label.text = "Your spacecraft is skimming low over %s. Over heavier patches it speeds up by millimeters per second, which shifts its radio frequency. Keep the receiver locked on the signal to map the gravity below, like %s." % [named, info["mission"]]
	lock_width = LOCK_WIDTH[clamp(GameState.difficulty, 0, 2)]
	drift_phase = randf() * TAU
	drift_rate = randf_range(-0.15, 0.15)
	bin_locked.resize(BINS)
	bin_total.resize(BINS)
	bin_locked.fill(0.0)
	bin_total.fill(0.0)
	view.set_up(info, lock_width)
	receiver = signal_at(0.0)
	view.preview = [signal_at(0.0), receiver]
	readout_label.text = "Receiver ready. The signal is the bright line; your receiver's window is the blue band."
	status_label.text = "Press SPACE (or Start) when you're ready. Then keep the blue window on the signal with A and D."
	UiMotion.reveal_text(title_label, 0.1, 0.6, 0.4)
	UiMotion.slide_in($Body/Side, 0.15, Vector2(30, 0), 0.5)

func _input(event):
	if not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if training and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		return
	if event.pressed and not event.echo and event.keycode == KEY_SPACE and state == "ready":
		begin_pass()

func begin_pass():
	if state != "ready":
		return
	state = "tracking"
	start_button.visible = false
	keys_row.hints = [["A D", "tune"], ["Shift", "fine"]]
	play_sound("select")

# ---------------------------------------------------------------------------
# The signal
# ---------------------------------------------------------------------------
# How far along the pass (0 to 1) the deep part of the signal is: for an occultation, the share of the way down
# through the air; for gravity, the place along the track
func share_at(seconds):
	return clamp(seconds / PASS_SECONDS, 0.0, 1.0)

# Where the signal is on the display (−1 to 1) at a moment of the pass: the slow drift every pass has (the orbit is
# never predicted perfectly), plus the shift the science makes
func signal_at(seconds):
	var share = share_at(seconds)
	var drift = 0.25 * sin(drift_phase + seconds * 0.35) + drift_rate * share
	return clamp(drift + science_shift(share), -0.95, 0.95)

func science_shift(share):
	if info["mode"] == "gravity":
		var total = 0.0
		for bump in info["bumps"]:
			total += bump[1] * 0.45 * exp(-pow((share - bump[0]) / 0.06, 2))
		return total
	return 0.75 * depth_factor(share)

# How dense the air is where the signal passes, compared with the deepest point it reaches (0 to 1)
func depth_factor(share):
	if info["profile"] == "temperature":
		return pow(share, 2.2)   # pressure grows a thousandfold over the pass; the shift grows with it
	var span = info["top_km"] - info["lowest_km"]
	var height = info["top_km"] - span * share
	return exp(-(height - info["lowest_km"]) / info["scale_km"]) if span > 0.0 else 0.0

# How strong the signal is (1 = full): bending spreads it out (and giant planets' ammonia soaks it up) deeper down
func strength_at(seconds):
	if info["mode"] == "gravity":
		return 0.9
	var share = share_at(seconds)
	return clamp(1.0 - 0.75 * depth_factor(share), 0.2, 1.0)

func _process(delta):
	if state != "tracking":
		return
	delta = min(delta, 0.05)
	clock += delta
	var tune = (1.0 if held(KEY_D) else 0.0) - (1.0 if held(KEY_A) else 0.0)
	receiver = clamp(receiver + tune * TUNE_SPEED * (0.33 if held(KEY_SHIFT) else 1.0) * delta, -1.0, 1.0)
	var signal_place = signal_at(clock) + randf_range(-0.012, 0.012)
	var locked = abs(signal_place - receiver) <= lock_width * 0.5
	var bin = clamp(int(share_at(clock) * BINS), 0, BINS - 1)
	bin_total[bin] += delta
	if locked:
		bin_locked[bin] += delta
	view.add_row(signal_place, strength_at(clock), receiver, locked)
	coverage = measured_bins() / float(BINS)
	readout_label.text = "%s\nSIGNAL      %d%%\nLOCK        %s\nDATA        %d of %d points" % [
		where_text(share_at(clock)), int(round(strength_at(clock) * 100.0)), "LOCKED" if locked else "LOST: tune toward the signal", measured_bins(), BINS]
	readout_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7) if locked else Color(1.0, 0.6, 0.5))
	status_label.text = "Keep the blue window on the bright line: A and D (Shift for fine tuning)."
	if clock >= PASS_SECONDS:
		end_pass()

func where_text(share):
	if info["mode"] == "gravity":
		return "ALONG TRACK %d%%" % int(round(share * 100.0))
	if info["profile"] == "temperature":
		return "PRESSURE    %s" % pressure_text(pow(10.0, -3.0 + 3.0 * share))
	return "RAY HEIGHT  %d km" % int(round(info["top_km"] - (info["top_km"] - info["lowest_km"]) * share))

static func pressure_text(bar):
	if bar >= 1.0:
		return "%.1f bar" % bar
	if bar >= 0.001:
		return "%.1f millibar" % (bar * 1000.0) if bar < 0.01 else "%d millibar" % int(round(bar * 1000.0))
	return "%.1f microbar" % (bar * 1000000.0)

func measured_bins():
	var count = 0
	for index in BINS:
		if bin_total[index] > 0.0 and bin_locked[index] >= bin_total[index] * 0.6:
			count += 1
	return count

# ---------------------------------------------------------------------------
# After the pass: the profile, and the question
# ---------------------------------------------------------------------------
func end_pass():
	state = "question"
	var measured = []
	for index in BINS:
		measured.append(bin_total[index] > 0.0 and bin_locked[index] >= bin_total[index] * 0.6)
	view.show_profile(measured)
	coverage = measured_bins() / float(BINS)
	readout_label.text = "Pass complete: %d of %d data points (%d%%)." % [measured_bins(), BINS, int(round(coverage * 100.0))]
	readout_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	status_label.text = "Here's what your data shows. Read it, then answer below."
	keys_row.visible = false
	question_label.text = info["question"]
	question_label.visible = true
	var options = info["options"].duplicate()
	options.shuffle()
	for option in options:
		var button = Button.new()
		button.text = option
		button.focus_mode = Control.FOCUS_NONE
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 36)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(answer.bind(option))
		answer_buttons.add_child(button)
	UiMotion.stagger(answer_buttons.get_children(), 0.1, 0.06, Vector2(0, 12), 0.4)
	play_sound("confirm")

func answer(option):
	if state != "question":
		return
	state = "done"
	var right = option == info["options"][0]
	for button in answer_buttons.get_children():
		button.disabled = true
		if button.text == info["options"][0]:
			button.add_theme_color_override("font_disabled_color", Color(0.45, 1.0, 0.6))
		elif button.text == option:
			button.add_theme_color_override("font_disabled_color", Color(1.0, 0.5, 0.45))
	score = clamp(int(round(coverage * 60.0)) + (40 if right else 0), 0, 100)
	science = 3 + int(round(score / 12.0))
	var medal = null
	for entry in MEDALS:
		if score >= entry[0]:
			medal = entry
			break
	var science_text = "" if training else " · +%d science" % science
	var reward = "%d / 100%s" % [score, science_text]
	if medal:
		medal_name = medal[1]
		var bests = GameState.career.get("radio_best", {})
		var research = research_for(medal, bests.get(world, 0))
		GameState.career["research"] = GameState.career.get("research", 0) + research
		var new_best = score > bests.get(world, -1)
		bests[world] = max(bests.get(world, 0), score)
		GameState.career["radio_best"] = bests
		Career.save_data(GameState.career)
		if medal[1] == "GOLD":
			GameState.note_gold_medal()
		reward = "%s · %d / 100%s%s · +%d research points" % [medal[1], score, " (new best!)" if new_best else "", science_text, research]
		if research > 0:
			GameState.show_toast("%s radio science" % medal[1].capitalize(), "+%d research points." % research, "research")
	if coverage >= 0.9:
		GameState.award_achievement("radio_lock")
	result_label.text = "%s%s\n\n%s" % ["Right! " if right else "", info["why"], reward]
	result_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8) if right else Color(1.0, 0.85, 0.8))
	result_label.visible = true
	continue_button.visible = true
	UiMotion.slide_in(result_label, 0.0, Vector2(0, 12), 0.4)
	play_sound("confirm" if right else "glitch")
	print("RADIO SCIENCE %s" % [{"world": world, "mode": info["mode"], "coverage": coverage, "right": right, "score": score}])

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
	finished.emit({"science": science, "score": score, "medal": medal_name, "coverage": coverage})
	queue_free()

func play_sound(sound_name):
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_effect(sound_name, -6.0)
