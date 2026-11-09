extends Node3D

# Change these if your scenes live somewhere else (right-click the file > Copy Path)
const SOLAR_SYSTEM_SCENE = "res://solar_system.tscn"
const LAUNCH_SCENE = "res://launch.tscn"

# If you fixed this path before, keep your working version of this line.
@onready var vbox = $CanvasLayer/BuilderPanel/VBox
@onready var title_label = vbox.get_node("TitleLabel")
@onready var slots_box = vbox.get_node("Scroll/Slots")
@onready var rocket_option = vbox.get_node("RocketOption")
@onready var stats_label = vbox.get_node("StatsLabel")
@onready var launch_button = vbox.get_node("LaunchButton")
@onready var back_button = vbox.get_node("BackButton")

var slot_ids = {}
var rocket_ids = []

func _ready():
	title_label.text = "Build a probe for " + GameState.destination
	back_button.pressed.connect(_on_back_pressed)
	launch_button.pressed.connect(_on_launch_pressed)
	build_slot_ui()
	fill_rockets()
	update_stats()

func part_label(id):
	var p = GameState.PARTS[id]
	var text = "%s  (%d kg, $%dM" % [p["name"], p["mass"], p["cost"]]
	if p.has("power_use"):
		text += ", uses %d W" % p["power_use"]
	if p.has("power_at_earth"):
		text += ", %d W at Earth" % p["power_at_earth"]
	if p.has("power_fixed"):
		text += ", %d W anywhere" % p["power_fixed"]
	return text + ")"

func build_slot_ui():
	for child in slots_box.get_children():
		child.queue_free()

	for slot in GameState.SLOT_ORDER:
		var label = Label.new()
		label.text = GameState.SLOT_NAMES[slot]
		slots_box.add_child(label)

		var option = OptionButton.new()
		slot_ids[slot] = []
		for id in GameState.PARTS:
			if GameState.PARTS[id]["slot"] == slot:
				option.add_item(part_label(id))
				slot_ids[slot].append(id)
		option.select(slot_ids[slot].find(GameState.choices[slot]))
		option.item_selected.connect(_on_part_selected.bind(slot))
		slots_box.add_child(option)

	var inst_label = Label.new()
	inst_label.text = "Science instruments (pick any)"
	slots_box.add_child(inst_label)
	for id in GameState.PARTS:
		if GameState.PARTS[id]["slot"] == "instrument":
			var box = CheckBox.new()
			box.text = part_label(id)
			box.button_pressed = id in GameState.instruments
			box.toggled.connect(_on_instrument_toggled.bind(id))
			slots_box.add_child(box)

func _on_part_selected(index, slot):
	GameState.choices[slot] = slot_ids[slot][index]
	update_stats()

func _on_instrument_toggled(pressed, id):
	if pressed and not id in GameState.instruments:
		GameState.instruments.append(id)
	elif not pressed:
		GameState.instruments.erase(id)
	update_stats()

func fill_rockets():
	rocket_option.clear()
	rocket_ids = []
	for id in GameState.ROCKETS:
		rocket_option.add_item("%s rocket  ($%dM)" % [GameState.ROCKETS[id]["name"], GameState.ROCKETS[id]["cost"]])
		rocket_ids.append(id)
	rocket_option.select(rocket_ids.find(GameState.rocket))
	rocket_option.item_selected.connect(_on_rocket_selected)

func _on_rocket_selected(index):
	GameState.rocket = rocket_ids[index]
	update_stats()

func update_stats():
	var mass = GameState.total_mass()
	var capacity = GameState.rocket_capacity()
	var made = GameState.power_made()
	var needed = GameState.power_needed()
	var cost = GameState.total_cost()
	var budget = GameState.budget()

	var mass_ok = mass <= capacity
	var power_ok = made >= needed
	var cost_ok = cost <= budget

	var lines = []
	lines.append(colored("Mass: %d / %d kg" % [mass, capacity], "green" if mass_ok else "red"))
	lines.append(colored("Power at %s: %d W made / %d W needed" % [GameState.destination, made, needed], "green" if power_ok else "yellow"))
	lines.append(colored("Cost: $%dM / $%dM" % [cost, budget], "green" if cost_ok else "red"))
	lines.append("Instruments: %d" % GameState.instruments.size())
	lines.append("")
	if not mass_ok:
		lines.append(colored("Too heavy for this rocket. Pick a bigger rocket or lighter parts.", "red"))
	if not cost_ok:
		lines.append(colored("Over budget. Pick cheaper parts or a cheaper rocket.", "red"))
	if not power_ok:
		lines.append(colored("Warning: not enough power at " + GameState.destination + ". You can launch, but...", "yellow"))
	if GameState.instruments.is_empty():
		lines.append(colored("No instruments means very little science.", "yellow"))
	var landing = GameState.choices["landing"] != "landing_none"
	if not landing and (GameState.is_chosen("inst_drill") or GameState.is_chosen("inst_seismometer")):
		lines.append(colored("The drill and seismometer only work on a lander.", "yellow"))
	if landing and GameState.destination == "Jupiter":
		lines.append(colored("Jupiter has no solid surface to land on.", "yellow"))
	if landing and GameState.destination == "Saturn":
		lines.append("Your lander will go to Saturn's moon Titan.")
	stats_label.text = "\n".join(lines)

	# Gray out rockets that can't lift this probe
	for i in rocket_ids.size():
		var cap = GameState.ROCKETS[rocket_ids[i]]["capacity"][GameState.destination]
		rocket_option.set_item_disabled(i, cap < mass)

	# Only Mass and Cost block launch; Power is just a warning
	launch_button.disabled = not (mass_ok and cost_ok)

func colored(text, color):
	return "[color=%s]%s[/color]" % [color, text]

func _on_launch_pressed():
	get_tree().change_scene_to_file(LAUNCH_SCENE)

func _on_back_pressed():
	get_tree().change_scene_to_file(SOLAR_SYSTEM_SCENE)
