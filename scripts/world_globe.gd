extends Control

# A world turning slowly inside engraved rings (res://scenes/world_globe.tscn). It's the real world from the
# solar system, not a stand-in: show_world() copies the body the Bodies node built (scripts/solar_system_bodies.gd)
# with its surface, clouds and air glow, and adds its rings. Comets get a glowing cloud around their icy rock,
# the Sun a warm glow, and spacecraft are their real 3D models.
#
# Used by the destination codex (the Go to... menu) and the travel screen.

const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const SpaceTextures = preload("res://scripts/space_textures.gd")
const Spacecraft = preload("res://scripts/spacecraft.gd")
const TURN_SPEED = 0.22   # radians per second

@onready var astrolabe: Control = $Astrolabe
@onready var globe_tilt: Node3D = $GlobeView/GlobeViewport/GlobeWorld/GlobeTilt
@onready var globe_spin: Node3D = $GlobeView/GlobeViewport/GlobeWorld/GlobeTilt/GlobeSpin
@onready var key_light: DirectionalLight3D = $GlobeView/GlobeViewport/GlobeWorld/KeyLight
@onready var halo: TextureRect = $Halo

func _process(delta):
	if is_visible_in_tree():
		globe_spin.rotate_y(delta * TURN_SPEED)

# The rings sweep in around the circle
func draw_in(delay := 0.0, duration := 1.1):
	astrolabe.draw_in(delay, duration)

# The rings flash once
func pulse():
	astrolabe.pulse()

# The world swells in from a little smaller, with a small bounce
func swell():
	globe_spin.scale = Vector3.ONE * 0.8
	globe_spin.create_tween().tween_property(globe_spin, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func show_world(bodies_node, body_name):
	for old in globe_spin.get_children():
		globe_spin.remove_child(old)
		old.queue_free()
	if not SolarSystemData.BODIES.has(body_name):
		return
	var data = SolarSystemData.BODIES[body_name]
	var info = {}
	if bodies_node and "bodies" in bodies_node and bodies_node.bodies.has(body_name):
		info = bodies_node.bodies[body_name]
	var copy: Node3D = null
	if info.has("mesh") and is_instance_valid(info["mesh"]):
		copy = info["mesh"].duplicate()
		copy.transform = Transform3D.IDENTITY
		for child in copy.find_children("*", "Node", true, false):
			if child is Light3D or child is CollisionObject3D:
				child.queue_free()
	if copy == null:
		copy = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radial_segments = 64
		sphere.rings = 32
		copy.mesh = sphere
		var plain = StandardMaterial3D.new()
		plain.albedo_color = data.get("color", Color(0.6, 0.6, 0.6))
		copy.material_override = plain
	globe_spin.add_child(copy)
	# The air glow and Earth's night lights point at the Sun: here, the Sun is the key light
	var toward_light = key_light.global_basis.z.normalized()
	for part in [copy] + copy.find_children("*", "GeometryInstance3D", true, false):
		if part is GeometryInstance3D and part.material_override is ShaderMaterial:
			var shader_material: ShaderMaterial = part.material_override
			if shader_material.shader and "sun_direction" in shader_material.shader.code:
				part.material_override = shader_material.duplicate()
				part.material_override.set_shader_parameter("sun_direction", toward_light)
	var fit_radius = 1.0
	match data["kind"]:
		"spacecraft":
			# Spacecraft models come in every size: make this one fill the view and stand in the middle
			fit_to_view(copy)
			for part in copy.find_children("*", "VisualInstance3D", true, false):
				part.layers = 1 | 2
		"comet":
			# A comet is a small dark lump of ice and dust: show the lump big, inside its glowing cloud (the coma)
			fit_to_view(copy, 1.4)
		_:
			copy.scale = info["shape"] if info.has("shape") else Vector3.ONE
			if data.has("rings"):
				var rings = SpaceTextures.make_rings(data["rings"], 1.0)
				globe_spin.add_child(rings)
				fit_radius = SpaceTextures.RING_SIZES[data["rings"]][1]
	globe_tilt.scale = Vector3.ONE / fit_radius
	# A glow behind it: a comet's cloud of gas and dust (its coma), or the Sun's light
	halo.visible = data["kind"] in ["comet", "star"]
	halo.modulate = Color(0.55, 0.75, 1.0, 0.8) if data["kind"] == "comet" else Color(1.0, 0.62, 0.25, 0.75)
	halo.scale = Vector2.ONE * (1.0 if data["kind"] == "comet" else 1.25)
	halo.pivot_offset = halo.size / 2.0

# Scales and centers a model so its biggest side is size across
func fit_to_view(model, size := 2.0):
	var box = Spacecraft.model_bounds(model, Transform3D.IDENTITY, null)
	if box == null:
		return
	var biggest = max(box.size.x, max(box.size.y, box.size.z))
	model.scale = Vector3.ONE * (size / max(biggest, 0.0001))
	model.position = -box.get_center() * model.scale.x
