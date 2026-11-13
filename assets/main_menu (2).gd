extends Node3D
## MAIN MENU: a rocket launches in the background, with one "Start a Mission" button.
## Everything is built in code, so the scene only needs this script on a Node3D.

# The scene that opens when the player clicks the button.
# (Right-click the scene file in the FileSystem panel > Copy Path, then paste it here.)
const START_SCENE = "res://scenes/solar_system.tscn"
const BUTTON_TEXT = "Start a Mission"

# Launch timeline in seconds (the whole launch loops forever)
const IGNITE_TIME = 2.0      # engines light, flame and smoke start
const LIFTOFF_TIME = 4.0     # rocket starts to climb
const ACCELERATION = 3.5     # how quickly the rocket speeds up
const FADE_OUT_TIME = 14.0   # screen fades to black...
const LOOP_TIME = 15.5       # ...then the launch starts over

const PAD_TOP = 0.4
const CAM_BASE = Vector3(26, 3, 37)

# Rocket look
const SIDE_BOOSTERS = true   # two extra boosters on the sides of the built-in rocket
const BOOSTER_X = 1.15

# OPTIONAL: use your own 3D model instead of the built-in rocket.
# Put a .glb / .gltf / .tscn file in your project, right-click it > Copy Path, paste it below.
# Leave it as "" to use the built-in rocket. The model's bottom (engine end) should sit at its origin.
const ROCKET_MODEL = ""
const ROCKET_MODEL_SCALE = 1.0
const ROCKET_MODEL_OFFSET = Vector3.ZERO

# Daytime sky with drifting clouds and a sun (it fades to space as the rocket climbs).
# The script feeds it colors every frame, so you normally never need to edit this.
const SKY_SHADER = """
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.2, 0.36, 0.68);
uniform vec3 horizon_color : source_color = vec3(0.95, 0.68, 0.5);
uniform vec3 sun_direction = vec3(-0.09, 0.35, -0.93);
uniform float space_amount = 0.0;
uniform float cloud_offset = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p = p * 2.03 + vec2(11.7, 3.1);
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sun = normalize(sun_direction);
	float up = dir.y;

	// Gradient from the horizon up to the top of the sky
	vec3 col = mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), 0.45));
	if (up < 0.0) {
		col = horizon_color;
	}

	// Sun: small bright disc plus a soft glow
	float sd = max(dot(dir, sun), 0.0);
	col += vec3(1.0, 0.85, 0.6) * (pow(sd, 700.0) * 3.0 + pow(sd, 10.0) * 0.3) * (1.0 - space_amount);

	// Clouds on a big flat layer, shaded so they look puffy
	if (up > 0.0) {
		vec2 uv = dir.xz / (up + 0.2) * 1.4 + vec2(cloud_offset, 0.0);
		float dens = fbm(uv);
		float cover = smoothstep(0.5, 0.78, dens) * smoothstep(0.0, 0.16, up);
		float toward_sun = fbm(uv + sun.xz * 0.12);
		float lit = clamp((dens - toward_sun) * 3.0 + 0.65, 0.35, 1.0);
		vec3 cloud_col = mix(vec3(0.55, 0.6, 0.72), vec3(1.0, 0.95, 0.88), lit);
		cloud_col = mix(cloud_col, horizon_color, 0.35 * (1.0 - smoothstep(0.0, 0.4, up)));
		col = mix(col, cloud_col, cover * 0.9 * (1.0 - space_amount));
	}
	COLOR = col;
}
"""

var t := 0.0
var focus_y := 6.0
var starting := false

var rocket: Node3D
var flames: Array[Node3D] = []
var exhaust: GPUParticles3D
var ground_smoke: GPUParticles3D
var engine_light: OmniLight3D
var arm_pivot: Node3D
var cam: Camera3D
var sky_mat: ShaderMaterial
var star_mat: StandardMaterial3D
var env: Environment
var fade: ColorRect
var start_button: Button
var message: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_world()
	_build_stars()
	_build_scenery()
	_build_hills()
	_build_rocket()
	_build_ui()


# ----------------------------------------------------------------------------
# Animation: runs every frame
# ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	t += delta
	var burn := maxf(t - LIFTOFF_TIME, 0.0)
	var altitude := 0.5 * ACCELERATION * burn * burn
	var lit := t >= IGNITE_TIME
	var ramp := clampf((t - IGNITE_TIME) / (LIFTOFF_TIME - IGNITE_TIME), 0.0, 1.0)   # engines throttle up
	var shake := ramp * clampf(1.0 - altitude / 80.0, 0.0, 1.0)

	# Rocket, flame, light and smoke
	rocket.position = Vector3(randf_range(-1.0, 1.0) * 0.02 * shake, PAD_TOP + altitude, 0.0)
	var flicker := randf_range(0.85, 1.25)
	for f in flames:
		f.visible = lit
		f.scale = Vector3(1.0, flicker * randf_range(0.95, 1.05), 1.0) * (0.4 + 0.6 * ramp)
	engine_light.light_energy = 10.0 * ramp * randf_range(0.8, 1.2)
	exhaust.emitting = lit
	ground_smoke.emitting = lit and t < LIFTOFF_TIME + 5.0
	arm_pivot.rotation_degrees.y = 75.0 * clampf((t - IGNITE_TIME) / 2.0, 0.0, 1.0)   # tower arm swings away

	# Camera rises a little, tilts up to follow the rocket and shakes during the burn
	focus_y = lerpf(focus_y, maxf(altitude + 4.0, 6.0), clampf(delta * 1.5, 0.0, 1.0))
	cam.position = Vector3(CAM_BASE.x, CAM_BASE.y + altitude * 0.3, CAM_BASE.z)
	cam.look_at(Vector3(0.0, focus_y, 0.0))
	cam.h_offset = randf_range(-1.0, 1.0) * 0.05 * shake
	cam.v_offset = randf_range(-1.0, 1.0) * 0.05 * shake

	# Sky fades from daytime blue into black space as the rocket climbs
	var space := clampf(altitude / 150.0, 0.0, 1.0)
	var top := Color(0.2, 0.36, 0.68).lerp(Color(0.0, 0.0, 0.01), space)
	var horizon := Color(0.95, 0.68, 0.5).lerp(Color(0.01, 0.015, 0.04), space)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("space_amount", space)
	sky_mat.set_shader_parameter("cloud_offset", t * 0.01)   # clouds slowly drift
	env.ambient_light_color = top.lerp(horizon, 0.5)
	env.fog_light_color = horizon
	star_mat.albedo_color = Color(1, 1, 1, space)

	# Fade in at the start and out at the end of each loop
	if not starting:
		fade.color = Color(0, 0, 0, _fade_alpha())
		if t >= LOOP_TIME:
			_reset_launch()


func _fade_alpha() -> float:
	if t < 1.0:
		return 1.0 - t
	if t > FADE_OUT_TIME:
		return clampf((t - FADE_OUT_TIME) / (LOOP_TIME - FADE_OUT_TIME), 0.0, 1.0)
	return 0.0


func _reset_launch() -> void:
	t = 0.0
	focus_y = 6.0
	for f in flames:
		f.visible = false
	exhaust.emitting = false
	ground_smoke.emitting = false


# ----------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------

func _cyl_mesh(bottom: float, top: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.bottom_radius = bottom
	m.top_radius = top
	m.height = height
	m.radial_segments = 24
	m.rings = 1
	return m


func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _add_mesh(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO, metal := 0.0, rough := 0.6) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _soft_circle() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	return gt


# ----------------------------------------------------------------------------
# World: sky, sun, camera, stars, ground, launch tower
# ----------------------------------------------------------------------------

func _build_world() -> void:
	var sky_shader := Shader.new()
	sky_shader.code = SKY_SHADER
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sky_shader
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR   # updated every frame from the sky colors
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Low warm sun shining on the side of the rocket that faces the camera
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-15, 30, 0)
	sun.light_color = Color(1.0, 0.85, 0.7)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)

	cam = Camera3D.new()
	cam.position = CAM_BASE
	cam.fov = 50.0
	cam.far = 6000.0
	add_child(cam)
	cam.make_current()


func _build_stars() -> void:
	var img := Image.create(2048, 1024, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for _i in 3500:
		var x := r.randi_range(0, 2046)
		var y := r.randi_range(0, 1022)
		var b := 0.35 + pow(r.randf(), 3.0) * 0.65
		img.set_pixel(x, y, Color(1, 1, 1, b))
		if b > 0.8:
			img.set_pixel(x + 1, y, Color(1, 1, 1, b * 0.5))
			img.set_pixel(x, y + 1, Color(1, 1, 1, b * 0.5))

	star_mat = StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	star_mat.disable_fog = true
	star_mat.albedo_texture = ImageTexture.create_from_image(img)
	star_mat.albedo_color = Color(1, 1, 1, 0)   # invisible until the rocket climbs

	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1500.0
	sm.height = 3000.0
	sm.radial_segments = 32
	sm.rings = 16
	dome.mesh = sm
	dome.material_override = star_mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)


func _build_scenery() -> void:
	# Ground
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000, 3000)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.22, 0.18)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)

	# Launch pad
	_add_mesh(self, _box_mesh(Vector3(10, PAD_TOP, 10)), Color(0.55, 0.55, 0.58), Vector3(0, PAD_TOP * 0.5, 0), 0.0, 0.9)

	# Launch tower (4 posts and cross beams)
	var tower := Node3D.new()
	tower.position = Vector3(-5.5, 0, 0)
	add_child(tower)
	var steel := Color(0.35, 0.37, 0.4)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_add_mesh(tower, _box_mesh(Vector3(0.25, 14, 0.25)), steel, Vector3(sx * 0.9, 7.2, sz * 0.9), 0.6, 0.5)
	for k in 6:
		var y := 1.5 + k * 2.2
		for s in [-1, 1]:
			_add_mesh(tower, _box_mesh(Vector3(1.9, 0.15, 0.15)), steel, Vector3(0, y, s * 0.9), 0.6, 0.5)
			_add_mesh(tower, _box_mesh(Vector3(0.15, 0.15, 1.9)), steel, Vector3(s * 0.9, y, 0), 0.6, 0.5)

	# Swing arm that reaches the rocket and then swings away at ignition
	arm_pivot = Node3D.new()
	arm_pivot.position = Vector3(-4.6, 6.0, 0)
	add_child(arm_pivot)
	_add_mesh(arm_pivot, _box_mesh(Vector3(3.0, 0.3, 0.5)), Color(0.8, 0.3, 0.1), Vector3(1.5, 0, 0), 0.3, 0.6)


func _build_hills() -> void:
	# A ring of big, low hills far away. The fog turns them hazy so they read as distant.
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var hill_mesh := SphereMesh.new()
	hill_mesh.radius = 1.0
	hill_mesh.height = 2.0
	hill_mesh.radial_segments = 24
	hill_mesh.rings = 12
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.14, 0.18, 0.15)
	hm.roughness = 1.0
	for i in 26:
		var a := (i + r.randf_range(-0.3, 0.3)) / 26.0 * TAU
		var dist := r.randf_range(700.0, 1100.0)
		var hill := MeshInstance3D.new()
		hill.mesh = hill_mesh
		hill.material_override = hm
		hill.position = Vector3(cos(a) * dist, 0.0, sin(a) * dist)
		hill.scale = Vector3(r.randf_range(150.0, 320.0), r.randf_range(35.0, 110.0), r.randf_range(150.0, 320.0))
		hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hill)


# ----------------------------------------------------------------------------
# Rocket (all simple shapes)
# ----------------------------------------------------------------------------

func _build_rocket() -> void:
	rocket = Node3D.new()
	rocket.position = Vector3(0, PAD_TOP, 0)
	add_child(rocket)

	# Your own model if ROCKET_MODEL is set, otherwise the built-in rocket
	var custom := ROCKET_MODEL != "" and _add_custom_model()
	if not custom:
		_build_builtin_rocket()

	# Engine flames (hidden until ignition)
	_add_flame(Vector3.ZERO, 0.5, 3.4)
	if not custom and SIDE_BOOSTERS:
		_add_flame(Vector3(-BOOSTER_X, 0, 0), 0.3, 2.2)
		_add_flame(Vector3(BOOSTER_X, 0, 0), 0.3, 2.2)

	# Light from the flame that glows on the pad and tower
	engine_light = OmniLight3D.new()
	engine_light.position = Vector3(0, -1.5, 0)
	engine_light.light_color = Color(1.0, 0.6, 0.3)
	engine_light.omni_range = 40.0
	engine_light.light_energy = 0.0
	rocket.add_child(engine_light)

	# Smoke: a trail behind the rocket, plus big billows around the pad during ignition
	exhaust = _make_smoke(Vector3(0, 0.3, 0), 160, 4.0, Vector3(0, -1, 0), 14.0, 8.0, 14.0, 1.0, 2.2)
	rocket.add_child(exhaust)
	ground_smoke = _make_smoke(Vector3(0, 0.8, 0), 140, 5.0, Vector3(0, 1, 0), 80.0, 4.0, 9.0, 2.5, 4.5)
	add_child(ground_smoke)


func _add_custom_model() -> bool:
	if not ResourceLoader.exists(ROCKET_MODEL):
		push_warning("ROCKET_MODEL not found, using the built-in rocket: " + ROCKET_MODEL)
		return false
	var scene := load(ROCKET_MODEL) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	if model == null:
		return false
	model.scale = Vector3.ONE * ROCKET_MODEL_SCALE
	model.position = ROCKET_MODEL_OFFSET
	rocket.add_child(model)
	return true


func _fill(c: Color, n: int) -> PackedColorArray:
	var arr := PackedColorArray()
	for _i in n:
		arr.append(c)
	return arr


func _build_builtin_rocket() -> void:
	var dark := Color(0.16, 0.16, 0.19)
	var white := Color(0.95, 0.95, 0.97)
	var black := Color(0.06, 0.06, 0.08)
	var red := Color(0.85, 0.15, 0.1)
	var steel := Color(0.28, 0.28, 0.31)

	# Each shape is a profile of (radius, height) points that gets spun around the rocket's
	# axis, so the nose is a smooth curve. Colors are per segment (bottom to top).
	var core_pts := PackedVector2Array([
		Vector2(0.0, 0.9), Vector2(0.70, 0.9), Vector2(0.76, 1.3),     # base disc and flared skirt
		Vector2(0.76, 3.6), Vector2(0.76, 4.0), Vector2(0.76, 6.4),    # body with a black band
		Vector2(0.74, 6.9), Vector2(0.68, 7.4), Vector2(0.58, 7.9),    # nose cone curve...
		Vector2(0.44, 8.4), Vector2(0.28, 8.85), Vector2(0.12, 9.2),
		Vector2(0.0, 9.45)])                                           # ...to the tip
	var core_cols := PackedColorArray([dark, dark, white, black, white])
	core_cols.append_array(_fill(red, 7))
	_add_lathe(core_pts, core_cols, Vector3.ZERO)

	var bell_pts := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.55, 0.0), Vector2(0.5, 0.2), Vector2(0.42, 0.45),
		Vector2(0.34, 0.7), Vector2(0.3, 0.95), Vector2(0.0, 0.95)])
	var bell_cols := _fill(steel, 6)
	_add_lathe(bell_pts, bell_cols, Vector3.ZERO, 0.9, 0.35)           # engine bell

	# Four swept fins
	var fin_mesh := PrismMesh.new()
	fin_mesh.size = Vector3(1.0, 2.0, 0.1)
	fin_mesh.left_to_right = 0.0
	for i in 4:
		var a := i * PI / 2.0
		var fin := _add_mesh(rocket, fin_mesh, red, Vector3(cos(a), 0.0, sin(a)) * 1.22 + Vector3(0, 1.95, 0), 0.2, 0.4)
		fin.rotation.y = -a

	# Porthole
	var window := _add_mesh(rocket, SphereMesh.new(), Color(0.2, 0.5, 0.8), Vector3(0, 5.3, 0.74), 0.5, 0.1)
	window.scale = Vector3(0.2, 0.2, 0.1)

	# Side boosters
	if SIDE_BOOSTERS:
		var booster_pts := PackedVector2Array([
			Vector2(0.0, 0.9), Vector2(0.34, 0.9), Vector2(0.38, 1.2), Vector2(0.38, 5.2),
			Vector2(0.36, 5.6), Vector2(0.3, 6.0), Vector2(0.2, 6.35), Vector2(0.08, 6.6), Vector2(0.0, 6.75)])
		var booster_cols := PackedColorArray([dark, dark, white])
		booster_cols.append_array(_fill(red, 5))
		for sx in [-1, 1]:
			_add_lathe(booster_pts, booster_cols, Vector3(sx * BOOSTER_X, 0, 0))
			var small_bell := _add_lathe(bell_pts, bell_cols, Vector3(sx * BOOSTER_X, 0, 0), 0.9, 0.35)
			small_bell.scale = Vector3(0.6, 1.0, 0.6)


func _add_lathe(pts: PackedVector2Array, cols: PackedColorArray, pos: Vector3, metal := 0.3, rough := 0.35) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _lathe_mesh(pts, cols)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.metallic = metal
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.position = pos
	rocket.add_child(mi)
	return mi


# Spins a (radius, height) profile around the Y axis into a smooth mesh.
func _lathe_mesh(pts: PackedVector2Array, cols: PackedColorArray, sides := 40) -> ArrayMesh:
	var segs := pts.size() - 1

	# Outward normal of each profile segment, in (radius, height) space
	var seg_n: Array[Vector2] = []
	for i in segs:
		var d := pts[i + 1] - pts[i]
		var n := Vector2(d.y, -d.x)
		seg_n.append(n.normalized() if n.length() > 0.0001 else Vector2(1, 0))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		# Smooth the shading across gentle bends, keep hard edges (like the base) sharp
		var n_bottom := seg_n[i]
		if i > 0 and seg_n[i - 1].dot(seg_n[i]) > 0.7:
			n_bottom = (seg_n[i - 1] + seg_n[i]).normalized()
		var n_top := seg_n[i]
		if i < segs - 1 and seg_n[i].dot(seg_n[i + 1]) > 0.7:
			n_top = (seg_n[i] + seg_n[i + 1]).normalized()
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			# Two triangles per quad (clockwise from outside = front face in Godot)
			_lathe_vertex(st, pts[i + 1], n_top, a1, cols[i])
			_lathe_vertex(st, pts[i + 1], n_top, a0, cols[i])
			_lathe_vertex(st, pts[i], n_bottom, a0, cols[i])
			_lathe_vertex(st, pts[i + 1], n_top, a1, cols[i])
			_lathe_vertex(st, pts[i], n_bottom, a0, cols[i])
			_lathe_vertex(st, pts[i], n_bottom, a1, cols[i])
	return st.commit()


func _lathe_vertex(st: SurfaceTool, pt: Vector2, n: Vector2, a: float, color: Color) -> void:
	st.set_color(color)
	st.set_normal(Vector3(cos(a) * n.x, n.y, sin(a) * n.x))
	st.add_vertex(Vector3(cos(a) * pt.x, pt.y, sin(a) * pt.x))


func _add_flame(pos: Vector3, radius: float, height: float) -> void:
	var f := Node3D.new()
	f.position = pos
	f.visible = false
	rocket.add_child(f)
	_add_flame_cone(f, radius, height, Color(1.8, 0.8, 0.2, 0.75))             # orange outer flame
	_add_flame_cone(f, radius * 0.55, height * 0.65, Color(2.2, 1.9, 1.2, 0.95))  # bright inner flame
	flames.append(f)


func _add_flame_cone(parent: Node3D, radius: float, height: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _cyl_mesh(0.0, radius, height)   # wide at the nozzle, pointed at the bottom
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	mi.material_override = m
	mi.position = Vector3(0, -height * 0.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _make_smoke(pos: Vector3, amount: int, life: float, dir: Vector3, spread: float, vmin: float, vmax: float, smin: float, smax: float) -> GPUParticles3D:
	# Puff color: starts warm and clear, turns white-grey, then fades away
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.1, 0.4, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 0.85, 0.6, 0.0), Color(1.0, 0.9, 0.8, 0.85),
		Color(0.85, 0.85, 0.88, 0.6), Color(0.7, 0.7, 0.75, 0.0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp

	# Puffs grow as they age
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(1.0, 1.6))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve

	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3.ZERO
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.scale_min = smin
	pm.scale_max = smax
	pm.scale_curve = curve_tex
	pm.color_ramp = ramp_tex
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.8

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.particles_anim_h_frames = 1
	mat.particles_anim_v_frames = 1
	mat.albedo_texture = _soft_circle()
	mat.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.material = mat

	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false          # puffs stay where they were made, so the rocket leaves a trail
	p.emitting = false
	p.process_material = pm
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-80, -300, -80), Vector3(160, 600, 160))
	p.position = pos
	return p


# ----------------------------------------------------------------------------
# Menu UI
# ----------------------------------------------------------------------------

func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	sb.shadow_color = Color(border.r, border.g, border.b, 0.35)
	sb.shadow_size = 12
	return sb


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# The one button
	start_button = Button.new()
	start_button.text = BUTTON_TEXT
	start_button.add_theme_font_size_override("font_size", 30)
	start_button.add_theme_color_override("font_color", Color.WHITE)
	start_button.add_theme_color_override("font_hover_color", Color.WHITE)
	start_button.add_theme_stylebox_override("normal", _button_style(Color(0.02, 0.05, 0.1, 0.7), Color(0.45, 0.8, 1.0, 0.9)))
	start_button.add_theme_stylebox_override("hover", _button_style(Color(0.1, 0.22, 0.38, 0.9), Color.WHITE))
	start_button.add_theme_stylebox_override("pressed", _button_style(Color(0.3, 0.6, 0.9, 0.95), Color.WHITE))
	start_button.add_theme_stylebox_override("focus", _button_style(Color(0, 0, 0, 0), Color.WHITE))
	start_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	start_button.offset_left = -190
	start_button.offset_right = 190
	start_button.offset_top = -170
	start_button.offset_bottom = -90
	start_button.pressed.connect(_on_start_pressed)
	layer.add_child(start_button)
	start_button.grab_focus()   # Enter / Space also works

	# Shows a hint if START_SCENE is wrong (instead of crashing)
	message = Label.new()
	message.visible = false
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	message.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	message.offset_left = -400
	message.offset_right = 400
	message.offset_top = -80
	message.offset_bottom = -20
	layer.add_child(message)

	# Black overlay for the fades (added last so it draws on top)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_start_pressed() -> void:
	if starting:
		return
	if not ResourceLoader.exists(START_SCENE):
		message.text = "START_SCENE is not set to a real scene yet.\nOpen main_menu.gd and change START_SCENE at the top (right-click your scene > Copy Path)."
		message.visible = true
		return
	starting = true
	start_button.disabled = true
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.7)
	tween.tween_callback(func(): get_tree().change_scene_to_file(START_SCENE))
