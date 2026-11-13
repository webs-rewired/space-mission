extends Control

signal mission_started

# Scene to load when the player clicks "Start a Mission".
# (Leave empty if Overlay Mode is on.)
@export_file("*.tscn") var mission_scene: String = ""

# Turn this ON only if you placed this menu INSIDE your map scene.
# Then "Start a Mission" just removes the menu so the map underneath is playable.
@export var overlay_mode: bool = false

@onready var start_button: Button = $MenuContainer/VBoxContainer/StartButton

# Anything you add as a child of AnimationLayer shows up BEHIND the menu.
@onready var animation_layer: Node2D = $AnimationLayer


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	start_button.grab_focus()


func _on_start_pressed() -> void:
	print("Start a Mission pressed")

	if overlay_mode:
		mission_started.emit()
		queue_free()
		return

	if mission_scene == "solar_system.tscn":
		print("Mission Scene is empty! Click MainMenu and set it in the Inspector.")
		push_warning("Mission Scene is empty! Set it in the Inspector.")
		return

	get_tree().change_scene_to_file(mission_scene)
