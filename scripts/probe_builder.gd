extends Node3D

@onready var vbox = $CanvasLayer/BuilderPanel/VBox
@onready var title_label = vbox.get_node("TitleLabel")
@onready var back_button = vbox.get_node("BackButton")
@onready var stats_label = vbox.get_node("StatsLabel")
@onready var launch_button = vbox.get_node("LaunchButton")
@onready var rocket_option = vbox.get_node("RocketOption")

var slot_options = {}
var slot_ids = {}
var rocket_ids = []

func _ready():
	title_label.text = "Build a probe for " + GameState.destination
	back_button.pressed.connect(_on_back_pressed)
	launch_button.pressed.connect(_on_launch_pressed)
	slot_options = {
		"power": vbox.get_node("PowerOption"),
		"battery": vbox.get_node("BatteryOption"),
		"antenna": vbox.get_node("AntennaOption"),
		"shield": vbox.get_node("ShieldOption"),
	}
	for slot in slot_options:
		fill_slot(slot)
	fill_rockets()
	update_stats()

func fill_slot(slot):
	var option = slot_options[slot]
	option.clear()
	slot_ids[slot] = []
	for id in GameState.PARTS:
		var part = GameState.PARTS[id]
		if part["slot"] == slot:
			option.add_item(part["name"])
			slot_ids[slot].append(id)
	option.select(slot_ids[slot].find(GameState.choices[slot]))
	option.item_selected.connect(func(index): _on_part_selected(slot, index))

func _on_part_selected(slot, index):
	GameState.choices[slot] = slot_ids[slot][index]
	update_stats()

func fill_rockets():
	rocket_option.clear()
	for id in GameState.ROCKETS:
		rocket_option.add_item(GameState.ROCKETS[id]["name"] + " rocket")
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
	lines.append(colored("Power: %d W made / %d W needed" % [made, needed], "green" if power_ok else "yellow"))
	lines.append(colored("Cost: $%dM / $%dM" % [cost, budget], "green" if cost_ok else "red"))
	lines.append("")
	if not mass_ok:
		lines.append(colored("Too heavy for this rocket. Pick a bigger rocket or lighter parts.", "red"))
	if not cost_ok:
		lines.append(colored("Over budget. Pick cheaper parts or a cheaper rocket.", "red"))
	if not power_ok:
		lines.append(colored("Warning: not enough power at " + GameState.destination + ". You can launch, but...", "yellow"))
	stats_label.text = "\n".join(lines)

	# Gray out rockets that can't lift this probe
	for i in rocket_ids.size():
		var cap = GameState.ROCKETS[rocket_ids[i]]["capacity"][GameState.destination]
		rocket_option.set_item_disabled(i, cap < mass)

	# Only Mass and Cost block launch; Power is just a warning
	launch_button.disabled = not (mass_ok and cost_ok)

func colored(text, color):
	return "[color=%s]%s[/color]" % [color, text]

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/solar_system.tscn")  # <- use your path
	
func _on_launch_pressed():
	get_tree().change_scene_to_file("res://scenes/launch.tscn")
