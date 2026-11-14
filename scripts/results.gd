extends Control

const RealRocket = preload("res://scripts/real_rocket.gd")
const SpacecraftLookalike = preload("res://scripts/spacecraft_lookalike.gd")
const SpaceTextures = preload("res://scripts/space_textures.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")

# Results: the mission report. On the left, how the mission went (NASA's four mission segments, then every event).
# On the right, a mission patch, the mission grade and the key numbers. Behind it all, the world you visited with
# your spacecraft in front of it. The node names below must match res://scenes/results.tscn.

const GRADES = [[95, "A+", "Outstanding. A mission NASA would be proud of."], [85, "A", "Excellent engineering and great science."],
	[70, "B", "A solid mission with good science."], [55, "C", "It worked, but there was room to do better."],
	[40, "D", "It barely made it. Check the GO / NO-GO reviews next time."], [0, "F", "The mission fell short of its goals."]]
const GRADE_COLORS = {"A+": Color(0.4, 1.0, 0.6), "A": Color(0.45, 0.95, 0.6), "B": Color(0.55, 0.85, 1.0), "C": Color(1.0, 0.85, 0.4),
	"D": Color(1.0, 0.65, 0.35), "F": Color(1.0, 0.45, 0.4), "LOST": Color(1.0, 0.4, 0.35)}

@onready var box = $Layout/ReportPanel/VBox
@onready var outcome_label = box.get_node("OutcomeLabel")
@onready var score_label = box.get_node("ScoreLabel")
@onready var events_label = box.get_node("Scroll/ScrollColumn/EventsLabel")   # inside a scroll box, so long reports never run off the screen
@onready var real_mission_label = box.get_node("Scroll/ScrollColumn/RealMissionLabel")
@onready var try_again_button = box.get_node("Buttons/TryAgainButton")
@onready var new_destination_button = box.get_node("Buttons/NewDestinationButton")
@onready var kicker_label: Label = box.get_node("Kicker")
@onready var patch = $Layout/Side/Patch
@onready var grade_label: Label = $Layout/Side/GradeTile/Row/Grade
@onready var grade_words: Label = $Layout/Side/GradeTile/Row/Words/GradeWords
@onready var stats_grid: GridContainer = $Layout/Side/Stats
@onready var planet: MeshInstance3D = $View/Viewport/Planet
@onready var probe_holder: Node3D = $View/Viewport/ProbeHolder

var probe_model: Node3D = null

func _ready():
	var destination_name = SolarSystemData.BODIES.get(GameState.destination, {}).get("label", GameState.destination)
	kicker_label.text = "MISSION REPORT   |   %s" % destination_name.to_upper()
	outcome_label.text = GameState.outcome
	score_label.text = "Score: %d / 100\n%s" % [GameState.score, GameState.ending]
	var lines = [segments_review()]
	for log_entry in GameState.mission_log:
		var color = "#7dff9a" if log_entry["ok"] else "#ff7a6e"
		lines.append("[color=%s][b]%s[/b][/color]: %s" % [color, log_entry["title"], log_entry["text"]])
	if not GameState.lost and GameState.data_share < 1.0:
		lines.append("[color=yellow][b]Small antenna[/b][/color]: only %d%% of your science data reached Earth from %s." % [int(GameState.data_share * 100), GameState.destination])
	events_label.text = "\n\n".join(lines)
	real_mission_label.text = "How NASA did it: " + GameState.REAL_MISSIONS.get(GameState.destination, "")
	show_grade()
	show_stats()
	make_patch(destination_name)
	build_view()
	play_ending_sound()
	try_again_button.pressed.connect(_on_try_again_pressed)
	new_destination_button.pressed.connect(_on_new_destination_pressed)

func _process(delta):
	planet.rotate_y(delta * 0.04)
	if probe_model:
		probe_holder.rotate_y(delta * 0.25)

# ---------------------------------------------------------------------------
# The grade, the numbers and the patch
# ---------------------------------------------------------------------------
func show_grade():
	var grade = "LOST" if GameState.lost else "F"
	var words = "The spacecraft was lost. Every real program has lost missions and learned from them: try again!"
	if not GameState.lost:
		for entry in GRADES:
			if GameState.score >= entry[0]:
				grade = entry[1]
				words = entry[2]
				break
	grade_label.text = grade
	grade_label.add_theme_font_size_override("font_size", 40 if grade == "LOST" else 60)
	grade_label.add_theme_color_override("font_color", GRADE_COLORS.get(grade, Color.WHITE))
	grade_words.text = words

func show_stats():
	var days = GameState.trip_years() * 365.25
	var trip_text = "%d days" % int(round(days)) if days < 400.0 else "%.1f years" % (days / 365.25)
	var distance = GameState.DESTINATIONS.get(GameState.destination, {}).get("distance_from_sun_au", 1.0)
	var lookalike = SpacecraftLookalike.LOOKALIKES.get(SpacecraftLookalike.closest(), {})
	add_stat("SCIENCE", "%d points" % int(GameState.science) if not GameState.lost else "none")
	add_stat("DATA HOME", "%d %%" % int(GameState.data_share * 100.0) if not GameState.lost else "0 %")
	add_stat("COST", "%s of %s" % [GameState.money_text(GameState.total_cost()), GameState.money_text(GameState.budget())])
	add_stat("TRIP", trip_text)
	add_stat("FROM THE SUN", "%.2f AU" % distance)
	add_stat("MOST LIKE", lookalike.get("name", "your own design"))

func add_stat(title, value):
	var tile = PanelContainer.new()
	tile.add_theme_stylebox_override("panel", $Layout/Side/GradeTile.get_theme_stylebox("panel"))
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column = VBoxContainer.new()
	tile.add_child(column)
	var heading = Label.new()
	heading.text = title
	heading.theme_type_variation = "DataLabel"
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Color(0.6, 0.66, 0.75))
	column.add_child(heading)
	var number = Label.new()
	number.text = value
	number.theme_type_variation = "TitleLabel"
	number.add_theme_font_size_override("font_size", 20)
	number.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(number)
	stats_grid.add_child(tile)

func make_patch(destination_name):
	var data = SolarSystemData.BODIES.get(GameState.destination, {})
	patch.mission_name = "ORBIT LAB   %s" % destination_name
	var year = int(1970 + floor(((GameState.launch_date if GameState.launch_date > 0.0 else 2461360.0) - 2440587.5) / 365.25))
	patch.bottom_text = "%s   %d" % ["LOST IN SPACE" if GameState.lost else "MISSION COMPLETE", year]
	patch.destination_color = data.get("color", Color(0.75, 0.55, 0.4))
	patch.ring_color = Color(1.0, 0.5, 0.4) if GameState.lost else Color(0.45, 0.8, 1.0)

# ---------------------------------------------------------------------------
# The 3D view behind the report: the destination's real map on a slowly turning globe, with the spacecraft in
# front of it (the real NASA spacecraft your design was closest to)
# ---------------------------------------------------------------------------
func build_view():
	var data = SolarSystemData.BODIES.get(GameState.destination, {})
	var picture = SpaceTextures.find_texture(data.get("images", []))
	var material: StandardMaterial3D = planet.get_surface_override_material(0).duplicate()
	if picture:
		material.albedo_texture = picture
	else:
		material.albedo_color = data.get("color", Color(0.7, 0.6, 0.5))
	if GameState.destination == "Sun":
		material.emission_enabled = true
		material.emission_texture = picture
	planet.set_surface_override_material(0, material)
	if data.has("rings"):
		# Saturn, Uranus, Neptune, Jupiter (and Haumea) get their rings, tilted the way the planet's pole is
		var rings = SpaceTextures.make_rings(data["rings"], 1.0)
		if rings:
			planet.get_parent().add_child.call_deferred(rings)   # beside the globe, so they don't wobble as it turns
			rings.transform = Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(-{"saturn": 26.7, "uranus": 97.8, "neptune": 28.3, "jupiter": 3.1}.get(data["rings"], 15.0))).rotated(Vector3.RIGHT, deg_to_rad(12.0)).scaled(planet.scale * 0.5), planet.position)
	SpaceTextures.add_star_sky($View/Viewport/WorldEnvironment)
	if GameState.lost:
		return   # no spacecraft left to show
	probe_model = SpacecraftLookalike.load_model(SpacecraftLookalike.closest(), 1.6)
	if probe_model:
		probe_holder.add_child(probe_model)

func segments_review():
	var rocket_stack = RealRocket.STACKS.get(RealRocket.closest_stack(GameState.rocket), {})
	var lookalike = SpacecraftLookalike.LOOKALIKES.get(SpacecraftLookalike.closest(), {})
	var rate = GameState.data_rate_kilobits()
	var rate_text = "%.1f megabits per second" % (rate / 1000.0) if rate >= 1000.0 else ("%d kilobits per second" % int(rate) if rate >= 10.0 else "%.2f kilobits per second" % rate)
	var delay = GameState.radio_delay_minutes()
	var delay_text = "%.1f hours" % (delay / 60.0) if delay >= 90.0 else ("%d minutes" % int(round(delay)) if delay >= 1.5 else "%d seconds" % int(round(delay * 60.0)))
	var review = "[color=#8fd4ff][b]YOUR MISSION IN NASA'S FOUR SEGMENTS[/b][/color]"
	review += "\n[b]Launch segment[/b] (the rocket): a rocket like the %s. Mission cost: %s." % [rocket_stack.get("name", "one you designed"), GameState.money_text(GameState.total_cost())]
	review += "\n[b]Space segment[/b] (the spacecraft): %d instrument%s on a spacecraft most like %s." % [GameState.instruments.size(), "" if GameState.instruments.size() == 1 else "s", lookalike.get("name", "your own design")]
	review += "\n[b]Ground segment[/b] (the dishes on Earth): the Deep Space Network heard it at %s, with radio signals taking %s each way." % [rate_text, delay_text]
	review += "\n[b]User segment[/b] (the scientists): %s" % ("the spacecraft was lost, so no data reached them." if GameState.lost else "%d %% of the data reached them, worth %d science points." % [int(GameState.data_share * 100.0), int(GameState.science)])
	return review

# A short jingle for how the mission went, then the menu music comes back
func play_ending_sound():
	var sound = get_node_or_null("/root/AudioManager")
	if sound == null:
		return
	sound.stop_music(0.5)
	sound.stop_ambience(0.5)
	sound.play_effect("jingle_failure" if GameState.lost else "jingle_success", -2.0)
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree():
		sound.play_music("music_menu", 3.0)

func _on_try_again_pressed():
	GameState.go_to_scene("res://scenes/probe_builder.tscn")

func _on_new_destination_pressed():
	GameState.go_to_scene("res://scenes/solar_system.tscn")
