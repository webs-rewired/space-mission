extends Node3D

# Spins this node, which carries a planet around the Sun (or a moon around its planet).
# Follows the time controls: pause, faster, slower and reverse.

@export var orbit_speed: float = 0.5

func _process(delta):
	rotate_y(orbit_speed * delta * GameState.time_speed)
