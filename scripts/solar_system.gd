extends Node3D

# Planet facts (approximate NASA values). Later these move into game_data.json.
var planets = {
	"Earth": {"au": 1.00, "diameter": 12756, "gravity": 9.8, "sunlight": 100, "goal": "Home. Every mission launches from here."},
	"Moon": {"au": 1.00, "diameter": 3475, "gravity": 1.62, "sunlight": 100, "goal": "Map the surface for future landing sites."},
	"Mars": {"au": 1.52, "diameter": 6792, "gravity": 3.71, "sunlight": 43, "goal": "Land and study the soil."},
	"Jupiter": {"au": 5.20, "diameter": 142984, "gravity": 24.8, "sunlight": 4, "goal": "Orbit Jupiter and study its atmosphere."},
}

var selected_planet = ""

@onready var info_panel = $CanvasLayer/InfoPanel
@onready var name_label = $CanvasLayer/InfoPanel/VBoxContainer/NameLabel
@onready var stats_label = $CanvasLayer/InfoPanel/VBoxContainer/StatsLabel
@onready var mission_button = $CanvasLayer/InfoPanel/VBoxContainer/MissionButton

func _ready():
	info_panel.visible = false
	mission_button.pressed.connect(_on_mission_pressed)

func show_planet_info(planet_name):
	selected_planet = planet_name
	var p = planets[planet_name]
	name_label.text = planet_name
	stats_label.text = "Distance from Sun: %.2f AU\nDiameter: %d km\nGravity: %.2f m/s²\nSunlight: %d%% of Earth's\n\nGoal: %s" % [p["au"], p["diameter"], p["gravity"], p["sunlight"], p["goal"]]
	mission_button.visible = planet_name != "Earth"
	info_panel.visible = true

func _on_mission_pressed():
	GameState.destination = selected_planet
	get_tree().change_scene_to_file("res://scenes/probe_builder.tscn")
