extends Node3D

# Launch: the probe flies to its destination and the flight events pop up along the way.

# Change this if your results scene lives somewhere else (right-click the file > Copy Path)
const RESULTS_SCENE = "res://scenes/results.tscn"

# Real planet images, Saturn's rings and the starry sky
const SpaceTextures = preload("res://scripts/space_textures.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const MoonSurfaces = preload("res://scripts/moon_surfaces.gd")
const BeltBuilder = preload("res://scripts/belt_builder.gd")

@onready var probe = $Probe
@onready var target_planet = $Target
@onready var event_panel = $CanvasLayer/EventPanel
@onready var event_title = $CanvasLayer/EventPanel/VBox/EventTitle
@onready var event_text = $CanvasLayer/EventPanel/VBox/EventText
@onready var choice_buttons = $CanvasLayer/EventPanel/VBox/ChoiceButtons
@onready var continue_button = $CanvasLayer/EventPanel/VBox/ContinueButton

# Real sizes compared with Earth (Earth = 1.0). The Earth sphere in this scene has radius 1.
const SIZE_COMPARED_WITH_EARTH = {
	"Moon": 0.27,
	"Mars": 0.53,
	"Venus": 0.95,
	"Jupiter": 11.2,
	"Saturn": 9.45,
}

const FLIGHT_START = Vector3(-10, 0, 0)
var flight_end = Vector3.ZERO
var flight_progress = 0.0
var event_index = 0

func _ready():
	event_panel.visible = false
	continue_button.pressed.connect(_on_continue_pressed)
	set_up_target_planet()
	GameState.build_mission()
	fly_to(progress_at_event(0))

func set_up_target_planet():
	var destination = GameState.destination
	var data = SolarSystemData.BODIES.get(destination, {})
	var is_moon_of_planet = data.has("orbit") and data["orbit"].has("satellite")
	if is_moon_of_planet:
		target_planet.material_override = MoonSurfaces.make_material(destination)
		if data.get("irregular", false):
			target_planet.mesh = BeltBuilder.make_rock_mesh(abs(destination.hash()) % 1000, 0.12, false)
	else:
		SpaceTextures.texture_planet(target_planet, destination)

	# Earth (where the probe starts) and the starry sky
	var earth = get_node_or_null("Earth")
	if earth is MeshInstance3D:
		SpaceTextures.texture_planet(earth, "Earth")
	for child in get_children():
		if child is WorldEnvironment:
			SpaceTextures.add_star_sky(child)

	# Scale the planet to its real size compared with Earth
	var planet_radius = SIZE_COMPARED_WITH_EARTH.get(destination, data.get("radius_km", 6371.0) / 6371.0)
	# Tiny worlds like Phobos, Ceres and Makemake are drawn bigger so you can see them
	planet_radius = max(planet_radius, 0.18)
	var sphere_radius = target_planet.mesh.radius if target_planet.mesh is SphereMesh else 1.0
	target_planet.scale = data.get("shape", Vector3.ONE) * (planet_radius / sphere_radius)

	# Big planets sit farther away so they don't swallow the screen
	target_planet.position = Vector3(6 + planet_radius, 0, 0)
	flight_end = target_planet.position - Vector3(planet_radius + 1.0, 0, 0)

	if destination == "Saturn":
		add_saturn_rings(sphere_radius)
	elif data.has("rings") and not is_moon_of_planet:
		var rings = SpaceTextures.make_rings(data["rings"], sphere_radius)
		# Undo the world's stretched shape (Haumea is egg-shaped) so its ring stays round
		rings.scale = Vector3.ONE / data.get("shape", Vector3.ONE)
		target_planet.add_child(rings)
		# Tip the world over by its real tilt (Uranus lies on its side, so you see its rings face-on like Voyager 2 did)
		target_planet.rotation_degrees.z = {"Uranus": 98.0, "Neptune": 28.0, "Jupiter": 3.0, "Haumea": 30.0}.get(destination, 10.0)
	if is_moon_of_planet:
		add_parent_planet(data["parent"], planet_radius)

# For a moon mission, its planet hangs in the sky behind it, at its real size compared with Earth
func add_parent_planet(parent_name, moon_radius):
	var parent_data = SolarSystemData.BODIES[parent_name]
	var parent_radius = parent_data["radius_km"] / 6371.0
	var parent_planet = MeshInstance3D.new()
	parent_planet.name = "ParentPlanet"
	var sphere = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	parent_planet.mesh = sphere
	SpaceTextures.texture_planet(parent_planet, parent_name)
	parent_planet.scale = Vector3.ONE * parent_radius
	add_child(parent_planet)
	parent_planet.position = target_planet.position + Vector3(parent_radius * 1.2 + moon_radius + 2.0, parent_radius * 0.3, -parent_radius * 2.2 - 5.0)
	if parent_data.has("rings"):
		var rings = SpaceTextures.make_rings(parent_data["rings"], 1.0)
		parent_planet.add_child(rings)
		rings.rotation_degrees.x = 20

func add_saturn_rings(sphere_radius):
	target_planet.add_child(SpaceTextures.make_saturn_rings(sphere_radius))
	# Saturn is tilted about 27 degrees
	target_planet.rotation_degrees.z = 27

# How far along the flight (0 to 1) the probe is when event number "index" happens
func progress_at_event(index):
	return float(index + 1) / GameState.events.size()

func set_flight_progress(new_progress):
	flight_progress = new_progress
	var probe_position = FLIGHT_START.lerp(flight_end, new_progress)
	probe_position.y = sin(new_progress * PI) * 4.0   # curved path
	probe.position = probe_position
	# Point the rocket's nose the way it's flying (up at first, level at the top of the curve, then down)
	var direction = flight_end - FLIGHT_START
	direction.y = cos(new_progress * PI) * 4.0 * PI
	probe.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))

func fly_to(target_progress):
	var tween = create_tween()
	tween.tween_method(set_flight_progress, flight_progress, target_progress, 1.5)
	tween.finished.connect(_show_event)

func remove_choice_buttons():
	for button in choice_buttons.get_children():
		button.queue_free()

func _show_event():
	var event = GameState.events[event_index]
	remove_choice_buttons()
	event_panel.visible = true
	if event.has("choices"):
		event_title.text = "Decision: " + event["title"]
		event_text.text = event["text"]
		continue_button.visible = false
		for choice_index in event["choices"].size():
			var choice = event["choices"][choice_index]
			var button = Button.new()
			button.text = choice["label"]
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if choice.has("needs") and not GameState.requirement_met(choice["needs"]):
				button.disabled = true
				button.text += "  (needs " + GameState.requirement_part_names(choice["needs"]) + ")"
			button.pressed.connect(_on_choice_pressed.bind(choice_index))
			choice_buttons.add_child(button)
	else:
		var result = GameState.apply_event(event)
		event_title.text = ("Good: " if result["ok"] else "Problem: ") + event["title"]
		event_text.text = result["text"]
		continue_button.visible = true

func _on_choice_pressed(choice_index):
	var event = GameState.events[event_index]
	var result = GameState.resolve_choice(event, choice_index)
	remove_choice_buttons()
	event_title.text = ("Good: " if result["ok"] else "Problem: ") + event["title"]
	event_text.text = result["text"]
	continue_button.visible = true

func _on_continue_pressed():
	event_panel.visible = false
	event_index += 1
	if GameState.lost or event_index >= GameState.events.size():
		go_to_results()
	else:
		fly_to(progress_at_event(event_index))

func go_to_results():
	GameState.finish_mission()
	get_tree().change_scene_to_file(RESULTS_SCENE)
