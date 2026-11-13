extends Node3D

# A planet or moon in the sky over a landing site, at its real size as seen from there and lit by the Sun, so it
# shows its phase. The site scene sets which body it is, how wide it looks and where it hangs.

const SpaceTextures = preload("res://scripts/space_textures.gd")
const DISTANCE = 9000.0

@export var body_name = "Earth"
@export var width_degrees = 1.9                       # how wide it looks (Earth from the Moon is about 1.9 degrees)
@export var direction = Vector3(-0.45, 0.28, -0.85)   # where it hangs in the sky
@export var rings = ""                                # "saturn" draws Saturn's rings
@export var ring_opening_degrees = 0.0                # 0: exactly edge-on, a thin line (the moons orbit in the ring plane)
@export var spin_degrees = 0.0

func _ready():
	var sphere = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	var planet = MeshInstance3D.new()
	planet.mesh = sphere
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	SpaceTextures.texture_planet(planet, body_name)
	if planet.material_override is BaseMaterial3D:
		planet.material_override.disable_fog = true
	var look = direction.normalized()
	# Its pole stands across our line of sight, so its equator (and any rings) runs straight through our eye
	var pole = (Vector3.UP - look * look.dot(Vector3.UP)).normalized().rotated(look, deg_to_rad(spin_degrees))
	var side = pole.cross(look).normalized()
	pole = pole.rotated(side, deg_to_rad(ring_opening_degrees))
	var holder = Node3D.new()
	add_child(holder)
	holder.basis = Basis(side, pole, side.cross(pole)).scaled(Vector3.ONE * DISTANCE * tan(deg_to_rad(width_degrees) * 0.5))
	holder.position = look * DISTANCE
	holder.add_child(planet)
	if rings != "":
		holder.add_child(SpaceTextures.make_rings(rings, 1.0))
