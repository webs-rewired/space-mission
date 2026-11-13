extends Control

# Results: shows how the mission went, the score, what happened on the way and how NASA really did it.
# The node names below must match the results scene.

@onready var box = $CenterContainer/PanelContainer/VBox
@onready var outcome_label = box.get_node("OutcomeLabel")
@onready var score_label = box.get_node("ScoreLabel")
@onready var events_label = box.get_node("Scroll/ScrollColumn/EventsLabel")   # inside a scroll box, so long reports never run off the screen
@onready var real_mission_label = box.get_node("Scroll/ScrollColumn/RealMissionLabel")
@onready var try_again_button = box.get_node("Buttons/TryAgainButton")
@onready var new_destination_button = box.get_node("Buttons/NewDestinationButton")

func _ready():
	outcome_label.text = GameState.outcome
	score_label.text = "Score: %d / 100\n%s" % [GameState.score, GameState.ending]
	var lines = []
	for log_entry in GameState.mission_log:
		var color = "green" if log_entry["ok"] else "red"
		lines.append("[color=%s][b]%s[/b][/color]: %s" % [color, log_entry["title"], log_entry["text"]])
	if not GameState.lost and GameState.data_share < 1.0:
		lines.append("[color=yellow][b]Small antenna[/b][/color]: only %d%% of your science data reached Earth from %s." % [int(GameState.data_share * 100), GameState.destination])
	events_label.text = "\n\n".join(lines)
	real_mission_label.text = "How NASA did it: " + GameState.REAL_MISSIONS.get(GameState.destination, "")
	play_ending_sound()
	try_again_button.pressed.connect(_on_try_again_pressed)
	new_destination_button.pressed.connect(_on_new_destination_pressed)

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
	get_tree().change_scene_to_file("res://scenes/probe_builder.tscn")

func _on_new_destination_pressed():
	get_tree().change_scene_to_file("res://scenes/solar_system.tscn")
