extends RefCounted

# Real rocket models for the launch, split into their real stages so the actual parts fall away:
# Falcon 9 and Starship (Sketchfab, CC BY), Atlas V (Sketchfab), SLS (NASA).
# Every part of a rocket was cut from one model, so the parts share the same coordinates and line up when stacked.
# build() returns the same pieces as rocket_model.gd, so the launch can use either.

const RocketData = preload("res://scripts/rocket_data.gd")
const RocketModel = preload("res://scripts/rocket_model.gd")
const Spacecraft = preload("res://scripts/spacecraft.gd")
const SpacecraftLookalike = preload("res://scripts/spacecraft_lookalike.gd")

# Each stack: its real height in meters, the part files, and where the flames go.
# Engines are rings of [how many, distance from the middle in meters, turn in degrees]; flame sizes are nozzle radii in meters.
const STACKS = {
	"falcon9": {
		"name": "Falcon 9", "height": 70.0,
		"bottom": "falcon9_first_stage.glb", "top": "falcon9_second_stage.glb",
		"fairing": ["falcon9_fairing_1.glb", "falcon9_fairing_2.glb"],
		"bottom_engines": [[1, 0.0, 0.0], [8, 1.25, 0.0]], "bottom_nozzle": 0.46,   # 9 Merlins in the "octaweb"
		"top_engines": [[1, 0.0, 0.0]], "top_nozzle": 1.6,                           # the Merlin Vacuum's huge bell
		"fairing_caption": "Fairing separation: there's your probe!",
	},
	"atlas5": {
		"name": "Atlas V", "height": 58.3,
		"bottom": "atlas_v_core_stage.glb", "top": "atlas_v_centaur.glb",
		"fairing": ["atlas_v_fairing_1.glb", "atlas_v_fairing_2.glb"],
		"small_booster": "atlas_v_booster_1.glb",
		"bottom_engines": [[2, 0.75, 0.0]], "bottom_nozzle": 0.7,                   # the RD-180's two nozzles
		"top_engines": [[1, 0.0, 0.0]], "top_nozzle": 0.55,
		"fairing_caption": "Fairing separation: there's your probe!",
	},
	"sls": {
		"name": "SLS", "height": 98.0,
		"bottom": "sls_core_stage.glb", "top": "sls_upper_stage.glb",
		"fairing": ["sls_abort_tower.glb"],
		"giant_boosters": ["sls_booster_1.glb", "sls_booster_2.glb"],
		"bottom_engines": [[4, 1.9, 45.0]], "bottom_nozzle": 1.2,                   # 4 RS-25s in a square
		"top_engines": [[1, 0.0, 0.0]], "top_nozzle": 1.0,
		"fairing_caption": "Launch abort tower jettisoned", "show_probe": false,
	},
	"starship": {
		"name": "Starship", "height": 121.0,
		"bottom": "starship_super_heavy.glb", "top": "starship_ship.glb",
		"fairing": [],
		"bottom_engines": [[3, 0.9, 0.0], [10, 2.4, 0.0], [20, 3.9, 0.0]], "bottom_nozzle": 0.65,   # 33 Raptors
		"top_engines": [[3, 0.9, 60.0], [3, 2.5, 0.0]], "top_nozzle": 1.0,
		"fairing_caption": "", "show_probe": false,
	},
}

const SMALL_BOOSTER_HEIGHT = 20.0   # GEM 63 / AJ-60A solid boosters
const SMALL_BOOSTER_NOZZLE = 0.6
const GIANT_BOOSTER_NOZZLE = 1.9

# The real rocket a design looks most like, picked by its bottom-stage engine
static func closest_stack(rocket):
	return {"merlin": "falcon9", "rd180": "atlas5", "rs25": "sls", "raptor": "starship"}.get(rocket["bottom_engine"], "falcon9")

static func stack_for_preset(preset):
	return {"falcon9": "falcon9", "atlas5": "atlas5", "atlas5_star48": "atlas5", "sls": "sls", "starship": "starship"}.get(preset, "")

static func load_part(file_name):
	var path = Spacecraft.find_model(file_name)
	if path == "":
		return null
	var scene = load(path)
	return scene.instantiate() if scene is PackedScene else null

static func has_all_parts(stack_id):
	var stack = STACKS[stack_id]
	for file_name in [stack["bottom"], stack["top"]] + stack["fairing"] + stack.get("giant_boosters", []):
		if Spacecraft.find_model(file_name) == "":
			return false
	return true

# Loads every part of a stack, scaled to meters and stood up with the bottom at y = 0.
# Returns {"parts": {name: Node3D}, "height", "width"} or null if a part is missing.
static func load_stack(stack_id):
	if not has_all_parts(stack_id):
		return null
	var stack = STACKS[stack_id]
	var files = {"bottom": stack["bottom"], "top": stack["top"]}
	for index in stack["fairing"].size():
		files["fairing_%d" % index] = stack["fairing"][index]
	for index in stack.get("giant_boosters", []).size():
		files["giant_booster_%d" % index] = stack["giant_boosters"][index]
	var models = {}
	var box = null
	for part_name in files:
		var model = load_part(files[part_name])
		if model == null:
			return null
		models[part_name] = model
		var part_box = Spacecraft.model_bounds(model, Transform3D.IDENTITY, null)
		if part_box != null:
			box = part_box if box == null else box.merge(part_box)
	var scale = stack["height"] / max(box.size.y, 0.001)
	var center = box.get_center()
	var parts = {}
	for part_name in models:
		var holder = Node3D.new()
		holder.name = part_name.capitalize().replace(" ", "")
		var model = models[part_name]
		model.scale = model.scale * scale
		model.position = Vector3(-center.x, -box.position.y, -center.z) * scale
		holder.add_child(model)
		parts[part_name] = holder
	return {"parts": parts, "height": box.size.y * scale, "width": max(box.size.x, box.size.z) * scale}

# The bounds of a part (in its holder's space), after scaling, leaving out flames
static func part_bounds(holder):
	return solid_bounds(holder.get_child(0), Transform3D.IDENTITY, null)

# Like Spacecraft.model_bounds, but skips engine flames (they'd make a stage look much longer than it is)
static func solid_bounds(node, parent_transform, box):
	if node.has_meta("is_flame"):
		return box
	var here = parent_transform
	if node is Node3D:
		here = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var mesh_box = here * node.mesh.get_aabb()
		box = mesh_box if box == null else box.merge(mesh_box)
	for child in node.get_children():
		box = solid_bounds(child, here, box)
	return box

# The whole rocket standing still, for the rocket builder. Returns {"root", "height"} or null.
static func assemble(stack_id):
	var loaded = load_stack(stack_id)
	if loaded == null:
		return null
	var root = Node3D.new()
	for part_name in loaded["parts"]:
		root.add_child(loaded["parts"][part_name])
	if stack_id == "atlas5":
		var core_box = part_bounds(loaded["parts"]["bottom"])
		place_boosters(root, "small_boosters_4", 4, core_box, stack_id)   # Atlas V 541, like Curiosity and Perseverance flew on
	return {"root": root, "height": loaded["height"]}

# Flames under a part, laid out in the stack's engine rings
static func add_flames(part, rings, nozzle_radius, bottom_y, length, fuel):
	var flames = []
	for ring in rings:
		for index in ring[0]:
			var angle = deg_to_rad(ring[2]) + TAU * index / max(ring[0], 1)
			var flame = RocketModel.make_flame(fuel)
			flame.position = Vector3(cos(angle) * ring[1], bottom_y, sin(angle) * ring[1])
			flame.scale = Vector3(nozzle_radius * 1.25, length, nozzle_radius * 1.25)
			part.add_child(flame)
			flames.append(flame)
	# A cluster's plumes merge into one big plume a little way below the engines, like Falcon 9's 9 Merlins
	var engine_count = 0
	var outer_radius = 0.0
	for ring in rings:
		engine_count += ring[0]
		outer_radius = max(outer_radius, ring[1])
	if engine_count >= 3:
		var plume = RocketModel.make_flame(fuel)
		plume.position = Vector3(0, bottom_y - length * 0.04, 0)
		plume.scale = Vector3(outer_radius + nozzle_radius, length * 1.15, outer_radius + nozzle_radius)
		part.add_child(plume)
		flames.append(plume)
	return flames

# Side boosters around the core, using real booster models: Atlas V's solids for small ones, NASA's Shuttle booster for giant ones
static func place_boosters(root, booster_id, count, core_box, stack_id):
	var placed = []
	var core_radius = min(core_box.size.x, core_box.size.z) * 0.5
	var giant = booster_id == "giant_boosters_2"
	for index in count:
		var booster = null
		if giant:
			booster = RocketModel.load_giant_booster()
			if booster:
				booster.scale = Vector3(1.0, RocketData.BOOSTERS[booster_id]["height"] / RocketModel.SHUTTLE_BOOSTER_LENGTH, 1.0)
		else:
			var model = load_part(STACKS["atlas5"]["small_booster"])
			if model:
				var box = Spacecraft.model_bounds(model, Transform3D.IDENTITY, null)
				var scale = SMALL_BOOSTER_HEIGHT / max(box.size.y, 0.001)
				model.scale = model.scale * scale
				model.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * scale
				booster = Node3D.new()
				booster.add_child(model)
		if booster == null:
			continue
		var holder = Node3D.new()
		holder.name = "Booster%d" % (index + 1)
		var angle = TAU * index / count + (PI / 2.0 if count == 2 else PI / 4.0)
		var distance = core_radius + (1.85 if giant else 0.8) + 0.1
		holder.position = Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		holder.add_child(booster)
		root.add_child(holder)
		placed.append(holder)
	return placed

# The launch rocket: the real rocket closest to the player's design, as separate pieces that can fall away.
# Returns the same dictionary as RocketModel.build, or null if the model files aren't in the project.
static func build(rocket):
	var stack_id = closest_stack(rocket)
	var loaded = load_stack(stack_id)
	if loaded == null:
		return null
	var stack = STACKS[stack_id]
	var parts = loaded["parts"]
	var root = Node3D.new()
	root.name = "Rocket"
	var pieces = {"root": root, "boosters": [], "booster_flames": [], "bottom_flames": [], "top_flames": [], "fairing": [],
		"real_rocket": stack["name"], "fairing_caption": stack["fairing_caption"]}

	var bottom = parts["bottom"]
	root.add_child(bottom)
	var bottom_box = part_bounds(bottom)
	pieces["bottom"] = bottom
	pieces["bottom_flames"] = add_flames(bottom, stack["bottom_engines"], stack["bottom_nozzle"], bottom_box.position.y + 0.3, stack["height"] * 0.42, RocketData.ENGINES[rocket["bottom_engine"]]["fuel"])

	var top = parts["top"]
	root.add_child(top)
	var top_box = part_bounds(top)
	pieces["top"] = top
	pieces["top_flames"] = add_flames(top, stack["top_engines"], stack["top_nozzle"], top_box.position.y + 0.2, stack["height"] * 0.2, RocketData.ENGINES[rocket["top_engine"]]["fuel"])

	# The probe rides on top of the top stage, inside the fairing
	var payload = Node3D.new()
	payload.name = "Payload"
	payload.position = Vector3(0, top_box.end.y, 0)
	top.add_child(payload)
	var fairing_width = max(top_box.size.x, top_box.size.z)
	if stack.get("show_probe", true):   # (Starship's cargo bay and SLS's Orion hide it)
		# NASA's models have their solar panels and booms unfolded, so the probe is shown big, and only once the fairing opens
		var probe = SpacecraftLookalike.load_model(SpacecraftLookalike.closest(), fairing_width * 1.3)
		if probe:
			payload.add_child(probe)
			payload.visible = false
	pieces["payload"] = payload
	for index in stack["fairing"].size():
		var half = parts["fairing_%d" % index]
		top.add_child(half)
		pieces["fairing"].append(half)

	# Side boosters: the model's own when they match the design, otherwise real booster models placed around the core
	var booster_id = rocket["boosters"]
	var booster = RocketData.BOOSTERS[booster_id]
	pieces["booster_count"] = booster["count"]
	if booster["count"] > 0:
		var holders = []
		if booster_id == "giant_boosters_2" and parts.has("giant_booster_0"):
			for index in 2:
				var holder = parts["giant_booster_%d" % index]
				root.add_child(holder)
				holders.append(holder)
		else:
			holders = place_boosters(root, booster_id, booster["count"], bottom_box, stack_id)
		for holder in holders:
			var box = part_bounds(holder)
			var flame = RocketModel.make_flame("solid")
			var nozzle = GIANT_BOOSTER_NOZZLE if booster_id == "giant_boosters_2" else SMALL_BOOSTER_NOZZLE
			var spot = Vector3.ZERO
			if box != null:
				spot = Vector3(box.get_center().x, box.position.y + 0.3, box.get_center().z)
			flame.position = spot
			flame.scale = Vector3(nozzle * 1.4, loaded["height"] * 0.6, nozzle * 1.4)
			holder.add_child(flame)
			pieces["boosters"].append(holder)
			pieces["booster_flames"].append(flame)

	pieces["height"] = loaded["height"]
	pieces["width"] = loaded["width"]
	return pieces
