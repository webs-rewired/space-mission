extends Node3D

# Change this if your results scene lives somewhere else (right-click the file > Copy Path)
const RESULTS_SCENE = "res://results.tscn"

@onready var probe = $Probe
@onready var target = $Target
@onready var event_panel = $CanvasLayer/EventPanel
@onready var event_title = $CanvasLayer/EventPanel/VBox/EventTitle
@onready var event_text = $CanvasLayer/EventPanel/VBox/EventText
@onready var choice_box = $CanvasLayer/EventPanel/VBox/ChoiceButtons
@onready var continue_button = $CanvasLayer/EventPanel/VBox/ContinueButton

const COLORS = {
	"Moon": Color(0.8, 0.8, 0.8),
	"Mars": Color(0.85, 0.35, 0.15),
	"Venus": Color(0.95, 0.85, 0.55),
	"Jupiter": Color(0.85, 0.65, 0.45),
	"Saturn": Color(0.9, 0.8, 0.55),
}

var progress = 0.0
var event_index = 0

func _ready():
	event_panel.visible = false
	continue_button.pressed.connect(_on_continue)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = COLORS[GameState.destination]
	target.material_override = mat
	GameState.build_mission()
	fly_to(checkpoint(0))

func checkpoint(i):
	return float(i + 1) / GameState.events.size()

func set_progress(p):
	progress = p
	var start = Vector3(-10, 0, 0)
	var pos = start.lerp(target.position, p)
	pos.y = sin(p * PI) * 4.0
	probe.position = pos

func fly_to(p):
	var tween = create_tween()
	tween.tween_method(set_progress, progress, p, 1.5)
	tween.finished.connect(_show_event)

func clear_choices():
	for b in choice_box.get_children():
		b.queue_free()

func _show_event():
	var e = GameState.events[event_index]
	clear_choices()
	event_panel.visible = true
	if e.has("choices"):
		event_title.text = "Decision: " + e["title"]
		event_text.text = e["text"]
		continue_button.visible = false
		for i in e["choices"].size():
			var c = e["choices"][i]
			var b = Button.new()
			b.text = c["label"]
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if c.has("needs") and not GameState.req_met(c["needs"]):
				b.disabled = true
				b.text += "  (needs " + GameState.req_names(c["needs"]) + ")"
			b.pressed.connect(_on_choice.bind(i))
			choice_box.add_child(b)
	else:
		var r = GameState.apply_event(e)
		event_title.text = ("Good: " if r["ok"] else "Problem: ") + e["title"]
		event_text.text = r["text"]
		continue_button.visible = true

func _on_choice(index):
	var e = GameState.events[event_index]
	var r = GameState.resolve_choice(e, index)
	clear_choices()
	event_title.text = ("Good: " if r["ok"] else "Problem: ") + e["title"]
	event_text.text = r["text"]
	continue_button.visible = true

func _on_continue():
	event_panel.visible = false
	event_index += 1
	if GameState.lost or event_index >= GameState.events.size():
		go_to_results()
	else:
		fly_to(checkpoint(event_index))

func go_to_results():
	GameState.finish_mission()
	get_tree().change_scene_to_file(RESULTS_SCENE)
