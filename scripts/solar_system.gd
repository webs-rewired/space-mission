extends Node3D

# Solar System: click a planet to see its real stats, then send a mission to it.

# Change this if your scene lives somewhere else (right-click the file > Copy Path)
const PROBE_BUILDER_SCENE = "res://scenes/probe_builder.tscn"

# Real facts, rounded (NASA planetary fact sheets).
const PLANET_FACTS = {
	"Sun": {
		"type": "Star",
		"distance": "At the center of the solar system",
		"diameter_km": 1392700,
		"mass": "1.99 × 10^30 kg (333,000 Earths)",
		"gravity": 274.0,
		"escape_speed": 617.7,
		"orbital_speed": "Circles the Milky Way at about 230 km/s",
		"day": "About 25 Earth days at its equator",
		"year": "About 230 million years to circle the Milky Way",
		"temperature": "About 5,500 °C at the surface",
		"moons": "8 planets orbit it",
		"sunlight": "",
		"goal": "",
	},
	"Venus": {
		"type": "Rocky planet",
		"distance": "0.72 AU (108 million km) from the Sun",
		"diameter_km": 12104,
		"mass": "4.87 × 10^24 kg (0.82 Earths)",
		"gravity": 8.87,
		"escape_speed": 10.4,
		"orbital_speed": "35.0 km/s",
		"day": "243 Earth days, spinning backwards",
		"year": "225 Earth days",
		"temperature": "About 464 °C, hot enough to melt lead",
		"moons": "0",
		"sunlight": "191% of Earth's",
		"goal": "See through the clouds, or survive on the surface.",
	},
	"Earth": {
		"type": "Rocky planet",
		"distance": "1.00 AU (150 million km) from the Sun",
		"diameter_km": 12756,
		"mass": "5.97 × 10^24 kg",
		"gravity": 9.81,
		"escape_speed": 11.2,
		"orbital_speed": "29.8 km/s",
		"day": "23.9 hours",
		"year": "365.25 days",
		"temperature": "About 15 °C",
		"moons": "1",
		"sunlight": "100%",
		"goal": "Home. Every mission launches from here.",
	},
	"Moon": {
		"type": "Moon of Earth",
		"distance": "384,400 km from Earth",
		"diameter_km": 3475,
		"mass": "7.35 × 10^22 kg (0.012 Earths)",
		"gravity": 1.62,
		"escape_speed": 2.4,
		"orbital_speed": "1.0 km/s around Earth",
		"day": "27.3 Earth days (the same side always faces Earth)",
		"year": "Orbits Earth every 27.3 days",
		"temperature": "From -173 °C at night to 127 °C in the day",
		"moons": "0",
		"sunlight": "100% of Earth's",
		"goal": "Map the surface for future landing sites.",
	},
	"Mars": {
		"type": "Rocky planet",
		"distance": "1.52 AU (228 million km) from the Sun",
		"diameter_km": 6792,
		"mass": "6.42 × 10^23 kg (0.11 Earths)",
		"gravity": 3.71,
		"escape_speed": 5.0,
		"orbital_speed": "24.1 km/s",
		"day": "24.6 hours",
		"year": "687 Earth days",
		"temperature": "About -65 °C",
		"moons": "2 (Phobos and Deimos)",
		"sunlight": "43% of Earth's",
		"goal": "Land and study the soil.",
	},
	"Jupiter": {
		"type": "Gas giant",
		"distance": "5.20 AU (778 million km) from the Sun",
		"diameter_km": 142984,
		"mass": "1.90 × 10^27 kg (318 Earths)",
		"gravity": 24.8,
		"escape_speed": 59.5,
		"orbital_speed": "13.1 km/s",
		"day": "9.9 hours, the shortest of any planet",
		"year": "11.9 Earth years",
		"temperature": "About -110 °C at the cloud tops",
		"moons": "More than 90 known",
		"sunlight": "4% of Earth's",
		"goal": "Orbit Jupiter and study its atmosphere.",
	},
	"Saturn": {
		"type": "Gas giant",
		"distance": "9.54 AU (1.43 billion km) from the Sun",
		"diameter_km": 120536,
		"mass": "5.68 × 10^26 kg (95 Earths)",
		"gravity": 10.4,
		"escape_speed": 35.5,
		"orbital_speed": "9.7 km/s",
		"day": "10.7 hours",
		"year": "29.4 Earth years",
		"temperature": "About -140 °C at the cloud tops",
		"moons": "More than 270 known, including Titan",
		"sunlight": "1% of Earth's",
		"goal": "Study the rings and moons, and maybe land on Titan.",
	},
}

var selected_planet = ""

# If you renamed any of these nodes, change the names here too
@onready var info_panel = $CanvasLayer/InfoPanel
@onready var name_label = $CanvasLayer/InfoPanel/VBoxContainer/NameLabel
@onready var stats_label = $CanvasLayer/InfoPanel/VBoxContainer/StatsLabel
@onready var mission_button = $CanvasLayer/InfoPanel/VBoxContainer/MissionButton

func _ready():
	info_panel.visible = false
	mission_button.focus_mode = Control.FOCUS_NONE   # so Space pauses time instead of pressing it
	mission_button.pressed.connect(_on_mission_pressed)
	# Keep the stats panel in the top right corner, growing to the left and down so it never runs off screen
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label.custom_minimum_size.x = 340
	stats_label.add_theme_font_size_override("font_size", 14)
	info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)

func format_number(number):
	# 142984 -> "142,984"
	var digits = str(int(number))
	var result = ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return digits + result

func show_planet_info(planet_name):
	if not PLANET_FACTS.has(planet_name):
		return
	selected_planet = planet_name
	var facts = PLANET_FACTS[planet_name]
	var weight_compared_with_earth = facts["gravity"] / 9.81

	var lines = []
	lines.append(facts["type"])
	lines.append("")
	lines.append("Distance: " + facts["distance"])
	lines.append("Diameter: %s km" % format_number(facts["diameter_km"]))
	lines.append("Mass: " + facts["mass"])
	lines.append("Surface gravity: %.2f m/s²" % facts["gravity"])
	lines.append("    You'd weigh %.2f× what you weigh on Earth" % weight_compared_with_earth)
	lines.append("Escape speed: %.1f km/s" % facts["escape_speed"])
	lines.append("Orbital speed: " + facts["orbital_speed"])
	lines.append("Day: " + facts["day"])
	lines.append("Year: " + facts["year"])
	lines.append("Temperature: " + facts["temperature"])
	lines.append("Moons: " + facts["moons"])
	if facts["sunlight"] != "":
		lines.append("Sunlight: " + facts["sunlight"])
	if facts["goal"] != "":
		lines.append("")
		lines.append("Mission goal: " + facts["goal"])
	lines.append("")
	lines.append("Press F to follow %s with the camera." % planet_name)

	name_label.text = planet_name
	stats_label.text = "\n".join(lines)
	mission_button.visible = planet_name != "Earth" and planet_name != "Sun"
	info_panel.visible = true

func _on_mission_pressed():
	GameState.destination = selected_planet
	get_tree().change_scene_to_file(PROBE_BUILDER_SCENE)
