extends Node3D

# Camera controls for the solar system, like Godot's 3D viewport but without holding the mouse:
#   WASD or arrow keys: move      Q / E: down / up      Shift: move faster
#   Right-drag: look around (the mouse hides while you drag, so it can't leave the screen)
#   Scroll: zoom in and out
#   F: follow the planet you clicked      R: go back to the starting view
#
# The scene setup stays the same: a CameraPivot node with a Camera3D inside it.

@export var look_speed: float = 0.005
@export var move_speed: float = 1.0
@export var min_distance: float = 2.0
@export var max_distance: float = 250.0

@onready var camera: Camera3D = $Camera3D

var looking_around = false
var followed_planet = ""
var follow_gap = Vector3.ZERO   # how far the camera still has to fly to reach the planet
var start_position: Vector3
var start_rotation: Vector3
var start_distance: float

func _ready():
	start_position = position
	start_rotation = rotation
	start_distance = camera.position.z

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			looking_around = event.pressed
			# Hide and lock the mouse while looking around, show it again when you let go
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking_around else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera.position.z = max(min_distance, camera.position.z * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera.position.z = min(max_distance, camera.position.z * 1.1)
	elif event is InputEventMouseMotion and looking_around:
		rotation.y -= event.relative.x * look_speed
		rotation.x = clamp(rotation.x - event.relative.y * look_speed, deg_to_rad(-89), deg_to_rad(89))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			follow_selected_planet()
		elif event.keycode == KEY_R:
			reset_view()

func _notification(what):
	# If the window loses focus while looking around, give the mouse back
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		looking_around = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta):
	var forward_back = 0.0
	var left_right = 0.0
	var up_down = 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		forward_back -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		forward_back += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		left_right -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		left_right += 1.0
	if Input.is_key_pressed(KEY_E):
		up_down += 1.0
	if Input.is_key_pressed(KEY_Q):
		up_down -= 1.0

	if forward_back != 0.0 or left_right != 0.0 or up_down != 0.0:
		followed_planet = ""   # moving yourself stops following
		# Move in the direction the camera is facing, flat along the solar system
		var facing = Basis(Vector3.UP, rotation.y)
		var flat_move = facing * Vector3(left_right, 0, forward_back)
		if flat_move.length() > 0:
			flat_move = flat_move.normalized()
		var movement = flat_move + Vector3(0, up_down, 0)
		# Move faster when zoomed out, so it feels the same at any zoom
		var speed = camera.position.z * 0.8 * move_speed
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= 3.0
		position += movement * speed * delta

	# How close and how far the camera can see, adjusted to the zoom so tiny planets don't get cut off
	camera.near = max(0.0001, camera.position.z * 0.01)
	camera.far = clamp(camera.near * 500000.0, 50.0, 30000.0)

	if followed_planet != "":
		var planet = get_tree().current_scene.find_child(followed_planet, true, false)
		if planet:
			# Ride along with the planet and close the gap smoothly, even when the planet moves fast
			follow_gap = follow_gap.lerp(Vector3.ZERO, min(1.0, 4.0 * delta))
			global_position = planet.global_position + follow_gap

func follow_selected_planet():
	var scene = get_tree().current_scene
	if scene and "selected_planet" in scene and scene.selected_planet != "":
		if followed_planet == scene.selected_planet:
			followed_planet = ""   # press F again to stop following
		else:
			follow_planet(scene.selected_planet)

# Flies to a planet and zooms in so it fills a good part of the screen, whatever its size
func follow_planet(planet_name):
	followed_planet = planet_name
	var planet = get_tree().current_scene.find_child(planet_name, true, false)
	if planet:
		follow_gap = global_position - planet.global_position
	var planet_radius = 1.0
	if planet is MeshInstance3D and planet.mesh is SphereMesh:
		planet_radius = planet.mesh.radius * planet.global_transform.basis.get_scale().x
	camera.position.z = clamp(planet_radius * 6.0, min_distance, max_distance)

func reset_view():
	followed_planet = ""
	position = start_position
	rotation = start_rotation
	camera.position.z = start_distance
