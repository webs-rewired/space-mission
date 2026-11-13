extends Node3D

# Keeps falling snow, drizzle or floating dust around whoever is watching

func _process(_delta):
	var camera = get_viewport().get_camera_3d()
	if camera:
		global_position = camera.global_position
