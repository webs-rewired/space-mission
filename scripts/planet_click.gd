extends StaticBody3D

@export var planet_name: String = "Earth"

func _input_event(camera, event, event_position, normal, shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		#print("Clicked ", planet_name)
		get_tree().current_scene.show_planet_info(planet_name)
