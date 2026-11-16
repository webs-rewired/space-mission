extends Node

# Gets the graphics ready when the web version starts (GameState adds this node as "ShaderWarmup").
#
# In a browser, the first time a material or effect is drawn the browser has to compile its shader, and the game
# freezes while it does. Without this, every new step of the first mission stutters: the clean room, the Vehicle
# Assembly Building, the launch pad, the plumes, each planet. The desktop version compiles shaders much faster, so
# this only runs in the web version (or with warmup=1 on the command line, for testing; warmup=0 turns it off).
#
# It works in two parts:
#   1. Behind the loading screen ("Getting the graphics ready"): the main mission steps, one at a time in the order a
#      mission plays them. Each is loaded, every mesh, material, particle effect and sky is read out of it (from the
#      saved scene file, without running its scripts), and each one is drawn once in a small hidden viewport so the
#      browser compiles it. Nothing is kept loaded afterwards, to save memory on slower computers.
#   2. In the background afterwards: the spacecraft and rocket models, the minigames, landing sites, places, parts,
#      effects, every shader in res://shaders/ and every material file, a few per frame. This only runs on menu screens (where a moment's hitch doesn't matter)
#      and waits while a scene is loading or a mission is flying.
# Materials that scripts build while the game runs can still compile the first time they're seen, but most of what
# a mission draws is in the scene files.

const SHADER_FOLDER = "res://shaders/"
const MATERIAL_FOLDERS = ["res://assets/", "res://scenes/", "res://shaders/"]
const ITEMS_PER_FRAME = 10          # things drawn per frame behind the loading screen
const BACKGROUND_ITEMS_PER_FRAME = 3 # things drawn per frame in the background, so menus stay smooth
const LONGEST_SECONDS = 60.0        # let the player in after this long even if part 1 isn't finished (the rest carries on in the background)
# Screens where the background part may run (a moment's hitch doesn't matter in a menu)
const BACKGROUND_SCENES = ["main_menu (2)", "solar_system", "probe_builder", "rocket_builder", "career_screen", "results"]

# Part 1, in the order a mission plays them
const STEP_SCENES = [
	"res://scenes/solar_system.tscn",
	"res://scenes/probe_builder.tscn",
	"res://scenes/rocket_builder.tscn",
	"res://scenes/launch.tscn",
	"res://scenes/results.tscn",
]
# Part 2: looked through for their materials, then let go
const LOOK_SCENES = [
	"res://scenes/career_screen.tscn",
	"res://scenes/surface_view.tscn",
	"res://scenes/orbit_science.tscn",
	"res://scenes/orbital_insertion.tscn",
	"res://scenes/gravity_assist.tscn",
	"res://scenes/engine_test_lab.tscn",
	"res://scenes/docking.tscn",
	"res://scenes/sample_lab.tscn",
	"res://scenes/life_search.tscn",
	"res://scenes/seismometer.tscn",
	"res://scenes/aerobraking.tscn",
	"res://scenes/radio_science.tscn",
	"res://scenes/landing_cut.tscn",
	"res://scenes/travel_screen.tscn",
	"res://scenes/destination_codex.tscn",
	"res://scenes/world_globe.tscn",
	"res://scenes/places/clean_room.tscn",
	"res://scenes/places/vehicle_assembly_building.tscn",
	"res://scenes/places/launch_complex.tscn",
	"res://scenes/places/sample_orbiter.tscn",
	"res://scenes/places/station_docking_port.tscn",
	"res://scenes/places/station_zenith_port.tscn",
	"res://scenes/parts/aeroshell.tscn",
	"res://scenes/parts/airbags.tscn",
	"res://scenes/parts/parachute.tscn",
	"res://scenes/parts/rover_platform.tscn",
	"res://scenes/parts/sky_crane.tscn",
	"res://scenes/worlds/rock_field.tscn",
	"res://scenes/worlds/sky_planet.tscn",
	"res://scenes/worlds/moon_site.tscn",
	"res://scenes/worlds/mars_site.tscn",
	"res://scenes/worlds/titan_site.tscn",
	"res://scenes/worlds/europa_site.tscn",
]
const EFFECTS_FOLDER = "res://scenes/effects/"
const MODEL_FOLDERS = ["res://assets/", "res://assets/surface/", "res://assets/surface/rocks/"]
# What the loading screen says while each mission step loads
const STEP_NAMES = {"solar_system": "the solar system", "probe_builder": "the clean room", "rocket_builder": "the Vehicle Assembly Building", "launch": "the launch pad and flight", "results": "the mission report"}

var ready_to_play = false   # part 1 is finished and the loading screen has lifted
var done = false            # both parts are finished
var drawing_now = false     # drawing things this frame (GameState's speed check skips these frames)
var steps_read = 0          # mission steps read in part 1
var started_msec = 0
var drawn = 0               # how many of the queued items have been drawn

# What gets drawn: each entry is {"kind": "mesh"/"particles"/"canvas"/"sky", ...}, grouped by the scene it came from
var items = []
var seen = {}               # IDs of resources already queued, so each one is drawn once (IDs, so nothing stays loaded)

var viewport_3d: SubViewport
var viewport_2d: SubViewport
var environment_node: WorldEnvironment
var default_environment: Environment
var fallback_mesh: SphereMesh  # for materials that come without a mesh

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not wanted():
		done = true
		queue_free()
		return
	run()

func wanted():
	for argument in OS.get_cmdline_user_args():
		if argument == "warmup=1":
			return true
		if argument == "warmup=0":
			return false
	return OS.has_feature("web")

func screen():
	return get_tree().root.get_node_or_null("LoadingScreen")

func run():
	started_msec = Time.get_ticks_msec()
	# Wait for the loading screen and the main menu to exist
	for frame in 3:
		await get_tree().process_frame
	make_viewports()
	var loading_screen = screen()
	if loading_screen and loading_screen.has_method("begin_warmup"):
		loading_screen.begin_warmup()
	# Part 1: the mission steps, behind the loading screen
	var paths = STEP_SCENES.filter(func(path): return ResourceLoader.exists(path))
	for step in paths.size():
		if not part_one_wanted():
			break
		var share = 1.0 / paths.size()
		var scene = await load_scene(paths[step], step * share, (step + 0.5) * share)
		if scene:
			steps_read += 1
			gather_scene(scene, null, 0)
		await draw_queued((step + 0.5) * share, (step + 1) * share, ITEMS_PER_FRAME, false)
	ready_to_play = true
	print("Graphics warm-up: mission steps ready in %.1fs" % seconds_running())
	loading_screen = screen()
	if loading_screen and loading_screen.has_method("end_warmup"):
		loading_screen.end_warmup()
	# Part 2: everything else, in the background. First the spacecraft and rocket models (scripts load these by
	# name, so they aren't in any scene file, and the next steps show them), then the minigames, places and sites.
	var more = []
	for folder in MODEL_FOLDERS:
		for file_name in list_folder(folder):
			if file_name.ends_with(".glb"):
				more.append(folder + file_name)
	more.append_array(LOOK_SCENES)
	for file_name in list_folder(EFFECTS_FOLDER):
		if file_name.ends_with(".tscn"):
			more.append(EFFECTS_FOLDER + file_name)
	for path in more.filter(func(path): return ResourceLoader.exists(path)):
		await wait_for_a_menu()
		gather_scene(await load_scene(path, -1, -1), null, 0)
		await draw_queued(-1, -1, BACKGROUND_ITEMS_PER_FRAME, true)
	await wait_for_a_menu()
	gather_shaders()
	gather_material_files()
	await draw_queued(-1, -1, BACKGROUND_ITEMS_PER_FRAME, true)
	finish()

func seconds_running():
	return (Time.get_ticks_msec() - started_msec) / 1000.0

# Part 1 stops early if the player starts a scene change or it's taking too long (part 2 picks up the rest)
func part_one_wanted():
	var loading_screen = screen()
	if loading_screen and loading_screen.get("loading"):
		return false
	return seconds_running() < LONGEST_SECONDS

# Part 2 only runs on a menu screen, and not while a scene is loading
func on_a_menu():
	var loading_screen = screen()
	if loading_screen and (loading_screen.get("loading") or loading_screen.get("warming")):
		return false
	var scene = get_tree().current_scene
	return scene != null and scene.scene_file_path.get_file().get_basename() in BACKGROUND_SCENES

func wait_for_a_menu():
	while not on_a_menu():
		await get_tree().create_timer(0.5).timeout

func set_progress(fraction, status):
	if fraction < 0.0:
		return
	var loading_screen = screen()
	if loading_screen and loading_screen.has_method("warmup_progress"):
		loading_screen.warmup_progress(fraction, status)

# Loads one scene in the background (the browser build has threads), moving the loading bar from one point to another
func load_scene(path, from, to):
	if ResourceLoader.load_threaded_request(path, "", true) != OK:
		return null
	while true:
		var progress = []
		var status = ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var scene = ResourceLoader.load_threaded_get(path)
			return scene if scene is PackedScene else null
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return null
		var fraction = progress[0] if progress.size() > 0 else 0.0
		set_progress(from + (to - from) * fraction, "Loading " + STEP_NAMES.get(path.get_file().get_basename(), "the mission"))
		await get_tree().process_frame
	return null

func list_folder(folder):
	if ResourceLoader.has_method("list_directory"):
		return Array(ResourceLoader.list_directory(folder))
	var names = []
	for file_name in DirAccess.get_files_at(folder):
		names.append(file_name.trim_suffix(".remap").trim_suffix(".import"))
	return names

# Reads a saved scene's nodes (without running any scripts) and queues every mesh, material, effect and sky in it
func gather_scene(scene: PackedScene, environment, depth):
	if scene == null or depth > 8 or seen.has(scene.get_instance_id()):
		return
	seen[scene.get_instance_id()] = true
	var state = scene.get_state()
	# The scene's own sky and lighting, so its materials compile the way they'll be drawn
	for node in state.get_node_count():
		for index in state.get_node_property_count(node):
			var value = state.get_node_property_value(node, index)
			if value is Environment:
				environment = value
				queue_sky(value)
	for node in state.get_node_count():
		var type = String(state.get_node_type(node))
		var sub_scene = state.get_node_instance(node)
		if sub_scene:
			gather_scene(sub_scene, environment, depth + 1)
		var mesh: Mesh = null
		var override_materials = []
		var process_material: Material = null
		for index in state.get_node_property_count(node):
			var property = String(state.get_node_property_name(node, index))
			var value = state.get_node_property_value(node, index)
			if value is Mesh and (property == "mesh" or property == "draw_pass_1"):
				mesh = value
			elif value is MultiMesh and value.mesh:
				mesh = value.mesh
			elif value is Material:
				if property == "process_material":
					process_material = value
				elif type != "" and ClassDB.is_parent_class(type, "CanvasItem"):
					queue_canvas(value)
				else:
					override_materials.append(value)
			elif value is PackedScene:
				gather_scene(value, environment, depth + 1)
		if process_material:
			queue_particles(process_material, mesh, environment)
		elif mesh:
			queue_mesh(mesh, null, environment)
			for material in override_materials:
				queue_mesh(mesh, material, environment)
		else:
			for material in override_materials:
				queue_mesh(null, material, environment)

func id_of(resource):
	return resource.get_instance_id() if resource else 0

func queue_mesh(mesh, material, environment):
	var key = [id_of(mesh), id_of(material)]
	if seen.has(key):
		return
	seen[key] = true
	if material is ShaderMaterial and material.shader and material.shader.get_mode() == Shader.MODE_CANVAS_ITEM:
		queue_canvas(material)
		return
	items.append({"kind": "mesh", "mesh": mesh, "material": material, "environment": environment})

func queue_particles(process_material, mesh, environment):
	var key = [id_of(process_material), id_of(mesh)]
	if seen.has(key):
		return
	seen[key] = true
	items.append({"kind": "particles", "process": process_material, "mesh": mesh, "environment": environment})

func queue_canvas(material):
	if seen.has(id_of(material)):
		return
	seen[id_of(material)] = true
	items.append({"kind": "canvas", "material": material})

func queue_sky(environment):
	if seen.has(id_of(environment)):
		return
	seen[id_of(environment)] = true
	items.append({"kind": "sky", "environment": environment})

# Every shader in res://shaders/, drawn the way its type is used
func gather_shaders():
	for file_name in list_folder(SHADER_FOLDER):
		if not file_name.ends_with(".gdshader"):
			continue
		var shader = load(SHADER_FOLDER + file_name)
		if not shader is Shader:
			continue
		var material = ShaderMaterial.new()
		material.shader = shader
		match shader.get_mode():
			Shader.MODE_SPATIAL:
				queue_mesh(null, material, null)
			Shader.MODE_CANVAS_ITEM:
				queue_canvas(material)
			Shader.MODE_PARTICLES:
				queue_particles(material, null, null)
			Shader.MODE_SKY:
				var sky_environment = Environment.new()
				sky_environment.background_mode = Environment.BG_SKY
				sky_environment.sky = Sky.new()
				sky_environment.sky.sky_material = material
				queue_sky(sky_environment)

# Material files saved in the project (scripts load some of these themselves)
func gather_material_files():
	for folder in MATERIAL_FOLDERS:
		gather_material_folder(folder, 0)

func gather_material_folder(folder, depth):
	if depth > 4:
		return
	for file_name in list_folder(folder):
		if file_name.ends_with("/"):
			gather_material_folder(folder + file_name, depth + 1)
		elif file_name.ends_with(".tres") or file_name.ends_with(".material"):
			var resource = load(folder + file_name)
			if resource is Material:
				queue_mesh(null, resource, null)
	if not ResourceLoader.has_method("list_directory"):
		for sub_folder in DirAccess.get_directories_at(folder):
			gather_material_folder(folder + sub_folder + "/", depth + 1)

# 2. A small hidden viewport with its own world, a camera, sunlight with shadows and a lamp
func make_viewports():
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(96, 96)
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport_3d)
	var camera = Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	camera.near = 0.05
	camera.far = 100000.0
	viewport_3d.add_child(camera)
	camera.current = true
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	viewport_3d.add_child(sun)
	var lamp = OmniLight3D.new()
	lamp.position = Vector3(1, 1, 2)
	lamp.omni_range = 10.0
	viewport_3d.add_child(lamp)
	default_environment = Environment.new()
	default_environment.background_mode = Environment.BG_COLOR
	fallback_mesh = SphereMesh.new()
	fallback_mesh.radial_segments = 8
	fallback_mesh.rings = 4
	environment_node = WorldEnvironment.new()
	environment_node.environment = default_environment
	viewport_3d.add_child(environment_node)
	viewport_2d = SubViewport.new()
	viewport_2d.size = Vector2i(96, 96)
	viewport_2d.transparent_bg = true
	viewport_2d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport_2d)

# Draws everything queued since last time, a few things per frame, with each scene's sky on while its materials draw.
# In the background it stops drawing (and waits) whenever the player leaves the menus.
func draw_queued(from, to, per_frame, in_background):
	var first = drawn
	while drawn < items.size():
		if in_background:
			await wait_for_a_menu()
		elif not part_one_wanted():
			return
		var batch = []
		var environment = items[drawn].get("environment")
		while drawn < items.size() and batch.size() < per_frame and items[drawn].get("environment") == environment:
			batch.append(items[drawn])
			items[drawn] = {}   # let go of it once drawn, so it can unload
			drawn += 1
		environment_node.environment = environment if environment else default_environment
		var made = []
		for item in batch:
			var node = make_node(item)
			if node:
				made.append(node)
		drawing_now = true
		await RenderingServer.frame_post_draw
		drawing_now = false
		for node in made:
			node.queue_free()
		set_progress(from + (to - from) * float(drawn - first) / max(1, items.size() - first), "Preparing materials and effects")

func make_node(item):
	match item["kind"]:
		"mesh":
			var mesh_node = MeshInstance3D.new()
			mesh_node.mesh = item["mesh"] if item["mesh"] else fallback_mesh
			if item["material"]:
				mesh_node.material_override = item["material"]
			viewport_3d.add_child(mesh_node)
			return mesh_node
		"particles":
			var particles = GPUParticles3D.new()
			particles.amount = 4
			particles.process_material = item["process"]
			particles.draw_pass_1 = item["mesh"] if item["mesh"] else fallback_mesh
			particles.emitting = true
			viewport_3d.add_child(particles)
			return particles
		"canvas":
			var rect = ColorRect.new()
			rect.size = Vector2(64, 64)
			rect.material = item["material"]
			viewport_2d.add_child(rect)
			return rect
		"sky":
			environment_node.environment = item["environment"]
	return null

func finish():
	if viewport_3d:
		viewport_3d.queue_free()
	if viewport_2d:
		viewport_2d.queue_free()
	print("Graphics warm-up: finished everything (%d things drawn) in %.1fs" % [drawn, seconds_running()])
	items.clear()
	seen.clear()
	done = true
