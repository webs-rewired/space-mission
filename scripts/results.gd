extends Control

const RealRocket = preload("res://scripts/real_rocket.gd")
const SpacecraftLookalike = preload("res://scripts/spacecraft_lookalike.gd")

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
	var lines = [segments_review()]
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

# The mission summed up the way NASA organizes every science mission: in four segments
# (from NASA's "Design and Develop Science Missions" guide): launch, space, ground and user.
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
