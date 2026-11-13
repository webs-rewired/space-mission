extends Node
# The "Controls" node in the solar system scene. It adds:
#   - time controls: pause, slower, faster, reverse, "Now" and Reset, with the real date and time
#   - switches for true scale, orbit paths, names, spin axes, gravity fields, the belts, dwarf planets and comets
#   - a "Go to" menu that flies the camera to any body
#   - planet names you can click to fly there, and clicking a planet to see its stats
#   - a help box listing the keys
# Keys: P = pause, + = faster, - = slower, T = true scale, H = hide or show all the on-screen panels
#
# Time speed is in DAYS PER SECOND (GameState.time_speed). The Bodies node moves everything to match.
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const OrbitMath = preload("res://scripts/orbit_math.gd")
# [days that pass every real second, what to call it]
const SPEEDS = [
	[1.0 / 86400.0, "real time"],
	[1.0 / 1440.0, "1 minute per second"],
	[1.0 / 24.0, "1 hour per second"],
	[0.25, "6 hours per second"],
	[1.0, "1 day per second"],
	[7.0, "1 week per second"],
	[30.4375, "1 month per second"],
	[91.3125, "3 months per second"],
	[365.25, "1 year per second"],
	[3652.5, "10 years per second"],
]
const NORMAL_SPEED_STEP = 0   # the scene starts in real time
# Which names win when two would overlap on screen (lower = more important)
const NAME_PRIORITY = {"star": 0, "planet": 1, "moon": 2, "dwarf": 3, "comet": 4, "spacecraft": 5}
var bodies_node: Node = null
var scene_root: Node = null
var speed_step = NORMAL_SPEED_STEP
var paused = false
var reversed = false
var controls_layer: CanvasLayer
var names_layer: CanvasLayer
var controls_shown = true
var names_shown = true
var speed_label: Label
var date_label: Label
var pause_button: Button
var reverse_button: Button
var scale_note: Label
var switches = {}             # switch name -> CheckButton, so Reset can set them back
var message_label: Label      # short messages above the time bar, like "Slower: ..."
var message_time_left = 0.0
var name_tags = {}            # body name -> Button

# --- Go To selection screen ---
var goto_panel: Control
var goto_open := false
var goto_selected: String = ""
var goto_preview_name: Label
var goto_preview_kind: Label
var goto_preview_desc: Label
var goto_list: VBoxContainer
var goto_category_buttons: Dictionary = {}
var current_goto_category := "planet"
var loading_panel: Control
var loading_status: Label
var loading_body_name: Label
var is_loading := false
var preview_cache: Dictionary = {}
const LOADING_MESSAGES = [
	"Getting the rocket ready for your mission...",
	"Calibrating navigation systems...",
	"Aligning trajectory with target body...",
	"Confirming orbital insertion parameters...",
	"Final systems check complete. Preparing departure.",
]
var goto_globe_pivot: Node3D
var goto_globe_mat: StandardMaterial3D
var loading_globe_pivot: Node3D
var loading_globe_mat: StandardMaterial3D
var globe_spin_speed := 0.35

func _ready():
	process_priority = 200   # after the planets and the camera have moved, so names line up exactly
	add_to_group("space_controls")   # so the camera can show messages here (camera_pivot.gd)
	scene_root = owner if owner else get_parent()
	GameState.time_speed = SPEEDS[NORMAL_SPEED_STEP][0]
	build_controls()
	update_time_speed()
	bodies_node = get_tree().get_first_node_in_group("solar_system_world")
	if bodies_node == null:
		push_warning("No Bodies node found. Put solar_system_bodies.gd on the node that used to be called Textures.")
		return
	if not bodies_node.is_built:
		await bodies_node.built
	bodies_node.date_limit_reached.connect(_on_date_limit_reached)
	bodies_node.edge_reached.connect(_on_edge_reached)
	build_name_tags()

func _process(delta):
	# Fade out the message above the time bar
	if message_time_left > 0:
		message_time_left -= delta
		message_label.modulate.a = clamp(message_time_left, 0.0, 1.0)
	# Slow spin on the 3D globe previews
	if goto_open and goto_globe_pivot:
		goto_globe_pivot.rotation.y += delta * globe_spin_speed
	if is_loading and loading_globe_pivot:
		loading_globe_pivot.rotation.y += delta * globe_spin_speed * 1.2
	if bodies_node == null or not bodies_node.is_built:
		return
	var date = OrbitMath.date_text(bodies_node.julian_date)
	# Show the time of day when time moves slowly enough to read it
	if paused or SPEEDS[speed_step][0] <= 1.0:
		date += "   " + OrbitMath.time_text(bodies_node.julian_date, speed_step <= 1)
	date_label.text = date
	update_name_tags()

func _unhandled_input(event):
	if is_loading:
		return

	if goto_open:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_ESCAPE:
					close_goto()
					get_viewport().set_input_as_handled()
					return
				KEY_F:
					if goto_selected != "":
						_start_loading_then_go(goto_selected, true)
						get_viewport().set_input_as_handled()
						return
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var clicked_body = body_at(event.position)
		if clicked_body != "" and scene_root.has_method("show_planet_info"):
			scene_root.show_planet_info(clicked_body)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F11:
				toggle_fullscreen()
			KEY_P:
				toggle_pause()
			KEY_EQUAL, KEY_KP_ADD:
				go_faster()
			KEY_MINUS, KEY_KP_SUBTRACT:
				go_slower()
			KEY_H:
				toggle_controls()
			KEY_T:
				if switches.has("True scale"):
					switches["True scale"].button_pressed = not switches["True scale"].button_pressed

# H hides every on-screen panel (time bar, switches, help, names and planet stats), great for screenshots
func toggle_controls():
	controls_shown = not controls_shown
	controls_layer.visible = controls_shown
	names_layer.visible = controls_shown
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
	if speed_step == SPEEDS.size() - 1:
		show_message("Already at the fastest speed (%s)" % SPEEDS[speed_step][1])
		return
	change_speed(speed_step + 1)

func go_slower():
	if speed_step == 0:
		show_message("Already at the slowest speed (%s)" % SPEEDS[speed_step][1])
		return
	change_speed(speed_step - 1)

func change_speed(new_step):
	var old_step = speed_step
	speed_step = new_step
	paused = false
	update_time_speed()
	var old_speed = SPEEDS[old_step][0]
	var new_speed = SPEEDS[new_step][0]
	if new_speed > old_speed:
		show_message("Faster: %s to %s  (%s times faster)" % [SPEEDS[old_step][1], SPEEDS[new_step][1], number_text(new_speed / old_speed)])
	else:
		show_message("Slower: %s to %s  (%s times slower)" % [SPEEDS[old_step][1], SPEEDS[new_step][1], number_text(old_speed / new_speed)])

func number_text(value):
	if abs(value - round(value)) < 0.05:
		return str(int(round(value)))
	return str(snapped(value, 0.1))

func show_message(text):
	message_label.text = text
	message_label.modulate.a = 1.0
	message_time_left = 3.0

func toggle_reverse():
	reversed = not reversed
	paused = false
	update_time_speed()

func update_time_speed():
	var speed = SPEEDS[speed_step][0]
	if reversed:
		speed = -speed
	if paused:
		GameState.time_speed = 0.0
		speed_label.text = "Paused"
		pause_button.text = "Play"
	else:
		GameState.time_speed = speed
		speed_label.text = "Speed: %s%s" % [SPEEDS[speed_step][1], "  backwards" if reversed else ""]
		pause_button.text = "Pause"
	reverse_button.text = "Forward" if reversed else "Reverse"

func go_to_today():
	if bodies_node:
		bodies_node.reset_to_today()
		show_message("Back to today: " + OrbitMath.date_text(bodies_node.julian_date))

func _on_edge_reached():
	show_message("The edge of the solar system: about 2 light-years out, where the Sun's gravity gives way to other stars. You can't go farther.")

func _on_date_limit_reached():
	paused = true
	update_time_speed()
	show_message("Time stopped: NASA's planet data here covers the years 1800 to 2200")

func reset_everything():
	speed_step = NORMAL_SPEED_STEP
	paused = false
	reversed = false
	update_time_speed()
	if bodies_node:
		bodies_node.reset_to_today()
	switches["True scale"].button_pressed = false
	switches["Orbit paths"].button_pressed = true
	switches["Planet names"].button_pressed = true
	switches["Spin axes"].button_pressed = false
	switches["Gravity fields"].button_pressed = false
	switches["Asteroid belt"].button_pressed = true
	switches["Kuiper belt"].button_pressed = true
	switches["Oort cloud"].button_pressed = true
	switches["Dwarf planets"].button_pressed = true
	switches["Comets"].button_pressed = true
	var camera_pivot = scene_root.find_child("CameraPivot", true, false)
	if camera_pivot and camera_pivot.has_method("reset_view"):
		camera_pivot.reset_view()
	var info_panel = scene_root.find_child("InfoPanel", true, false)
	if info_panel:
		info_panel.visible = false
	if not controls_shown:
		toggle_controls()
	show_message("Everything is back to the start: today's date, in real time")

# ---------------------------------------------------------------------------
# On-screen controls (same layout as the original)
# ---------------------------------------------------------------------------
func make_button(text, action):
	var button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button

func build_controls():
	controls_layer = CanvasLayer.new()
	controls_layer.layer = 2
	add_child(controls_layer)
	names_layer = CanvasLayer.new()
	names_layer.layer = 0
	add_child(names_layer)

	# Time bar in the bottom right
	var time_panel = PanelContainer.new()
	controls_layer.add_child(time_panel)
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
	time_row.add_child(make_button("Now", go_to_today))
	time_row.add_child(make_button("Reset", reset_everything))
	speed_label = Label.new()
	speed_label.custom_minimum_size.x = 280
	time_row.add_child(speed_label)
	date_label = Label.new()
	date_label.custom_minimum_size.x = 210
	time_row.add_child(date_label)
	time_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	time_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	time_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Messages appear just above the time bar and fade away
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 18)
	message_label.add_theme_color_override("font_outline_color", Color.BLACK)
	message_label.add_theme_constant_override("outline_size", 6)
	message_label.modulate.a = 0.0
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls_layer.add_child(message_label)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE, 0)
	message_label.offset_left = -420
	message_label.offset_right = 420
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	message_label.offset_top = -150
	message_label.offset_bottom = -70

	# Display switches in the bottom left
	var switch_panel = PanelContainer.new()
	controls_layer.add_child(switch_panel)
	var switch_column = VBoxContainer.new()
	switch_column.add_theme_constant_override("separation", 0)
	switch_panel.add_child(switch_column)

	# Go to button (opens the selection screen) — same place the old OptionButton was
	var goto_btn = make_button("Go to...", open_goto)
	goto_btn.custom_minimum_size.x = 140
	switch_column.add_child(goto_btn)

	switch_column.add_child(make_switch("True scale", false, set_true_scale))
	switch_column.add_child(make_switch("Orbit paths", true, func(on): call_bodies("set_orbit_lines_visible", [on])))
	switch_column.add_child(make_switch("Planet names", true, func(on): names_shown = on))
	switch_column.add_child(make_switch("Spin axes", false, func(on): call_bodies("set_spin_axes_visible", [on])))
	switch_column.add_child(make_switch("Gravity fields", false, func(on): call_bodies("set_gravity_fields_visible", [on])))
	switch_column.add_child(make_switch("Asteroid belt", true, func(on): call_bodies("set_belt_visible", ["asteroids", on])))
	switch_column.add_child(make_switch("Kuiper belt", true, func(on): call_bodies("set_belt_visible", ["kuiper", on])))
	switch_column.add_child(make_switch("Oort cloud", true, func(on): call_bodies("set_oort_cloud_visible", [on])))
	switch_column.add_child(make_switch("Dwarf planets", true, func(on): call_bodies("set_kind_visible", ["dwarf", on])))
	switch_column.add_child(make_switch("Comets", true, func(on): call_bodies("set_kind_visible", ["comet", on])))
	switch_column.add_child(make_switch("Spacecraft", true, func(on): call_bodies("set_kind_visible", ["spacecraft", on])))
	scale_note = Label.new()
	scale_note.add_theme_font_size_override("font_size", 11)
	scale_note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	switch_column.add_child(scale_note)
	update_scale_note(false)
	switch_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	switch_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Key help in the top left
	var help_panel = PanelContainer.new()
	controls_layer.add_child(help_panel)
	var help = Label.new()
	help.text = "WASD / arrows: move    Space: up    Ctrl: down    Shift: faster\nRight-drag: look around    Scroll: zoom    R: reset view\nClick a planet: stats    Click a name: fly there    F: follow    P: pause    + / -: speed\nT: true scale    H: hide controls    F11: fullscreen"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	help_panel.add_child(help)
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 12)

	# Build Go To panel last (if this fails, the rest of the UI still exists)
	build_goto_panel()

func make_switch(text, start_on, action):
	var switch = CheckButton.new()
	switch.text = text
	switch.button_pressed = start_on
	switch.focus_mode = Control.FOCUS_NONE
	switch.toggled.connect(action)
	switches[text] = switch
	return switch

func call_bodies(method_name, arguments):
	if bodies_node and bodies_node.is_built:
		bodies_node.callv(method_name, arguments)

func set_true_scale(on):
	call_bodies("set_true_scale", [on])
	switches["Gravity fields"].disabled = on
	update_scale_note(on)

func update_scale_note(on):
	if on:
		scale_note.text = "TRUE SCALE: real sizes and distances.\nThe planets are tiny dots! Click a name\nto fly to one and zoom in. (Belt rocks\nare drawn much bigger than real.)"
	else:
		scale_note.text = "Sizes and distances are squeezed so\neverything fits (directions are real).\nTurn on True scale (T) for the real thing."

func toggle_fullscreen():
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# ---------------------------------------------------------------------------
# Go To selection screen + 3D globe + loading screen
# ---------------------------------------------------------------------------
func build_goto_panel():
	goto_panel = Control.new()
	goto_panel.visible = false
	goto_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	goto_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	controls_layer.add_child(goto_panel)

	var dim = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	goto_panel.add_child(dim)

	var main = PanelContainer.new()
	main.set_anchors_preset(Control.PRESET_CENTER)
	main.custom_minimum_size = Vector2(920, 560)
	main.offset_left = -460
	main.offset_top = -280
	main.offset_right = 460
	main.offset_bottom = 280
	goto_panel.add_child(main)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	main.add_child(margin)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(root_vbox)

	var title_row = HBoxContainer.new()
	root_vbox.add_child(title_row)
	var title = Label.new()
	title.text = "SELECT DESTINATION"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(make_button("Close  (Esc)", close_goto))

	var cat_row = HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 6)
	root_vbox.add_child(cat_row)
	var categories = [
		["planet", "Planets"],
		["moon", "Moons"],
		["dwarf", "Dwarf planets"],
		["comet", "Comets"],
		["spacecraft", "Spacecraft"],
	]
	for cat in categories:
		var btn = Button.new()
		btn.text = cat[1]
		btn.focus_mode = Control.FOCUS_NONE
		btn.toggle_mode = true
		btn.button_pressed = (cat[0] == "planet")
		btn.pressed.connect(_on_goto_category.bind(cat[0]))
		cat_row.add_child(btn)
		goto_category_buttons[cat[0]] = btn

	var content = HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(content)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	goto_list = VBoxContainer.new()
	goto_list.add_theme_constant_override("separation", 2)
	goto_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(goto_list)

	var preview_box = VBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 10)
	preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(preview_box)

	var goto_globe = _make_globe_viewport(360, 280)
	goto_globe_pivot = goto_globe["pivot"]
	goto_globe_mat = goto_globe["material"]
	preview_box.add_child(goto_globe["container"])

	goto_preview_name = Label.new()
	goto_preview_name.add_theme_font_size_override("font_size", 28)
	goto_preview_name.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
	goto_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_box.add_child(goto_preview_name)

	goto_preview_kind = Label.new()
	goto_preview_kind.add_theme_font_size_override("font_size", 14)
	goto_preview_kind.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	goto_preview_kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_box.add_child(goto_preview_kind)

	goto_preview_desc = Label.new()
	goto_preview_desc.add_theme_font_size_override("font_size", 13)
	goto_preview_desc.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	goto_preview_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goto_preview_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_box.add_child(goto_preview_desc)

	var action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_box.add_child(action_row)

	var travel_btn = make_button("Travel  (click name)", func():
		if goto_selected != "":
			_start_loading_then_go(goto_selected, false)
	)
	travel_btn.custom_minimum_size = Vector2(180, 36)
	action_row.add_child(travel_btn)

	var follow_btn = make_button("Follow  (F)", func():
		if goto_selected != "":
			_start_loading_then_go(goto_selected, true)
	)
	follow_btn.custom_minimum_size = Vector2(140, 36)
	action_row.add_child(follow_btn)

	_populate_goto_list("planet")
	_show_goto_preview("")
	_build_loading_screen()

func _make_globe_viewport(width: int, height: int) -> Dictionary:
	var container = SubViewportContainer.new()
	container.custom_minimum_size = Vector2(width, height)
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vp = SubViewport.new()
	vp.size = Vector2i(width, height)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(vp)

	var world = Node3D.new()
	vp.add_child(world)

	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 40, 0)
	key.light_energy = 1.35
	key.shadow_enabled = false
	world.add_child(key)

	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20, -120, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.7, 0.8, 1.0)
	world.add_child(fill)

	var cam = Camera3D.new()
	cam.position = Vector3(0, 0, 4.0)
	cam.fov = 35.0
	world.add_child(cam)
	cam.make_current()

	var pivot = Node3D.new()
	world.add_child(pivot)

	var sphere = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 64
	mesh.rings = 32
	sphere.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.metallic = 0.05
	mat.roughness = 0.55
	sphere.material_override = mat
	pivot.add_child(sphere)

	return {"container": container, "pivot": pivot, "material": mat}

func _build_loading_screen():
	loading_panel = Control.new()
	loading_panel.visible = false
	loading_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	controls_layer.add_child(loading_panel)

	var bg = ColorRect.new()
	bg.color = Color(0.01, 0.02, 0.04, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_panel.add_child(bg)

	var center = VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -180
	center.offset_top = -220
	center.offset_right = 180
	center.offset_bottom = 140
	center.add_theme_constant_override("separation", 16)
	loading_panel.add_child(center)

	var loading_globe = _make_globe_viewport(340, 340)
	loading_globe_pivot = loading_globe["pivot"]
	loading_globe_mat = loading_globe["material"]
	center.add_child(loading_globe["container"])

	loading_body_name = Label.new()
	loading_body_name.add_theme_font_size_override("font_size", 32)
	loading_body_name.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
	loading_body_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(loading_body_name)

	loading_status = Label.new()
	loading_status.add_theme_font_size_override("font_size", 16)
	loading_status.add_theme_color_override("font_color", Color(0.55, 0.85, 0.65))
	loading_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	loading_status.add_theme_constant_override("outline_size", 4)
	loading_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 28)
	loading_status.offset_bottom = -28
	loading_panel.add_child(loading_status)

func open_goto():
	goto_open = true
	goto_panel.visible = true
	_populate_goto_list(current_goto_category)

func close_goto():
	goto_open = false
	goto_panel.visible = false
	goto_selected = ""

func _on_goto_category(kind: String):
	current_goto_category = kind
	for k in goto_category_buttons:
		goto_category_buttons[k].button_pressed = (k == kind)
	_populate_goto_list(kind)
	_show_goto_preview("")

func _populate_goto_list(kind: String):
	for child in goto_list.get_children():
		child.queue_free()

	if kind == "planet":
		_add_goto_entry("Sun")

	for body_name in SolarSystemData.BODY_ORDER:
		if not SolarSystemData.BODIES.has(body_name):
			continue
		var data = SolarSystemData.BODIES[body_name]
		if data["kind"] == kind:
			_add_goto_entry(body_name)

func _add_goto_entry(body_name: String):
	if not SolarSystemData.BODIES.has(body_name):
		return
	var data = SolarSystemData.BODIES[body_name]
	var btn = Button.new()
	btn.text = "  " + str(data.get("label", body_name))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size.y = 32
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.18, 0.6)
	normal.set_content_margin_all(6)
	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.22, 0.28, 0.38, 0.9)
	hover.set_content_margin_all(6)
	var pressed = StyleBoxFlat.new()
	pressed.bg_color = Color(0.3, 0.4, 0.55, 1.0)
	pressed.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)

	btn.mouse_entered.connect(_show_goto_preview.bind(body_name))
	btn.pressed.connect(func():
		goto_selected = body_name
		_start_loading_then_go(body_name, false)
	)
	goto_list.add_child(btn)

func _show_goto_preview(body_name: String):
	goto_selected = body_name
	if body_name == "" or not SolarSystemData.BODIES.has(body_name):
		_apply_globe_material(goto_globe_mat, "")
		goto_preview_name.text = "Hover over a destination"
		goto_preview_kind.text = ""
		goto_preview_desc.text = "Select a body from the list.\nClick name = Travel    |    Press F = Follow"
		return

	var data = SolarSystemData.BODIES[body_name]
	goto_preview_name.text = str(data.get("label", body_name))
	var kind_label = str(data.get("kind", "")).capitalize()
	if data.get("kind") == "star":
		kind_label = "Star"
	elif data.get("kind") == "dwarf":
		kind_label = "Dwarf planet"
	goto_preview_kind.text = kind_label
	_apply_globe_material(goto_globe_mat, body_name)

	var desc = ""
	match data.get("kind"):
		"star":
			desc = "The center of the solar system."
		"planet":
			desc = "A major planet orbiting the Sun."
		"moon":
			desc = "A natural satellite."
		"dwarf":
			desc = "A dwarf planet in the outer solar system."
		"comet":
			desc = "An icy body with a highly elliptical orbit."
		"spacecraft":
			desc = "A human-made probe or craft."
	goto_preview_desc.text = desc + "\n\nClick name = Travel    |    Press F = Follow"

func _apply_globe_material(mat: StandardMaterial3D, body_name: String) -> void:
	if mat == null:
		return
	if body_name == "" or not SolarSystemData.BODIES.has(body_name):
		mat.albedo_texture = null
		mat.albedo_color = Color(0.15, 0.17, 0.2)
		mat.emission_enabled = false
		return

	var tex = _get_body_preview(body_name)
	var data = SolarSystemData.BODIES[body_name]
	var is_star = data.get("kind") == "star"

	if tex:
		mat.albedo_texture = tex
		mat.albedo_color = Color.WHITE
	else:
		mat.albedo_texture = null
		mat.albedo_color = data.get("label_color", Color(0.6, 0.65, 0.7))

	if is_star:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.85, 0.45)
		mat.emission_energy_multiplier = 0.85
		if tex:
			mat.emission_texture = tex
	else:
		mat.emission_enabled = false
		mat.emission_texture = null

	mat.roughness = 0.4 if is_star else 0.55
	mat.metallic = 0.0

func _get_body_preview(body_name: String) -> Texture2D:
	if preview_cache.has(body_name):
		return preview_cache[body_name]

	var texture_map = {
		"Sun": "2k_sun.jpg",
		"Mercury": "2k_mercury.jpg",
		"Venus": "2k_venus_surface.jpg",
		"Earth": "2k_earth_daymap.jpg",
		"Moon": "2k_moon.jpg",
		"Mars": "2k_mars.jpg",
		"Jupiter": "2k_jupiter.jpg",
		"Saturn": "2k_saturn.jpg",
		"Uranus": "2k_uranus.jpg",
		"Neptune": "2k_neptune.jpg",
		"Ceres": "2k_ceres_fictional.jpg",
		"Pluto": "2k_pluto.jpg",
		"Eris": "2k_eris_fictional.jpg",
		"Haumea": "2k_haumea_fictional.jpg",
		"Makemake": "2k_makemake_fictional.jpg",
		"Io": "2k_io.jpg",
		"Europa": "2k_europa.jpg",
		"Ganymede": "2k_ganymede.jpg",
		"Callisto": "2k_callisto.jpg",
		"Titan": "2k_titan.jpg",
		"Triton": "2k_triton.jpg",
		"Charon": "2k_charon.jpg",
	}

	var candidates: Array[String] = []
	if texture_map.has(body_name):
		candidates.append("res://textures/" + texture_map[body_name])

	var lower = body_name.to_lower()
	candidates.append_array([
		"res://textures/2k_%s.jpg" % lower,
		"res://textures/2k_%s.png" % lower,
		"res://textures/2k_%s_daymap.jpg" % lower,
		"res://textures/2k_%s_fictional.jpg" % lower,
		"res://textures/2k_%s_surface.jpg" % lower,
		"res://textures/%s.jpg" % lower,
		"res://textures/%s.png" % lower,
	])

	for path in candidates:
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Texture2D:
				preview_cache[body_name] = res
				return res

	preview_cache[body_name] = null
	return null

func _start_loading_then_go(body_name: String, do_follow: bool):
	if is_loading:
		return
	if not SolarSystemData.BODIES.has(body_name):
		return
	is_loading = true
	close_goto()

	var data = SolarSystemData.BODIES[body_name]
	_apply_globe_material(loading_globe_mat, body_name)
	if loading_globe_pivot:
		loading_globe_pivot.rotation.y = 0.0
	loading_body_name.text = str(data.get("label", body_name))
	loading_status.text = LOADING_MESSAGES[0]
	loading_panel.visible = true

	var tween = create_tween()
	for i in LOADING_MESSAGES.size():
		var msg = LOADING_MESSAGES[i]
		tween.tween_callback(func(): loading_status.text = msg)
		tween.tween_interval(0.55)
	tween.tween_callback(func():
		_finish_loading_and_go(body_name, do_follow)
	)

func _finish_loading_and_go(body_name: String, do_follow: bool):
	loading_panel.visible = false
	is_loading = false
	go_to_planet(body_name, do_follow)

func go_to_planet(body_name, do_follow := true):
	if bodies_node and bodies_node.has_method("is_body_shown") and not bodies_node.is_body_shown(body_name):
		return
	if scene_root.has_method("show_planet_info"):
		scene_root.show_planet_info(body_name)
	var camera_pivot = scene_root.find_child("CameraPivot", true, false)
	if camera_pivot == null:
		return
	if do_follow and camera_pivot.has_method("follow_planet"):
		camera_pivot.follow_planet(body_name)
	elif camera_pivot.has_method("fly_to_planet"):
		camera_pivot.fly_to_planet(body_name)
	elif camera_pivot.has_method("follow_planet"):
		camera_pivot.follow_planet(body_name)

# ---------------------------------------------------------------------------
# Names on screen, and clicking planets
# ---------------------------------------------------------------------------
func build_name_tags():
	for body_name in SolarSystemData.BODY_ORDER:
		if not SolarSystemData.BODIES.has(body_name):
			continue
		var data = SolarSystemData.BODIES[body_name]
		var tag = Button.new()
		tag.text = data["label"]
		tag.flat = true
		tag.focus_mode = Control.FOCUS_NONE
		tag.add_theme_font_size_override("font_size", 15 if data["kind"] in ["star", "planet"] else 13)
		for color_name in ["font_color", "font_hover_color", "font_pressed_color"]:
			tag.add_theme_color_override(color_name, data["label_color"] if color_name == "font_color" else Color.WHITE)
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		tag.add_theme_constant_override("outline_size", 5)
		var no_box = StyleBoxEmpty.new()
		for style_name in ["normal", "hover", "pressed", "focus"]:
			tag.add_theme_stylebox_override(style_name, no_box)
		tag.pressed.connect(go_to_planet.bind(body_name))
		tag.visible = false
		names_layer.add_child(tag)
		name_tags[body_name] = tag

func screen_radius(camera, center, radius):
	var edge = center + camera.global_transform.basis.x * radius
	return camera.unproject_position(edge).distance_to(camera.unproject_position(center))

func update_name_tags():
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen_size = get_viewport().get_visible_rect().size
	var camera_pivot = scene_root.find_child("CameraPivot", true, false)
	var followed = camera_pivot.followed_planet if camera_pivot and "followed_planet" in camera_pivot else ""
	var selected = scene_root.selected_planet if "selected_planet" in scene_root else ""
	var on_screen = {}
	for body_name in SolarSystemData.BODY_ORDER:
		if not name_tags.has(body_name):
			continue
		name_tags[body_name].visible = false
		var marker = bodies_node.body_marker(body_name)
		if not names_shown or not marker.is_visible_in_tree():
			continue
		var center = marker.global_position
		if camera.is_position_behind(center):
			continue
		on_screen[body_name] = {"center": camera.unproject_position(center),
			"radius": screen_radius(camera, center, bodies_node.body_radius(body_name)),
			"distance": camera.global_position.distance_to(center)}
	var order = on_screen.keys()
	order.sort_custom(func(first, second): return name_rank(first, followed, selected) < name_rank(second, followed, selected))
	var taken_spaces = []
	for body_name in order:
		var body = on_screen[body_name]
		if body["radius"] > screen_size.y * 0.6:
			continue
		var tag = name_tags[body_name]
		var tag_size = tag.get_combined_minimum_size()
		var tag_position = body["center"] - Vector2(tag_size.x / 2.0, body["radius"] + tag_size.y + 2.0)
		var space = Rect2(tag_position, tag_size).grow(-3.0)
		if not Rect2(Vector2.ZERO, screen_size).intersects(space):
			continue
		if hidden_behind_a_planet(body_name, body, space, on_screen):
			continue
		var overlaps = false
		for taken in taken_spaces:
			if taken.intersects(space):
				overlaps = true
				break
		if overlaps:
			continue
		taken_spaces.append(space)
		tag.size = tag_size
		tag.position = tag_position
		tag.visible = true

func hidden_behind_a_planet(body_name, body, space, on_screen):
	for other_name in on_screen:
		var other = on_screen[other_name]
		if other_name == body_name or other["distance"] >= body["distance"] or other["radius"] < 3.0:
			continue
		if body["center"].distance_to(other["center"]) < other["radius"]:
			return true
		if other["radius"] > 12.0:
			var closest = Vector2(clamp(other["center"].x, space.position.x, space.end.x), clamp(other["center"].y, space.position.y, space.end.y))
			if closest.distance_to(other["center"]) < other["radius"]:
				return true
	return false

func name_rank(body_name, followed, selected):
	if body_name == followed:
		return -2
	if body_name == selected:
		return -1
	return NAME_PRIORITY[SolarSystemData.BODIES[body_name]["kind"]] * 100 + SolarSystemData.BODY_ORDER.find(body_name)

func body_at(mouse_position):
	if bodies_node == null or not bodies_node.is_built:
		return ""
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return ""
	var closest_name = ""
	var closest_distance = INF
	for body_name in SolarSystemData.BODY_ORDER:
		var marker = bodies_node.body_marker(body_name)
		if not marker.is_visible_in_tree():
			continue
		var center = marker.global_position
		if camera.is_position_behind(center):
			continue
		var reach = max(screen_radius(camera, center, bodies_node.body_radius(body_name)), 10.0)
		if camera.unproject_position(center).distance_to(mouse_position) <= reach:
			var distance = camera.global_position.distance_to(center)
			if distance < closest_distance:
				closest_distance = distance
				closest_name = body_name
	return closest_name
