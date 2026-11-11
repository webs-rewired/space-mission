extends StaticBody3D

# Old click sphere on each planet. No longer needed: the Bodies node turns these off and the Controls node
# works out clicks on screen instead. Kept so scenes that still have ClickArea nodes load without errors.

@export var planet_name: String = "Earth"

func _input_event(camera, event, event_position, normal, shape_index):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_tree().current_scene.show_planet_info(planet_name)
