extends Control

# MINIGAME: ROCKET ENGINE TEST LAB (res://scenes/engine_test_lab.tscn)
# Put a real engine from the rocket builder on a test stand (sea level, or a vacuum chamber for top-stage
# engines), light it, and work the throttle and the mixture ratio to meet a test objective, watching the live
# thrust, chamber pressure, wall temperature and Isp. Real engines are tested like this before they fly:
# RS-25s for SLS are fired on the A-1 stand at NASA's Stennis Space Center.
#
# The physics is in scripts/engine_model.gd. Each test picks one of four objectives (some only for engines
# that can throttle), so no two sessions are the same. A medal earns research points the first time
# (scripts/career.gd), and your best score on each engine is kept.
#
# The rocket builder opens this with open_lab(engine_id); closing it sends closed.

signal closed

const EngineModel = preload("res://scripts/engine_model.gd")
const RocketData = preload("res://scripts/rocket_data.gd")
const Career = preload("res://scripts/career.gd")
const SAMPLE_SECONDS = 0.1
const MEDALS = [[85, "GOLD", Color(1.0, 0.82, 0.35), 15], [65, "SILVER", Color(0.8, 0.85, 0.92), 8], [40, "BRONZE", Color(0.85, 0.55, 0.35), 4]]

# The test objectives: [id, title, what to do]
const OBJECTIVES = {
	"rated_power": ["Acceptance test", "Hold 95 to 100% of rated thrust for 8 seconds without overheating. Every flight engine passes this before it's allowed on a rocket."],
	"best_isp": ["Mixture tuning", "Find the mixture ratio that gives the best Isp (the most push from each kilogram of propellant), then hold it for 5 seconds."],
	"throttle_bucket": ["Throttle profile", "Follow the gold band: full power, down to about 70% through \"Max-Q\" (when the air pushes hardest on a climbing rocket), then back up."],
	"cool_running": ["Hot-day test", "Run 15 seconds at full power with the chamber wall under 900 K. Running a little fuel-rich cools the engine, but costs some Isp."],
}

@onready var engine_picker: OptionButton = $Layout/Left/EnginePicker
@onready var specs_label: Label = $Layout/Left/Specs
@onready var throttle_slider: HSlider = $Layout/Left/ThrottleRow/Throttle
@onready var throttle_label: Label = $Layout/Left/ThrottleValue
@onready var mixture_slider: HSlider = $Layout/Left/MixtureRow/Mixture
@onready var mixture_label: Label = $Layout/Left/MixtureValue
@onready var place_picker: OptionButton = $Layout/Left/PlacePicker
@onready var ignite_button: Button = $Layout/Left/Buttons/IgniteButton
@onready var stop_button: Button = $Layout/Left/Buttons/StopButton
@onready var objective_title: Label = $Layout/Left/Objective/Column/Title
@onready var objective_text: Label = $Layout/Left/Objective/Column/Text
@onready var objective_progress: ProgressBar = $Layout/Left/Objective/Column/Progress
@onready var plume: Control = $Layout/Middle/Plume
@onready var thrust_graph: Control = $Layout/Middle/Graphs/Thrust
@onready var pressure_graph: Control = $Layout/Middle/Graphs/Pressure
@onready var wall_graph: Control = $Layout/Middle/Graphs/Wall
@onready var isp_graph: Control = $Layout/Middle/Graphs/Isp
@onready var readouts: Label = $Layout/Right/Readouts
@onready var lesson_label: Label = $Layout/Right/Lesson
@onready var result_box: PanelContainer = $Layout/Right/Result
@onready var result_title: Label = $Layout/Right/Result/Column/Title
@onready var result_text: Label = $Layout/Right/Result/Column/Text
@onready var title_label: Label = $Header/Title
@onready var place_label: Label = $Header/Place

var model = EngineModel.new()
var engine_ids = []
var objective_id = "rated_power"
var clock = 0.0
var sample_timer = 0.0
var progress_seconds = 0.0    # time spent meeting the objective
var best_isp_seen = 0.0
var held_best_isp = 0.0
var test_started_at = 0.0
var test_done = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Header/CloseButton.pressed.connect(close)
	ignite_button.pressed.connect(ignite)
	stop_button.pressed.connect(func(): end_test(""))
	throttle_slider.value_changed.connect(func(value):
		model.throttle = value / 100.0
		update_control_labels())
	mixture_slider.value_changed.connect(func(value):
		model.mixture = value
		update_control_labels())
	place_picker.item_selected.connect(func(index):
		model.in_vacuum = index == 1
		new_objective())
	engine_picker.item_selected.connect(func(index): choose_engine(engine_ids[index]))
	for engine_id in RocketData.ENGINES:
		engine_ids.append(engine_id)
		engine_picker.add_item(RocketData.ENGINES[engine_id]["name"])
	place_picker.add_item("Sea-level test stand (like Stennis A-1)")
	place_picker.add_item("Vacuum chamber (space conditions)")
	result_box.visible = false
	for graph in [thrust_graph, pressure_graph, wall_graph, isp_graph]:
		graph.window_seconds = 20.0

func open_lab(engine_id := ""):
	get_viewport().gui_release_focus()
	if engine_id == "" or not RocketData.ENGINES.has(engine_id):
		engine_id = engine_ids[0]
	engine_picker.selected = engine_ids.find(engine_id)
	choose_engine(engine_id)
	UiMotion.reveal_text(title_label, 0.1, 0.7, 0.4)
	UiMotion.stagger([$Layout/Left, $Layout/Middle, $Layout/Right], 0.1, 0.08, Vector2(0, 20), 0.6)

func close():
	model.running = false
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.stop_engine(0.4)
	closed.emit()
	queue_free()

# (_input, not _unhandled_input: a button left focused underneath would otherwise take Space first)
func _input(event):
	if not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			close()
		KEY_SPACE:
			if not event.echo:
				if model.running:
					end_test("")
				else:
					ignite()
		_:
			return
	get_viewport().set_input_as_handled()

func choose_engine(engine_id):
	var engine = RocketData.ENGINES[engine_id]
	model.set_up(engine_id, engine)
	title_label.text = "ENGINE TEST LAB  ·  %s" % engine["name"].to_upper()
	# Top-stage engines only fire in the vacuum chamber: their huge nozzles don't work in air
	var top_stage = engine["stage"] == "top"
	place_picker.selected = 1 if top_stage else 0
	place_picker.set_item_disabled(0, top_stage)
	model.in_vacuum = top_stage
	throttle_slider.min_value = model.details[2] * 100.0
	throttle_slider.max_value = (model.details[3] + 0.1) * 100.0 if model.can_throttle() else 100.0
	throttle_slider.editable = model.can_throttle()
	throttle_slider.value = 100.0
	mixture_slider.min_value = snapped(model.details[1] * 0.6, 0.01)
	mixture_slider.max_value = snapped(model.details[1] * 1.3, 0.01)
	mixture_slider.step = 0.01
	mixture_slider.value = model.details[1]
	specs_label.text = "Rated thrust: %s kN at sea level, %s kN in space\nIsp: %s s at sea level, %d s in space\nEngine mass: %s kg\nChamber pressure: about %.1f MPa\nUsual mixture: about %.2f parts oxidizer to 1 part fuel\nThrottle: %s" % [
		format_number(engine.get("thrust_sea_level", 0)) if engine.has("thrust_sea_level") else "—", format_number(engine.get("thrust_vacuum", 0)),
		str(engine.get("isp_sea_level", "—")), engine.get("isp_vacuum", 0), format_number(engine.get("mass", 0)), model.details[0], model.details[1],
		("%d%% to %d%%" % [int(model.details[2] * 100), int(model.details[3] * 100)]) if model.can_throttle() else "none (full power only)"]
	plume.fuel = engine.get("fuel", "kerosene")
	plume.nozzle_wide = 1.5 if top_stage else 1.0
	new_objective()

# A fresh test with a random objective that suits this engine
func new_objective():
	model.reset()
	test_done = false
	result_box.visible = false
	var possible = ["rated_power", "best_isp", "cool_running"]
	if model.can_throttle():
		possible.append("throttle_bucket")
	objective_id = possible[randi() % possible.size()]
	objective_title.text = OBJECTIVES[objective_id][0].to_upper()
	objective_text.text = OBJECTIVES[objective_id][1]
	objective_progress.value = 0.0
	progress_seconds = 0.0
	best_isp_seen = 0.0
	held_best_isp = 0.0
	clock = 0.0
	for graph in [thrust_graph, pressure_graph, wall_graph, isp_graph]:
		graph.clear()
	thrust_graph.top_value = model.rated_thrust() * 1.25
	pressure_graph.top_value = model.details[0] * 1.3
	wall_graph.top_value = 1200.0
	wall_graph.limit = 900.0 if objective_id == "cool_running" else EngineModel.WALL_LIMIT
	isp_graph.top_value = model.rated_isp() * 1.15
	place_label.text = "Vacuum chamber" if model.in_vacuum else "Sea-level test stand"
	lesson_label.text = lesson_text()
	ignite_button.disabled = false
	stop_button.disabled = true
	update_control_labels()

func ignite():
	if model.running or test_done:
		if test_done:
			new_objective()
		else:
			return
	model.running = true
	test_started_at = clock
	ignite_button.disabled = true
	stop_button.disabled = false
	ignite_button.text = "Ignite"
	play_sound("thump")
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.start_engine("engine_loop" if model.in_vacuum else "launch_roar", -14.0)

func update_control_labels():
	throttle_label.text = "Throttle: %d%%%s" % [int(round(model.throttle * 100.0)), "   OVERDRIVE: heats fast!" if model.throttle > model.details[3] + 0.001 else ""]
	var offset = model.mixture_offset() * 100.0
	mixture_label.text = "Mixture: %.2f to 1   (%s%d%% %s)" % [model.mixture, "+" if offset >= 0 else "", int(round(offset)), "oxygen-rich: hotter" if offset > 1 else ("fuel-rich: cooler" if offset < -1 else "usual")]

# The band the throttle profile objective asks for, at a time since ignition
func bucket_band(seconds):
	var shape = 1.0
	if seconds > 6.0 and seconds < 9.0:
		shape = lerp(1.0, 0.7, (seconds - 6.0) / 3.0)
	elif seconds >= 9.0 and seconds < 13.0:
		shape = 0.7
	elif seconds >= 13.0 and seconds < 16.0:
		shape = lerp(0.7, 1.0, (seconds - 13.0) / 3.0)
	var rated = model.rated_thrust()
	return [rated * (shape - 0.06), rated * (shape + 0.04)]

func _process(delta):
	clock += delta
	# Keys: W/S throttle, A/D mixture
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		throttle_slider.value += 30.0 * delta
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		throttle_slider.value -= 30.0 * delta
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mixture_slider.value += model.details[1] * 0.12 * delta
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mixture_slider.value -= model.details[1] * 0.12 * delta
	var was_running = model.running
	model.step(delta)
	if was_running and not model.running and model.failed != "":
		end_test(model.failed)
	var seconds = clock - test_started_at
	if model.running and model.spool >= 1.0:
		check_objective(seconds, delta)
	plume.thrust_share = model.thrust() / max(model.rated_thrust(), 0.001)
	plume.in_vacuum = model.in_vacuum
	plume.shake = model.shake
	sample_timer -= delta
	if sample_timer <= 0.0:
		sample_timer = SAMPLE_SECONDS
		var band = bucket_band(seconds) if objective_id == "throttle_bucket" and model.running else [-1.0, -1.0]
		thrust_graph.add_sample(clock, model.thrust(), band[0], band[1])
		pressure_graph.add_sample(clock, model.chamber_pressure())
		wall_graph.add_sample(clock, model.wall_temperature)
		isp_graph.add_sample(clock, model.isp() if model.spool > 0.0 else 0.0)
		update_readouts()

func check_objective(seconds, delta):
	var thrust_share = model.thrust() / max(model.rated_thrust(), 0.001)
	var goal_seconds = 8.0
	match objective_id:
		"rated_power":
			if thrust_share >= 0.95 and thrust_share <= 1.0:
				progress_seconds += delta
		"best_isp":
			goal_seconds = 5.0
			var best_possible = model.rated_isp() * (1.0 - 0.06 * (1.0 - clamp(model.throttle, 0.0, 1.0)))
			if model.isp() >= best_possible * 0.995:
				progress_seconds += delta
				held_best_isp = max(held_best_isp, model.isp())
			else:
				progress_seconds = max(progress_seconds - delta * 0.5, 0.0)
		"throttle_bucket":
			goal_seconds = 16.0
			var band = bucket_band(seconds)
			if model.thrust() >= band[0] and model.thrust() <= band[1]:
				progress_seconds += delta
			if seconds >= 18.0:
				end_test("")
				return
		"cool_running":
			goal_seconds = 15.0
			if thrust_share >= 0.95 and model.wall_temperature < 900.0:
				progress_seconds += delta
	best_isp_seen = max(best_isp_seen, model.isp())
	objective_progress.value = 100.0 * clamp(progress_seconds / goal_seconds, 0.0, 1.0)
	if progress_seconds >= goal_seconds and objective_id != "throttle_bucket":
		end_test("")

# The test is over (stopped, objective met, or the stand cut the engine): score it
func end_test(failure_reason):
	if test_done:
		return
	model.running = false
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.stop_engine(0.8)
	test_done = true
	ignite_button.disabled = false
	ignite_button.text = "New test"
	stop_button.disabled = true
	var goal_seconds = {"rated_power": 8.0, "best_isp": 5.0, "throttle_bucket": 16.0, "cool_running": 15.0}[objective_id]
	var met = clamp(progress_seconds / goal_seconds, 0.0, 1.0)
	var score = int(round(70.0 * met))
	# Efficiency: how good the Isp was, and how much of the margin to the wall limit was kept
	var isp_share = clamp(best_isp_seen / max(model.rated_isp(), 1.0), 0.0, 1.0)
	score += int(round(20.0 * clamp((isp_share - 0.9) / 0.1, 0.0, 1.0)))
	var wall_margin = clamp((wall_graph.limit - model.wall_temperature) / 200.0, 0.0, 1.0)
	score += int(round(10.0 * wall_margin))
	if failure_reason != "":
		score = min(score, 30)
	var medal = null
	for entry in MEDALS:
		if score >= entry[0]:
			medal = entry
			break
	# Best score on this engine and objective, and research points the first time a medal is earned
	var tests = GameState.career.get("engine_tests", {})
	var key = "%s/%s" % [model.engine_id, objective_id]
	var previous_best = tests.get(key, 0)
	var research = 0
	if medal and score > previous_best:
		var previous_medal_points = 0
		for entry in MEDALS:
			if previous_best >= entry[0]:
				previous_medal_points = entry[3]
				break
		research = max(medal[3] - previous_medal_points, 0)
	tests[key] = max(previous_best, score)
	GameState.career["engine_tests"] = tests
	GameState.career["research"] = GameState.career.get("research", 0) + research
	Career.save_data(GameState.career)
	result_title.text = (medal[1] + " MEDAL  ·  %d / 100" % score) if medal else "TEST FAILED  ·  %d / 100" % score
	result_title.add_theme_color_override("font_color", medal[2] if medal else Color(1.0, 0.5, 0.45))
	var lines = []
	if failure_reason != "":
		lines.append(failure_reason)
	lines.append("Objective: %d%% met.  Best Isp: %d s of %d s rated.  Wall: %d K at the end." % [int(met * 100), int(best_isp_seen), int(model.rated_isp()), int(model.wall_temperature)])
	lines.append("Propellant burned: %s kg in %.1f s." % [format_number(model.propellant_used), model.burn_seconds])
	lines.append("Your best on this test: %d.%s" % [max(previous_best, score), ("  +%d research points!" % research) if research > 0 else ""])
	result_text.text = "\n".join(lines)
	result_box.visible = true
	UiMotion.pop_in(result_box, 0.0, 0.5)
	if research > 0:
		GameState.show_toast("%s medal" % medal[1].capitalize(), "%s, %s test. +%d research points." % [RocketData.ENGINES[model.engine_id]["name"], OBJECTIVES[objective_id][0].to_lower(), research], "research")
	play_sound("confirm" if medal else "alarm")

func update_readouts():
	var engine_weight = model.engine.get("mass", 1.0) * EngineModel.G0 / 1000.0
	var lines = [
		"THRUST          %s kN" % format_number(model.thrust()),
		"ISP             %d s" % int(model.isp()) if model.spool > 0.0 else "ISP             —",
		"MASS FLOW       %s kg/s" % format_number(model.mass_flow()),
		"EXHAUST SPEED   %.2f km/s" % (model.isp() * EngineModel.G0 / 1000.0),
		"CHAMBER         %.1f MPa" % model.chamber_pressure(),
		"GAS TEMPERATURE %d K" % int(model.gas_temperature()),
		"WALL            %d K" % int(model.wall_temperature),
		"THRUST/WEIGHT   %d (engine alone)" % int(model.thrust() / max(engine_weight, 0.001)),
		"PROPELLANT      %s kg burned" % format_number(model.propellant_used),
		"BURN TIME       %.1f s" % model.burn_seconds,
	]
	readouts.text = "\n".join(lines)

func lesson_text():
	match objective_id:
		"best_isp":
			return "Isp is the exhaust speed divided by g0 (9.81 m/s²). More Isp means more speed from the same propellant: that's why hydrogen engines (about 450 s in space) beat kerosene ones (about 310 s), even though they push less."
		"throttle_bucket":
			return "Rockets throttle down through Max-Q, about a minute after liftoff, when speed and air together squeeze the rocket hardest. The Space Shuttle's engines went down to about 67%."
		"cool_running":
			return "Engines are cooled by running their own cold propellant through channels in the chamber wall. Running fuel-rich keeps the flame cooler, at the cost of a little Isp."
	return "Mass flow = thrust ÷ (Isp × g0). At full power a big engine like the F-1 swallowed about 2.6 tonnes of propellant every second."

func play_sound(sound_name):
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_effect(sound_name, -6.0)

static func format_number(number):
	var digits = str(int(round(number)))
	var negative = digits.begins_with("-")
	digits = digits.trim_prefix("-")
	var result = ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if negative else "") + digits + result
