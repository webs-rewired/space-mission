extends Node3D

# The Sun's moving surface, its glow, and solar flares.
# The Bodies node adds this next to the Sun and scales it to the Sun's size, so every size here is
# measured in Sun radii. Everything grows, flickers and fades smoothly.
#
#   Prominences: glowing loops of hot gas that rise from the surface along magnetic fields, then fade
#   Flares: a sudden bright flash, sometimes throwing out a burst of particles (like a coronal mass ejection)

const SUN_SURFACE_SHADER = """
shader_type spatial;
render_mode unshaded;
uniform sampler2D surface_image : source_color;
uniform sampler2D churn : repeat_enable;
uniform bool has_image = false;
uniform vec4 base_color : source_color = vec4(1.0, 0.72, 0.3, 1.0);
void fragment() {
	// Two layers of slowly drifting noise make the surface boil, like the Sun's granulation
	vec2 drift = vec2(TIME * 0.003, TIME * 0.0015);
	float churn_large = texture(churn, UV * 3.0 + drift).r;
	float churn_small = texture(churn, UV * 9.0 - drift * 2.3).r;
	vec2 wobble = (vec2(churn_large, churn_small) - 0.5) * 0.006;
	vec3 color = has_image ? texture(surface_image, UV + wobble).rgb : base_color.rgb;
	float granulation = 0.82 + 0.36 * churn_small;
	// Limb darkening: the Sun's edge looks darker and redder than its middle
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float limb = pow(facing, 0.4);
	ALBEDO = color * granulation * mix(vec3(0.75, 0.45, 0.25), vec3(1.15), limb);
}
"""

const PROMINENCE_SHADER = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
uniform float life = 0.0;      // 0 = just born, 1 = gone
uniform float growth = 0.0;    // how much of the loop has risen, from the feet up
uniform float seed = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.42, 0.12, 1.0);
void fragment() {
	float along = UV.x;   // 0 at one foot of the loop, 1 at the other
	float distance_from_feet = min(along, 1.0 - along) * 2.0;
	float risen = 1.0 - smoothstep(growth - 0.15, growth, distance_from_feet);
	float flicker = 0.7 + 0.3 * sin(TIME * 5.0 + along * 25.0 + seed * 7.0);
	float fade = sin(clamp(life, 0.0, 1.0) * PI);   // fades in and out smoothly
	float core = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	ALBEDO = glow_color.rgb * (0.5 + core) * flicker * fade * risen * 1.5;
}
"""

@export var prominence_every_seconds: Vector2 = Vector2(1.5, 4.0)
@export var flare_every_seconds: Vector2 = Vector2(12.0, 24.0)
@export var most_prominences_at_once: int = 6

var sun_mesh: MeshInstance3D
var sun_radius = 1.0
var prominences = []           # each is {"node", "material", "age", "lifetime", "height"}
var flashes = []               # each is {"node", "material", "age", "lifetime"}
var seconds_to_next_prominence = 1.0
var seconds_to_next_flare = 8.0
var glow_material: StandardMaterial3D
var prominence_mesh: ArrayMesh
var random = RandomNumberGenerator.new()

func set_up(sun: MeshInstance3D, radius: float, surface_image):
	sun_mesh = sun
	sun_radius = radius
	random.randomize()
	make_surface(surface_image)
	make_glow()
	prominence_mesh = make_loop_mesh()

func make_surface(surface_image):
	var noise = FastNoiseLite.new()
	noise.frequency = 0.03
	noise.fractal_octaves = 4
	var churn = NoiseTexture2D.new()
	churn.width = 256
	churn.height = 256
	churn.seamless = true
	churn.noise = noise
	var shader = Shader.new()
	shader.code = SUN_SURFACE_SHADER
	var surface_material = ShaderMaterial.new()
	surface_material.shader = shader
	surface_material.set_shader_parameter("churn", churn)
	if surface_image:
		surface_material.set_shader_parameter("surface_image", surface_image)
		surface_material.set_shader_parameter("has_image", true)
	sun_mesh.material_override = surface_material

func make_glow():
	var glow = MeshInstance3D.new()
	glow.name = "SunGlow"
	var quad = QuadMesh.new()
	quad.size = Vector2.ONE * sun_radius * 4.0
	glow.mesh = quad
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.48, 0.56, 0.7, 0.85, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.95, 0.8, 0.6), Color(1.0, 0.92, 0.75, 0.5), Color(1.0, 0.85, 0.6, 0.22),
		Color(1.0, 0.75, 0.45, 0.08), Color(1.0, 0.7, 0.4, 0.02), Color(1.0, 0.7, 0.4, 0.0),
	])
	var glow_texture = GradientTexture2D.new()
	glow_texture.gradient = gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(1.0, 0.5)
	glow_texture.width = 256
	glow_texture.height = 256
	glow_material = StandardMaterial3D.new()
	glow_material.albedo_texture = glow_texture
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_material.billboard_keep_scale = true   # grows and shrinks with the Sun
	glow.material_override = glow_material
	add_child(glow)

# A tube bent into a half circle, standing on the surface with its two feet on the x axis
func make_loop_mesh():
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps_along = 48
	var steps_around = 10
	var tube_radius = 0.11
	for step in steps_along:
		for around in steps_around:
			var corners = [[step, around], [step + 1, around], [step + 1, around + 1], [step, around], [step + 1, around + 1], [step, around + 1]]
			for corner in corners:
				var along_fraction = float(corner[0]) / steps_along
				var angle_along = PI * along_fraction
				var center = Vector3(-cos(angle_along), sin(angle_along), 0.0)
				var outward = Vector3(-cos(angle_along), sin(angle_along), 0.0)
				var angle_around = TAU * corner[1] / steps_around
				var normal = (outward * cos(angle_around) + Vector3.BACK * sin(angle_around)).normalized()
				surface.set_normal(normal)
				surface.set_uv(Vector2(along_fraction, float(corner[1]) / steps_around))
				surface.add_vertex(center + normal * tube_radius)
	return surface.commit()

func _process(delta):
	if sun_mesh == null:
		return
	# Everything freezes while time is paused
	var animation_speed = 0.0 if GameState.time_speed == 0.0 else 1.0
	var step = delta * animation_speed

	# The glow breathes very slowly
	if glow_material:
		glow_material.albedo_color.a = 0.9 + 0.1 * sin(Time.get_ticks_msec() / 2300.0)

	seconds_to_next_prominence -= step
	if seconds_to_next_prominence <= 0.0 and prominences.size() < most_prominences_at_once:
		spawn_prominence()
		seconds_to_next_prominence = random.randf_range(prominence_every_seconds.x, prominence_every_seconds.y)

	seconds_to_next_flare -= step
	if seconds_to_next_flare <= 0.0:
		spawn_flare()
		seconds_to_next_flare = random.randf_range(flare_every_seconds.x, flare_every_seconds.y)

	for prominence in prominences.duplicate():
		prominence["age"] += step
		var life = prominence["age"] / prominence["lifetime"]
		prominence["material"].set_shader_parameter("life", life)
		prominence["material"].set_shader_parameter("growth", smoothstep(0.0, 0.35, life) * 1.15)
		# The loop slowly swells upward as it rises
		var size = prominence["size"]
		prominence["node"].scale = Vector3(size, size * prominence["height"] * (0.75 + 0.35 * life), size)
		if life >= 1.0:
			prominence["node"].queue_free()
			prominences.erase(prominence)

	for flash in flashes.duplicate():
		flash["age"] += step
		var life = flash["age"] / flash["lifetime"]
		# A quick bright rise, then a slower fade
		var brightness = smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.12, 1.0, life))
		flash["material"].albedo_color = Color(1.0, 0.95, 0.85, brightness)
		flash["node"].scale = Vector3.ONE * (0.6 + 0.8 * life)
		if life >= 1.0:
			flash["node"].queue_free()
			flashes.erase(flash)

# A random point on the Sun, with the surface pointing outward from it.
# near_edge picks a point on the Sun's edge as seen from the camera, where glowing gas stands out against
# black space (in front of the bright surface it would be lost in the glare, just like in real photos).
func random_surface_frame(near_edge = false):
	var outward = Vector3(random.randfn(), random.randfn() * 0.6, random.randfn()).normalized()
	var camera = get_viewport().get_camera_3d()
	if near_edge and camera:
		var toward_camera = (global_transform.basis.orthonormalized().inverse() * (camera.global_position - global_position)).normalized()
		var around = toward_camera.cross(Vector3(random.randfn(), random.randfn(), random.randfn())).normalized()
		outward = (around + toward_camera * random.randf_range(-0.3, 0.12)).normalized()
	var sideways = outward.cross(Vector3(random.randf(), random.randf(), random.randf()) + Vector3(0.1, 0.0, 0.0)).normalized()
	var forward = sideways.cross(outward).normalized()
	return Basis(sideways, outward, forward)

func spawn_prominence():
	var loop = MeshInstance3D.new()
	loop.mesh = prominence_mesh
	var shader = Shader.new()
	shader.code = PROMINENCE_SHADER
	var loop_material = ShaderMaterial.new()
	loop_material.shader = shader
	loop_material.set_shader_parameter("seed", random.randf() * 10.0)
	# Some loops are hotter (more yellow), some cooler (more red)
	loop_material.set_shader_parameter("glow_color", Color(1.0, random.randf_range(0.3, 0.55), random.randf_range(0.08, 0.2)))
	loop.material_override = loop_material
	var frame = random_surface_frame(random.randf() < 0.75)
	loop.basis = frame
	loop.position = frame.y * sun_radius * 0.98
	var size = sun_radius * random.randf_range(0.14, 0.36)
	loop.scale = Vector3(size, size * 0.75, size)
	add_child(loop)
	prominences.append({"node": loop, "material": loop_material, "age": 0.0,
		"lifetime": random.randf_range(7.0, 12.0), "size": size, "height": random.randf_range(0.9, 1.6)})

func spawn_flare():
	var frame = random_surface_frame(random.randf() < 0.5)
	var spot = frame.y * sun_radius * 1.01
	# A bright flash on the surface
	var flash = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2.ONE * sun_radius * 0.7
	flash.mesh = quad
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 0.8, 0.5, 0))
	var flash_texture = GradientTexture2D.new()
	flash_texture.gradient = gradient
	flash_texture.fill = GradientTexture2D.FILL_RADIAL
	flash_texture.fill_from = Vector2(0.5, 0.5)
	flash_texture.fill_to = Vector2(1.0, 0.5)
	var flash_material = StandardMaterial3D.new()
	flash_material.albedo_texture = flash_texture
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_material.billboard_keep_scale = true
	flash_material.albedo_color = Color(1, 1, 1, 0)
	flash.material_override = flash_material
	flash.position = spot
	add_child(flash)
	flashes.append({"node": flash, "material": flash_material, "age": 0.0, "lifetime": 3.5})

	# Sometimes the flare throws gas out into space
	if random.randf() < 0.6:
		var burst = CPUParticles3D.new()
		burst.one_shot = true
		burst.amount = 70
		burst.lifetime = 4.0
		burst.explosiveness = 0.85
		burst.local_coords = true   # stays sized and placed with the Sun, at any scale
		burst.direction = Vector3.UP
		burst.spread = 28.0
		burst.initial_velocity_min = sun_radius * 0.25
		burst.initial_velocity_max = sun_radius * 0.7
		burst.gravity = Vector3.ZERO
		burst.damping_min = 0.02
		burst.damping_max = 0.08
		burst.scale_amount_min = 0.6
		burst.scale_amount_max = 1.4
		var dot = QuadMesh.new()
		dot.size = Vector2.ONE * sun_radius * 0.09
		var dot_material = StandardMaterial3D.new()
		dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dot_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		dot_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		dot_material.billboard_keep_scale = true
		dot_material.vertex_color_use_as_albedo = true
		# Each bit of gas is a soft round glow, not a square
		var dot_gradient = Gradient.new()
		dot_gradient.set_color(0, Color(1, 1, 1, 1))
		dot_gradient.set_color(1, Color(1, 1, 1, 0))
		var dot_texture = GradientTexture2D.new()
		dot_texture.gradient = dot_gradient
		dot_texture.fill = GradientTexture2D.FILL_RADIAL
		dot_texture.fill_from = Vector2(0.5, 0.5)
		dot_texture.fill_to = Vector2(1.0, 0.5)
		dot_texture.width = 32
		dot_texture.height = 32
		dot_material.albedo_texture = dot_texture
		dot.material = dot_material
		burst.mesh = dot
		var colors = Gradient.new()
		colors.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
		colors.set_color(1, Color(1.0, 0.35, 0.1, 0.0))
		burst.color_ramp = colors
		burst.basis = frame
		burst.position = spot
		add_child(burst)
		burst.emitting = true
		get_tree().create_timer(5.0).timeout.connect(burst.queue_free)
