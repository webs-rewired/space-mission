extends Node3D

@export var rotate_speed: float = 0.005
@export var zoom_speed: float = 4.0
@export var min_distance: float = 10.0
@export var max_distance: float = 120.0

@onready var camera: Camera3D = $Camera3D
var dragging := false

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera.position.z = max(min_distance, camera.position.z - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera.position.z = min(max_distance, camera.position.z + zoom_speed)
	elif event is InputEventMouseMotion and dragging:
		rotation.y -= event.relative.x * rotate_speed
		rotation.x = clamp(rotation.x - event.relative.y * rotate_speed, deg_to_rad(-89), deg_to_rad(-5))
