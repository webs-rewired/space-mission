extends Control

# MINIGAMES: ROBOTIC SAMPLE COLLECTION and GEOLOGICAL IDENTIFICATION (res://scenes/sample_lab.tscn)
# Opened when the rover studies a glowing target on the ground (surface_view.gd, the E key).
#
# 1. COLLECT: drive the robotic arm's joints (shoulder, elbow, turret) to put the tool on the marked spot,
#    square to the surface, then drill or scoop and carry the sample to the inlet on the deck. Joints move at
#    real arm speeds and have real limits; bumping the rock or the ground strains the arm, and moving while the
#    drill is turning can jam the bit (Curiosity's drill had a real fault like this in 2016).
#    With the Robotic arm instrument it's a long 2.2 m arm like Curiosity's; without it, a short sampling arm.
#    With the Drill it drills rock; without it, it can only scoop the loose soil beside the rock.
# 2. IDENTIFY: run your probe's instruments on the sample (only the ones you built it with), read the results,
#    and decide what it is. There's only enough power for a few instrument runs, so choose wisely.
#    Every sample is a real material found on this world (scripts/geology_samples.gd).
#
# Sends finished(result): {"sample", "name", "correct", "science", "collection", "instruments_used"}

signal finished(result)

const GeologySamples = preload("res://scripts/geology_samples.gd")
const JOINT_SPEED = 0.45              # radians per second (robot arms move slowly and carefully)
const DRILL_SECONDS = 3.0
const SCOOP_SECONDS = 1.2
const SPOT_REACH = 0.07               # meters: how close the tool must be to the spot
const SQUARE_TOLERANCE = deg_to_rad(20.0)
const INSTRUMENT_RUNS = [5, 3, 2]     # instrument runs the battery allows: Cadet, Standard, Veteran
const INSTRUMENT_NAMES = {"camera": "Camera", "arm": "Hand lens (arm)", "spectrometer": "Infrared spectrometer",
	"thermal": "Thermal imager", "mass_spec": "Mass spectrometer", "drill": "Drill"}
const INSTRUMENT_PARTS = {"arm": "instrument_arm", "spectrometer": "instrument_spectrometer", "thermal": "instrument_thermal",
	"mass_spec": "instrument_mass_spec", "drill": "instrument_drill"}

@onready var title_label: Label = $Header/Title
@onready var stage_label: Label = $Header/Stage
@onready var collect_stage: Control = $CollectStage
@onready var arm_view: Control = $CollectStage/ArmView
@onready var collect_help: Label = $CollectStage/Side/Column/Help
@onready var collect_status: Label = $CollectStage/Side/Column/Status
@onready var work_bar: ProgressBar = $CollectStage/Side/Column/WorkBar
@onready var stress_bar: ProgressBar = $CollectStage/Side/Column/StressBar
@onready var skip_button: Button = $CollectStage/Side/Column/SkipButton
@onready var identify_stage: Control = $IdentifyStage
@onready var instrument_buttons: VBoxContainer = $IdentifyStage/Instruments/Column/Buttons
@onready var runs_label: Label = $IdentifyStage/Instruments/Column/Runs
@onready var readings_list: VBoxContainer = $IdentifyStage/Readings/Scroll/List
@onready var candidate_buttons: VBoxContainer = $IdentifyStage/Answers/Column/Buttons
@onready var answer_text: Label = $IdentifyStage/Answers/Column/AnswerText
@onready var continue_button: Button = $IdentifyStage/Answers/Column/ContinueButton

var sample_id = ""
var sample = {}
var target_name = ""
var has_drill = false
var work = 0.0
var bumps = 0
var jammed = false
var collected = false
var collection = "clean"
var runs_left = 3
var instruments_used = []
var answered = false
var was_correct = false
var science = 0

func _ready():
	identify_stage.visible = false
	continue_button.visible = false
	skip_button.pressed.connect(collect_automatically)
	continue_button.pressed.connect(_on_continue_pressed)

func start(new_target_name):
	get_viewport().gui_release_focus()
	target_name = new_target_name
	var world = GameState.destination
	var choices_here = GeologySamples.samples_for(world)
	sample_id = choices_here[randi() % choices_here.size()]
	sample = GeologySamples.SAMPLES[sample_id]
	has_drill = "instrument_drill" in GameState.instruments
	var long_arm = "instrument_arm" in GameState.instruments
	title_label.text = "SAMPLE LAB  ·  %s" % target_name.to_upper()
	stage_label.text = "1  COLLECT     ›     2  IDENTIFY"
	# The arm: a 2.2 m arm like Curiosity's, or a short sampling arm
	arm_view.upper_length = 1.05 if long_arm else 0.7
	arm_view.lower_length = 0.95 if long_arm else 0.6
	arm_view.tool_length = 0.25 if long_arm else 0.2
	arm_view.tool_name = "DRILL" if has_drill else "SCOOP"
	var reach = arm_view.upper_length + arm_view.lower_length
	# A rock somewhere in reach (a different place every time), with the sample spot on top
	var rock_middle = randf_range(0.75, reach * 0.8)
	var rock_height = randf_range(0.12, 0.4)
	var rock_width = randf_range(0.35, 0.6)
	arm_view.rock_points = PackedVector2Array([Vector2(rock_middle - rock_width, 0), Vector2(rock_middle - rock_width * 0.7, rock_height * 0.8),
		Vector2(rock_middle - rock_width * 0.1, rock_height), Vector2(rock_middle + rock_width * 0.5, rock_height * 0.85), Vector2(rock_middle + rock_width, 0)])
	if has_drill:
		arm_view.spot = Vector2(rock_middle - rock_width * 0.1 + randf_range(-0.05, 0.15), rock_height * 0.97)
	else:
		arm_view.spot = Vector2(rock_middle + rock_width + 0.18, 0.0)   # the loose soil beside the rock
	arm_view.spot_normal = Vector2(0, 1)   # straight up (y points up here; Vector2.UP is the screen's up)
	arm_view.rock_color = Color(0.32, 0.3, 0.28).lerp(Color(0.85, 0.88, 0.95), sample["brightness"] * 0.6)
	if GameState.destination in ["Europa", "Enceladus", "Titan", "Pluto", "Triton", "Charon", "Ganymede", "Callisto", "Eris", "Haumea", "Makemake", "Titania"]:
		arm_view.ground_color = Color(0.55, 0.6, 0.68)
	elif GameState.destination in ["Moon", "Mercury", "Ceres"]:
		arm_view.ground_color = Color(0.42, 0.42, 0.44)
	elif GameState.destination == "Io":
		arm_view.ground_color = Color(0.7, 0.6, 0.25)
	collect_help.text = ("A/D swing the shoulder, W/S bend the elbow, Q/E turn the tool. Put the %s on the glowing spot, pointing straight into the surface, and hold SPACE. Keep the arm still while it works, then carry the sample to the inlet on the deck and press SPACE." % ("drill" if has_drill else "scoop")) + ("" if has_drill else " (No drill on board: you can only scoop loose soil.)")
	runs_left = INSTRUMENT_RUNS[GameState.difficulty]
	UiMotion.reveal_text(title_label, 0.1, 0.6, 0.4)
	UiMotion.slide_in($CollectStage/Side, 0.15, Vector2(30, 0), 0.5)

# ---------------------------------------------------------------------------
# Stage 1: collect
# ---------------------------------------------------------------------------
func _process(delta):
	if not collect_stage.visible:
		return
	var turning = 0.0
	var bending = 0.0
	var twisting = 0.0
	if Input.is_key_pressed(KEY_A):
		turning += 1.0
	if Input.is_key_pressed(KEY_D):
		turning -= 1.0
	if Input.is_key_pressed(KEY_W):
		bending += 1.0
	if Input.is_key_pressed(KEY_S):
		bending -= 1.0
	if Input.is_key_pressed(KEY_Q):
		twisting += 1.0
	if Input.is_key_pressed(KEY_E):
		twisting -= 1.0
	var moving = turning != 0.0 or bending != 0.0 or twisting != 0.0
	var before = [arm_view.shoulder_angle, arm_view.elbow_angle, arm_view.tool_angle]
	arm_view.shoulder_angle = clamp(arm_view.shoulder_angle + turning * JOINT_SPEED * delta, deg_to_rad(-10.0), deg_to_rad(170.0))
	arm_view.elbow_angle = clamp(arm_view.elbow_angle + bending * JOINT_SPEED * delta, deg_to_rad(-165.0), deg_to_rad(0.0))
	arm_view.tool_angle = arm_view.tool_angle + twisting * JOINT_SPEED * 1.4 * delta
	# The arm can't go into the ground or the rock: it stops, and a hard bump strains it
	var tip = arm_view.tool_tip()
	var wrist = arm_view.wrist_position()
	if hits_something(tip) or hits_something(wrist) or hits_something(arm_view.elbow_position()):
		arm_view.shoulder_angle = before[0]
		arm_view.elbow_angle = before[1]
		arm_view.tool_angle = before[2]
		if moving:
			arm_view.stress = min(arm_view.stress + 30.0 * delta, 100.0)
			arm_view.flash = 0.6
			if arm_view.stress > 25.0 and collection == "clean":
				collection = "rough"
	arm_view.flash = max(arm_view.flash - delta * 2.0, 0.0)
	tip = arm_view.tool_tip()
	var pointing = Vector2(cos(arm_view.tool_angle), sin(arm_view.tool_angle))
	var square = pointing.angle_to(-arm_view.spot_normal)
	var at_spot = tip.distance_to(arm_view.spot) < SPOT_REACH + 0.04
	var squared_up = abs(square) < SQUARE_TOLERANCE
	var working = Input.is_key_pressed(KEY_SPACE)
	arm_view.tool_active = false
	if not collected:
		if at_spot and squared_up and working:
			arm_view.tool_active = true
			work += delta / (DRILL_SECONDS if has_drill else SCOOP_SECONDS)
			if moving and has_drill:
				# Moving the arm while the drill is turning bends the bit
				arm_view.stress = min(arm_view.stress + 45.0 * delta, 100.0)
				if arm_view.stress >= 100.0 and not jammed:
					jammed = true
					collection = "damaged"
			if work >= 1.0:
				collected = true
				arm_view.holding_sample = true
				arm_view.spot_taken = true
				play_sound("confirm")
		collect_status.text = status_text(at_spot, squared_up, square)
	else:
		var at_inlet = tip.distance_to(arm_view.inlet) < 0.12
		collect_status.text = "Sample in the tool. Carry it to the SAMPLE INLET on the deck and press SPACE." + ("\nOver the inlet: press SPACE." if at_inlet else "")
		if at_inlet and working:
			go_to_identify()
	work_bar.value = work * 100.0
	stress_bar.value = arm_view.stress
	arm_view.stress = max(arm_view.stress - 4.0 * delta, 0.0) if not moving else arm_view.stress

func hits_something(place):
	if place.y < -0.01:
		return true
	return arm_view.rock_points.size() >= 3 and Geometry2D.is_point_in_polygon(place + Vector2(0, 0.02), arm_view.rock_points) and place.distance_to(arm_view.spot) > SPOT_REACH

func status_text(at_spot, squared_up, square):
	var distance = arm_view.tool_tip().distance_to(arm_view.spot)
	var lines = ["Tool to the spot: %d cm" % int(round(distance * 100.0))]
	lines.append("Tool angle to the surface: %d° off square" % int(round(abs(rad_to_deg(square)))))
	if at_spot and squared_up:
		lines.append("READY: hold SPACE to %s" % ("drill" if has_drill else "scoop"))
	elif at_spot:
		lines.append("On the spot, but not square: turn the tool with Q/E")
	if jammed:
		lines.append("The bit bent! The sample will be poor.")
	return "\n".join(lines)

# The arm team does it for you: slower and not as careful, but it gets a sample
func collect_automatically():
	collection = "rough" if collection == "clean" else collection
	collected = true
	go_to_identify()

# ---------------------------------------------------------------------------
# Stage 2: identify
# ---------------------------------------------------------------------------
func go_to_identify():
	collect_stage.visible = false
	identify_stage.visible = true
	stage_label.text = "1  COLLECT  ✓     ›     2  IDENTIFY"
	for old in instrument_buttons.get_children():
		old.queue_free()
	for instrument_key in INSTRUMENT_NAMES:
		var part_id = INSTRUMENT_PARTS.get(instrument_key, "")
		if part_id != "" and not part_id in GameState.instruments:
			continue
		var button = Button.new()
		button.text = INSTRUMENT_NAMES[instrument_key]
		button.custom_minimum_size = Vector2(0, 36)
		button.pressed.connect(run_instrument.bind(instrument_key, button))
		instrument_buttons.add_child(button)
	var options = [sample_id]
	var pool = GeologySamples.samples_for(GameState.destination).duplicate()
	pool.shuffle()
	for other in pool + GeologySamples.ROCKY_SET + GeologySamples.ICY_SET:
		if options.size() >= 4:
			break
		if not other in options:
			options.append(other)
	options.shuffle()
	for option_id in options:
		var button = Button.new()
		button.text = GeologySamples.SAMPLES[option_id]["name"]
		button.custom_minimum_size = Vector2(0, 38)
		button.pressed.connect(answer.bind(option_id))
		candidate_buttons.add_child(button)
	update_runs()
	add_reading("THE SAMPLE", "Collected from %s on %s%s." % [target_name.to_lower(), GameState.destination, {"clean": ", cleanly", "rough": ", a little roughly", "damaged": ", with a bent drill bit (a poor sample)"}[collection]])
	UiMotion.stagger([$IdentifyStage/Instruments, $IdentifyStage/Readings, $IdentifyStage/Answers], 0.05, 0.08, Vector2(0, 20), 0.5)

func run_instrument(instrument_key, button):
	if runs_left <= 0 or answered:
		return
	runs_left -= 1
	instruments_used.append(instrument_key)
	button.disabled = true
	if instrument_key == "spectrometer":
		var chart = Control.new()
		chart.set_script(load("res://scripts/spectrum_chart.gd"))
		chart.custom_minimum_size = Vector2(0, 170)
		add_reading("INFRARED SPECTROMETER", "Dips in the curve are absorption bands: each mineral or ice absorbs at its own wavelengths." if not sample["bands"].is_empty() else "No clear absorption bands: a flat, featureless spectrum.", chart)
		chart.show_spectrum(sample["brightness"], sample["bands"])
	else:
		add_reading(INSTRUMENT_NAMES[instrument_key].to_upper(), sample[instrument_key])
	update_runs()
	play_sound("select")

func add_reading(title, text, extra = null):
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.15, 0.95)
	style.border_color = Color(0.45, 0.8, 1.0, 0.4)
	style.border_width_left = 3
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	var column = VBoxContainer.new()
	card.add_child(column)
	var heading = Label.new()
	heading.text = title
	heading.theme_type_variation = "DataLabel"
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Color(0.45, 0.8, 1.0))
	column.add_child(heading)
	var words = Label.new()
	words.text = text
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_theme_font_size_override("font_size", 14)
	column.add_child(words)
	if extra:
		column.add_child(extra)
	readings_list.add_child(card)
	UiMotion.slide_in(card, 0.0, Vector2(0, 14), 0.4)

func update_runs():
	runs_label.text = "Power for %d more instrument run%s" % [runs_left, "" if runs_left == 1 else "s"]
	if runs_left <= 0:
		for button in instrument_buttons.get_children():
			button.disabled = true

func answer(option_id):
	if answered:
		return
	answered = true
	var correct = option_id == sample_id
	was_correct = correct
	science = (8 if correct else 2) + {"clean": 2, "rough": 0, "damaged": -1}[collection]
	if correct and instruments_used.size() <= 2:
		science += 2   # a sharp, efficient identification
	for button in candidate_buttons.get_children():
		button.disabled = true
		if button.text == sample["name"]:
			button.add_theme_color_override("font_disabled_color", Color(0.45, 1.0, 0.6))
		elif button.text == GeologySamples.SAMPLES[option_id]["name"]:
			button.add_theme_color_override("font_disabled_color", Color(1.0, 0.5, 0.45))
	answer_text.text = ("Correct! " if correct else "Not quite: it's %s. " % sample["name"].to_lower()) + sample["about"] + "\n+%d science." % science
	answer_text.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8) if correct else Color(1.0, 0.85, 0.8))
	continue_button.visible = true
	UiMotion.slide_in(answer_text, 0.0, Vector2(0, 12), 0.4)
	play_sound("confirm" if correct else "glitch")

func _on_continue_pressed():
	finished.emit({"sample": sample_id, "name": sample["name"], "correct": was_correct, "science": science,
		"collection": collection, "instruments_used": instruments_used})
	queue_free()

func play_sound(sound_name):
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_effect(sound_name, -6.0)
