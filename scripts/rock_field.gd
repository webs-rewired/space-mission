extends Node3D

# Rocks scattered around a landing site the way real ones lie: the ground is covered in pebbles, there are plenty of
# rocks and a few big boulders, more of them around crater rims (thrown out by the impacts), all partly sunk into the
# ground. Some worlds add a special kind: flat lava slabs (Venus), fields of ice blades (Europa) or tall frosty
# knobs (Callisto).
# The site scene (res://scenes/worlds/) sets the counts, sizes, shapes and colors.
# surface_view.gd calls scatter() once the ground is ready, so everything sits on it.
#
# To keep it fast, the ground is split into squares ("chunks"): each square's pebbles only draw when the camera is
# near, and rocks swap to a simpler model farther away. Rocks big enough to stop a wheel get a collision shape.

@export_group("Shapes")
@export var tiny_shapes: Array[PackedScene] = []     # very simple models, for pebbles
@export var small_shapes: Array[PackedScene] = []    # simple models, for rocks seen from far away
@export var medium_shapes: Array[PackedScene] = []   # detailed models, for rocks close up
@export var large_shapes: Array[PackedScene] = []    # the most detailed models, for boulders
@export var rock_material: ShaderMaterial

@export_group("How many")
@export var pebble_count = 16000
@export var pebble_size = Vector2(0.04, 0.3)         # smallest and biggest, in meters
@export var pebble_spread = 200.0
@export var rock_count = 1300
@export var rock_size = Vector2(0.3, 1.6)
@export var boulder_count = 30
@export var boulder_size = Vector2(1.6, 5.0)
@export var spread = 225.0                           # how far out the rocks go, in meters
@export var near_craters = 0.3                       # the share of rocks lying around crater rims

@export_group("Special")
@export var special_shape: PackedScene
@export var special_material: ShaderMaterial
@export var special_count = 0
@export var special_size = Vector2(1.0, 3.0)
@export var special_spread = Vector2(8.0, 220.0)     # nearest and farthest
@export var special_clusters = 0                     # 0: spread out; otherwise grouped in this many patches
@export var special_cluster_radius = 12.0
@export var special_sink = 0.2                       # the share of its height that's buried
@export var special_stand_up = false                 # stays upright (ice blades, knobs) instead of lying tumbled
@export var special_blocks_rover = true

const LANDING_CLEARANCE = 6.0
const CHUNK_SIZE = 50.0
const PEBBLE_VIEW_DISTANCE = 75.0
const ROCK_DETAIL_DISTANCE = 55.0
const ROCK_VIEW_DISTANCE = 320.0
const BLOCKING_SIZE = 0.35        # rocks at least this big (meters) get a collision shape: they can stop a wheel

var random = RandomNumberGenerator.new()
var mesh_cache = {}
var hull_cache = {}
var colliders: StaticBody3D = null

func scatter(site):
	random.seed = hash(site.destination) + 11
	colliders = StaticBody3D.new()
	colliders.name = "RockColliders"
	add_child(colliders)
	var nearby_craters = []
	for crater in site.crater_list:
		if Vector2(crater.x, crater.y).length() < spread:
			nearby_craters.append(crater)
	# On Low and Medium graphics there are fewer pebbles and rocks (Settings > Graphics quality)
	var detail = GameState.detail_share()
	# Pebbles: lots, close by
	var pebbles = place_rocks(site, int(pebble_count * detail * detail), pebble_size, Vector2(LANDING_CLEARANCE * 0.5, pebble_spread), nearby_craters, 0.3, false, [])
	add_chunked(pebbles, tiny_shapes, [[0.0, PEBBLE_VIEW_DISTANCE]], false)
	# Rocks: a detailed model up close, a simple one farther off
	var rocks = place_rocks(site, int(rock_count * lerp(0.55, 1.0, detail)), rock_size, Vector2(LANDING_CLEARANCE, spread), nearby_craters, 0.25, false, [])
	add_chunked(rocks, medium_shapes, [[0.0, ROCK_DETAIL_DISTANCE]], true)
	add_chunked(rocks, small_shapes, [[ROCK_DETAIL_DISTANCE, ROCK_VIEW_DISTANCE]], true)
	add_colliders(site, rocks, medium_shapes)
	# Boulders: few, big, seen from anywhere
	var boulders = place_rocks(site, boulder_count, boulder_size, Vector2(LANDING_CLEARANCE * 3.0, spread * 1.5), nearby_craters, 0.3, false, [])
	add_chunked(boulders, large_shapes, [[0.0, 0.0]], true)
	add_colliders(site, boulders, large_shapes)
	if special_shape and special_count > 0:
		var cluster_centers = []
		for index in special_clusters:
			var angle = random.randf() * TAU
			cluster_centers.append(Vector2(cos(angle), sin(angle)) * random.randf_range(special_spread.x + 10.0, special_spread.y))
		var specials = place_rocks(site, special_count, special_size, special_spread, [], special_sink, special_stand_up, cluster_centers)
		add_chunked(specials, [special_shape], [[0.0, 0.0]], true, special_material if special_material else rock_material)
		if special_blocks_rover:
			add_colliders(site, specials, [special_shape])

# Where each rock goes: [place on the ground (Vector2), transform, which shape]
func place_rocks(site, count, size_range, distance_range, craters, sink, stand_up, cluster_centers):
	var placed = []
	for index in count:
		var place = pick_place(distance_range, craters, cluster_centers)
		# Many small ones, few big ones, like real rock fields
		var size = lerp(size_range.x, size_range.y, pow(random.randf(), 2.4))
		var stretch = Vector3(random.randf_range(0.8, 1.25), random.randf_range(0.75, 1.15), random.randf_range(0.8, 1.25))
		var turn
		if stand_up:
			turn = Basis(Vector3.UP, random.randf() * TAU) * Basis(Vector3(random.randf() - 0.5, 0, random.randf() - 0.5).normalized(), random.randf() * 0.15)
		else:
			turn = Basis(Vector3(random.randf() - 0.5, random.randf() - 0.5, random.randf() - 0.5).normalized(), random.randf() * TAU)
			turn = turn.slerp(Basis(Vector3.UP, random.randf() * TAU), 0.65)   # mostly settled, flat side down
		var where = Vector3(place.x, site.ground_height(place) - size * sink, place.y)
		placed.append([place, Transform3D(turn.scaled(stretch * size), where), random.randi(), size])
	return placed

func pick_place(distance_range, craters, cluster_centers):
	for attempt in 8:
		var place
		if not cluster_centers.is_empty():
			var center = cluster_centers[random.randi() % cluster_centers.size()]
			var angle = random.randf() * TAU
			place = center + Vector2(cos(angle), sin(angle)) * special_cluster_radius * sqrt(random.randf())
		elif not craters.is_empty() and random.randf() < near_craters:
			# Thrown out of a crater: piled around its rim
			var crater = craters[random.randi() % craters.size()]
			var angle = random.randf() * TAU
			place = Vector2(crater.x, crater.y) + Vector2(cos(angle), sin(angle)) * crater.z * random.randf_range(0.85, 1.9)
		else:
			# Spread evenly over the ground (the same number per square meter near and far)
			var angle = random.randf() * TAU
			var distance = sqrt(lerp(distance_range.x * distance_range.x, distance_range.y * distance_range.y, random.randf()))
			place = Vector2(cos(angle), sin(angle)) * distance
		if place.length() > LANDING_CLEARANCE:
			return place
	return Vector2(distance_range.y, 0.0)

func first_mesh(scene):
	if mesh_cache.has(scene):
		return mesh_cache[scene]
	var model = scene.instantiate()
	var found = null
	var waiting = [model]
	while not waiting.is_empty() and found == null:
		var node = waiting.pop_front()
		if node is MeshInstance3D:
			found = node.mesh
		waiting.append_array(node.get_children())
	model.free()
	mesh_cache[scene] = found
	return found

# One set of instances per square of ground and per shape, each drawn only within its view distances
func add_chunked(placed, shapes, view_ranges, shadows, material = null):
	if shapes.is_empty() or placed.is_empty():
		return
	var groups = {}
	for rock in placed:
		var key = [int(floor(rock[0].x / CHUNK_SIZE)), int(floor(rock[0].y / CHUNK_SIZE)), rock[2] % shapes.size()]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(rock[1])
	for key in groups:
		var mesh = first_mesh(shapes[key[2]])
		if mesh == null:
			continue
		var transforms = groups[key]
		var center = Vector3((key[0] + 0.5) * CHUNK_SIZE, 0.0, (key[1] + 0.5) * CHUNK_SIZE)
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = transforms.size()
		for index in transforms.size():
			var rock_transform = transforms[index]
			rock_transform.origin -= center
			multimesh.set_instance_transform(index, rock_transform)
		for view_range in view_ranges:
			var instance = MultiMeshInstance3D.new()
			instance.multimesh = multimesh
			instance.position = center
			instance.material_override = material if material else rock_material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_begin = view_range[0]
			instance.visibility_range_end = view_range[1]
			add_child(instance)

# A collision shape for each rock big enough to stop a wheel: the rock's own outline, simplified (a convex hull)
func add_colliders(site, placed, shapes):
	for rock in placed:
		var size = rock[3]
		if size < BLOCKING_SIZE or shapes.is_empty():
			continue
		var mesh = first_mesh(shapes[rock[2] % shapes.size()])
		if mesh == null:
			continue
		if not hull_cache.has(mesh):
			var hull = mesh.create_convex_shape(true, true)
			hull_cache[mesh] = hull.points if hull else PackedVector3Array()
		var rock_transform: Transform3D = rock[1]
		var points = PackedVector3Array()
		for point in hull_cache[mesh]:
			points.append(rock_transform.basis * point)   # turned and sized like the rock (shapes can't be stretched by their node)
		var shape = ConvexPolygonShape3D.new()
		shape.points = points
		var shape_node = CollisionShape3D.new()
		shape_node.shape = shape
		shape_node.position = rock_transform.origin
		colliders.add_child(shape_node)
		if size > 0.9:
			site.big_rocks.append([rock[0], size * 0.5])
