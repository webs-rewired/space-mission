extends RefCounted

# Builds a 3D model of the probe from the parts the player picked, at real size (1 unit = 1 meter).
# The dish points up (+Y), the main engine points down, solar wings stretch out to the sides,
# RTGs sit on a strut away from the instruments (their radiation would disturb them, like on New Horizons),
# and the magnetometer rides on a long boom (like Juno's and Voyager's), far from the probe's own electronics.

static func material(color, metallic = 0.0, roughness = 0.6, glow = Color.BLACK):
	var surface = StandardMaterial3D.new()
	surface.albedo_color = color
	surface.metallic = metallic
	surface.roughness = roughness
	if glow != Color.BLACK:
		surface.emission_enabled = true
		surface.emission = glow
		surface.emission_energy_multiplier = 1.5
	return surface

static func box(parent, size, place, surface, turn = Vector3.ZERO):
	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = surface
	mesh_instance.position = place
	mesh_instance.rotation_degrees = turn
	parent.add_child(mesh_instance)
	return mesh_instance

static func cylinder(parent, top_radius, bottom_radius, height, place, surface, turn = Vector3.ZERO, sides = 32):
	var mesh_instance = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	mesh_instance.mesh = mesh
	mesh_instance.material_override = surface
	mesh_instance.position = place
	mesh_instance.rotation_degrees = turn
	parent.add_child(mesh_instance)
	return mesh_instance

static func ball(parent, radius, place, surface):
	var mesh_instance = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.material_override = surface
	mesh_instance.position = place
	parent.add_child(mesh_instance)
	return mesh_instance

# A thin rod from one point to another
static func strut(parent, from, to, radius, surface):
	var length = from.distance_to(to)
	var rod = cylinder(parent, radius, radius, length, (from + to) / 2.0, surface, Vector3.ZERO, 8)
	var direction = (to - from).normalized()
	if abs(direction.dot(Vector3.UP)) < 0.999:
		rod.basis = Basis(Quaternion(Vector3.UP, direction))
	return rod

# A solar wing: dark blue cells in a silver frame, reaching out along "direction"
static func solar_wing(parent, start, direction, length, width, frame_surface, cell_surface):
	var wing = Node3D.new()
	parent.add_child(wing)
	wing.position = start
	wing.basis = Basis(Quaternion(Vector3.RIGHT, direction.normalized()))
	box(wing, Vector3(length, 0.05, width), Vector3(length / 2.0 + 0.4, 0, 0), frame_surface)
	var panels = max(2, int(round(length / 2.2)))
	var panel_length = (length - 0.1 * (panels + 1)) / panels
	for index in panels:
		box(wing, Vector3(panel_length, 0.07, width - 0.12), Vector3(0.4 + 0.1 + panel_length / 2.0 + index * (panel_length + 0.1), 0, 0), cell_surface)
	box(wing, Vector3(0.5, 0.08, 0.08), Vector3(0.2, 0, 0), frame_surface)   # the arm that holds it
	return wing

# An RTG: a black finned cylinder about 1.1 m long
static func rtg(parent, place, turn, dark):
	var holder = Node3D.new()
	parent.add_child(holder)
	holder.position = place
	holder.rotation_degrees = turn
	cylinder(holder, 0.21, 0.21, 1.1, Vector3.ZERO, dark)
	for fin in 8:
		var angle = TAU * fin / 8.0
		box(holder, Vector3(0.05, 1.0, 0.2), Vector3(cos(angle) * 0.3, 0, sin(angle) * 0.3), dark, Vector3(0, -rad_to_deg(angle), 0))
	return holder

# Builds the whole probe. Returns {"root": Node3D, "size": how big it is (for framing the camera)}.
static func build(choices, instruments):
	var root = Node3D.new()
	root.name = "ProbeModel"
	var gold = material(Color(0.83, 0.62, 0.22), 0.85, 0.3)       # gold insulation blankets
	var silver = material(Color(0.8, 0.8, 0.82), 0.9, 0.25)
	var white = material(Color(0.93, 0.93, 0.91), 0.0, 0.5)
	var dark = material(Color(0.12, 0.12, 0.13), 0.4, 0.5)
	var cells = material(Color(0.08, 0.13, 0.35), 0.6, 0.25)
	var titanium = material(Color(0.55, 0.56, 0.58), 0.9, 0.35)
	var size = 4.0

	# The body: taller with the big propellant tank inside
	var body_height = 2.6 if choices["fuel"] == "fuel_large" else 1.6
	box(root, Vector3(2.0, body_height, 2.0), Vector3(0, body_height / 2.0, 0), gold)
	box(root, Vector3(2.06, 0.08, 2.06), Vector3(0, body_height, 0), silver)
	box(root, Vector3(2.06, 0.08, 2.06), Vector3(0, 0.0, 0), silver)
	var top = body_height + 0.04

	# Temperature control
	if choices["thermal"] in ["thermal_radiators", "thermal_both"]:
		for side in [-1.0, 1.0]:
			box(root, Vector3(1.6, body_height * 0.8, 0.04), Vector3(0, body_height / 2.0, side * 1.03), white)
	if choices["thermal"] == "thermal_radiators":
		box(root, Vector3(2.6, 0.06, 2.6), Vector3(0, top + 0.05, 0), white)   # sunshade on top

	# Radiation vault on top of the body
	if choices["shield"] == "shield_radiation":
		box(root, Vector3(1.2, 0.7, 1.2), Vector3(0, top + 0.35, 0), titanium)
		top += 0.7

	# Antenna
	if choices["antenna"] == "antenna_large":
		cylinder(root, 0.2, 0.2, 0.5, Vector3(0, top + 0.25, 0), silver)
		cylinder(root, 1.5, 0.3, 0.45, Vector3(0, top + 0.7, 0), white, Vector3.ZERO, 48)
		for leg in 3:
			var angle = TAU * leg / 3.0
			strut(root, Vector3(cos(angle) * 1.3, top + 0.9, sin(angle) * 1.3), Vector3(0, top + 1.6, 0), 0.02, silver)
		cylinder(root, 0.08, 0.12, 0.25, Vector3(0, top + 1.6, 0), silver)
	else:
		strut(root, Vector3(0.6, top, 0.6), Vector3(0.6, top + 0.8, 0.6), 0.03, silver)
		cylinder(root, 0.12, 0.05, 0.25, Vector3(0.6, top + 0.9, 0.6), white)

	# Power
	match choices["power"]:
		"solar_small":
			for side in [-1.0, 1.0]:
				solar_wing(root, Vector3(side * 1.0, body_height * 0.6, 0), Vector3(side, 0, 0), 3.2, 1.6, silver, cells)
			size = max(size, 9.0)
		"solar_large":
			for wing in 3:
				var angle = TAU * wing / 3.0 + PI / 6.0
				var outward = Vector3(cos(angle), 0, sin(angle))
				solar_wing(root, outward * 1.0 + Vector3(0, body_height * 0.6, 0), outward, 8.9, 2.65, silver, cells)
			size = max(size, 21.0)
		"rtg":
			strut(root, Vector3(0, body_height * 0.5, -1.0), Vector3(0, body_height * 0.5, -2.2), 0.06, silver)
			rtg(root, Vector3(0, body_height * 0.5, -2.75), Vector3(90, 0, 0), dark)
			size = max(size, 7.0)
		"rtg_triple":
			for index in 3:
				var angle = PI + (index - 1) * 0.9
				var outward = Vector3(cos(angle), 0, sin(angle))
				strut(root, outward * 1.0 + Vector3(0, 0.4, 0), outward * 2.0 + Vector3(0, 0.2, 0), 0.06, silver)
				rtg(root, outward * 2.5 + Vector3(0, 0.2, 0), Vector3(90, -rad_to_deg(angle) + 90, 0), dark)
			size = max(size, 8.0)

	# Engine
	if choices["engine"] == "engine_ion":
		var blue_glow = material(Color(0.3, 0.5, 1.0), 0.0, 0.5, Color(0.25, 0.45, 1.0))
		for index in 3:
			var angle = TAU * index / 3.0
			var spot = Vector3(cos(angle) * 0.55, -0.13, sin(angle) * 0.55)
			cylinder(root, 0.2, 0.2, 0.25, spot, dark)
			cylinder(root, 0.17, 0.17, 0.02, spot - Vector3(0, 0.13, 0), blue_glow)
	else:
		cylinder(root, 0.12, 0.2, 0.25, Vector3(0, -0.13, 0), silver)
		cylinder(root, 0.16, 0.42, 0.8, Vector3(0, -0.65, 0), dark)

	# Protection below: a heat shield, or the Venus lander's pressure sphere
	var bottom = -1.1
	if choices["shield"] == "shield_heat":
		cylinder(root, 0.6, 2.25, 0.55, Vector3(0, bottom - 0.3, 0), material(Color(0.32, 0.22, 0.15), 0.0, 0.9))
		bottom -= 0.6
	elif choices["shield"] == "shield_venus":
		ball(root, 0.9, Vector3(0, bottom - 0.9, 0), white)
		cylinder(root, 1.6, 1.6, 0.06, Vector3(0, bottom - 0.6, 0), white)   # drag plate, like Venera's
		bottom -= 1.8

	# Landing system
	var lowest = bottom
	if choices["engine"] == "engine_chemical":
		lowest = min(lowest, -1.05)
	match choices["landing"]:
		"landing_legs":
			for leg in 4:
				var angle = TAU * leg / 4.0 + PI / 4.0
				var corner = Vector3(cos(angle) * 1.0, 0.2, sin(angle) * 1.0)
				var foot = Vector3(cos(angle) * 2.0, bottom - 0.4, sin(angle) * 2.0)
				strut(root, corner, foot, 0.06, silver)
				cylinder(root, 0.25, 0.3, 0.06, foot, silver)
			lowest = min(lowest, bottom - 0.45)
		"landing_airbags":
			var bag = material(Color(0.95, 0.94, 0.88), 0.0, 0.8)
			for index in 6:
				var angle = TAU * index / 6.0
				ball(root, 0.75, Vector3(cos(angle) * 1.3, 0.3 + (0.5 if index % 2 == 0 else -0.4), sin(angle) * 1.3), bag)
			ball(root, 0.8, Vector3(0, bottom - 0.4, 0), bag)
			lowest = min(lowest, bottom - 1.2)
		"landing_skycrane":
			var crane_top = top + (2.0 if choices["antenna"] == "antenna_large" else 1.2) + 1.5
			box(root, Vector3(3.2, 0.5, 3.2), Vector3(0, crane_top, 0), dark)
			for index in 8:
				var angle = TAU * index / 8.0
				cylinder(root, 0.08, 0.18, 0.4, Vector3(cos(angle) * 1.7, crane_top - 0.2, sin(angle) * 1.7), silver, Vector3(0, 0, 0))
			for cable in 3:
				var angle = TAU * cable / 3.0
				strut(root, Vector3(cos(angle) * 0.7, crane_top - 0.25, sin(angle) * 0.7), Vector3(cos(angle) * 0.7, body_height, sin(angle) * 0.7), 0.01, dark)
			size = max(size, crane_top + 2.0)

	# Science instruments
	if "instrument_camera" in instruments:
		cylinder(root, 0.16, 0.16, 0.7, Vector3(1.25, body_height * 0.35, 0.5), dark, Vector3(0, 0, 90))
		cylinder(root, 0.12, 0.12, 0.02, Vector3(1.61, body_height * 0.35, 0.5), material(Color(0.1, 0.2, 0.3), 0.9, 0.05), Vector3(0, 0, 90))
	if "instrument_spectrometer" in instruments:
		box(root, Vector3(0.45, 0.35, 0.35), Vector3(-1.2, body_height * 0.35, 0.5), silver)
		box(root, Vector3(0.05, 0.15, 0.2), Vector3(-1.45, body_height * 0.35, 0.5), dark)
	if "instrument_radar" in instruments:
		box(root, Vector3(0.05, 0.6, 2.4), Vector3(1.05, body_height * 0.75, 0), white)
		strut(root, Vector3(0, body_height, 1.0), Vector3(0, body_height + 0.1, 5.0), 0.015, silver)
		strut(root, Vector3(0, body_height, -1.0), Vector3(0, body_height + 0.1, -5.0), 0.015, silver)
		size = max(size, 10.0)
	if "instrument_magnetometer" in instruments:
		strut(root, Vector3(-0.8, body_height * 0.8, 1.0), Vector3(-0.8, body_height * 0.8, 7.0), 0.03, silver)
		box(root, Vector3(0.25, 0.25, 0.25), Vector3(-0.8, body_height * 0.8, 7.1), white)
		size = max(size, 14.0)
	if "instrument_drill" in instruments:
		strut(root, Vector3(0.6, 0.0, -0.6), Vector3(0.6, bottom - 0.2, -0.6), 0.05, silver)
		cylinder(root, 0.02, 0.07, 0.25, Vector3(0.6, bottom - 0.3, -0.6), dark)
		lowest = min(lowest, bottom - 0.45)
	if "instrument_seismometer" in instruments:
		var dome = ball(root, 0.3, Vector3(-0.5, top + 0.05, -0.5), material(Color(0.85, 0.85, 0.87), 0.6, 0.3))
		dome.scale = Vector3(1, 0.6, 1)

	var highest = top + (1.7 if choices["antenna"] == "antenna_large" else 1.0)
	if choices["landing"] == "landing_skycrane":
		highest = top + (2.0 if choices["antenna"] == "antenna_large" else 1.2) + 1.8
	return {"root": root, "size": size, "bottom": lowest, "top": highest}
