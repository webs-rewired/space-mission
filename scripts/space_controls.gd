extends Node

# Add this as a child node of the solar system scene (the "Controls" node).
# It adds:
#   - time controls: pause, slower, faster, reverse, with the speed and the date
#   - switches for orbit paths, gravity fields, planet names, the asteroid belt and TRUE SCALE
#   - a "Go to" menu that flies the camera to any planet
#   - a help box listing the keys
# Keys: Space = pause, + = faster, - = slower, H = hide or show all the on-screen panels

const SPEED_STEPS = [0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0]
const NORMAL_SPEED_STEP = 3

const PLANETS_AROUND_SUN = ["Venus", "Earth", "Mars", "Jupiter", "Saturn"]
const ALL_BODIES = ["Sun", "Venus", "Earth", "Moon", "Mars", "Jupiter", "Saturn"]

# ---------------------------------------------------------------------------
# Real numbers for TRUE SCALE (NASA planetary fact sheets)
# ---------------------------------------------------------------------------
const KILOMETERS_PER_AU = 149597870.7   # 1 AU = the average distance from Earth to the Sun
const UNITS_PER_AU = 100.0              # at true scale, 1 AU = 100 units in the game

# Average distance from the Sun, in AU
const TRUE_DISTANCE_AU = {"Venus": 0.723, "Earth": 1.0, "Mars": 1.524, "Jupiter": 5.203, "Saturn": 9.537}
# Average radius, in km
const TRUE_RADIUS_KM = {"Sun": 696340.0, "Venus": 6051.8, "Earth": 6371.0, "Moon": 1737.4,
	"Mars": 3389.5, "Jupiter": 69911.0, "Saturn": 58232.0}
const MOON_DISTANCE_KM = 384400.0
# How long one orbit takes, in Earth years
const ORBIT_TIME_YEARS = {"Venus": 0.615, "Earth": 1.0, "Mars": 1.881, "Jupiter": 11.86, "Saturn": 29.46, "Moon": 0.0748}

# Mass compared with Earth (Earth = 1), used to size the gravity fields
const MASS_COMPARED_WITH_EARTH = {
	"Sun": 333000.0,
	"Venus": 0.815,
	"Earth": 1.0,
	"Moon": 0.0123,
	"Mars": 0.107,
	"Jupiter": 317.8,
	"Saturn": 95.2,
}

const LABEL_COLORS = {
	"Sun": Color(1.0, 0.85, 0.4),
	"Venus": Color(1.0, 0.9, 0.6),
	"Earth": Color(0.5, 0.75, 1.0),
	"Moon": Color(0.85, 0.85, 0.85),
	"Mars": Color(1.0, 0.55, 0.4),
	"Jupiter": Color(0.95, 0.8, 0.6),
	"Saturn": Color(0.95, 0.88, 0.65),
}

const GRAVITY_FIELD_SHADER = """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;
uniform vec4 field_color : source_color;
void fragment() {
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = field_color.rgb * (0.06 + 0.45 * pow(edge, 2.0));
}
"""

var speed_step = NORMAL_SPEED_STEP
var paused = false
var reversed = false
var days_passed = 0.0
var seconds_per_earth_year = 12.57   # updated from Earth's orbit speed when the scene starts
var earth_orbit_speed = 0.5

var scene_root: Node = null
var controls_layer: CanvasLayer
var controls_shown = true
var speed_label: Label
var date_label: Label
var pause_button: Button
var reverse_button: Button
var scale_note: Label
var go_to_menu: OptionButton
var gravity_switch: CheckButton
var switches = {}             # switch name -> CheckButton, so Reset can set them back
var message_label: Label      # short messages above the time bar, like "Slower: 5x to 2x"
var message_time_left = 0.0
var starting_orbit_angles = {}

var orbit_lines = []          # each is {"line": node, "viewable_radius": number, "true_radius": number}
var gravity_fields = []
var name_labels = []
var asteroid_belt: MultiMeshInstance3D = null
var asteroid_belt_speed = 0.0
var asteroid_belt_shown = true
var sun_position = Vector3.ZERO

# The viewable layout, saved so true scale can be switched back off
var true_scale_on = false
var saved_layout = {}

func _ready():
	scene_root = owner
	if scene_root == null:
		scene_root = get_parent()
	GameState.time_speed = 1.0
	build_controls()
	update_time_speed()
	# Wait two frames so the planets and their markers are in place before drawing overlays
	await get_tree().process_frame
	await get_tree().process_frame
	measure_earth_year()
	build_overlays()
	save_viewable_layout()

func _process(delta):
	days_passed += delta * GameState.time_speed * 365.25 / seconds_per_earth_year
	# Fade out the message above the time bar
	if message_time_left > 0:
		message_time_left -= delta
		message_label.modulate.a = clamp(message_time_left, 0.0, 1.0)
	if asteroid_belt:
		asteroid_belt.rotate_y(asteroid_belt_speed * delta * GameState.time_speed)
	var total_days = abs(days_passed)
	var years = int(total_days / 365.25)
	var days = int(fmod(total_days, 365.25))
	var direction = "since start" if days_passed >= 0 else "before start"
	date_label.text = "%d years, %d days %s" % [years, days, direction]

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var clicked_name = planet_name_at(event.position)
		if clicked_name != "":
			go_to_planet(clicked_name)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F11:
				toggle_fullscreen()
			KEY_SPACE:
				toggle_pause()
			KEY_EQUAL, KEY_KP_ADD:
				go_faster()
			KEY_MINUS, KEY_KP_SUBTRACT:
				go_slower()
			KEY_H:
				toggle_controls()

# H hides every on-screen panel (time bar, switches, help and planet stats), great for screenshots
func toggle_controls():
	controls_shown = not controls_shown
	controls_layer.visible = controls_shown
	var stats_layer = scene_root.get_node_or_null("CanvasLayer")
	if stats_layer:
		stats_layer.visible = controls_shown

# ---------------------------------------------------------------------------
# Time
# ---------------------------------------------------------------------------
func toggle_pause():
	paused = not paused
	update_time_speed()

func go_faster():
	var old_speed = SPEED_STEPS[speed_step]
	if speed_step == SPEED_STEPS.size() - 1:
		show_message("Already at the fastest speed (%sx)" % speed_text(old_speed))
	speed_step = min(speed_step + 1, SPEED_STEPS.size() - 1)
	paused = false
	update_time_speed()
	var new_speed = SPEED_STEPS[speed_step]
	if new_speed != old_speed:
		show_message("Faster: %sx to %sx  (%s times faster)" % [speed_text(old_speed), speed_text(new_speed), speed_text(new_speed / old_speed)])

func go_slower():
	var old_speed = SPEED_STEPS[speed_step]
	if speed_step == 0:
		show_message("Already at the slowest speed (%sx)" % speed_text(old_speed))
	speed_step = max(speed_step - 1, 0)
	paused = false
	update_time_speed()
	var new_speed = SPEED_STEPS[speed_step]
	if new_speed != old_speed:
		show_message("Slower: %sx to %sx  (%s times slower)" % [speed_text(old_speed), speed_text(new_speed), speed_text(old_speed / new_speed)])

# 2.0 -> "2", 0.25 -> "0.25", 2.5 -> "2.5"
func speed_text(value):
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return str(snapped(value, 0.01))

func show_message(text):
	message_label.text = text
	message_label.modulate.a = 1.0
	message_time_left = 2.5

# Puts everything back the way it was when the scene started
func reset_everything():
	speed_step = NORMAL_SPEED_STEP
	paused = false
	reversed = false
	update_time_speed()
	days_passed = 0.0
	# Planets back to their starting places
	for orbit_name in starting_orbit_angles:
		var orbit = scene_root.find_child(orbit_name, true, false)
		if orbit:
			orbit.rotation.y = starting_orbit_angles[orbit_name]
	if asteroid_belt:
		asteroid_belt.rotation.y = 0.0
	# Switches back to their defaults (this also turns True scale off)
	switches["True scale"].button_pressed = false
	switches["Orbit paths"].button_pressed = true
	switches["Gravity fields"].button_pressed = false
	switches["Planet names"].button_pressed = true
	switches["Asteroid belt"].button_pressed = true
	# Camera back to the starting view, stats panel closed, panels shown
	var camera_pivot = scene_root.find_child("CameraPivot", true, false)
	if camera_pivot and camera_pivot.has_method("reset_view"):
		camera_pivot.reset_view()
	var info_panel = scene_root.find_child("InfoPanel", true, false)
	if info_panel:
		info_panel.visible = false
	if not controls_shown:
		toggle_controls()
	show_message("Everything is back to the start")

func toggle_reverse():
	reversed = not reversed
	paused = false
	update_time_speed()

func update_time_speed():
	var speed = SPEED_STEPS[speed_step]
	if reversed:
		speed = -speed
	if paused:
		GameState.time_speed = 0.0
		speed_label.text = "Paused"
		pause_button.text = "Play"
	else:
		GameState.time_speed = speed
		# Also show what the speed means: how many days pass every real second
		var days_per_second = abs(speed) * 365.25 / seconds_per_earth_year
		speed_label.text = "Speed: %sx%s  (%s days per second)" % [speed_text(abs(speed)), " backwards" if reversed else "", speed_text(snapped(days_per_second, 0.1))]
		pause_button.text = "Pause"
	reverse_button.text = "Forward" if reversed else "Reverse"

func measure_earth_year():
	var earth_orbit = scene_root.find_child("EarthOrbit", true, false)
	if earth_orbit and "orbit_speed" in earth_orbit and earth_orbit.orbit_speed != 0:
		earth_orbit_speed = abs(earth_orbit.orbit_speed)
		seconds_per_earth_year = TAU / earth_orbit_speed

# ---------------------------------------------------------------------------
# On-screen controls
# ---------------------------------------------------------------------------
func make_button(text, action):
	var button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE   # so Space doesn't press the last clicked button
	button.pressed.connect(action)
	return button

func build_controls():
	var layer = CanvasLayer.new()
	add_child(layer)
	controls_layer = layer

	# Time bar in the bottom right
	var time_panel = PanelContainer.new()
	layer.add_child(time_panel)
	var time_row = HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	time_panel.add_child(time_row)
	reverse_button = make_button("Reverse", toggle_reverse)
	time_row.add_child(reverse_button)
	time_row.add_child(make_button("Slower", go_slower))
	pause_button = make_button("Pause", toggle_pause)
	pause_button.custom_minimum_size.x = 70
	time_row.add_child(pause_button)
	time_row.add_child(make_button("Faster", go_faster))
	time_row.add_child(make_button("Reset", reset_everything))
	speed_label = Label.new()
	speed_label.custom_minimum_size.x = 300
	time_row.add_child(speed_label)
	date_label = Label.new()
	date_label.custom_minimum_size.x = 220
	time_row.add_child(date_label)
	time_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)

	# Messages appear just above the time bar and fade away
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 18)
	message_label.add_theme_color_override("font_outline_color", Color.BLACK)
	message_label.add_theme_constant_override("outline_size", 6)
	message_label.modulate.a = 0.0
	layer.add_child(message_label)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE, 0)
	message_label.custom_minimum_size = Vector2(700, 30)
	message_label.offset_left = -350
	message_label.offset_right = 350
	message_label.offset_top = -100
	message_label.offset_bottom = -70

	# Display switches in the bottom left
	var switch_panel = PanelContainer.new()
	layer.add_child(switch_panel)
	var switch_column = VBoxContainer.new()
	switch_panel.add_child(switch_column)

	go_to_menu = OptionButton.new()
	go_to_menu.focus_mode = Control.FOCUS_NONE
	go_to_menu.add_item("Go to a planet...")
	for body_name in ALL_BODIES:
		go_to_menu.add_item(body_name)
	go_to_menu.item_selected.connect(_on_go_to_selected)
	switch_column.add_child(go_to_menu)

	switch_column.add_child(make_switch("True scale", false, set_true_scale))
	switch_column.add_child(make_switch("Orbit paths", true, func(on): set_orbit_lines_visible(on)))
	gravity_switch = make_switch("Gravity fields", false, func(on): set_all_visible(gravity_fields, on))
	switch_column.add_child(gravity_switch)
	switch_column.add_child(make_switch("Planet names", true, func(on): set_all_visible(name_labels, on)))
	switch_column.add_child(make_switch("Asteroid belt", true, func(on): set_asteroid_belt_visible(on)))
	scale_note = Label.new()
	scale_note.text = "Sizes and distances are squeezed so\neverything fits. Turn on True scale to\nsee the real solar system."
	scale_note.add_theme_font_size_override("font_size", 11)
	scale_note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	switch_column.add_child(scale_note)
	switch_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)

	# Key help in the top left (the planet stats use the right side)
	var help_panel = PanelContainer.new()
	layer.add_child(help_panel)
	var help = Label.new()
	help.text = "WASD / arrows: move    Q / E: down / up    Shift: faster\nRight-drag: look around    Scroll: zoom    R: reset view\nClick a planet: stats    Click a name: fly there    F: follow    Space: pause    + / -: speed\nH: hide controls    F11: fullscreen"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	help_panel.add_child(help)
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 12)

func make_switch(text, start_on, action):
	var switch = CheckButton.new()
	switch.text = text
	switch.button_pressed = start_on
	switch.focus_mode = Control.FOCUS_NONE
	switch.toggled.connect(action)
	switches[text] = switch
	return switch

func set_all_visible(nodes, on):
	for node in nodes:
		if is_instance_valid(node):
			node.visible = on

func set_orbit_lines_visible(on):
	for info in orbit_lines:
		info["line"].visible = on

func set_asteroid_belt_visible(on):
	asteroid_belt_shown = on
	if asteroid_belt:
		asteroid_belt.visible = on

# F11 switches between a window and fullscreen (when the game runs in its own window)
func toggle_fullscreen():
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# Finds which planet name (if any) is under the mouse. Names sit just above each planet on screen.
func planet_name_at(mouse_position):
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return ""
	var closest_name = ""
	var closest_distance = INF
	for label in name_labels:
		if not is_instance_valid(label) or not label.is_visible_in_tree():
			continue
		var world_position = label.global_position
		if camera.is_position_behind(world_position):
			continue
		var screen_position = camera.unproject_position(world_position)
		# The name is drawn about 26 pixels above the planet (below it for the Moon)
		var name_center = screen_position - Vector2(0, label.offset.y * 0.9)
		var half_width = label.text.length() * 7.0 + 10.0
		var offset_from_name = mouse_position - name_center
		if abs(offset_from_name.x) <= half_width and abs(offset_from_name.y) <= 16.0:
			var distance = offset_from_name.length()
			if distance < closest_distance:
				closest_distance = distance
				closest_name = label.text
	return closest_name

# Flies the camera to a planet and shows its stats
func _on_go_to_selected(index):
	if index == 0:
		return
	go_to_planet(ALL_BODIES[index - 1])
	go_to_menu.select(0)

func go_to_planet(body_name):
	if scene_root.has_method("show_planet_info"):
		scene_root.show_planet_info(body_name)
	var camera_pivot = scene_root.find_child("CameraPivot", true, false)
	if camera_pivot and camera_pivot.has_method("follow_planet"):
		camera_pivot.follow_planet(body_name)
	go_to_menu.select(0)

# ---------------------------------------------------------------------------
# Orbit paths, gravity fields, names and the asteroid belt in 3D
# ---------------------------------------------------------------------------
func build_overlays():
	var sun = scene_root.find_child("Sun", true, false)
	if sun == null:
		return
	sun_position = sun.global_position

	# Orbit paths around the Sun (drawn in place, they don't move)
	for planet_name in PLANETS_AROUND_SUN:
		var planet = scene_root.find_child(planet_name, true, false)
		if planet == null:
			continue
		var offset = planet.global_position - sun_position
		var distance = Vector2(offset.x, offset.z).length()
		var path = make_circle(distance, LABEL_COLORS[planet_name])
		scene_root.add_child(path)
		path.global_position = sun_position
		orbit_lines.append({"line": path, "viewable_radius": distance, "true_radius": TRUE_DISTANCE_AU[planet_name] * UNITS_PER_AU})

	build_viewable_asteroid_belt()

	# The Moon's orbit path rides along with Earth
	var earth_marker = scene_root.find_child("EarthMarker", true, false)
	var moon = scene_root.find_child("Moon", true, false)
	if earth_marker and moon:
		var moon_distance = (moon.global_position - earth_marker.global_position).length()
		var moon_path = make_circle(moon_distance, LABEL_COLORS["Moon"])
		earth_marker.add_child(moon_path)
		orbit_lines.append({"line": moon_path, "viewable_radius": moon_distance, "true_radius": MOON_DISTANCE_KM / KILOMETERS_PER_AU * UNITS_PER_AU})

	# Names and gravity fields hang off each planet's marker
	for planet_name in MASS_COMPARED_WITH_EARTH:
		var planet = scene_root.find_child(planet_name, true, false)
		var marker = scene_root.find_child(planet_name + "Marker", true, false)
		if planet == null or marker == null:
			continue
		var planet_radius = 1.0
		if planet is MeshInstance3D and planet.mesh is SphereMesh:
			planet_radius = planet.mesh.radius * planet.scale.x
		marker.add_child(make_name_label(planet_name))
		marker.add_child(make_gravity_field(planet_name, planet_radius))

# The main asteroid belt is between Mars (1.52 AU) and Jupiter (5.2 AU), from about 2.2 to 3.2 AU.
# In the viewable layout it sits at the same proportion of the gap between your Mars and Jupiter.
func build_viewable_asteroid_belt():
	var mars = scene_root.find_child("Mars", true, false)
	var jupiter = scene_root.find_child("Jupiter", true, false)
	if mars == null or jupiter == null:
		return
	var mars_distance = Vector2(mars.global_position.x - sun_position.x, mars.global_position.z - sun_position.z).length()
	var jupiter_distance = Vector2(jupiter.global_position.x - sun_position.x, jupiter.global_position.z - sun_position.z).length()
	var gap = jupiter_distance - mars_distance
	var inner_edge = mars_distance + gap * (2.2 - 1.52) / (5.2 - 1.52)
	var outer_edge = mars_distance + gap * (3.2 - 1.52) / (5.2 - 1.52)
	make_asteroid_belt(inner_edge, outer_edge, gap * 0.02, 1.0)

func make_asteroid_belt(inner_edge, outer_edge, thickness, rock_size):
	if asteroid_belt:
		asteroid_belt.queue_free()

	var rock = SphereMesh.new()   # a low-detail lumpy ball for each asteroid
	rock.radius = 0.05 * rock_size
	rock.height = 0.08 * rock_size
	rock.radial_segments = 6
	rock.rings = 3
	var rock_material = StandardMaterial3D.new()
	rock_material.albedo_color = Color(0.55, 0.5, 0.45)
	rock_material.roughness = 1.0
	rock.material = rock_material

	var asteroid_count = 2000
	var asteroids = MultiMesh.new()
	asteroids.transform_format = MultiMesh.TRANSFORM_3D
	asteroids.mesh = rock
	asteroids.instance_count = asteroid_count
	var random = RandomNumberGenerator.new()
	random.seed = 2026
	for index in asteroid_count:
		var angle = random.randf() * TAU
		var distance = random.randf_range(inner_edge, outer_edge)
		var height = random.randfn(0.0, thickness)   # the belt is a thick ring, not a flat disk
		var size = random.randf_range(0.4, 1.8)
		var rock_basis = Basis(Vector3(random.randf(), random.randf(), random.randf()).normalized(), random.randf() * TAU)
		rock_basis = rock_basis.scaled(Vector3(size, size * random.randf_range(0.6, 1.0), size))
		asteroids.set_instance_transform(index, Transform3D(rock_basis, Vector3(cos(angle) * distance, height, sin(angle) * distance)))

	asteroid_belt = MultiMeshInstance3D.new()
	asteroid_belt.name = "AsteroidBelt"
	asteroid_belt.multimesh = asteroids
	asteroid_belt.visible = asteroid_belt_shown
	scene_root.add_child(asteroid_belt)
	asteroid_belt.global_position = sun_position
	# Asteroids around 2.7 AU take about 4.4 Earth years to go around the Sun (Kepler's third law)
	asteroid_belt_speed = earth_orbit_speed / pow(2.7, 1.5)

func make_circle(radius, color):
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINE_STRIP)
	var segments = 360
	for segment in segments + 1:
		var angle = TAU * segment / segments
		surface.add_vertex(Vector3(cos(angle), 0, sin(angle)) * radius)
	var line = MeshInstance3D.new()
	line.mesh = surface.commit()
	var line_material = StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.albedo_color = Color(color.r, color.g, color.b, 0.35)
	line.material_override = line_material
	return line

func make_name_label(planet_name):
	var label = Label3D.new()
	label.text = planet_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true          # stays the same size on screen at any zoom
	label.pixel_size = 0.0012
	label.font_size = 28
	label.outline_size = 8
	label.modulate = LABEL_COLORS[planet_name]
	label.offset = Vector2(0, 26)    # just above the planet on screen, at any size
	if planet_name == "Moon":
		label.offset = Vector2(0, -26)   # below, so it doesn't cover Earth's name
		label.font_size = 22
	name_labels.append(label)
	return label

# Bigger, brighter bubbles for heavier bodies. Size uses a logarithm so the Sun doesn't fill the screen.
func make_gravity_field(planet_name, planet_radius):
	var mass = MASS_COMPARED_WITH_EARTH[planet_name]
	var field_radius = planet_radius * 1.3 + 0.8 * (log(1.0 + mass * 10.0) / log(10.0))
	var field = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = field_radius
	mesh.height = field_radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	field.mesh = mesh
	var shader = Shader.new()
	shader.code = GRAVITY_FIELD_SHADER
	var field_material = ShaderMaterial.new()
	field_material.shader = shader
	field_material.set_shader_parameter("field_color", Color(0.4, 0.7, 1.0))
	field.material_override = field_material
	field.visible = false
	gravity_fields.append(field)
	return field

# ---------------------------------------------------------------------------
# TRUE SCALE: real sizes, real distances and real orbit times
# ---------------------------------------------------------------------------
func save_viewable_layout():
	for orbit_name in ["VenusOrbit", "EarthOrbit", "MarsOrbit", "JupiterOrbit", "SaturnOrbit", "MoonOrbit"]:
		var orbit = scene_root.find_child(orbit_name, true, false)
		if orbit:
			starting_orbit_angles[orbit_name] = orbit.rotation.y
	for body_name in ALL_BODIES:
		var body = scene_root.find_child(body_name, true, false)
		if body:
			saved_layout[body_name] = {"position": body.position, "scale": body.scale}
		var orbit = scene_root.find_child(body_name + "Orbit", true, false)
		if orbit and "orbit_speed" in orbit:
			saved_layout[body_name + "Orbit"] = orbit.orbit_speed
	var sun = scene_root.find_child("Sun", true, false)
	if sun:
		for child in sun.get_children():
			if child is OmniLight3D:
				saved_layout["light"] = {"range": child.omni_range, "attenuation": child.omni_attenuation}
	var camera_pivot = scene_root.find_child("CameraPivot", true, false)
	if camera_pivot and "min_distance" in camera_pivot:
		saved_layout["camera"] = {"min": camera_pivot.min_distance, "max": camera_pivot.max_distance}

func sphere_radius_of(body):
	if body is MeshInstance3D and body.mesh is SphereMesh:
		return body.mesh.radius
	return 1.0

func set_true_scale(on):
	true_scale_on = on
	for body_name in ALL_BODIES:
		var body = scene_root.find_child(body_name, true, false)
		if body == null or not saved_layout.has(body_name):
			continue
		var marker = scene_root.find_child(body_name + "Marker", true, false)
		var saved = saved_layout[body_name]
		if on:
			# Real size: radius in km, turned into game units
			var true_radius = TRUE_RADIUS_KM[body_name] / KILOMETERS_PER_AU * UNITS_PER_AU
			body.scale = Vector3.ONE * (true_radius / sphere_radius_of(body))
			# Real distance from the Sun (or from Earth, for the Moon)
			if body_name != "Sun":
				var true_distance = 0.0
				if body_name == "Moon":
					true_distance = MOON_DISTANCE_KM / KILOMETERS_PER_AU * UNITS_PER_AU
				else:
					true_distance = TRUE_DISTANCE_AU[body_name] * UNITS_PER_AU
				var direction = saved["position"].normalized()
				if direction == Vector3.ZERO:
					direction = Vector3.RIGHT
				body.position = direction * true_distance
		else:
			body.scale = saved["scale"]
			body.position = saved["position"]
		if marker:
			marker.position = body.position
		# Saturn's rings grow and shrink with Saturn
		if body_name == "Saturn":
			var rings = scene_root.find_child("SaturnRings", true, false)
			if rings:
				rings.scale = body.scale

	# Real orbit times: each orbit takes its real number of Earth years
	for body_name in ORBIT_TIME_YEARS:
		var orbit = scene_root.find_child(body_name + "Orbit", true, false)
		if orbit == null or not saved_layout.has(body_name + "Orbit"):
			continue
		orbit.orbit_speed = earth_orbit_speed / ORBIT_TIME_YEARS[body_name] if on else saved_layout[body_name + "Orbit"]

	# Orbit paths
	for info in orbit_lines:
		var radius = info["true_radius"] if on else info["viewable_radius"]
		info["line"].scale = Vector3.ONE * (radius / info["viewable_radius"])

	# Asteroid belt: real distance (2.2 to 3.2 AU). The rocks are drawn much bigger than real so you can see them.
	if on:
		make_asteroid_belt(2.2 * UNITS_PER_AU, 3.2 * UNITS_PER_AU, 4.0, 12.0)
	else:
		build_viewable_asteroid_belt()

	# Gravity fields don't make sense at true scale
	if on:
		set_all_visible(gravity_fields, false)
	gravity_switch.disabled = on

	# Sunlight has to reach much farther
	var sun = scene_root.find_child("Sun", true, false)
	if sun and saved_layout.has("light"):
		for child in sun.get_children():
			if child is OmniLight3D:
				child.omni_range = 2000.0 if on else saved_layout["light"]["range"]
				child.omni_attenuation = 0.4 if on else saved_layout["light"]["attenuation"]

	# The camera has to zoom much closer (to see tiny planets) and much farther (to see the whole system)
	var camera_pivot = scene_root.find_child("CameraPivot", true, false)
	if camera_pivot and saved_layout.has("camera"):
		var camera = camera_pivot.get_node_or_null("Camera3D")
		if on:
			camera_pivot.min_distance = 0.002
			camera_pivot.max_distance = 3000.0
			if camera:
				camera.position.z = 260.0
		else:
			camera_pivot.min_distance = saved_layout["camera"]["min"]
			camera_pivot.max_distance = saved_layout["camera"]["max"]
		if camera_pivot.has_method("reset_view") and not on:
			camera_pivot.reset_view()
		elif on:
			camera_pivot.position = sun_position

	if on:
		scale_note.text = "TRUE SCALE: real sizes and distances.\nThe planets are tiny dots! Use \"Go to\"\nto fly to one and zoom in. (Asteroids\nare drawn bigger than real.)"
	else:
		scale_note.text = "Sizes and distances are squeezed so\neverything fits. Turn on True scale to\nsee the real solar system."
