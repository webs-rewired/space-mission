extends Control

@onready var vbox = $CenterContainer/PanelContainer/VBox
@onready var outcome_label = vbox.get_node("OutcomeLabel")
@onready var score_label = vbox.get_node("ScoreLabel")
@onready var events_label = vbox.get_node("EventsLabel")
@onready var real_label = vbox.get_node("RealMissionLabel")
@onready var try_again = vbox.get_node("Buttons/TryAgainButton")
@onready var new_dest = vbox.get_node("Buttons/NewDestinationButton")

func _ready():
	outcome_label.text = GameState.outcome
	score_label.text = "Score: %d / 100" % GameState.score

	var lines = []
	for e in GameState.events:
		var color = "green" if e["ok"] else "red"
		lines.append("[color=%s][b]%s[/b][/color]: %s" % [color, e["title"], e["text"]])
	if not GameState.lost and GameState.data_share < 1.0:
		lines.append("[color=yellow][b]Small antenna[/b][/color]: only %d%% of your science data reached Earth from %s." % [int(GameState.data_share * 100), GameState.destination])
	events_label.text = "\n\n".join(lines)

	real_label.text = "How NASA did it: " + GameState.REAL_MISSIONS[GameState.destination]

	try_again.pressed.connect(_on_try_again)
	new_dest.pressed.connect(_on_new_destination)

func _on_try_again():
	get_tree().change_scene_to_file("res://scenes/probe_builder.tscn")

func _on_new_destination():
	get_tree().change_scene_to_file("res://scenes/solar_system.tscn")
