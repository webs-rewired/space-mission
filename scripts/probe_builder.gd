extends Node3D

@onready var title_label = $CanvasLayer/TitleLabel
@onready var back_button = $CanvasLayer/BackButton

func _ready():
	title_label.text = "Build a probe for " + GameState.destination
	back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/solar_system.tscn")
