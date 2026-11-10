extends Node3D

# Rocket Builder: stack your own rocket from real engines, tanks and boosters.
# This script builds the whole screen in code, so the scene only needs one Node3D with this script.

# Change these if your scenes live somewhere else (right-click the file > Copy Path)
const PROBE_SCENE = "res://scenes/probe_builder.tscn"
const LAUNCH_SCENE = "res://scenes/launch.tscn"

const RocketData = preload("res://scripts/rocket_data.gd")

# ---------------------------------------------------------------------------
# Plain-language text for this screen
# ---------------------------------------------------------------------------
const STARTING_ROCKET_LABELS = {
	"custom": "My own design",
	"falcon9": "Falcon 9 (cheap, good for nearby worlds)",
	"atlas5": "Atlas V (strong, reaches Jupiter)",
	"sls": "SLS (most powerful, very expensive)",
}

const FUEL_LABELS = {"kerosene": "Kerosene", "hydrogen": "Hydrogen", "methane": "Methane"}

const PART_NAMES = {
	"merlin": "Merlin (Falcon 9)",
	"rd180": "RD-180 (Atlas V)",
	"rs25": "RS-25 (Space Shuttle, SLS)",
	"raptor": "Raptor (Starship)",
	"merlin_vacuum": "Merlin Vacuum (Falcon 9)",
	"rl10": "RL10 (Centaur)",
	"raptor_vacuum": "Raptor Vacuum (Starship)",
	"kerosene_30": "Small (30 t)",
	"kerosene_100": "Medium (100 t)",
	"kerosene_250": "Large (250 t)",
	"kerosene_400": "Extra large (400 t)",
	"hydrogen_21": "Small (21 t)",
	"hydrogen_60": "Medium (60 t)",
	"hydrogen_900": "Giant (900 t)",
	"methane_150": "Medium (150 t)",
	"methane_1200": "Giant (1,200 t)",
	"none": "None",
	"small_boosters_2": "2 small boosters",
	"small_boosters_4": "4 small boosters",
	"giant_boosters_2": "2 giant boosters (SLS)",
	"star48": "Star 48 (used by New Horizons)",
}

const PART_DESCRIPTIONS = {
	"merlin": "Falcon 9's engine. Cheap, so you can use lots of them.",
	"rd180": "One huge, powerful engine. Used on Atlas V.",
	"rs25": "The Space Shuttle's engine. Very fuel-efficient, but about $100M each.",
	"raptor": "Starship's engine. Powerful and cheap. Burns methane.",
	"merlin_vacuum": "Falcon 9's top-stage engine. Strong, with average fuel efficiency.",
	"rl10": "The most fuel-efficient engine here, but not very strong. Best for faraway worlds.",
	"raptor_vacuum": "Starship's space engine. Very strong. Needs big methane tanks.",
	"none_boosters": "No extra help off the launch pad.",
	"small_boosters_2": "Strap-on solid rockets for extra power at liftoff. They burn out after about a minute and fall away.",
	"small_boosters_4": "Four strap-on solid rockets for lots of extra power at liftoff.",
	"giant_boosters_2": "The most powerful boosters ever flown. Huge power, huge price.",
	"none_kick": "No extra push. Fine for the Moon, Mars and Venus.",
	"star48": "A small rocket motor that gives your probe one last push after the top stage. Great for Jupiter and Saturn.",
}

# 1 to 5 dots, shown as simple ratings
const ENGINE_RATINGS = {
	"merlin": {"power": 2, "efficiency": 2},
	"rd180": {"power": 5, "efficiency": 3},
	"rs25": {"power": 3, "efficiency": 5},
	"raptor": {"power": 4, "efficiency": 3},
	"merlin_vacuum": {"power": 3, "efficiency": 3},
	"rl10": {"power": 1, "efficiency": 5},
	"raptor_vacuum": {"power": 5, "efficiency": 4},
}

const GOOD = Color(0.3, 0.85, 0.4)
const BAD = Color(0.95, 0.35, 0.3)

# 3D
var rocket_root: Node3D
var cam_pivot: Node3D
var camera: Camera3D
var tower: Node3D
var cam_dist = 60.0
var dragging = false

# UI
var meters = {}       # name -> {"label": Label, "bar": ProgressBar, "style": StyleBoxFlat}
var tip_label: RichTextLabel
var details_label: RichTextLabel
var launch_button: Button
var options = {}      # setting name -> OptionButton
var option_ids = {}   # setting name -> list of part ids, in dropdown order
var desc_labels = {}  # setting name -> Label under the dropdown
var spins = {}        # setting name -> SpinBox
var updating = false  # stops the controls from reacting while we set them in code

func _ready():
	setup_world()
	build_ui()
	refill_tanks("bottom")
	refill_tanks("top")
	sync_controls()
	refresh()

func _process(delta):
	if not dragging:
		cam_pivot.rotate_y(0.12 * delta)

func _unhandled_input(event):
	# Drag on the 3D side to spin the view, scroll to zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_dist = max(15.0, cam_dist * 0.9)
			place_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_dist = min(400.0, cam_dist * 1.1)
			place_camera()
	elif event is InputEventMouseMotion and dragging:
		cam_pivot.rotate_y(-event.relative.x * 0.006)

# ---------------------------------------------------------------------------
# 3D world: sky, ground, launch pad, tower
# ---------------------------------------------------------------------------
func make_mat(color, metallic = 0.0, roughness = 0.55):
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material

func setup_world():
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.32, 0.62)
	sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.86)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.6)
	sky_mat.ground_bottom_color = Color(0.25, 0.27, 0.22)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.82)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = false
	env.ssao_enabled = true
	env_node.environment = env
	add_child(env_node)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)

	# Ground: grass around a concrete pad, with a flame trench
	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(1200, 1200)
	ground.mesh = plane
	ground.position.y = -0.05
	ground.material_override = make_mat(Color(0.32, 0.4, 0.24), 0.0, 0.95)
	add_child(ground)

	var pad = MeshInstance3D.new()
	var pad_mesh = CylinderMesh.new()
	pad_mesh.top_radius = 32
	pad_mesh.bottom_radius = 34
	pad_mesh.height = 1.0
	pad_mesh.radial_segments = 64
	pad.mesh = pad_mesh
	pad.position.y = -0.5
	pad.material_override = make_mat(Color(0.4, 0.4, 0.39), 0.0, 1.0)
	add_child(pad)

	var trench = MeshInstance3D.new()
	var trench_mesh = BoxMesh.new()
	trench_mesh.size = Vector3(10, 0.1, 40)
	trench.mesh = trench_mesh
	trench.position = Vector3(0, 0.02, 18)
	trench.material_override = make_mat(Color(0.1, 0.09, 0.08), 0.0, 1.0)
	add_child(trench)

	rocket_root = Node3D.new()
	add_child(rocket_root)
	tower = Node3D.new()
	add_child(tower)

	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	camera = Camera3D.new()
	camera.fov = 55
	cam_pivot.add_child(camera)
	camera.current = true

# ---------------------------------------------------------------------------
# Controls on the left
# ---------------------------------------------------------------------------
func build_ui():
	var layer = CanvasLayer.new()
	add_child(layer)

	var panel = PanelContainer.new()
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size.x = 440

	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)

	var panel_column = VBoxContainer.new()
	panel_column.add_theme_constant_override("separation", 6)
	margin.add_child(panel_column)

	var title = Label.new()
	title.text = "Build your rocket"
	title.add_theme_font_size_override("font_size", 24)
	panel_column.add_child(title)

	var goal = Label.new()
	goal.text = "Your rocket has to lift your %d kg probe off Earth and throw it fast enough to reach %s." % [GameState.total_mass(), GameState.destination]
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	panel_column.add_child(goal)

	# The three things that matter, always on screen
	add_meter(panel_column, "speed")
	add_meter(panel_column, "liftoff")
	add_meter(panel_column, "cost")

	var tip_panel = PanelContainer.new()
	panel_column.add_child(tip_panel)
	tip_label = RichTextLabel.new()
	tip_label.bbcode_enabled = true
	tip_label.fit_content = true
	tip_label.scroll_active = false
	tip_panel.add_child(tip_label)

	# Parts scroll, so nothing above or below ever gets squashed
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_column.add_child(scroll)
	var parts_form = VBoxContainer.new()
	parts_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(parts_form)

	var preset_ids = STARTING_ROCKET_LABELS.keys()
	var preset_names = []
	for id in preset_ids:
		preset_names.append(STARTING_ROCKET_LABELS[id])
	add_option(parts_form, "preset", "Start from a real rocket", preset_ids, preset_names)

	add_heading(parts_form, "Bottom stage", "Lifts the whole rocket off the launch pad.")
	add_engine_option(parts_form, "bottom_engine", "bottom")
	add_spin(parts_form, "bottom_engine_count", "How many engines", 1, 9)
	add_option(parts_form, "bottom_tank", "Fuel tank", [], [])
	var booster_ids = RocketData.BOOSTERS.keys()
	var booster_names = []
	for id in booster_ids:
		var booster = RocketData.BOOSTERS[id]
		booster_names.append(PART_NAMES[id] + ("" if booster["count"] == 0 else "  ($%dM)" % (booster["cost_each"] * booster["count"])))
	add_option(parts_form, "boosters", "Side boosters", booster_ids, booster_names)

	add_heading(parts_form, "Top stage", "Takes over high in the sky and throws your probe toward %s." % GameState.destination)
	add_engine_option(parts_form, "top_engine", "top")
	add_spin(parts_form, "top_engine_count", "How many engines", 1, 4)
	add_option(parts_form, "top_tank", "Fuel tank", [], [])

	add_heading(parts_form, "Extra kick (optional)", "One last push for faraway worlds.")
	var kick_stage_ids = RocketData.KICK_STAGES.keys()
	var kick_stage_names = []
	for id in kick_stage_ids:
		var kick = RocketData.KICK_STAGES[id]
		kick_stage_names.append(PART_NAMES[id] + ("" if not kick.has("cost") else "  ($%dM)" % kick["cost"]))
	add_option(parts_form, "kick_stage", "Kick stage", kick_stage_ids, kick_stage_names)

	var science_toggle = CheckButton.new()
	science_toggle.text = "Show the science"
	parts_form.add_child(science_toggle)
	details_label = RichTextLabel.new()
	details_label.bbcode_enabled = true
	details_label.fit_content = true
	details_label.scroll_active = false
	details_label.visible = false
	parts_form.add_child(details_label)
	science_toggle.toggled.connect(func(on): details_label.visible = on)

	var buttons = HBoxContainer.new()
	panel_column.add_child(buttons)
	var back = Button.new()
	back.text = "Back to probe"
	back.pressed.connect(func(): get_tree().change_scene_to_file(PROBE_SCENE))
	buttons.add_child(back)
	launch_button = Button.new()
	launch_button.text = "Launch!"
	launch_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch_button.pressed.connect(func(): get_tree().change_scene_to_file(LAUNCH_SCENE))
	buttons.add_child(launch_button)

func add_meter(parent, key):
	var label = Label.new()
	parent.add_child(label)
	var bar = ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.custom_minimum_size.y = 12
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", style)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.2, 0.22)
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	parent.add_child(bar)
	meters[key] = {"label": label, "bar": bar, "style": style}

func set_meter(key, text, fraction, ok):
	var meter = meters[key]
	meter["label"].text = text
	meter["bar"].value = clamp(fraction, 0.0, 1.0)
	meter["style"].bg_color = GOOD if ok else BAD

func add_heading(parent, text, sub):
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 10
	parent.add_child(spacer)
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 19)
	parent.add_child(label)
	var sub_label = Label.new()
	sub_label.text = sub
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sub_label.add_theme_font_size_override("font_size", 13)
	parent.add_child(sub_label)

func add_option(parent, key, label_text, ids, names):
	var label = Label.new()
	label.text = label_text
	parent.add_child(label)
	var option = OptionButton.new()
	option.clip_text = true
	for item_name in names:
		option.add_item(item_name)
	options[key] = option
	option_ids[key] = ids
	option.item_selected.connect(_on_option.bind(key))
	parent.add_child(option)
	var desc = Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
	desc.add_theme_font_size_override("font_size", 13)
	parent.add_child(desc)
	desc_labels[key] = desc

func add_engine_option(parent, key, stage):
	var ids = []
	var names = []
	for id in RocketData.ENGINES:
		var engine = RocketData.ENGINES[id]
		if engine["stage"] != stage:
			continue
		ids.append(id)
		names.append("%s  ($%dM each)" % [PART_NAMES[id], engine["cost"]])
	add_option(parent, key, "Engine", ids, names)

func add_spin(parent, key, label_text, lo, hi):
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin = SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = 1
	spin.value_changed.connect(_on_spin.bind(key))
	row.add_child(spin)
	spins[key] = spin
	parent.add_child(row)

func dots(filled):
	return "●".repeat(filled) + "○".repeat(5 - filled)

# Only show tanks that hold the fuel the chosen engine burns
func refill_tanks(stage):
	var key = stage + "_tank"
	var fuel = RocketData.ENGINES[GameState.rocket[stage + "_engine"]]["fuel"]
	var ids = []
	var option = options[key]
	option.clear()
	for id in RocketData.TANKS:
		var tank = RocketData.TANKS[id]
		if tank["fuel"] == fuel:
			ids.append(id)
			option.add_item("%s %s  ($%dM)" % [FUEL_LABELS[fuel], PART_NAMES[id].to_lower(), tank["cost"]])
	option_ids[key] = ids
	if not GameState.rocket[key] in ids:
		GameState.rocket[key] = ids[0]

# ---------------------------------------------------------------------------
# Reacting to changes
# ---------------------------------------------------------------------------
func _on_option(index, key):
	if updating:
		return
	var id = option_ids[key][index]
	if key == "preset":
		if id != "custom":
			GameState.rocket = RocketData.STARTING_ROCKETS[id].duplicate()
			refill_tanks("bottom")
			refill_tanks("top")
			sync_controls()
			refresh()
		return
	GameState.rocket[key] = id
	if key == "bottom_engine":
		refill_tanks("bottom")
	if key == "top_engine":
		refill_tanks("top")
	sync_controls()
	refresh()

func _on_spin(value, key):
	if updating:
		return
	GameState.rocket[key] = int(value)
	sync_controls()
	refresh()

# Makes every control show what's in GameState.rocket
func sync_controls():
	updating = true
	for key in options:
		if key == "preset":
			continue
		options[key].select(option_ids[key].find(GameState.rocket[key]))
	for key in spins:
		spins[key].value = GameState.rocket[key]
	var preset_index = 0
	for id in RocketData.STARTING_ROCKETS:
		if RocketData.STARTING_ROCKETS[id] == GameState.rocket:
			preset_index = option_ids["preset"].find(id)
	options["preset"].select(preset_index)
	updating = false
	update_descriptions()

func update_descriptions():
	var rocket = GameState.rocket
	for key in ["bottom_engine", "top_engine"]:
		var id = rocket[key]
		var rating = ENGINE_RATINGS[id]
		desc_labels[key].text = "%s\nPower %s   Fuel efficiency %s" % [PART_DESCRIPTIONS[id], dots(rating["power"]), dots(rating["efficiency"])]
	for key in ["bottom_tank", "top_tank"]:
		var engine = rocket[key.replace("_tank", "_engine")]
		desc_labels[key].text = "Bigger tanks hold more fuel but are heavier to lift. This engine burns %s." % RocketData.FUEL_NAMES[RocketData.ENGINES[engine]["fuel"]]
	desc_labels["boosters"].text = PART_DESCRIPTIONS["none_boosters" if rocket["boosters"] == "none" else rocket["boosters"]]
	desc_labels["kick_stage"].text = PART_DESCRIPTIONS["none_kick" if rocket["kick_stage"] == "none" else rocket["kick_stage"]]
	desc_labels["preset"].text = "Pick one to start, then change any part you like."

func format_number(number):
	# 16700 -> "16,700"
	var digits = str(int(round(number)))
	var result = ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return digits + result

func refresh():
	var report = GameState.rocket_report()
	var cost = GameState.total_cost()
	var budget = GameState.budget()
	var within_budget = cost <= budget
	var strong_enough_to_lift_off = report["liftoff_thrust_to_weight"] >= 1.2
	var top_stage_strong_enough = report["top_thrust_to_weight"] >= 0.4

	set_meter("speed", "Speed: %s of %s m/s needed" % [format_number(report["total_speed"]), format_number(report["speed_needed"])],
		report["total_speed"] / report["speed_needed"], report["fast_enough"])
	var lift_text = "Liftoff power: strong enough" if strong_enough_to_lift_off else "Liftoff power: too heavy to leave the pad"
	set_meter("liftoff", lift_text, report["liftoff_thrust_to_weight"] / 1.2, strong_enough_to_lift_off)
	set_meter("cost", "Cost: $%sM of your $%sM budget" % [format_number(cost), format_number(budget)], float(cost) / budget, within_budget)

	tip_label.text = make_tip(report, strong_enough_to_lift_off, top_stage_strong_enough, within_budget)
	details_label.text = make_details(report)
	launch_button.disabled = not (report["problems"].is_empty() and report["fast_enough"] and within_budget)
	build_rocket_model()

# One clear next step, in plain words
func make_tip(report, strong_enough_to_lift_off, top_stage_strong_enough, within_budget):
	var rocket = GameState.rocket
	if not strong_enough_to_lift_off:
		return "[color=#f26b5b]Too heavy to lift off.[/color] Add more bottom-stage engines or some side boosters."
	if not top_stage_strong_enough:
		return "[color=#f26b5b]The top stage is too weak to lift itself.[/color] Add another top-stage engine or pick a smaller top tank."
	if not report["fast_enough"]:
		var short = format_number(report["speed_needed"] - report["total_speed"])
		var tip = "[color=#f26b5b]Not fast enough, %s m/s short.[/color] " % short
		if rocket["top_engine"] != "rl10":
			tip += "Try the RL10 top-stage engine: it gets the most speed out of its fuel."
		elif rocket["kick_stage"] == "none":
			tip += "Add the Star 48 kick stage for one last push."
		else:
			tip += "Try a stronger rocket, like the Atlas V or SLS starting point."
		return tip
	if not within_budget:
		return "[color=#f26b5b]Over budget.[/color] RS-25 engines and giant boosters are expensive. Try a cheaper starting point like Falcon 9 or Atlas V."
	var spare = format_number(report["total_speed"] - report["speed_needed"])
	return "[color=#4fd96a]Ready to launch![/color] You have %s m/s to spare and $%sM left over." % [spare, format_number(GameState.budget() - GameState.total_cost())]

func make_details(report):
	var lines = []
	lines.append("[b]The rocket equation[/b]")
	lines.append("Speed gained = Isp × 9.81 × ln(full mass ÷ empty mass)")
	lines.append("Isp is fuel efficiency in seconds. Higher Isp means more speed from the same fuel. Each stage drops off when empty, so the next one has less weight to push.")
	lines.append("")
	lines.append("Bottom stage and boosters: %s m/s" % format_number(report["bottom_stage_speed"]))
	lines.append("Top stage: %s m/s" % format_number(report["top_stage_speed"]))
	if report["kick_speed"] > 0:
		lines.append("Kick stage: %s m/s" % format_number(report["kick_speed"]))
	lines.append("Liftoff thrust-to-weight: %.2f (real rockets need about 1.2 or more)" % report["liftoff_thrust_to_weight"])
	lines.append("Top stage thrust-to-weight: %.2f (needs about 0.4 or more)" % report["top_thrust_to_weight"])
	lines.append("Liftoff mass: %s tonnes" % format_number(report["liftoff_mass"] / 1000.0))
	lines.append("")
	lines.append(RocketData.SPEED_NOTE[GameState.destination])
	return "\n".join(lines)

# ---------------------------------------------------------------------------
# Drawing the rocket (1 unit = 1 meter)
# ---------------------------------------------------------------------------
func tank_height(tank):
	var radius = tank["radius"]
	var volume = tank["propellant"] / float(RocketData.FUEL_DENSITY[tank["fuel"]])
	return volume / (PI * radius * radius) + 1.5

func add_cylinder(parent, top_radius, bottom_radius, height, position_in_world, material):
	var mesh_instance = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 48
	mesh.rings = 1
	mesh_instance.mesh = mesh
	mesh_instance.position = position_in_world
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

# A smooth curved nose cone, built from stacked rings
func add_ogive(parent, radius, height, base_y, center, material):
	var steps = 10
	for step in steps:
		var lower_fraction = float(step) / steps
		var upper_fraction = float(step + 1) / steps
		var lower_radius = radius * pow(cos(lower_fraction * PI / 2.0), 0.6)
		var upper_radius = radius * pow(cos(upper_fraction * PI / 2.0), 0.6)
		var ring_height = height / steps
		add_cylinder(parent, upper_radius, lower_radius, ring_height, center + Vector3(0, base_y + ring_height * (step + 0.5), 0), material)

func add_engines(count, tank_radius, bottom_y, bell_height):
	var bell_radius = clamp(tank_radius * 1.7 / (count + 1), 0.35, 1.3)
	var bell_material = make_mat(Color(0.3, 0.3, 0.32), 0.9, 0.35)
	var chamber_material = make_mat(Color(0.55, 0.5, 0.45), 0.8, 0.4)
	var spots = []
	if count == 1:
		spots.append(Vector2.ZERO)
	else:
		var ring = count
		if count >= 7:
			spots.append(Vector2.ZERO)   # one in the middle, like Falcon 9
			ring = count - 1
		for i in ring:
			var angle = TAU * i / ring
			spots.append(Vector2(cos(angle), sin(angle)) * tank_radius * 0.62)
	for spot in spots:
		add_cylinder(rocket_root, bell_radius * 0.35, bell_radius, bell_height, Vector3(spot.x, bottom_y + bell_height / 2.0, spot.y), bell_material)
		add_cylinder(rocket_root, bell_radius * 0.4, bell_radius * 0.35, bell_height * 0.35, Vector3(spot.x, bottom_y + bell_height * 1.15, spot.y), chamber_material)

func add_tank(radius, height, base_y, fuel):
	var body = make_mat(RocketData.TANK_COLORS[fuel], 0.25 if fuel == "methane" else 0.0, 0.45)
	var band = make_mat(Color(0.12, 0.12, 0.13), 0.2, 0.6)
	add_cylinder(rocket_root, radius, radius, height, Vector3(0, base_y + height / 2.0, 0), body)
	add_cylinder(rocket_root, radius + 0.03, radius + 0.03, 0.4, Vector3(0, base_y + 0.2, 0), band)
	add_cylinder(rocket_root, radius + 0.03, radius + 0.03, 0.4, Vector3(0, base_y + height - 0.2, 0), band)
	if fuel == "hydrogen":
		# Insulation foam stripes, like on SLS
		for i in range(1, 4):
			add_cylinder(rocket_root, radius + 0.02, radius + 0.02, 0.15, Vector3(0, base_y + height * i / 4.0, 0), make_mat(Color(0.7, 0.36, 0.12), 0.0, 0.8))

func build_rocket_model():
	for child in rocket_root.get_children():
		child.queue_free()

	var rocket = GameState.rocket
	var white = make_mat(Color(0.95, 0.95, 0.95), 0.0, 0.4)
	var dark = make_mat(Color(0.1, 0.1, 0.11), 0.3, 0.5)
	var y = 0.0

	# Bottom stage
	var bottom_tank = RocketData.TANKS[rocket["bottom_tank"]]
	var bottom_radius = bottom_tank["radius"]
	add_cylinder(rocket_root, bottom_radius, bottom_radius * 1.05, 2.0, Vector3(0, 3.0 + 1.0, 0), dark)   # engine section
	add_engines(rocket["bottom_engine_count"], bottom_radius, 0.3, 2.8)
	y = 5.0
	var bottom_height = tank_height(bottom_tank)
	add_tank(bottom_radius, bottom_height, y, bottom_tank["fuel"])
	var bottom_stage_base = 3.0
	y += bottom_height

	# Side boosters
	var booster = RocketData.BOOSTERS[rocket["boosters"]]
	var booster_span = 0.0
	for i in booster["count"]:
		var angle = TAU * i / booster["count"] + PI / 4.0
		var distance_from_center = bottom_radius + booster["radius"] + 0.15
		booster_span = distance_from_center + booster["radius"]
		var booster_position = Vector3(cos(angle) * distance_from_center, 0, sin(angle) * distance_from_center)
		var booster_height = booster["height"]
		add_cylinder(rocket_root, booster["radius"], booster["radius"], booster_height, booster_position + Vector3(0, bottom_stage_base + booster_height / 2.0, 0), white)
		add_cylinder(rocket_root, booster["radius"] + 0.04, booster["radius"] + 0.04, 0.5, booster_position + Vector3(0, bottom_stage_base + booster_height * 0.7, 0), dark)
		add_ogive(rocket_root, booster["radius"], booster["radius"] * 3.0, bottom_stage_base + booster_height, booster_position, white)
		add_cylinder(rocket_root, booster["radius"] * 0.5, booster["radius"] * 0.9, 2.2, booster_position + Vector3(0, bottom_stage_base - 1.1, 0), make_mat(Color(0.3, 0.3, 0.32), 0.9, 0.35))

	# Interstage, with the top-stage engine hidden inside
	var top_tank = RocketData.TANKS[rocket["top_tank"]]
	var top_radius = top_tank["radius"]
	add_cylinder(rocket_root, top_radius, bottom_radius, 4.0, Vector3(0, y + 2.0, 0), dark)
	y += 4.0

	# Top stage
	var top_height = tank_height(top_tank)
	add_tank(top_radius, top_height, y, top_tank["fuel"])
	y += top_height

	# Fairing: protects the probe (and kick stage) on the way up
	var fairing_radius = max(top_radius, 2.2)
	var fairing_height = 6.0 + (2.0 if rocket["kick_stage"] != "none" else 0.0)
	add_cylinder(rocket_root, fairing_radius, top_radius, 1.2, Vector3(0, y + 0.6, 0), white)
	y += 1.2
	add_cylinder(rocket_root, fairing_radius, fairing_radius, fairing_height, Vector3(0, y + fairing_height / 2.0, 0), white)
	add_cylinder(rocket_root, fairing_radius + 0.02, fairing_radius + 0.02, 0.12, Vector3(0, y + fairing_height * 0.5, 0), make_mat(Color(0.6, 0.6, 0.62), 0.5, 0.5))
	y += fairing_height
	add_ogive(rocket_root, fairing_radius, fairing_radius * 2.6, y, Vector3.ZERO, white)
	y += fairing_radius * 2.6

	build_tower(y, max(bottom_radius, booster_span))
	frame_camera(y)

func build_tower(height, rocket_radius):
	for child in tower.get_children():
		child.queue_free()
	var steel = make_mat(Color(0.55, 0.3, 0.22), 0.6, 0.5)
	var x = -(rocket_radius + 9.0)
	var h = height * 0.9
	# Four corner posts
	for cx in [-2.0, 2.0]:
		for cz in [-2.0, 2.0]:
			var post = MeshInstance3D.new()
			var pm = BoxMesh.new()
			pm.size = Vector3(0.5, h, 0.5)
			post.mesh = pm
			post.position = Vector3(x + cx, h / 2.0, cz)
			post.material_override = steel
			tower.add_child(post)
	# Floors every 8 meters
	var level = 8.0
	while level < h:
		var floor_box = MeshInstance3D.new()
		var fm = BoxMesh.new()
		fm.size = Vector3(4.6, 0.35, 4.6)
		floor_box.mesh = fm
		floor_box.position = Vector3(x, level, 0)
		floor_box.material_override = steel
		tower.add_child(floor_box)
		level += 8.0
	# Access arm reaching to the rocket
	var arm = MeshInstance3D.new()
	var am = BoxMesh.new()
	var arm_len = abs(x) - 1.0
	am.size = Vector3(arm_len, 1.2, 1.6)
	arm.mesh = am
	arm.position = Vector3(x + arm_len / 2.0, h * 0.85, 0)
	arm.material_override = steel
	tower.add_child(arm)

func frame_camera(height):
	cam_pivot.position = Vector3(0, height * 0.5, 0)
	cam_dist = height * 1.05 + 12.0
	place_camera()

func place_camera():
	camera.position = Vector3(0, cam_dist * 0.12, cam_dist)
	camera.rotation_degrees = Vector3(-6, 0, 0)
	# Shift the view so the rocket sits to the right of the control panel
	camera.h_offset = -cam_dist * 0.32
