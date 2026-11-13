extends Node3D

# Drifts slowly around the spot it started from, following the ground (a dust devil crossing the plain)

@export var speed = 4.0               # meters per second
@export var wander_radius = 120.0

var center = Vector3.ZERO
var angle = 0.0

func _ready():
	center = position
	angle = randf() * TAU

func _process(delta):
	angle += delta * speed / max(wander_radius, 1.0)
	position = center + Vector3(cos(angle) * wander_radius, 0.0, sin(angle * 0.7) * wander_radius * 0.6)
	var site = get_tree().get_first_node_in_group("landing_site")
	if site and site.has_method("ground_height"):
		position.y = site.ground_height(Vector2(global_position.x, global_position.z))

# Heads over to pass close by a spot (a dust devil coming for the rover)
func pass_near(spot):
	center = Vector3(spot.x, 0.0, spot.z) - Vector3(cos(angle) * wander_radius, 0.0, sin(angle * 0.7) * wander_radius * 0.6) + Vector3(18.0, 0.0, 10.0)
