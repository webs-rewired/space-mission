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
	"Phobos": "Find out where Phobos came from and bring back a sample.",
	"Deimos": "Map the dusty little moon and compare it with Phobos.",
	"Io": "Watch the most volcanic world in the solar system erupt.",
	"Europa": "Find out if the ocean under the ice could support life.",
	"Ganymede": "Study the only moon with its own magnetic field.",
	"Callisto": "Explore the most cratered world and its hidden ocean.",
	"Enceladus": "Fly through the geysers and taste the ocean below.",
	"Titan": "Explore lakes of liquid methane under an orange sky.",
	"Titania": "See the half of Titania that no one has ever seen.",
	"Triton": "Study the backwards moon and its nitrogen geysers.",
	"Charon": "Map Charon's red pole and its giant canyons.",
	"Mercury": "Survive the heat and find the ice hiding at the poles.",
	"Uranus": "Find out why Uranus is tipped on its side.",
	"Neptune": "Study the fastest winds in the solar system.",
	"Ceres": "Find out where the bright salt spots come from.",
	"Pluto": "Explore the giant heart and its nitrogen glaciers.",
	"Haumea": "Be the first to see the egg-shaped world up close.",
	"Makemake": "Be the first to visit the red, icy world and its moon.",
	"Eris": "Reach the most distant dwarf planet we know of.",
}

var selected_planet = ""
var bodies_node: Node = null
var seconds_until_refresh = 0.0
var stats_scroll: ScrollContainer = null

# Space kept clear at the bottom of the screen for the time bar
const SPACE_FOR_TIME_BAR = 72

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
	# The stats scroll when they're too long, so the panel never covers the time bar
	stats_scroll = ScrollContainer.new()
	stats_scroll.name = "StatsScroll"
	stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var stats_parent = stats_label.get_parent()
	stats_parent.add_child(stats_scroll)
	stats_parent.move_child(stats_scroll, stats_label.get_index())
	stats_label.reparent(stats_scroll, false)
	stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fit_panel()
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
	if facts.has("moons"):
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
	fit_panel()

# Makes the stats area as tall as its text, but never so tall that the panel reaches the time bar
func fit_panel():
	if stats_scroll == null:
		return
	var screen_height = get_viewport().get_visible_rect().size.y
	var other_parts = name_label.get_combined_minimum_size().y + 30.0
	if mission_button.visible:
		other_parts += mission_button.get_combined_minimum_size().y + 4.0
	var room = max(80.0, screen_height - 10.0 - SPACE_FOR_TIME_BAR - other_parts)
	var text_height = stats_label.get_line_count() * (stats_label.get_line_height() + stats_label.get_theme_constant("line_spacing")) + 8.0
	stats_scroll.custom_minimum_size = Vector2(stats_label.custom_minimum_size.x + 12.0, min(text_height, room))
	info_panel.reset_size()
	info_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)

func _on_mission_pressed():
	GameState.destination = selected_planet
	get_tree().change_scene_to_file(PROBE_BUILDER_SCENE)
