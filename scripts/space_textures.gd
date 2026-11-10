extends RefCounted

# Puts real planet images on the planets, adds Saturn's rings and the starry sky.
# Textures by Solar System Scope (solarsystemscope.com/textures), based on NASA data, CC BY 4.0.
#
# Put the downloaded images in this folder. The file names can start with 2k_, 4k_ or 8k_.
# If an image is missing, the planet keeps a plain color so the game still runs.

const TEXTURE_FOLDER = "res://assets/textures/"

const PLANET_IMAGE_NAMES = {
	"Sun": "sun",
	"Earth": "earth_daymap",
	"Moon": "moon",
	"Mars": "mars",
	"Venus": "venus_atmosphere",
	"Jupiter": "jupiter",
	"Saturn": "saturn",
}

const BACKUP_COLORS = {
	"Sun": Color(1.0, 0.85, 0.3),
	"Earth": Color(0.2, 0.4, 0.9),
	"Moon": Color(0.8, 0.8, 0.8),
	"Mars": Color(0.85, 0.35, 0.15),
	"Venus": Color(0.95, 0.85, 0.55),
	"Jupiter": Color(0.85, 0.65, 0.45),
	"Saturn": Color(0.9, 0.8, 0.55),
}

# Finds an image like "2k_mars.jpg". Returns null if it isn't there.
static func find_texture(image_name):
	for size in ["2k_", "4k_", "8k_", ""]:
		for extension in [".jpg", ".png"]:
			var path = TEXTURE_FOLDER + size + image_name + extension
			if ResourceLoader.exists(path):
				return load(path)
	return null

# Gives a planet sphere its real surface. planet_name is "Mars", "Saturn" and so on.
static func texture_planet(planet_mesh: MeshInstance3D, planet_name: String):
	var planet_material = StandardMaterial3D.new()
	var texture = find_texture(PLANET_IMAGE_NAMES.get(planet_name, ""))
	if texture:
		planet_material.albedo_texture = texture
	else:
		planet_material.albedo_color = BACKUP_COLORS.get(planet_name, Color.WHITE)
		print("No texture found for %s in %s, using a plain color." % [planet_name, TEXTURE_FOLDER])
	if planet_name == "Sun":
		# The Sun makes its own light, so it ignores shadows and glows
		planet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		planet_material.roughness = 0.9
	planet_mesh.material_override = planet_material

# A flat ring with the hole in the middle, like Saturn's rings.
# The ring image runs from the inner edge (left) to the outer edge (right).
static func make_ring_mesh(inner_radius, outer_radius):
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments = 128
	for segment in segments:
		var angle_start = TAU * segment / segments
		var angle_end = TAU * (segment + 1) / segments
		var inner_start = Vector3(cos(angle_start), 0, sin(angle_start)) * inner_radius
		var outer_start = Vector3(cos(angle_start), 0, sin(angle_start)) * outer_radius
		var inner_end = Vector3(cos(angle_end), 0, sin(angle_end)) * inner_radius
		var outer_end = Vector3(cos(angle_end), 0, sin(angle_end)) * outer_radius
		for corner in [[inner_start, 0.0], [outer_start, 1.0], [outer_end, 1.0], [inner_start, 0.0], [outer_end, 1.0], [inner_end, 0.0]]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(Vector2(corner[1], 0.5))
			surface.add_vertex(corner[0])
	return surface.commit()

# Adds Saturn's rings to "parent". planet_radius is how big Saturn's sphere is.
# Saturn's main rings run from about 1.24 to 2.27 times Saturn's radius.
static func make_saturn_rings(planet_radius):
	var rings = MeshInstance3D.new()
	rings.name = "SaturnRings"
	rings.mesh = make_ring_mesh(planet_radius * 1.24, planet_radius * 2.27)
	var ring_material = StandardMaterial3D.new()
	var ring_texture = find_texture("saturn_ring_alpha")
	if ring_texture:
		ring_material.albedo_texture = ring_texture
		ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		ring_material.albedo_color = Color(0.85, 0.78, 0.6, 0.8)
		ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED   # visible from above and below
	rings.material_override = ring_material
	return rings

# Puts the Milky Way behind everything. Keeps the existing ambient light so planets stay bright.
static func add_star_sky(world_environment: WorldEnvironment):
	if world_environment == null:
		return
	var stars = find_texture("stars_milky_way")
	if stars == null:
		print("No star image found in %s, keeping the plain background." % TEXTURE_FOLDER)
		return
	var environment = world_environment.environment
	if environment == null:
		environment = Environment.new()
		world_environment.environment = environment
	var sky_material = PanoramaSkyMaterial.new()
	sky_material.panorama = stars
	sky_material.energy_multiplier = 0.6
	var sky = Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
