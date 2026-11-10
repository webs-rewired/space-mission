extends Node3D

# Probe Builder: pick the parts for your spacecraft.

# Change these if your scenes live somewhere else (right-click the file > Copy Path)
const SOLAR_SYSTEM_SCENE = "res://scenes/solar_system.tscn"
const ROCKET_SCENE = "res://scenes/rocket_builder.tscn"

# If you fixed this path before, keep your working version of this line.
@onready var builder_column = $CanvasLayer/BuilderPanel/VBox
@onready var title_label = builder_column.get_node("TitleLabel")
@onready var parts_list = builder_column.get_node("Scroll/Slots")
@onready var stats_label = builder_column.get_node("StatsLabel")
@onready var next_button = builder_column.get_node("LaunchButton")
@onready var back_button = builder_column.get_node("BackButton")

# For each slot (power, battery...), the part ids in the same order as its dropdown
var part_ids_by_slot = {}

func _ready():
	title_label.text = "Build a probe for " + GameState.destination
	next_button.text = "Next: build your rocket"
	back_button.pressed.connect(_on_back_pressed)
	next_button.pressed.connect(_on_next_pressed)
	# The rocket is now built on its own screen, so hide the old rocket dropdown if it's still here
	var old_rocket_dropdown = builder_column.get_node_or_null("RocketOption")
	if old_rocket_dropdown:
		old_rocket_dropdown.visible = false
	build_parts_list()
	update_stats()

func part_description(part_id):
	var part = GameState.PARTS[part_id]
	var text = "%s  (%d kg, $%dM" % [part["name"], part["mass"], part["cost"]]
	if part.has("power_used"):
		text += ", uses %d W" % part["power_used"]
	if part.has("power_at_earth"):
		text += ", %d W at Earth" % part["power_at_earth"]
	if part.has("power_anywhere"):
		text += ", %d W anywhere" % part["power_anywhere"]
	return text + ")"

func build_parts_list():
	for old_item in parts_list.get_children():
		old_item.queue_free()

	for slot in GameState.SLOT_ORDER:
		var slot_label = Label.new()
		slot_label.text = GameState.SLOT_NAMES[slot]
		parts_list.add_child(slot_label)

		var dropdown = OptionButton.new()
		part_ids_by_slot[slot] = []
		for part_id in GameState.PARTS:
			if GameState.PARTS[part_id]["slot"] == slot:
				dropdown.add_item(part_description(part_id))
				part_ids_by_slot[slot].append(part_id)
		dropdown.select(part_ids_by_slot[slot].find(GameState.choices[slot]))
		dropdown.item_selected.connect(_on_part_selected.bind(slot))
		parts_list.add_child(dropdown)

	var instruments_label = Label.new()
	instruments_label.text = "Science instruments (pick any)"
	parts_list.add_child(instruments_label)
	for part_id in GameState.PARTS:
		if GameState.PARTS[part_id]["slot"] == "instrument":
			var checkbox = CheckBox.new()
			checkbox.text = part_description(part_id)
			checkbox.button_pressed = part_id in GameState.instruments
			checkbox.toggled.connect(_on_instrument_toggled.bind(part_id))
			parts_list.add_child(checkbox)

func _on_part_selected(dropdown_index, slot):
	GameState.choices[slot] = part_ids_by_slot[slot][dropdown_index]
	update_stats()

func _on_instrument_toggled(is_checked, part_id):
	if is_checked and not part_id in GameState.instruments:
		GameState.instruments.append(part_id)
	elif not is_checked:
		GameState.instruments.erase(part_id)
	update_stats()

func update_stats():
	var mass = GameState.total_mass()
	var power_made = GameState.power_made()
	var power_needed = GameState.power_needed()
	var cost = GameState.probe_cost()
	var budget = GameState.budget()

	var enough_power = power_made >= power_needed
	var within_budget = cost <= budget

	var lines = []
	lines.append("Probe mass: %d kg (a heavier probe needs a bigger rocket)" % mass)
	lines.append(colored("Power at %s: %d W made / %d W needed" % [GameState.destination, power_made, power_needed], "green" if enough_power else "yellow"))
	lines.append(colored("Probe cost: $%dM of your $%dM budget (the rocket comes next)" % [cost, budget], "green" if within_budget else "red"))
	lines.append("")
	if not within_budget:
		lines.append(colored("The probe alone is over budget. Pick cheaper parts.", "red"))
	if not enough_power:
		lines.append(colored("Not enough power at %s. You can still launch, but..." % GameState.destination, "yellow"))
	if GameState.instruments.is_empty():
		lines.append(colored("No instruments means very little science.", "yellow"))
	var has_lander = GameState.choices["landing"] != "landing_none"
	if not has_lander and (GameState.is_chosen("instrument_drill") or GameState.is_chosen("instrument_seismometer")):
		lines.append(colored("The drill and seismometer only work on a lander.", "yellow"))
	if has_lander and GameState.destination == "Jupiter":
		lines.append(colored("Jupiter has no solid surface to land on.", "yellow"))
	if has_lander and GameState.destination == "Saturn":
		lines.append("Your lander will go to Saturn's moon Titan.")
	stats_label.text = "\n".join(lines)

	next_button.disabled = not within_budget

func colored(text, color):
	return "[color=%s]%s[/color]" % [color, text]

func _on_next_pressed():
	get_tree().change_scene_to_file(ROCKET_SCENE)

func _on_back_pressed():
	get_tree().change_scene_to_file(SOLAR_SYSTEM_SCENE)
