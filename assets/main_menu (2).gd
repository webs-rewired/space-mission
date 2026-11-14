extends Node3D
## MAIN MENU: a rocket launches in the background, with Start a Mission, Settings, Credits and Quit.
## Everything is built in code, so the scene only needs this script on a Node3D.
##
## Settings (graphics quality, fullscreen, volumes) are kept by scripts/game_settings.gd, which GameState starts.
## "Start a Mission" goes through GameState.go_to_scene(), which shows the loading screen while the next scene loads.

signal mission_started   # sent when the player clicks the button (handy if the menu is inside your game scene)

# What "Start a Mission" does:
#  - a scene path -> switches to that scene. RECOMMENDED: keep this menu as its own scene
#                    (set it as the project's Main Scene) and put your gameplay scene's path here.
#                    (Right-click the scene file in the FileSystem panel > Copy Path.)
#  - ""           -> just removes the menu and shows the scene it was added to. Use this only if you
#                    placed the menu INSIDE your game scene.
const START_SCENE = "res://scenes/solar_system.tscn"

# Only used when START_SCENE is "" (menu inside your game scene): freeze the game behind the menu
const PAUSE_GAME_WHILE_OPEN = true
const BUTTON_TEXT = "Start a Mission"
const GAME_TITLE = "ORBIT LAB"
const GAME_TAGLINE = "Design a space mission. Launch it. Fly it."

# Shown at the top of the Credits panel. Put your team's name and members here.
const TEAM_NAME = ""
const TEAM_MEMBERS = []

const CREDITS = [
	["ABOUT", [
		"Made for the NASA Space Apps Challenge 2026.",
		"Every planet and moon is where it really is today, and every number in the game (thrust, fuel, travel time, data rate, sunlight, gravity) comes from real physics and real missions."]],
	["SCIENCE AND DATA", [
		"Planet, moon and spacecraft positions: NASA JPL orbital elements",
		"Mission facts and numbers: NASA mission pages and press kits",
		"Mission design ideas: NASA's Design and Develop Science Missions guide, the Mission Design Lab, JPL's Concept Maturity Levels and CubeSat 101"]],
	["3D MODELS", [
		"Spacecraft, rovers, landers and the Mobile Launcher: NASA 3D Resources (public domain)",
		"Saturn V: juli on Sketchfab (CC BY 4.0), split into stages for the game",
		"Rocks: made for this game"]],
	["PICTURES", [
		"Planet and star maps: Solar System Scope (CC BY 4.0)",
		"Moon maps (Io, Europa, Ganymede, Callisto, Enceladus, Phobos, Deimos, Pluto, Charon): NASA 3D Resources (public domain)",
		"Lunar soil: NASA photo AS11-40-5878, Apollo 11 (public domain)",
		"Rock: ambientCG Rock023 (CC0)     Launch sky: Poly Haven (CC0)"]],
	["SOUND AND MUSIC", [
		"Mission audio: NASA (Apollo 11, Apollo 13, Artemis I, Space Shuttle, Perseverance, InSight, Juno), public domain",
		"Sound effects: Kenney (CC0)",
		"Music: \"Out There\" by yd and \"Outer Space Loop\" by wipics, OpenGameArt (CC0)"]],
	["BUILT WITH", ["Godot Engine 4"]],
]

# Launch timeline in seconds (the whole launch loops forever)
const IGNITE_TIME = 2.0      # engines light, flame and smoke start
const LIFTOFF_TIME = 4.0     # rocket starts to climb
const ACCELERATION = 3.5     # how quickly the rocket speeds up
const FADE_OUT_TIME = 14.0   # screen fades to black...
const LOOP_TIME = 15.5       # ...then the launch starts over

const PAD_TOP = 2.2   # height of the launch platform deck above the water
const CAM_BASE = Vector3(20, 2.5, 28)

# Which rocket to show:
#   "starship"  = SpaceX Starship (Super Heavy booster + ship)
#   "sls"       = NASA Space Launch System (orange core, two white boosters, Orion capsule)
#   "saturn_v"  = NASA Saturn V (the Apollo moon rocket)
#   "random"    = a different one on every launch loop
const ROCKET_STYLE = "random"
const ROCKET_STYLES = ["sls", "saturn_v", "falcon9", "starship"]
# The real rocket models from the game (the same ones the rocket builder uses) are shown when they're in the
# project; if one is missing, the simple built-in shape of that rocket is drawn instead
const REAL_ROCKET_PRESETS = {"sls": "sls", "saturn_v": "saturn5", "falcon9": "falcon9", "starship": "starship"}
const MENU_ROCKET_HEIGHT = 13.0   # meters in the menu scene (the platform and tower are built for this)

# Overall mood: "moody" = foggy overcast ocean (like a cinematic game menu), "sunrise" = warm clear morning
const LOOK = "moody"
# Fancy effects (reflections, soft shadows, light fog, depth blur). These only show on High graphics
# (Settings > Graphics quality); set this to false to turn them off for everyone.
const HEAVY_EFFECTS = true
# Size of the black cinematic bars at the top and bottom (fraction of screen height)
const BAR_SIZE = 0.12
const FOCUS_START = 9.0   # camera aims at this height at the start of each launch

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
uniform float overcast = 0.0;   // 0 = scattered clouds, 1 = heavy grey cloud cover

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
	col += vec3(1.0, 0.85, 0.6) * (pow(sd, 700.0) * 3.0 + pow(sd, 10.0) * 0.3) * (1.0 - space_amount) * (1.0 - 0.85 * overcast);

	// Clouds on a big flat layer, shaded so they look puffy
	if (up > 0.0) {
		vec2 uv = dir.xz / (up + 0.2) * 1.4 + vec2(cloud_offset, 0.0);
		float dens = fbm(uv);
		float cover = smoothstep(mix(0.5, 0.3, overcast), mix(0.78, 0.6, overcast), dens) * smoothstep(0.0, 0.16, up);
		float toward_sun = fbm(uv + sun.xz * 0.12);
		float lit = clamp((dens - toward_sun) * 3.0 + 0.65, 0.35, 1.0);
		vec3 cloud_col = mix(vec3(0.55, 0.6, 0.72), vec3(1.0, 0.95, 0.88), lit);
		cloud_col = mix(cloud_col, vec3(0.5, 0.55, 0.62) * (0.7 + 0.5 * lit), overcast);
		cloud_col = mix(cloud_col, horizon_color, 0.35 * (1.0 - smoothstep(0.0, 0.4, up)));
		col = mix(col, cloud_col, cover * mix(0.9, 1.0, overcast) * (1.0 - space_amount));
	}
	COLOR = col;
}
"""

# Ocean: big waves move the surface, small ripples only bend the light so it sparkles.
const WATER_SHADER = """
shader_type spatial;

uniform vec3 deep_color : source_color = vec3(0.01, 0.035, 0.05);
uniform vec3 shallow_color : source_color = vec3(0.05, 0.13, 0.16);

varying vec3 world_pos;

// One directional wave: x = height, y and z = slope along x and z
vec3 wave(vec2 p, vec2 dir, float k, float amp, float speed, float t) {
	vec2 d = normalize(dir);
	float ph = dot(d, p) * k + t * speed;
	return vec3(amp * sin(ph), amp * k * cos(ph) * d.x, amp * k * cos(ph) * d.y);
}

vec3 big_waves(vec2 p, float t) {
	vec3 r = wave(p, vec2(1.0, 0.35), 0.12, 0.34, 0.9, t);
	r += wave(p, vec2(0.55, 1.0), 0.18, 0.22, 1.2, t);
	r += wave(p, vec2(-0.45, 1.0), 0.25, 0.14, 1.5, t);
	return r;
}

vec3 small_waves(vec2 p, float t) {
	vec3 r = wave(p, vec2(1.0, 0.1), 0.55, 0.05, 1.9, t);
	r += wave(p, vec2(-0.3, 1.0), 0.9, 0.03, 2.3, t);
	r += wave(p, vec2(0.8, -0.6), 1.7, 0.016, 3.1, t);
	r += wave(p, vec2(-0.9, -0.4), 3.1, 0.008, 4.0, t);
	return r;
}

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec3 w = big_waves(p, TIME);
	VERTEX.y += w.x;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 bw = big_waves(p, TIME);
	vec3 sw = small_waves(p, TIME);

	// Fade the fine ripples with distance so the far water doesn't shimmer
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(60.0, 500.0, dist);
	vec2 slope = vec2(bw.y, bw.z) + vec2(sw.y, sw.z) * detail;
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float crest = clamp(bw.x * 1.6 + 0.5, 0.0, 1.0);
	float foam = smoothstep(0.78, 1.0, crest + sw.x * 4.0 * detail);
	ALBEDO = mix(mix(deep_color, shallow_color, crest * 0.7), vec3(0.62, 0.68, 0.72), foam * 0.45);
	ROUGHNESS = mix(0.04, 0.4, foam);
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
"""

# Film look drawn over the whole 3D view: grain, vignette, color fringing, cool grade.
const POST_SHADER = """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain_amount = 0.055;
uniform float vignette_amount = 0.55;
uniform float aberration = 0.0025;
uniform float desaturate = 0.22;
uniform vec3 tint = vec3(0.93, 0.98, 1.06);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	vec2 shift = c * aberration * (1.0 + dot(c, c) * 6.0);
	vec3 col;
	col.r = texture(screen_tex, uv + shift).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - shift).b;

	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(l), desaturate);
	col *= tint;

	float vig = 1.0 - smoothstep(0.2, 0.95, length(c) * 1.25);
	col *= mix(1.0 - vignette_amount, 1.0, vig);

	float n = hash12(uv * vec2(1920.0, 1080.0) + floor(TIME * 24.0) * 17.0) - 0.5;
	col += n * grain_amount * (1.0 - l * 0.6);
	COLOR = vec4(col, 1.0);
}
"""

var t := 0.0
var focus_y := FOCUS_START
var style_index := -1
var ui_time := 0.0
var day_top := Color(0.2, 0.36, 0.68)
var day_horizon := Color(0.95, 0.68, 0.5)
var birds: Array[Dictionary] = []
var starting := false
var paused_by_menu := false

var layer: CanvasLayer   # all menu visuals live on this layer, on top of everything else
var world: Node3D        # the menu's own 3D world (isolated from your game map)

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
var menu_buttons: VBoxContainer
var settings_panel: PanelContainer
var credits_panel: PanelContainer
var settings: Node = null   # scripts/game_settings.gd (null if the game was started without GameState)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep animating even if the game is paused behind it
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	settings = get_tree().root.get_node_or_null("GameSettings")
	if settings == null and "settings" in GameState:
		settings = GameState.settings
	if START_SCENE == "" and PAUSE_GAME_WHILE_OPEN:
		get_tree().paused = true
		paused_by_menu = true
	_build_viewport()
	_build_world()
	_build_stars()
	_build_scenery()
	_build_hills()
	_build_rocket()
	_build_birds()
	_build_ui()


func heavy_effects() -> bool:
	return HEAVY_EFFECTS and (settings == null or settings.fancy_effects_on())


func _build_viewport() -> void:
	layer = CanvasLayer.new()
	layer.layer = 100   # above your game's own UI
	add_child(layer)

	# The menu's 3D scene is drawn inside its own SubViewport with its own World3D, so its sky,
	# lights, ground and camera can never mix with (or overlap) your gameplay map.
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Film look: grain, vignette, slight color fringing and a cool, desaturated grade
	var post := ColorRect.new()
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var post_shader := Shader.new()
	post_shader.code = POST_SHADER
	var post_mat := ShaderMaterial.new()
	post_mat.shader = post_shader
	if LOOK != "moody":
		post_mat.set_shader_parameter("desaturate", 0.05)
		post_mat.set_shader_parameter("tint", Vector3(1.02, 1.0, 0.97))
	post.material = post_mat
	layer.add_child(post)
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	container.add_child(vp)

	world = Node3D.new()
	vp.add_child(world)


func _exit_tree() -> void:
	# Never leave the game stuck paused if the menu is removed
	if paused_by_menu and is_inside_tree():
		get_tree().paused = false


# ----------------------------------------------------------------------------
# Animation: runs every frame
# ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	t += delta
	ui_time += delta
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
		var base_scale: Vector3 = f.get_meta("base_scale", Vector3.ONE)   # (a real rocket's flames are sized to its nozzles)
		f.scale = base_scale * Vector3(1.0, flicker * randf_range(0.95, 1.05), 1.0) * (0.4 + 0.6 * ramp)
	engine_light.light_energy = 10.0 * ramp * randf_range(0.8, 1.2)
	exhaust.emitting = lit
	ground_smoke.emitting = lit and t < LIFTOFF_TIME + 5.0
	arm_pivot.rotation_degrees.y = 75.0 * clampf((t - IGNITE_TIME) / 2.0, 0.0, 1.0)   # tower arm swings away

	# Camera rises a little, tilts up to follow the rocket and shakes during the burn
	focus_y = lerpf(focus_y, maxf(altitude + FOCUS_START, FOCUS_START), clampf(delta * 1.5, 0.0, 1.0))
	cam.position = Vector3(CAM_BASE.x, CAM_BASE.y + altitude * 0.3, CAM_BASE.z)
	cam.look_at(Vector3(0.0, focus_y, 0.0))
	# Engine shake plus a slow handheld-camera drift
	cam.h_offset = randf_range(-1.0, 1.0) * 0.05 * shake + sin(t * 0.6) * 0.03
	cam.v_offset = randf_range(-1.0, 1.0) * 0.05 * shake + cos(t * 0.45) * 0.02

	# Sky fades from daytime blue into black space as the rocket climbs
	var space := clampf(altitude / 150.0, 0.0, 1.0)
	var top := day_top.lerp(Color(0.0, 0.0, 0.01), space)
	var horizon := day_horizon.lerp(Color(0.01, 0.015, 0.04), space)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("space_amount", space)
	sky_mat.set_shader_parameter("cloud_offset", t * 0.01)   # clouds slowly drift
	env.ambient_light_color = top.lerp(horizon, 0.5)
	env.fog_light_color = horizon
	star_mat.albedo_color = Color(1, 1, 1, space)

	_update_birds()
	# The button text slowly breathes, like a game's "press any button" prompt
	start_button.modulate = Color(1, 1, 1, 0.6 + 0.4 * (0.5 + 0.5 * sin(ui_time * 2.0)))
	if settings and settings.notice != "":
		# (the game turned its own graphics down because this computer was running slowly)
		message.text = settings.notice
		message.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		message.visible = true
		settings.notice = ""

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
	focus_y = FOCUS_START
	if ROCKET_STYLE == "random" and ROCKET_MODEL == "":
		# The screen is black right now, so swap in the next rocket
		rocket.queue_free()
		ground_smoke.queue_free()
		flames.clear()
		_build_rocket()
	else:
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
	var moody := LOOK == "moody"
	day_top = Color(0.33, 0.41, 0.51) if moody else Color(0.2, 0.36, 0.68)
	day_horizon = Color(0.68, 0.74, 0.8) if moody else Color(0.95, 0.68, 0.5)

	var sky_shader := Shader.new()
	sky_shader.code = SKY_SHADER
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sky_shader
	sky_mat.set_shader_parameter("overcast", 1.0 if moody else 0.0)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR   # updated every frame from the sky colors
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.8 if moody else 0.95
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.0035 if moody else 0.0012
	env.fog_sky_affect = 0.0
	if heavy_effects():
		env.ssao_enabled = true            # soft contact shadows
		env.ssr_enabled = true             # the rocket and platform reflect in the water
		env.volumetric_fog_enabled = true  # light fog you can see sunlight and the engine glow in
		env.volumetric_fog_density = 0.006
		env.volumetric_fog_albedo = Color(0.8, 0.85, 0.9)
		env.volumetric_fog_length = 120.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	# Low warm sun shining on the side of the rocket that faces the camera
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-15, 30, 0)
	sun.light_color = Color(0.9, 0.93, 1.0) if moody else Color(1.0, 0.85, 0.7)
	sun.light_energy = 1.25 if moody else 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	world.add_child(sun)

	cam = Camera3D.new()
	cam.position = CAM_BASE
	cam.fov = 50.0
	cam.far = 6000.0
	if heavy_effects():
		# Slight blur on the far distance, like a real lens
		var attrs := CameraAttributesPractical.new()
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = 300.0
		attrs.dof_blur_far_transition = 500.0
		attrs.dof_blur_amount = 0.06
		cam.attributes = attrs
	world.add_child(cam)
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
	world.add_child(dome)


func _build_scenery() -> void:
	# Ocean with animated waves
	var ocean := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2400, 2400)
	var water_detail: int = 400 if settings == null else [120, 240, 400][settings.quality]   # fewer wave points on slower computers
	plane.subdivide_width = water_detail
	plane.subdivide_depth = water_detail
	ocean.mesh = plane
	var water_shader := Shader.new()
	water_shader.code = WATER_SHADER
	var water_mat := ShaderMaterial.new()
	water_mat.shader = water_shader
	ocean.material_override = water_mat
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ocean)

	# Offshore launch platform: a deck standing on four legs in the water
	var concrete := Color(0.5, 0.52, 0.55)
	_add_mesh(world, _box_mesh(Vector3(14, 0.8, 14)), concrete, Vector3(0, PAD_TOP - 0.4, 0), 0.0, 0.9)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_add_mesh(world, _cyl_mesh(0.9, 0.9, PAD_TOP + 6.0), concrete.darkened(0.2), Vector3(sx * 5.8, (PAD_TOP - 6.0) * 0.5, sz * 5.8), 0.0, 0.9)
	for s_ in [-1, 1]:
		_add_mesh(world, _box_mesh(Vector3(11.6, 0.35, 0.35)), concrete.darkened(0.3), Vector3(0, -1.5, s_ * 5.8), 0.0, 0.9)
		_add_mesh(world, _box_mesh(Vector3(0.35, 0.35, 11.6)), concrete.darkened(0.3), Vector3(s_ * 5.8, -1.5, 0), 0.0, 0.9)

	# Launch tower (4 posts and cross beams)
	var tower := Node3D.new()
	tower.position = Vector3(-5.5, PAD_TOP, 0)
	world.add_child(tower)
	var steel := Color(0.35, 0.37, 0.4)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_add_mesh(tower, _box_mesh(Vector3(0.25, 15, 0.25)), steel, Vector3(sx * 0.9, 7.5, sz * 0.9), 0.6, 0.5)
	for k in 7:
		var y := 1.5 + k * 2.2
		for s_ in [-1, 1]:
			_add_mesh(tower, _box_mesh(Vector3(1.9, 0.15, 0.15)), steel, Vector3(0, y, s_ * 0.9), 0.6, 0.5)
			_add_mesh(tower, _box_mesh(Vector3(0.15, 0.15, 1.9)), steel, Vector3(s_ * 0.9, y, 0), 0.6, 0.5)

	# Swing arm that reaches the rocket and then swings away at ignition
	arm_pivot = Node3D.new()
	arm_pivot.position = Vector3(-4.6, PAD_TOP + 6.0, 0)
	world.add_child(arm_pivot)
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
		world.add_child(hill)


# ----------------------------------------------------------------------------
# Rocket (all simple shapes)
# ----------------------------------------------------------------------------

func _pick_style() -> String:
	if ROCKET_STYLE == "random":
		style_index = (style_index + 1) % ROCKET_STYLES.size()
		return ROCKET_STYLES[style_index]
	return ROCKET_STYLE


func _build_rocket() -> void:
	rocket = Node3D.new()
	rocket.position = Vector3(0, PAD_TOP, 0)
	world.add_child(rocket)

	# Your own model if ROCKET_MODEL is set, otherwise one of the built-in rockets
	var custom := ROCKET_MODEL != "" and _add_custom_model()
	if custom:
		_add_flame(Vector3.ZERO, 0.5, 3.4)
	else:
		var style := _pick_style()
		if not _add_real_rocket(style):
			match style:
				"sls":
					_build_sls()
				"saturn_v":
					_build_saturn_v()
				_:
					_build_starship()

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
	ground_smoke = _make_smoke(Vector3(0, PAD_TOP + 0.5, 0), 140, 5.0, Vector3(0, 1, 0), 80.0, 4.0, 9.0, 2.5, 4.5)
	world.add_child(ground_smoke)


# One of the game's real rocket models (scripts/real_rocket.gd), shrunk to the menu's size, with its own flames
func _add_real_rocket(style: String) -> bool:
	if not REAL_ROCKET_PRESETS.has(style):
		return false
	var real_rocket_script = load("res://scripts/real_rocket.gd")
	var rocket_data = load("res://scripts/rocket_data.gd")
	if real_rocket_script == null or rocket_data == null or not rocket_data.STARTING_ROCKETS.has(REAL_ROCKET_PRESETS[style]):
		return false
	var built = real_rocket_script.build(rocket_data.STARTING_ROCKETS[REAL_ROCKET_PRESETS[style]].duplicate())
	if built == null:
		return false
	var model: Node3D = built["root"]
	rocket.add_child(model)
	var box = real_rocket_script.solid_bounds(model, Transform3D.IDENTITY, null)
	if box == null or box.size.y <= 0.0:
		model.queue_free()
		return false
	var shrink: float = MENU_ROCKET_HEIGHT / box.size.y
	model.scale = Vector3.ONE * shrink
	model.position = Vector3(-box.get_center().x * shrink, -box.position.y * shrink, -box.get_center().z * shrink)
	for flame in built["bottom_flames"] + built["booster_flames"]:
		flame.set_meta("base_scale", flame.scale)
		flame.visible = false
		flames.append(flame)
	return true


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


# ----------------------------------------------------------------------------
# The three built-in rockets. Each is spun from a (radius, height) profile so the
# nose cones and tapers are smooth, then fins, flaps and engine bells are added.
# Proportions follow the real rockets, shrunk to about 13 m tall.
# ----------------------------------------------------------------------------

func _build_starship() -> void:
	var steel := Color(0.78, 0.8, 0.84)
	var dark := Color(0.12, 0.12, 0.14)
	var soot := Color(0.2, 0.18, 0.17)
	var plate := Color(0.2, 0.2, 0.23)

	# Super Heavy booster: stainless steel, sooty base, black hot-stage ring on top
	var booster_pts := PackedVector2Array([
		Vector2(0.0, 0.25), Vector2(0.48, 0.25), Vector2(0.48, 0.9),
		Vector2(0.48, 7.3), Vector2(0.48, 7.6), Vector2(0.0, 7.6)])
	var booster_cols := PackedColorArray([soot, soot, steel, dark, dark])
	_add_lathe(booster_pts, booster_cols, Vector3.ZERO, 0.95, 0.28)

	# Starship upper stage with a tapered nose
	var ship_pts := PackedVector2Array([
		Vector2(0.0, 7.6), Vector2(0.48, 7.6), Vector2(0.48, 11.6),
		Vector2(0.46, 11.9), Vector2(0.41, 12.2), Vector2(0.33, 12.5),
		Vector2(0.22, 12.75), Vector2(0.1, 12.92), Vector2(0.0, 13.0)])
	var ship_cols := PackedColorArray([dark])
	ship_cols.append_array(_fill(steel, 7))
	_add_lathe(ship_pts, ship_cols, Vector3.ZERO, 0.95, 0.28)

	# 19 Raptor engines: 1 in the middle, then rings of 6 and 12
	var engines: Array[Vector2] = [Vector2.ZERO]
	engines.append_array(_ring(6, 0.17))
	engines.append_array(_ring(12, 0.34, 0.26))
	_add_bells(engines, 0.065, 0.25)

	# Four grid fins at the top of the booster
	for i in 4:
		var a := i * PI / 2.0
		var grid_fin := _add_mesh(rocket, _box_mesh(Vector3(0.2, 0.34, 0.05)), plate, Vector3(cos(a), 0.0, sin(a)) * 0.58 + Vector3(0, 7.0, 0), 0.5, 0.5)
		grid_fin.rotation.y = -a

	# Two flaps on each side of the ship: big ones at the back, small ones near the nose
	for ang in [145.0, 325.0]:
		var fa := deg_to_rad(ang)
		var dir := Vector3(cos(fa), 0.0, sin(fa))
		var aft := _add_mesh(rocket, _box_mesh(Vector3(0.05, 1.15, 0.4)), plate, dir * 0.51 + Vector3(0, 8.45, 0), 0.4, 0.5)
		aft.rotation.y = -fa
		var fwd := _add_mesh(rocket, _box_mesh(Vector3(0.05, 0.55, 0.22)), plate, dir * 0.46 + Vector3(0, 12.1, 0), 0.4, 0.5)
		fwd.rotation.y = -fa

	# Wide pale plume from the engine cluster
	_add_flame(Vector3.ZERO, 0.47, 5.0, Color(1.2, 0.8, 0.6, 0.5), Color(1.7, 1.9, 2.4, 0.9))


func _build_sls() -> void:
	var orange := Color(0.86, 0.42, 0.14)
	var white := Color(0.94, 0.94, 0.96)
	var gray := Color(0.78, 0.78, 0.82)
	var black := Color(0.07, 0.07, 0.09)
	var dark := Color(0.14, 0.14, 0.16)

	# Orange core stage, upper stage, Orion capsule and the launch abort tower on top
	var core_pts := PackedVector2Array([
		Vector2(0.0, 0.35), Vector2(0.557, 0.35), Vector2(0.557, 8.6),
		Vector2(0.34, 9.0), Vector2(0.34, 10.2), Vector2(0.27, 10.5),
		Vector2(0.27, 11.0), Vector2(0.14, 11.5), Vector2(0.12, 12.3),
		Vector2(0.05, 12.7), Vector2(0.0, 13.0)])
	var core_cols := PackedColorArray([dark, orange, white, white, white, gray, white, white, white, white])
	_add_lathe(core_pts, core_cols, Vector3.ZERO, 0.1, 0.65)
	_add_bells(_ring(4, 0.22, PI / 4.0), 0.11, 0.35)   # four RS-25 engines
	_add_flame(Vector3.ZERO, 0.32, 3.2, Color(1.0, 0.75, 0.55, 0.4), Color(1.7, 1.5, 1.3, 0.8))

	# Two white solid rocket boosters
	var srb_pts := PackedVector2Array([
		Vector2(0.0, 0.2), Vector2(0.245, 0.2), Vector2(0.245, 6.8),
		Vector2(0.245, 7.0), Vector2(0.2, 7.3), Vector2(0.12, 7.6), Vector2(0.0, 7.8)])
	var srb_cols := PackedColorArray([dark, white, black, white, white, white])
	var srb_offsets: Array[Vector2] = [Vector2(-0.8, 0.0), Vector2(0.8, 0.0)]
	for o in srb_offsets:
		_add_lathe(srb_pts, srb_cols, Vector3(o.x, 0.0, o.y), 0.1, 0.5)
		_add_flame(Vector3(o.x, 0.0, o.y), 0.2, 3.6, Color(1.9, 0.8, 0.15, 0.8), Color(2.4, 2.0, 1.0, 0.95))
	_add_bells(srb_offsets, 0.17, 0.2)


func _build_saturn_v() -> void:
	var white := Color(0.95, 0.95, 0.97)
	var gray := Color(0.8, 0.8, 0.83)
	var black := Color(0.07, 0.07, 0.09)
	var dark := Color(0.14, 0.14, 0.16)

	# Three stages with the famous black and white bands, then the Apollo spacecraft and escape tower
	var stack_pts := PackedVector2Array([
		Vector2(0.0, 0.35), Vector2(0.57, 0.35), Vector2(0.57, 0.85),
		Vector2(0.57, 4.3), Vector2(0.57, 4.6), Vector2(0.57, 5.0),
		Vector2(0.57, 5.4), Vector2(0.57, 8.4), Vector2(0.57, 8.7),
		Vector2(0.4, 9.15), Vector2(0.4, 11.0), Vector2(0.4, 11.3),
		Vector2(0.24, 11.9), Vector2(0.24, 12.4), Vector2(0.11, 12.8),
		Vector2(0.07, 12.85), Vector2(0.045, 13.3), Vector2(0.0, 13.5)])
	var stack_cols := PackedColorArray([
		dark, black, white, black, white, black, white, black, black,
		white, black, white, gray, white, white, white, white])
	_add_lathe(stack_pts, stack_cols, Vector3.ZERO, 0.1, 0.5)

	# Five F-1 engines: one in the middle and four around it
	var engines: Array[Vector2] = [Vector2.ZERO]
	engines.append_array(_ring(4, 0.28, PI / 4.0))
	_add_bells(engines, 0.14, 0.35)

	# Four big fins at the base
	var fin_mesh := PrismMesh.new()
	fin_mesh.size = Vector3(0.6, 1.5, 0.06)
	fin_mesh.left_to_right = 0.0
	for i in 4:
		var a := i * PI / 2.0 + PI / 4.0
		var fin := _add_mesh(rocket, fin_mesh, dark, Vector3(cos(a), 0.0, sin(a)) * 0.84 + Vector3(0, 1.25, 0), 0.2, 0.5)
		fin.rotation.y = -a

	_add_flame(Vector3.ZERO, 0.62, 5.5, Color(1.9, 0.85, 0.2, 0.8), Color(2.4, 2.0, 1.1, 0.95))


func _ring(count: int, radius: float, phase := 0.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in count:
		var a := phase + TAU * i / count
		out.append(Vector2(cos(a), sin(a)) * radius)
	return out


# Engine bells: one shared bell shape placed at each (x, z) offset, hanging just below base_y
func _add_bells(offsets: Array[Vector2], bell_radius: float, base_y: float) -> void:
	var pts := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.9, 0.35), Vector2(0.75, 0.8),
		Vector2(0.6, 1.25), Vector2(0.55, 1.6), Vector2(0.0, 1.6)])
	var mesh := _lathe_mesh(pts, _fill(Color(0.22, 0.22, 0.25), 6), 20)
	for o in offsets:
		var bell := _add_lathe_mesh(mesh, Vector3(o.x, base_y - bell_radius * 1.6, o.y), 0.9, 0.35)
		bell.scale = Vector3.ONE * bell_radius


func _fill(c: Color, n: int) -> PackedColorArray:
	var arr := PackedColorArray()
	for _i in n:
		arr.append(c)
	return arr


func _add_lathe(pts: PackedVector2Array, cols: PackedColorArray, pos: Vector3, metal := 0.3, rough := 0.35) -> MeshInstance3D:
	return _add_lathe_mesh(_lathe_mesh(pts, cols), pos, metal, rough)


func _add_lathe_mesh(mesh: ArrayMesh, pos: Vector3, metal := 0.3, rough := 0.35) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
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


func _add_flame(pos: Vector3, radius: float, height: float, outer := Color(1.8, 0.8, 0.2, 0.75), inner := Color(2.2, 1.9, 1.2, 0.95)) -> void:
	var f := Node3D.new()
	f.position = pos
	f.visible = false
	rocket.add_child(f)
	_add_flame_cone(f, radius, height, outer)
	_add_flame_cone(f, radius * 0.55, height * 0.65, inner)
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
# Seagulls: flapping, gliding and banking in loose flocks. They scatter when the engines light.
# ----------------------------------------------------------------------------

func _build_birds() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	# [orbit center, min radius, max radius, min height, max height, number of birds]
	var flocks := [
		[Vector3(-8, 0, -12), 22.0, 36.0, 10.0, 22.0, 7],
		[Vector3(2, 0, -6), 18.0, 28.0, 3.0, 7.0, 6],
		[Vector3(6, 0, -30), 50.0, 70.0, 30.0, 48.0, 3]]
	for fl in flocks:
		var dir := 1.0 if r.randf() < 0.5 else -1.0
		var flock_phase := r.randf() * TAU
		for _i in int(fl[5]):
			var radius := r.randf_range(fl[1], fl[2])
			var bird := _make_bird()
			var node: Node3D = bird["node"]
			node.scale = Vector3.ONE * r.randf_range(0.9, 1.4)
			world.add_child(node)
			_no_shadows(node)
			bird["center"] = fl[0]
			bird["radius"] = radius
			bird["height"] = r.randf_range(fl[3], fl[4])
			bird["speed"] = dir * r.randf_range(6.0, 9.0) / radius   # orbit speed (rad/s) from a 6-9 m/s flight speed
			bird["phase"] = flock_phase + r.randf_range(-0.4, 0.4)
			bird["hz"] = r.randf_range(2.2, 3.6)
			birds.append(bird)


func _make_bird() -> Dictionary:
	var white := Color(0.92, 0.93, 0.95)
	var tip := Color(0.14, 0.15, 0.17)
	var node := Node3D.new()   # the bird faces -Z, like a Godot camera

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.07
	body_mesh.height = 0.5
	var body := _add_mesh(node, body_mesh, white, Vector3.ZERO, 0.0, 0.9)
	body.rotation_degrees = Vector3(90, 0, 0)

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.055
	head_mesh.height = 0.11
	_add_mesh(node, head_mesh, white, Vector3(0, 0.02, -0.28), 0.0, 0.9)
	var beak := _add_mesh(node, _cyl_mesh(0.02, 0.0, 0.1), Color(0.95, 0.65, 0.1), Vector3(0, 0.015, -0.37), 0.0, 0.6)
	beak.rotation_degrees = Vector3(-90, 0, 0)
	_add_mesh(node, _box_mesh(Vector3(0.14, 0.01, 0.18)), white, Vector3(0, 0, 0.3), 0.0, 0.9)   # tail

	# Each wing has an inner part (white) and an outer part (dark tip) that flap together
	var wings := {}
	for side in [-1, 1]:
		var root := Node3D.new()
		root.position = Vector3(side * 0.05, 0.03, -0.04)
		node.add_child(root)
		_add_mesh(root, _box_mesh(Vector3(0.36, 0.012, 0.2)), white, Vector3(side * 0.18, 0, 0), 0.0, 0.9)
		var elbow := Node3D.new()
		elbow.position = Vector3(side * 0.36, 0, 0)
		root.add_child(elbow)
		_add_mesh(elbow, _box_mesh(Vector3(0.34, 0.01, 0.13)), tip, Vector3(side * 0.17, 0, 0), 0.0, 0.9)
		wings[side] = [root, elbow]
	return {"node": node, "wl": wings[-1][0], "el": wings[-1][1], "wr": wings[1][0], "er": wings[1][1]}


func _no_shadows(n: Node) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_no_shadows(c)


func _update_birds() -> void:
	var flee := clampf((t - IGNITE_TIME) / 2.5, 0.0, 1.0)   # birds scatter when the engines light
	for b in birds:
		var node: Node3D = b["node"]
		var center: Vector3 = b["center"]
		var speed: float = b["speed"]
		var phase: float = b["phase"]
		var radius: float = b["radius"] * (1.0 + flee * 2.0)
		var height: float = b["height"] + sin(t * 0.4 + phase * 2.0) * 1.8 + flee * 22.0
		var ang := phase + t * speed
		var ahead := ang + 0.03 * signf(speed)
		node.position = center + Vector3(cos(ang) * radius, height, sin(ang) * radius)
		node.look_at(center + Vector3(cos(ahead) * radius, height, sin(ahead) * radius))
		node.rotate_object_local(Vector3.FORWARD, 0.3 * signf(speed))   # lean into the turn

		# Flap in bursts, glide in between
		var hz: float = b["hz"]
		var glide := clampf(sin(t * 0.35 + phase * 3.0) * 1.5 + 0.6, 0.0, 1.0)
		var flap := sin(t * TAU * hz + phase * 7.0) * 0.75 * glide + 0.15
		var wr: Node3D = b["wr"]
		var er: Node3D = b["er"]
		var wl: Node3D = b["wl"]
		var el: Node3D = b["el"]
		wr.rotation.z = flap
		er.rotation.z = flap * 0.6
		wl.rotation.z = -flap
		el.rotation.z = -flap * 0.6


# ----------------------------------------------------------------------------
# Menu UI
# ----------------------------------------------------------------------------

func _place(c: Control, al: float, at: float, ar: float, ab: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


func _black_bar(top: bool) -> void:
	var bar := ColorRect.new()
	bar.color = Color.BLACK
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bar)
	if top:
		_place(bar, 0.0, 0.0, 1.0, BAR_SIZE)
	else:
		_place(bar, 0.0, 1.0 - BAR_SIZE, 1.0, 1.0)


# The game's fonts (assets/fonts, set up in assets/ui/orbit_lab_theme.tres), with extra letter spacing.
# role: "logo" (Orbitron, for the title), "heading" (Barlow Condensed) or "body" (Inter).
# If the font files are missing, Godot's built-in font is used instead.
const FONT_FILES = {
	"logo": "res://assets/fonts/Orbitron-Variable.ttf",
	"heading": "res://assets/fonts/BarlowCondensed-SemiBold.ttf",
	"body": "res://assets/fonts/Inter-Variable.ttf",
}
func _menu_font(spacing: int, role := "heading") -> FontVariation:
	var font := FontVariation.new()
	var path: String = FONT_FILES.get(role, "")
	font.base_font = load(path) if path != "" and ResourceLoader.exists(path) else ThemeDB.fallback_font
	if role == "logo":
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	font.spacing_glyph = spacing
	return font


# One line of the menu: spaced-out white text with no box, like the original "Start a Mission" prompt
func _menu_button(text: String, size: int, action: Callable) -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(460, size + 22)
	button.add_theme_font_override("font", _menu_font(3))
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", Color(0.93, 0.95, 0.97, 0.85))
	button.add_theme_color_override("font_hover_color", Color(0.55, 0.85, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.7, 0.8, 0.9))
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.6, 0.65, 0.7))
	button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))   # readable over the bright sky
	button.add_theme_constant_override("outline_size", 4)
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	button.pressed.connect(action)
	return button


func _build_ui() -> void:
	# Cinematic black bars, like a movie
	_black_bar(true)
	_black_bar(false)

	# Title
	var title := Label.new()
	title.text = GAME_TITLE
	title.add_theme_font_override("font", _menu_font(10, "logo"))
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 3)
	layer.add_child(title)
	_place(title, 0.066, 0.2, 0.066, 0.2)
	var tagline := Label.new()
	tagline.text = GAME_TAGLINE.to_upper()
	tagline.add_theme_font_override("font", _menu_font(3))
	tagline.add_theme_font_size_override("font_size", 18)
	tagline.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	tagline.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))   # readable over the bright sky
	tagline.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(tagline)
	_place(tagline, 0.068, 0.2, 0.068, 0.2)
	tagline.offset_top = 84.0

	# The menu: small spaced-out white text on the left, no boxes (like "PRESS ANY BUTTON")
	menu_buttons = VBoxContainer.new()
	menu_buttons.add_theme_constant_override("separation", 2)
	layer.add_child(menu_buttons)
	_place(menu_buttons, 0.066, 0.52, 0.066, 0.52)
	start_button = _menu_button(BUTTON_TEXT, 24, _on_start_pressed)
	menu_buttons.add_child(start_button)
	menu_buttons.add_child(_menu_button("Settings", 18, _open_panel.bind("settings")))
	menu_buttons.add_child(_menu_button("Credits", 18, _open_panel.bind("credits")))
	menu_buttons.add_child(_menu_button("Quit", 18, _on_quit_pressed))
	start_button.grab_focus()   # Enter / Space also works

	# Shows a hint if START_SCENE is wrong (instead of crashing), and any notice from the settings
	message = Label.new()
	message.visible = false
	message.custom_minimum_size = Vector2(620, 0)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	layer.add_child(message)
	_place(message, 0.066, 0.8, 0.066, 0.8)

	_build_settings_panel()
	_build_credits_panel()

	# Black overlay for the fades (added last so it draws on top)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# A dark see-through panel on the right side of the screen, with a heading and a Close button
func _side_panel(heading_text: String) -> Array:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.09, 0.88)
	style.border_color = Color(0.45, 0.8, 1.0, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	panel.visible = false
	layer.add_child(panel)
	_place(panel, 0.5, 0.16, 0.94, 0.84)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = heading_text
	heading.add_theme_font_override("font", _menu_font(5))
	heading.add_theme_font_size_override("font_size", 24)
	column.add_child(heading)
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	var close := Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.custom_minimum_size = Vector2(120, 36)
	close.pressed.connect(_open_panel.bind(""))
	column.add_child(close)
	return [panel, body]


func _settings_row(parent: Control, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(190, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


func _build_settings_panel() -> void:
	var made := _side_panel("SETTINGS")
	settings_panel = made[0]
	var body: VBoxContainer = made[1]
	if settings == null:
		var missing := Label.new()
		missing.text = "Settings need the GameState autoload (Project > Project Settings > Globals)."
		missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(missing)
		return

	var quality := OptionButton.new()
	for quality_name in settings.QUALITY_NAMES:
		quality.add_item(quality_name)
	quality.selected = settings.quality
	quality.item_selected.connect(func(index): settings.set_quality(index))
	_settings_row(body, "Graphics quality", quality)
	var quality_help := Label.new()
	quality_help.text = "Is the game slow or jumpy? Pick Low. It draws a smaller picture, with no shadows or reflections and fewer rocks, which most laptops can handle. (The launch behind this menu changes the next time the menu opens.)"
	quality_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quality_help.add_theme_font_size_override("font_size", 13)
	quality_help.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	body.add_child(quality_help)
	settings.changed.connect(func(): quality.selected = settings.quality)

	var fullscreen := CheckButton.new()
	fullscreen.button_pressed = settings.fullscreen
	fullscreen.toggled.connect(func(on): settings.set_fullscreen(on))
	_settings_row(body, "Fullscreen", fullscreen)

	body.add_child(HSeparator.new())
	for channel in settings.SOUND_CHANNELS:
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = settings.volumes[channel]
		slider.custom_minimum_size = Vector2(0, 24)
		slider.value_changed.connect(func(value): settings.set_volume(channel, value))
		_settings_row(body, {"Master": "Volume: everything", "Music": "Volume: music", "Effects": "Volume: sound effects", "Voice": "Volume: mission radio"}[channel], slider)

	var keys := Label.new()
	keys.text = "Keys: M turns the music on and off.   F11 switches fullscreen in the solar system."
	keys.add_theme_font_size_override("font_size", 13)
	keys.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(keys)


func _build_credits_panel() -> void:
	var made := _side_panel("CREDITS")
	credits_panel = made[0]
	var body: VBoxContainer = made[1]
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	var lines := "[b][color=#8fd4ff]%s[/color][/b]\n" % GAME_TITLE
	if TEAM_NAME != "":
		lines += "by %s\n" % TEAM_NAME
	if not TEAM_MEMBERS.is_empty():
		lines += ", ".join(TEAM_MEMBERS) + "\n"
	for section in CREDITS:
		lines += "\n[b][color=#ffcc59]%s[/color][/b]\n" % section[0]
		for line in section[1]:
			lines += line + "\n"
	text.text = lines
	scroll.add_child(text)


# Opens the settings or the credits ("" closes both and brings the menu back)
func _open_panel(which: String) -> void:
	if starting:
		return
	settings_panel.visible = which == "settings"
	credits_panel.visible = which == "credits"


func _on_quit_pressed() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_open_panel("")


func _on_start_pressed() -> void:
	if starting:
		return
	if START_SCENE != "" and not ResourceLoader.exists(START_SCENE):
		message.text = "START_SCENE is not set to a real scene yet.\nOpen main_menu.gd and change START_SCENE at the top (right-click your scene > Copy Path)."
		message.visible = true
		return
	starting = true
	settings_panel.visible = false
	credits_panel.visible = false
	for button in menu_buttons.get_children():
		button.disabled = true
	if START_SCENE != "" and GameState.has_method("go_to_scene"):
		# The loading screen fades in over the menu and stays until the next scene is ready to show
		GameState.go_to_scene(START_SCENE)
		return
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.7)
	tween.tween_callback(_finish_start)


func _finish_start() -> void:
	if START_SCENE != "":
		get_tree().change_scene_to_file(START_SCENE)
	else:
		# Menu was placed inside the game scene: unfreeze the game and remove the menu
		if paused_by_menu:
			get_tree().paused = false
			paused_by_menu = false
		mission_started.emit()
		queue_free()
