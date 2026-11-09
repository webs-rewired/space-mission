extends Node3D

@export var orbit_speed: float = 0.5

func _process(delta):
	rotate_y(orbit_speed * delta)
	
