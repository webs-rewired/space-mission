extends RefCounted

# Images for planets, rings and the starry sky.
# Textures by Solar System Scope (solarsystemscope.com/textures), based on NASA data, CC BY 4.0.
#
# Put the downloaded images in this folder. File names can start with 2k_, 4k_ or 8k_.
# If an image is missing, the body gets a generated rocky or cloudy surface in its real colors instead.

const TEXTURE_FOLDER = "res://assets/textures/"
const SolarSystemData = preload("res://scripts/solar_system_data.gd")

# Finds the first image that exists from a list of names like ["ceres", "ceres_fictional"]. Returns null if none.
static func find_texture(image_names):
	if image_names is String:
		image_names = [image_names]
	for image_name in image_names:
		for size in ["2k_", "4k_", "8k_", ""]:
			for extension in [".jpg", ".png"]:
				var path = TEXTURE_FOLDER + size + image_name + extension
				if ResourceLoader.exists(path):
					return load(path)
	return null

# A generated surface: blotchy for rocky and icy bodies, banded for giant planets
static func generated_surface(base_color: Color, banded: bool, seed_number: int):
	var noise = FastNoiseLite.new()
	noise.seed = seed_number
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 5
	noise.frequency = 0.02
	var texture = NoiseTexture2D.new()
	texture.width = 1024
	texture.height = 512
	texture.seamless = true
	texture.noise = noise
	var ramp = Gradient.new()
	ramp.set_color(0, base_color.darkened(0.45))
	ramp.set_color(1, base_color.lightened(0.25))
	ramp.add_point(0.5, base_color)
	if banded:
		# A narrow, tall image wrapped around the planet: the pattern changes quickly from north to south
		# and slowly around it, which makes cloud bands that circle the planet like on Jupiter
		noise.frequency = 0.011
		noise.domain_warp_enabled = true
		noise.domain_warp_amplitude = 12.0
		texture.width = 256
		texture.height = 1024
		ramp.set_color(0, base_color.darkened(0.3))
		ramp.set_color(1, base_color.lightened(0.2))
	texture.color_ramp = ramp
	return texture

# A flat ring with a hole in the middle. The ring image runs from the inner edge (left) to the outer edge (right).
static func make_ring_mesh(inner_radius, outer_radius):
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments = 192
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

# Thin rings drawn as bright bands: each band is [position from 0 (inner) to 1 (outer), width, brightness]
static func banded_ring_texture(bands, color: Color):
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0])
	gradient.colors = PackedColorArray([Color(color, 0.0)])
	for band in bands:
		var center = band[0]
		var half_width = band[1] / 2.0
		gradient.add_point(max(0.001, center - half_width), Color(color, 0.0))
		gradient.add_point(center, Color(color, band[2]))
		gradient.add_point(min(0.999, center + half_width), Color(color, 0.0))
	var texture = GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 1024
	return texture

# Ring sizes compared with the planet's radius, from spacecraft measurements
const RING_SIZES = {
	"saturn": [1.24, 2.27],    # the main rings, from the C ring to the edge of the A ring
	"uranus": [1.60, 2.03],    # 13 narrow dark rings; the brightest, Epsilon, is the outermost
	"neptune": [1.65, 2.60],   # faint rings named after the astronomers who found Neptune
	"jupiter": [1.40, 1.81],   # a faint dusty halo and the thin main ring
	"haumea": [2.9, 3.02],     # a narrow ring found in 2017, about 2,287 km from Haumea's center
}

# Makes the rings for a planet whose sphere has the given radius
static func make_rings(ring_type, planet_radius):
	var size = RING_SIZES[ring_type]
	var rings = MeshInstance3D.new()
	rings.name = "Rings"
	rings.mesh = make_ring_mesh(planet_radius * size[0], planet_radius * size[1])
	var ring_material = StandardMaterial3D.new()
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED   # visible from above and below
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match ring_type:
		"saturn":
			ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			var ring_image = find_texture("saturn_ring_alpha")
			if ring_image:
				ring_material.albedo_texture = ring_image
			else:
				ring_material.albedo_texture = banded_ring_texture([[0.15, 0.2, 0.25], [0.45, 0.3, 0.85], [0.6, 0.06, 0.05], [0.82, 0.3, 0.6]], Color(0.9, 0.82, 0.65))
		"uranus":
			ring_material.albedo_texture = banded_ring_texture([[0.05, 0.02, 0.35], [0.2, 0.02, 0.3], [0.35, 0.02, 0.3], [0.55, 0.03, 0.35], [0.7, 0.03, 0.35], [0.97, 0.05, 0.8]], Color(0.65, 0.68, 0.7))
		"neptune":
			ring_material.albedo_texture = banded_ring_texture([[0.04, 0.04, 0.25], [0.52, 0.03, 0.3], [0.96, 0.05, 0.4]], Color(0.6, 0.6, 0.65))
		"jupiter":
			ring_material.albedo_texture = banded_ring_texture([[0.4, 0.6, 0.08], [0.93, 0.1, 0.2]], Color(0.75, 0.65, 0.55))
		"haumea":
			ring_material.albedo_texture = banded_ring_texture([[0.5, 0.5, 0.5]], Color(0.85, 0.85, 0.9))
	rings.material_override = ring_material
	return rings

# Puts the Milky Way behind everything. Keeps the existing ambient light so planets stay lit.
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

# --- Kept so the launch scene keeps working ---
const PLANET_IMAGE_NAMES = {
	"Sun": "sun", "Earth": "earth_daymap", "Moon": "moon", "Mars": "mars",
	"Venus": "venus_atmosphere", "Jupiter": "jupiter", "Saturn": "saturn",
}
const BACKUP_COLORS = {
	"Sun": Color(1.0, 0.85, 0.3), "Earth": Color(0.2, 0.4, 0.9), "Moon": Color(0.8, 0.8, 0.8),
	"Mars": Color(0.85, 0.35, 0.15), "Venus": Color(0.95, 0.85, 0.55), "Jupiter": Color(0.85, 0.65, 0.45),
	"Saturn": Color(0.9, 0.8, 0.55),
}

static func texture_planet(planet_mesh: MeshInstance3D, planet_name: String):
	var planet_material = StandardMaterial3D.new()
	var image_names = [PLANET_IMAGE_NAMES.get(planet_name, "")]
	var backup_color = BACKUP_COLORS.get(planet_name, Color.WHITE)
	var banded = false
	if SolarSystemData.BODIES.has(planet_name):
		var data = SolarSystemData.BODIES[planet_name]
		image_names = data["images"]
		backup_color = data["color"]
		banded = data["mass_earths"] > 5.0
	var texture = find_texture(image_names) if image_names.size() > 0 else null
	if texture:
		planet_material.albedo_texture = texture
	else:
		# No image: a generated surface in the body's real colors
		planet_material.albedo_texture = generated_surface(backup_color, banded, abs(planet_name.hash()) % 10000)
	if planet_name == "Sun":
		planet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		planet_material.roughness = 0.9
	planet_mesh.material_override = planet_material

static func make_saturn_rings(planet_radius):
	var rings = make_rings("saturn", planet_radius)
	rings.name = "SaturnRings"
	return rings
