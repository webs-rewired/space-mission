extends Node3D

# Solar System: click a body to see its real stats (including where it is right now), then send a mission to it.
# The facts live in solar_system_data.gd. The Bodies node (solar_system_bodies.gd) builds and moves everything.

const SolarSystemData = preload("res://scripts/solar_system_data.gd")

# Change this if your scene lives somewhere else (right-click the file > Copy Path)
const PROBE_BUILDER_SCENE = "res://scenes/probe_builder.tscn"

# What a mission to each destination tries to do
const MISSION_GOALS = {
	"Venus": "See through the clouds, or survive on the surface.",
	"Moon": "Map the surface for future landing sites.",
	"Mars": "Land and study the soil.",
	"Jupiter": "Orbit Jupiter and study its atmosphere.",
	"Saturn": "Study the rings and moons, and maybe land on Titan.",
}

var selected_planet = ""
var bodies_node: Node = null
var seconds_until_refresh = 0.0

# If you renamed any of these nodes, change the names here too
@onready var info_panel = $CanvasLayer/InfoPanel
@onready var name_label = $CanvasLayer/InfoPanel/VBoxContainer/NameLabel
@onready var stats_label = $CanvasLayer/InfoPanel/VBoxContainer/StatsLabel
@onready var mission_button = $CanvasLayer/InfoPanel/VBoxContainer/MissionButton

func _ready():
	info_panel.visible = false
	mission_button.focus_mode = Control.FOCUS_NONE   # so Space moves the camera instead of pressing it
	mission_button.pressed.connect(_on_mission_pressed)
	# Keep the stats panel in the top right corner, growing to the left and down so it never runs off screen
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label.custom_minimum_size.x = 360
	stats_label.add_theme_font_size_override("font_size", 14)
	info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	bodies_node = get_tree().get_first_node_in_group("solar_system_world")

func _process(delta):
	# Keep the "Right now" line live while the stats are open
	if info_panel.visible and selected_planet != "":
		seconds_until_refresh -= delta
		if seconds_until_refresh <= 0.0:
			seconds_until_refresh = 0.25
			refresh_planet_info()

func format_number(number):
	# 142984 -> "142,984"
	var digits = str(int(number))
	var result = ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return digits + result

func show_planet_info(planet_name):
	if not SolarSystemData.BODIES.has(planet_name):
		return
	selected_planet = planet_name
	refresh_planet_info()
	info_panel.visible = true

func refresh_planet_info():
	var data = SolarSystemData.BODIES[selected_planet]
	var facts = data["facts"]
	var lines = []
	lines.append(facts["type"])
	lines.append("")
	if bodies_node and bodies_node.has_method("live_facts"):
		var live = bodies_node.live_facts(selected_planet)
		if live != "":
			lines.append(live)
			lines.append("")
	lines.append("Distance: " + facts["distance"])
	lines.append("Diameter: %s km" % format_number(facts["diameter_km"]))
	lines.append("Mass: " + facts["mass"])
	var gravity_text = "Surface gravity: %s m/s²" % str(snapped(facts["gravity"], 0.0001 if facts["gravity"] < 0.01 else 0.01))
	if facts.has("gravity_note"):
		gravity_text += " (" + facts["gravity_note"] + ")"
	lines.append(gravity_text)
	if facts["gravity"] >= 0.01:
		lines.append("    You'd weigh %.2f× what you weigh on Earth" % (facts["gravity"] / 9.81))
	lines.append("Escape speed: " + facts["escape_speed"])
	lines.append("Orbital speed: " + facts["orbital_speed"])
	lines.append("Day: " + facts["day"])
	lines.append("Year: " + facts["year"])
	lines.append("Temperature: " + facts["temperature"])
	lines.append("Moons: " + facts["moons"])
	if facts["sunlight"] != "":
		lines.append("Sunlight: " + facts["sunlight"])
	lines.append("Explored: " + facts["explored"])
	if MISSION_GOALS.has(selected_planet):
		lines.append("")
		lines.append("Mission goal: " + MISSION_GOALS[selected_planet])
	lines.append("")
	lines.append("Press F to follow %s with the camera." % data["label"])

	name_label.text = data["label"]
	stats_label.text = "\n".join(lines)
	mission_button.visible = GameState.DESTINATIONS.has(selected_planet)

func _on_mission_pressed():
	GameState.destination = selected_planet
	get_tree().change_scene_to_file(PROBE_BUILDER_SCENE)
