extends Node3D
## MAIN MENU: a rocket launches in the background, with one "Start a Mission" button.
## Everything is built in code, so the scene only needs this script on a Node3D.

# The scene that opens when the player clicks the button.
# (Right-click the scene file in the FileSystem panel > Copy Path, then paste it here.)
const START_SCENE = "res://scenes/select_rocket.tscn"
const BUTTON_TEXT = "Start a Mission"

# Launch timeline in seconds (the whole launch loops forever)
const IGNITE_TIME = 2.0      # engines light, flame and smoke start
const LIFTOFF_TIME = 4.0     # rocket starts to climb
const ACCELERATION = 3.5     # how quickly the rocket speeds up
const FADE_OUT_TIME = 14.0   # screen fades to black...
const LOOP_TIME = 15.5       # ...then the launch starts over

const PAD_TOP = 0.4
const CAM_BASE = Vector3(26, 3, 37)

var t := 0.0
var focus_y := 6.0
var starting := false

var rocket: Node3D
var flame: Node3D
var exhaust: GPUParticles3D
var ground_smoke: GPUParticles3D
var engine_light: OmniLight3D
var arm_pivot: Node3D
var cam: Camera3D
var sky_mat: ProceduralSkyMaterial
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
	flame.visible = lit
	flame.scale = Vector3(1.0, randf_range(0.85, 1.25), 1.0) * (0.4 + 0.6 * ramp)
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
	var horizon := Color(0.95, 0.68, 0.5).lerp(Color(0.01, 0.015, 0.04), space)
	sky_mat.sky_top_color = Color(0.2, 0.36, 0.68).lerp(Color(0.0, 0.0, 0.01), space)
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = horizon.darkened(0.5)
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
	flame.visible = false
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
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
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
	_add_mesh(arm_pivot, _box_mesh(Vector3(3.6, 0.3, 0.5)), Color(0.8, 0.3, 0.1), Vector3(1.8, 0, 0), 0.3, 0.6)


# ----------------------------------------------------------------------------
# Rocket (all simple shapes)
# ----------------------------------------------------------------------------

func _build_rocket() -> void:
	rocket = Node3D.new()
	rocket.position = Vector3(0, PAD_TOP, 0)
	add_child(rocket)

	var white := Color(0.95, 0.95, 0.97)
	var red := Color(0.85, 0.12, 0.1)
	_add_mesh(rocket, _cyl_mesh(0.55, 0.35, 0.8), Color(0.2, 0.2, 0.23), Vector3(0, 0.4, 0), 0.9, 0.4)   # engine nozzle
	_add_mesh(rocket, _cyl_mesh(0.7, 0.7, 5.5), white, Vector3(0, 3.55, 0), 0.2, 0.35)                   # body
	_add_mesh(rocket, _cyl_mesh(0.72, 0.72, 0.5), Color(0.08, 0.08, 0.1), Vector3(0, 4.6, 0))            # black band
	_add_mesh(rocket, _cyl_mesh(0.7, 0.0, 1.6), red, Vector3(0, 7.1, 0), 0.2, 0.4)                       # nose cone
	var window := _add_mesh(rocket, SphereMesh.new(), Color(0.2, 0.5, 0.8), Vector3(0, 5.6, 0.62), 0.5, 0.1)
	window.scale = Vector3(0.22, 0.22, 0.12)

	# Four fins
	for i in 4:
		var a := i * PI / 2.0
		var fin := _add_mesh(rocket, _box_mesh(Vector3(0.9, 1.7, 0.08)), red, Vector3(cos(a), 0.0, sin(a)) * 0.95 + Vector3(0, 1.7, 0))
		fin.rotation.y = -a

	# Engine flame (hidden until ignition): a bright inner cone inside an orange outer cone
	flame = Node3D.new()
	flame.visible = false
	rocket.add_child(flame)
	_add_flame_cone(flame, 0.5, 3.4, Color(1.8, 0.8, 0.2, 0.75))
	_add_flame_cone(flame, 0.28, 2.2, Color(2.2, 1.9, 1.2, 0.95))

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
