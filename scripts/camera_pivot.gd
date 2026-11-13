extends Node3D

# Camera controls for the solar system, like Godot's 3D viewport but without holding the mouse:
#   WASD or arrow keys: move      Space (or E): up      Ctrl (or Q): down      Shift: move faster
#   Right-drag: look around (the mouse hides while you drag, so it can't leave the screen)
#   Scroll: zoom in and out (smoothly)
#   F: follow the planet you clicked      R: go back to the starting view
#
# While you follow a planet, looking around swings the camera around that planet. When you're flying free,
# looking around turns the camera where it is (like turning your head), so the view never swings around a point
# you can't see.
#
# The scene setup stays the same: a CameraPivot node with a Camera3D inside it.
# The Bodies node keeps whatever this camera follows at the center of the game world, so following
# a planet never lags or shakes, even at true scale.

@export var look_speed: float = 0.005
@export var move_speed: float = 1.0
@export var min_distance: float = 0.05
@export var max_distance: float = 450.0
@export var zoom_smoothness: float = 8.0   # higher = the zoom settles faster

@onready var camera: Camera3D = $Camera3D

var looking_around = false
var followed_planet = ""
var left_behind = ""            # the planet you flew away from: F won't jump back to it until you click it again
var follow_gap = Vector3.ZERO   # how far the camera still has to fly to reach the planet
var follow_speed = 4.0          # how quickly that gap closes (faster for longer trips, so every trip takes about a second)
var zoom_target = 40.0
var start_position: Vector3
var start_rotation: Vector3
var start_distance: float

func _ready():
	process_priority = 100   # runs after the planets have moved this frame
	add_to_group("camera_pivot")
	start_position = position
	start_rotation = rotation
	start_distance = camera.position.z
	zoom_target = start_distance

# Starting to look around, zooming and the keys only count when the mouse isn't over a panel or button...
func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			looking_around = true
			# Hide and lock the mouse while looking around, show it again when you let go
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_target = max(min_distance, zoom_target * 0.85)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_target = min(max_distance, zoom_target * 1.18)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			follow_selected_planet()
		elif event.keycode == KEY_R:
			reset_view()

# ...but once you are looking around, every mouse movement counts, wherever the hidden mouse happens to be.
# (Before, a panel or a planet's name under the hidden mouse swallowed the movement and the view stopped turning.)
func _input(event):
	if not looking_around:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		looking_around = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion:
		var camera_place = camera.global_position
		rotation.y -= event.relative.x * look_speed
		rotation.x = clamp(rotation.x - event.relative.y * look_speed, deg_to_rad(-89), deg_to_rad(89))
		if followed_planet == "":
			# Flying free: turn the camera where it is, instead of swinging it around the point in front of it
			global_position += camera_place - camera.global_position
		get_viewport().set_input_as_handled()

func _notification(what):
	# If the window loses focus while looking around, give the mouse back
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		looking_around = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta):
	# Smooth zoom: glide toward the wanted distance (in steps that feel the same when near or far)
	zoom_target = clamp(zoom_target, min_distance, max_distance)
	var settle = min(1.0, zoom_smoothness * delta)
	camera.position.z = exp(lerp(log(max(camera.position.z, 0.000001)), log(zoom_target), settle))

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
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E):
		up_down += 1.0
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_Q):
		up_down -= 1.0

	if forward_back != 0.0 or left_right != 0.0 or up_down != 0.0:
		if followed_planet != "":
			left_behind = followed_planet   # moving yourself stops following, and F won't pull you back
		followed_planet = ""
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
	camera.near = max(0.00005, camera.position.z * 0.01)
	camera.far = clamp(camera.near * 500000.0, 50.0, 200000000.0)

	if followed_planet != "":
		var planet = get_tree().current_scene.find_child(followed_planet, true, false)
		if planet:
			# Ride along with the planet and close the gap smoothly
			follow_gap *= exp(-follow_speed * delta)
			if follow_gap.length() < zoom_target * 0.0005:
				follow_gap = Vector3.ZERO
			global_position = planet.global_position + follow_gap

func follow_selected_planet():
	var scene = get_tree().current_scene
	if scene and "selected_planet" in scene and scene.selected_planet != "":
		if followed_planet == scene.selected_planet:
			followed_planet = ""   # press F again to stop following
			left_behind = scene.selected_planet
		elif scene.selected_planet == left_behind:
			# You flew away from this one yourself: click it (or its name) again to follow it
			get_tree().call_group("space_controls", "show_message", "Click a planet first, then press F to follow it.")
		else:
			follow_planet(scene.selected_planet)

# Called when a planet is clicked or picked from the list: F follows it again
func planet_picked(_planet_name):
	left_behind = ""

# Flies to a planet and zooms in so it fills a good part of the screen, whatever its size
func follow_planet(planet_name):
	var planet = get_tree().current_scene.find_child(planet_name, true, false)
	if planet == null:
		return
	followed_planet = planet_name
	left_behind = ""
	follow_gap = global_position - planet.global_position
	var planet_radius = 1.0
	if planet.has_meta("radius"):
		planet_radius = planet.get_meta("radius")
	elif planet is MeshInstance3D and planet.mesh is SphereMesh:
		planet_radius = planet.mesh.radius * planet.global_transform.basis.get_scale().x
	zoom_to(planet_radius * 6.0)
	# Long trips (like Earth to Pluto at true scale) close the gap faster, so they still take about a second
	var close_enough = max(zoom_target * 0.0005, 0.0000001)
	follow_speed = max(4.0, log(max(follow_gap.length(), close_enough) / close_enough) / 1.2)

func zoom_to(distance):
	zoom_target = clamp(distance, min_distance, max_distance)

func reset_view():
	followed_planet = ""
	left_behind = ""
	follow_gap = Vector3.ZERO
	# Puts the Sun back where it started (the Bodies node moves the solar system around the camera)
	get_tree().call_group("solar_system_world", "reset_origin")
	position = start_position
	rotation = start_rotation
	zoom_to(start_distance)
