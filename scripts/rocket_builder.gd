extends Node3D

# Rocket Builder: stack your own rocket from real engines, tanks and boosters, on a real launch pad.
# The whole screen is laid out in res://scenes/rocket_builder.tscn: open it in the editor to move or restyle anything.
# This script only fills in the choices and keeps the review, the flight plan, the briefing and the 3D rocket up to date.

const PROBE_SCENE = "res://scenes/probe_builder.tscn"
const LAUNCH_SCENE = "res://scenes/launch.tscn"

const RocketData = preload("res://scripts/rocket_data.gd")
const RocketModel = preload("res://scripts/rocket_model.gd")
const Spacecraft = preload("res://scripts/spacecraft.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const RealRocket = preload("res://scripts/real_rocket.gd")

const GO = Color(0.35, 0.85, 0.45)
const WATCH = Color(1.0, 0.8, 0.3)
const NO_GO = Color(1.0, 0.4, 0.35)
const INFO = Color(0.55, 0.75, 1.0)
const EARTH_SPIN_BONUS = 408        # m/s: Earth's spin pushes a rocket launched east from Florida (28.5° N) this fast for free
const LIFTOFF_PUSH_NEEDED = 1.15    # thrust-to-weight a rocket needs to climb away from the pad (Saturn V lifted off at about 1.17)
const TOP_STAGE_PUSH_NEEDED = 0.4   # thrust-to-weight a top stage needs to reach orbit before falling back
const SAFE_SQUEEZE_G = 6.0          # most spacecraft are built to handle about 6 g of launch push
const TOWER_SCALE = 47.2            # NASA's Mobile Launcher model is 2.46 units tall; the real one is 116 m

@onready var rocket_holder: Node3D = $LaunchPad/RocketHolder
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var preset_choice: OptionButton = %PresetChoice
@onready var choices = {
	"bottom_engine": %BottomEngineChoice,
	"bottom_tank": %BottomTankChoice,
	"boosters": %BoostersChoice,
	"top_engine": %TopEngineChoice,
	"top_tank": %TopTankChoice,
	"kick_stage": %KickStageChoice,
}
@onready var notes = {
	"preset": %PresetNote,
	"bottom_engine": %BottomEngineNote,
	"bottom_tank": %BottomTankNote,
	"boosters": %BoostersNote,
	"top_engine": %TopEngineNote,
	"top_tank": %TopTankNote,
	"kick_stage": %KickStageNote,
}
@onready var engine_counts = {"bottom_engine_count": %BottomEngineCount, "top_engine_count": %TopEngineCount}
@onready var goal_label: Label = %GoalLabel
@onready var readiness_text: RichTextLabel = %ReadinessText
@onready var flight_plan_text: RichTextLabel = %FlightPlanText
@onready var briefing_text: RichTextLabel = %BriefingText
@onready var lookalike_label: Label = %LookalikeLabel
@onready var view_button: Button = %ViewButton
@onready var summary_label: Label = %SummaryLabel
@onready var launch_button: Button = %LaunchButton

var choice_ids = {}          # setting name -> part ids, in the order the dropdown lists them
var preset_ids = []          # starting rocket ids, in the order the dropdown lists them
var updating = false         # true while this script sets the controls, so they don't react to it
var show_my_parts = false
var camera_distance = 170.0
var wanted_distance = 170.0
var wanted_height = 45.0
var dragging = false
var turning_by_itself = true

func _ready():
	place_launch_tower()
	var destination_label = SolarSystemData.BODIES.get(GameState.destination, {}).get("label", GameState.destination)
	goal_label.text = "Lift your %s kg probe off Earth and throw it toward %s." % [format_number(GameState.total_mass()), destination_label]
	fill_choices()
	sync_controls()
	refresh()

# NASA's Mobile Launcher (the tower SLS launches from). The scene expects it in res://assets/rockets/; if it was put
# somewhere else in the project, find it there. With no tower at all, the rocket stands right on the concrete.
func place_launch_tower():
	var tower = get_node_or_null("LaunchPad/LaunchTower")
	if tower != null and tower.get_child_count() > 0:
		return
	var path = Spacecraft.find_model("mobile_launcher.glb")
	if path != "" and load(path) is PackedScene:
		var model = load(path).instantiate()
		model.scale = Vector3.ONE * TOWER_SCALE
		model.position.y = 1.0
		$LaunchPad.add_child(model)
	else:
		rocket_holder.position.y = 1.0

# ---------------------------------------------------------------------------
# The 3D view: the camera circles the pad by itself until you drag it
# ---------------------------------------------------------------------------
func _process(delta):
	if turning_by_itself:
		camera_pivot.rotation.y += delta * 0.08
	camera_distance = lerp(camera_distance, wanted_distance, min(1.0, delta * 3.0))
	camera.position = Vector3(0, 0, camera_distance)
	camera_pivot.position.y = lerp(camera_pivot.position.y, wanted_height, min(1.0, delta * 3.0))

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			if event.pressed:
				turning_by_itself = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			wanted_distance = max(25.0, wanted_distance * 0.88)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			wanted_distance = min(900.0, wanted_distance * 1.14)
	elif event is InputEventMouseMotion and dragging:
		camera_pivot.rotation.y -= event.relative.x * 0.006
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - event.relative.y * 0.004, deg_to_rad(-60), deg_to_rad(15))

# ---------------------------------------------------------------------------
# Filling in the dropdowns
# ---------------------------------------------------------------------------
func fill_choices():
	preset_choice.clear()
	preset_choice.add_item("My own design")
	preset_ids = ["custom"]
	for rocket_id in RocketData.STARTING_ROCKET_ORDER:
		preset_choice.add_item(RocketData.REAL_ROCKETS[rocket_id]["menu"])
		preset_ids.append(rocket_id)
	for stage in ["bottom", "top"]:
		var option = choices[stage + "_engine"]
		option.clear()
		choice_ids[stage + "_engine"] = []
		for engine_id in RocketData.ENGINES:
			var engine = RocketData.ENGINES[engine_id]
			if engine["stage"] != stage:
				continue
			var thrust = engine["thrust_sea_level"] if stage == "bottom" else engine["thrust_vacuum"]
			option.add_item("%s   %s kN, %d s, %s each" % [engine["name"], format_number(thrust), engine["isp_vacuum"], GameState.money_text(engine["cost"])])
			choice_ids[stage + "_engine"].append(engine_id)
	var boosters_option = choices["boosters"]
	boosters_option.clear()
	choice_ids["boosters"] = []
	for booster_id in RocketData.BOOSTERS:
		var booster = RocketData.BOOSTERS[booster_id]
		var text = booster["name"]
		if booster["count"] > 0:
			text += "   " + GameState.money_text(booster["cost_each"] * booster["count"])
		boosters_option.add_item(text)
		choice_ids["boosters"].append(booster_id)
	var kick_option = choices["kick_stage"]
	kick_option.clear()
	choice_ids["kick_stage"] = []
	for kick_id in RocketData.KICK_STAGES:
		var kick = RocketData.KICK_STAGES[kick_id]
		kick_option.add_item(kick["name"] + ("   " + GameState.money_text(kick["cost"]) if kick.has("cost") else ""))
		choice_ids["kick_stage"].append(kick_id)
	refill_tanks("bottom")
	refill_tanks("top")

# Only list the tanks that hold the fuel the chosen engine burns
func refill_tanks(stage):
	var setting = stage + "_tank"
	var fuel = RocketData.ENGINES[GameState.rocket[stage + "_engine"]]["fuel"]
	var option = choices[setting]
	option.clear()
	choice_ids[setting] = []
	for tank_id in RocketData.TANKS:
		var tank = RocketData.TANKS[tank_id]
		if tank["fuel"] != fuel:
			continue
		option.add_item("%s   %s" % [tank["name"], GameState.money_text(tank["cost"])])
		choice_ids[setting].append(tank_id)
	if not GameState.rocket[setting] in choice_ids[setting]:
		GameState.rocket[setting] = choice_ids[setting][0]

# Makes every control show what's in GameState.rocket
func sync_controls():
	updating = true
	for setting in choices:
		choices[setting].select(choice_ids[setting].find(GameState.rocket[setting]))
	for setting in engine_counts:
		engine_counts[setting].value = GameState.rocket[setting]
	preset_choice.select(max(0, preset_ids.find(matching_preset())))
	updating = false

func matching_preset():
	for rocket_id in RocketData.STARTING_ROCKETS:
		if RocketData.STARTING_ROCKETS[rocket_id] == GameState.rocket:
			return rocket_id
	return ""

# ---------------------------------------------------------------------------
# Reacting to the player (these are connected to the controls in rocket_builder.tscn)
# ---------------------------------------------------------------------------
func _on_preset_selected(index):
	if updating or preset_ids[index] == "custom":
		return
	GameState.rocket = RocketData.STARTING_ROCKETS[preset_ids[index]].duplicate()
	show_my_parts = false
	refill_tanks("bottom")
	refill_tanks("top")
	sync_controls()
	refresh()

func _on_part_selected(index, setting):
	if updating:
		return
	GameState.rocket[setting] = choice_ids[setting][index]
	if setting.ends_with("_engine"):
		refill_tanks(setting.replace("_engine", ""))
	sync_controls()
	refresh()

func _on_engine_count_changed(value, setting):
	if updating:
		return
	GameState.rocket[setting] = int(value)
	sync_controls()
	refresh()

func _on_view_pressed():
	show_my_parts = not show_my_parts
	rebuild_model()

func _on_back_pressed():
	GameState.go_to_scene(PROBE_SCENE)

func _on_launch_pressed():
	GameState.go_to_scene(LAUNCH_SCENE)

# ---------------------------------------------------------------------------
# Keeping everything up to date
# ---------------------------------------------------------------------------
func refresh():
	var report = GameState.rocket_report()
	var numbers = extra_numbers(report)
	update_notes()
	update_review(report, numbers)
	update_flight_plan(report)
	update_briefing(report, numbers)
	update_summary(report)
	rebuild_model()

func part_note(part_id):
	var facts = RocketData.PART_FACTS.get(part_id, {})
	if facts.is_empty():
		return ""
	return "%s. %s" % [facts["like"], facts["about"]]

func update_notes():
	var rocket = GameState.rocket
	var preset = matching_preset()
	notes["preset"].text = RocketData.REAL_ROCKETS[preset]["facts"] if preset != "" else "Your own design. Pick a real rocket to start from, then change any part."
	for setting in ["bottom_engine", "bottom_tank", "boosters", "top_engine", "top_tank"]:
		notes[setting].text = part_note(rocket[setting])
	notes["kick_stage"].text = part_note("no_kick" if rocket["kick_stage"] == "none" else rocket["kick_stage"])

# Numbers the review needs that the rocket report doesn't already have
func extra_numbers(report):
	var rocket = GameState.rocket
	var bottom_engine = RocketData.ENGINES[rocket["bottom_engine"]]
	var bottom_tank = RocketData.TANKS[rocket["bottom_tank"]]
	var booster = RocketData.BOOSTERS[rocket["boosters"]]
	var liftoff_thrust = bottom_engine["thrust_sea_level"] * rocket["bottom_engine_count"] + booster.get("thrust_each", 0) * booster["count"]
	# Just before the bottom stage runs dry it is nearly empty, so its engines push hardest on what's left
	var mass_at_cutoff = report["liftoff_mass"] - bottom_tank["propellant"] - (booster.get("propellant_each", 0) + booster.get("empty_mass_each", 0)) * booster["count"]
	var squeeze = bottom_engine["thrust_vacuum"] * 1000.0 * rocket["bottom_engine_count"] / (mass_at_cutoff * RocketData.GRAVITY)
	return {"liftoff_thrust": liftoff_thrust, "squeeze_g": squeeze}

func line(status, title, text):
	var colors = {"go": GO, "watch": WATCH, "no_go": NO_GO, "info": INFO}
	var words = {"go": "GO", "watch": "WATCH", "no_go": "NO-GO", "info": "NOTE"}
	return "[color=#%s]● %s[/color]  [b]%s[/b]\n%s\n" % [colors[status].to_html(false), words[status], title, text]

# Launch Readiness Review: each line is GO (green), WATCH (yellow) or NO-GO (red), like NASA's real launch polls
func update_review(report, numbers):
	var rocket = GameState.rocket
	var lines = ["[b]LAUNCH READINESS REVIEW[/b]\nBefore every launch, each team answers \"go\" or \"no-go\". Every line must be GO or WATCH to fly.\n"]

	var liftoff = report["liftoff_thrust_to_weight"]
	var liftoff_text = "Thrust-to-weight %.2f: the engines push with %s kN against %s tonnes. Falcon 9 lifts off at about 1.4, Saturn V at about 1.17." % [liftoff, format_number(numbers["liftoff_thrust"]), format_number(report["liftoff_mass"] / 1000.0)]
	if liftoff < LIFTOFF_PUSH_NEEDED:
		lines.append(line("no_go", "Lifting off the pad", liftoff_text + " Too heavy: add engines or boosters, or use a smaller tank."))
	elif liftoff < 1.3:
		lines.append(line("watch", "Lifting off the pad", liftoff_text + " A slow climb wastes fuel fighting gravity."))
	else:
		lines.append(line("go", "Lifting off the pad", liftoff_text))

	var top = report["top_thrust_to_weight"]
	var top_text = "Thrust-to-weight %.2f when it lights. A weak top stage falls back toward the ground before it's fast enough to stay in orbit." % top
	if top < TOP_STAGE_PUSH_NEEDED:
		lines.append(line("no_go", "Top stage strength", top_text + " Add a top-stage engine or use a smaller top tank."))
	elif top < 0.5:
		lines.append(line("watch", "Top stage strength", top_text + " Just enough, like Atlas V's gentle Centaur."))
	else:
		lines.append(line("go", "Top stage strength", top_text))

	var spare = report["total_speed"] - report["speed_needed"]
	var speed_text = "%s of %s m/s needed. Bottom stage%s %s, top stage %s" % [format_number(report["total_speed"]), format_number(report["speed_needed"]),
		" and boosters" if rocket["boosters"] != "none" else "", format_number(report["bottom_stage_speed"]), format_number(report["top_stage_speed"])]
	if report["kick_speed"] > 0:
		speed_text += ", kick stage %s" % format_number(report["kick_speed"])
	speed_text += " m/s."
	if spare < 0:
		lines.append(line("no_go", "Speed to reach %s" % GameState.destination, speed_text + " %s m/s short. Try the RL10 top engine, a kick stage or a bigger rocket." % format_number(-spare)))
	elif spare < report["speed_needed"] * 0.03:
		lines.append(line("watch", "Speed to reach %s" % GameState.destination, speed_text + " Only %s m/s to spare. Real missions keep a little extra for a less-than-perfect launch." % format_number(spare)))
	else:
		lines.append(line("go", "Speed to reach %s" % GameState.destination, speed_text + " %s m/s to spare." % format_number(spare)))

	var cost = GameState.total_cost()
	var budget = GameState.budget()
	var cost_text = "Rocket %s + probe %s = %s of your %s budget." % [GameState.money_text(GameState.rocket_cost()), GameState.money_text(GameState.probe_cost()), GameState.money_text(cost), GameState.money_text(budget)]
	if cost > budget:
		lines.append(line("no_go", "Budget", cost_text + " RS-25 engines and giant boosters are the expensive parts."))
	elif cost > budget * 0.9:
		lines.append(line("watch", "Budget", cost_text + " Almost no money left for surprises."))
	else:
		lines.append(line("go", "Budget", cost_text))

	# Just before the bottom stage runs dry it's almost empty, so the same engines shove much harder
	var squeeze = numbers["squeeze_g"]
	var squeeze_text = "At full power the push would peak at %.1f g just before the bottom stage runs dry. Space Shuttle astronauts never felt more than 3 g." % squeeze
	if squeeze <= SAFE_SQUEEZE_G:
		lines.append(line("go", "Squeeze on your probe", squeeze_text))
	elif squeeze <= SAFE_SQUEEZE_G * 1.7:
		lines.append(line("go", "Squeeze on your probe", squeeze_text + " The engines throttle down near the end to keep it under %d g, like real rockets do." % int(SAFE_SQUEEZE_G)))
	else:
		lines.append(line("watch", "Squeeze on your probe", squeeze_text + " Even throttled down that's a rough ride for your probe. Use fewer engines or a bigger bottom tank."))

	var count = rocket["bottom_engine_count"]
	if count >= 9:
		lines.append(line("info", "Engine out", "%d engines: it can lose one and still make it, like Falcon 9 did on its CRS-1 flight to the Space Station in 2012." % count))
	elif count == 1:
		lines.append(line("info", "Engine out", "1 engine: there's no backup if it fails, so it has to be extremely reliable."))
	else:
		lines.append(line("info", "Engine out", "%d engines: losing one late in the climb might still work out." % count))
	if rocket["bottom_engine"] in ["merlin", "raptor"]:
		lines.append(line("info", "Reusable booster", "This bottom stage flies back and lands after launch, which is why its engines cost so little."))
	for problem in report["problems"]:
		if problem.contains("fuel mismatch"):
			lines.append(line("no_go", "Fuel", problem))
	readiness_text.text = "\n".join(lines)

func clock_text(seconds):
	return "T+%d:%02d" % [int(seconds) / 60, int(seconds) % 60]

# Minute by minute, what will happen after liftoff (the launch scene plays the same timeline)
func update_flight_plan(report):
	var rocket = GameState.rocket
	var plan = RocketData.flight_plan(rocket, report)
	var events = [[0.0, "Liftoff from Launch Complex 39B, Kennedy Space Center, Florida"]]
	if plan["booster_burnout"] > 0.0:
		events.append([plan["booster_burnout"], "Side boosters burn out and fall into the Atlantic"])
	events.append([plan["main_engine_cutoff"], "Main engine cutoff: the bottom stage is empty"])
	events.append([plan["main_engine_cutoff"] + 3.0, "Stage separation" + (": the booster turns around to land" if rocket["bottom_engine"] in ["merlin", "raptor"] else "")])
	events.append([plan["top_ignition"], "Top stage lights"])
	events.append([plan["fairing"], "Fairing opens: the air is too thin to hurt your probe now"])
	events.append([plan["orbit"], "Top stage shuts down: in orbit around Earth, 28,000 km/h"])
	events.append([plan["escape_start"], "Top stage relights: the escape burn toward %s" % GameState.destination])
	events.append([plan["escape_end"], "Escape burn complete"])
	if rocket["kick_stage"] != "none":
		events.append([plan["kick_end"], RocketData.KICK_STAGES[rocket["kick_stage"]].get("caption", "The kick stage spins up and fires its last push")])
	events.append([plan["kick_end"] + 60.0, "Your probe separates and heads for %s" % GameState.destination])
	events.sort_custom(func(first, second): return first[0] < second[0])
	var lines = ["[b]FLIGHT PLAN[/b]\nWhat happens after liftoff, worked out from your engines and tanks.\n"]
	for event in events:
		lines.append("[color=#%s]%s[/color]  %s" % [INFO.to_html(false), clock_text(event[0]), event[1]])
	lines.append("")
	lines.append("Launching east from Florida, Earth's spin gives the rocket %d m/s for free. That's why the US launches from Florida, as far south as it can." % EARTH_SPIN_BONUS)
	flight_plan_text.text = "\n".join(lines)

func update_briefing(report, numbers):
	var rocket = GameState.rocket
	var lines = []
	var preset = matching_preset()
	if preset != "":
		lines.append("[b]%s[/b]\n%s\n" % [RocketData.REAL_ROCKETS[preset]["name"].to_upper(), RocketData.REAL_ROCKETS[preset]["facts"]])
	lines.append("[b]WHY ROCKETS HAVE STAGES[/b]\nMost of a rocket is fuel. Once a tank is empty it's dead weight, so it drops away and the next, smaller stage has less to push. That's how a rocket goes fast enough for space.\n")
	lines.append("[b]THE ROCKET EQUATION[/b]\nSpeed gained = Isp × 9.81 × ln(full mass ÷ empty mass)\nIsp is fuel efficiency in seconds: higher means more speed from the same fuel. Hydrogen engines like the RL10 reach 465 s, kerosene engines about 300 to 350 s.\n")
	lines.append("[b]YOUR ROCKET[/b]")
	lines.append("Liftoff mass: %s tonnes, of which your probe is %s kg" % [format_number(report["liftoff_mass"] / 1000.0), format_number(GameState.total_mass())])
	lines.append("Liftoff thrust: %s kN" % format_number(numbers["liftoff_thrust"]))
	lines.append("Bottom stage: %d × %s on a %s" % [rocket["bottom_engine_count"], RocketData.ENGINES[rocket["bottom_engine"]]["name"], RocketData.TANKS[rocket["bottom_tank"]]["name"].to_lower()])
	if rocket["boosters"] != "none":
		lines.append("Boosters: %s" % RocketData.BOOSTERS[rocket["boosters"]]["name"].to_lower())
	lines.append("Top stage: %d × %s on a %s" % [rocket["top_engine_count"], RocketData.ENGINES[rocket["top_engine"]]["name"], RocketData.TANKS[rocket["top_tank"]]["name"].to_lower()])
	if rocket["kick_stage"] != "none":
		lines.append("Kick stage: %s" % RocketData.KICK_STAGES[rocket["kick_stage"]]["name"])
	lines.append("")
	lines.append(RocketData.SPEED_NOTE[GameState.destination])
	briefing_text.text = "\n".join(lines)

func update_summary(report):
	var cost = GameState.total_cost()
	var ready = report["problems"].is_empty() and report["fast_enough"] and cost <= GameState.budget()
	summary_label.text = "%s t at liftoff    %s of %s m/s    %s of %s    %s" % [format_number(report["liftoff_mass"] / 1000.0), format_number(report["total_speed"]),
		format_number(report["speed_needed"]), GameState.money_text(cost), GameState.money_text(GameState.budget()), "GO for launch" if ready else "NO-GO: see the review"]
	summary_label.add_theme_color_override("font_color", GO if ready else NO_GO)
	launch_button.disabled = not ready

func format_number(number):
	var digits = str(int(round(number)))
	var result = ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return digits + result

# ---------------------------------------------------------------------------
# The rocket on the pad: the real rocket when your design matches one, otherwise your exact parts
# ---------------------------------------------------------------------------
func rebuild_model():
	for child in rocket_holder.get_children():
		child.queue_free()
	var preset = matching_preset()
	var real_rocket = RocketData.REAL_ROCKETS.get(preset, {})
	var real_model = null
	if not real_rocket.is_empty() and not show_my_parts:
		# The real rocket, stacked from the same stage models the launch uses
		var stack_id = RealRocket.stack_for_preset(preset)
		real_model = RealRocket.assemble(stack_id) if stack_id != "" else null
		if real_model != null:
			real_model["root"].rotation_degrees.y = real_rocket.get("turn_degrees", 0.0)
		else:
			real_model = load_real_model(real_rocket)
	var height = 0.0
	if real_model != null:
		rocket_holder.add_child(real_model["root"])
		height = real_model["height"]
		lookalike_label.text = "The real %s, %d m tall" % [real_rocket["name"], int(real_rocket["height"])]
		view_button.text = "Show my parts"
	else:
		var pieces = RocketModel.build(GameState.rocket)
		for flame in pieces["booster_flames"] + pieces["bottom_flames"] + pieces["top_flames"]:
			flame.visible = false
		rocket_holder.add_child(pieces["root"])
		height = pieces["height"]
		if real_rocket.is_empty():
			lookalike_label.text = "Your own design, %d m tall" % int(height)
		elif show_my_parts:
			lookalike_label.text = "Your parts, at their real sizes"
			view_button.text = "Show the real %s" % real_rocket["name"]
		else:
			lookalike_label.text = "Your parts (the %s model files aren't in the project)" % real_rocket["name"]
	view_button.visible = real_model != null or (show_my_parts and not real_rocket.is_empty())
	wanted_height = rocket_holder.global_position.y + height * 0.5
	wanted_distance = height * 1.9 + 50.0

# Loads a 3D model of a real rocket, stands it on the pad and scales it to the real rocket's height. Returns null if the file is missing.
func load_real_model(real_rocket):
	var path = Spacecraft.find_model(real_rocket["model"])
	if path == "":
		return null
	var scene = load(path)
	if not scene is PackedScene:
		return null
	var model = scene.instantiate()
	var holder = Node3D.new()
	holder.add_child(model)
	var box = Spacecraft.model_bounds(model, Transform3D.IDENTITY, null)
	if box == null:
		return null
	var shrink = real_rocket["height"] / max(box.size.y, 0.001)
	model.scale = model.scale * shrink
	var center = box.get_center() * shrink
	model.position = Vector3(-center.x, -box.position.y * shrink, -center.z)   # bottom of the rocket on the pad
	holder.rotation_degrees.y = real_rocket.get("turn_degrees", 0.0)
	return {"root": holder, "height": box.size.y * shrink}
