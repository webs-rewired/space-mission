extends Node3D

# Probe Builder: design your spacecraft like a NASA mission team would.
#
# Left: pick each part. Every part is based on real hardware ("like ...") with a plain description.
# Middle: your probe, built at real size in a clean room as you choose parts (drag to turn it, scroll to zoom).
# Right: the Flight Readiness Review, the same checks real missions pass before launch (power when you get there,
#   data home, braking into orbit, temperature, radiation, landing), plus a briefing about your destination.
#
# The numbers come from real missions: sunlight fades with the square of the distance, RTGs fade a little every
# year, data rates fall with distance (New Horizons sent about 1 to 2 kilobits per second from Pluto), and the
# braking burn uses the rocket equation (see game_state.gd).

const DIRECTIVES_CARD_SCENE = preload("res://scenes/directives_card.tscn")
const SOLAR_SYSTEM_SCENE = "res://scenes/solar_system.tscn"
const ROCKET_SCENE = "res://scenes/rocket_builder.tscn"

const ProbeModel = preload("res://scripts/probe_model.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const SolarSystemScript = preload("res://scripts/solar_system.gd")
const Spacecraft = preload("res://scripts/spacecraft.gd")
const SpacecraftLookalike = preload("res://scripts/spacecraft_lookalike.gd")

# NASA's own 3D models of real spacecraft (in res://assets/models/). The clean room shows the real spacecraft
# closest to your design; press "Show my parts" to see your exact parts instead.
# "size" is the real spacecraft's biggest measurement in meters, so each one is shown at its real size.
# The real spacecraft (their models, sizes and why your design is like them) are in spacecraft_lookalike.gd
const LOOKALIKES = SpacecraftLookalike.LOOKALIKES

const CLEAN_ROOM_SCENE = preload("res://scenes/places/clean_room.tscn")
const GO = Color(0.35, 0.85, 0.45)
const WATCH = Color(1.0, 0.8, 0.3)
const NO_GO = Color(1.0, 0.4, 0.35)
const NOTE = Color(0.7, 0.75, 0.82)
const PANEL_WIDTH = 340
const TABLE_TOP = -2.7    # height of the turntable's top

var part_ids_by_slot = {}
var part_notes = {}          # slot -> Label under its dropdown
var readiness_label: RichTextLabel
var briefing_label: RichTextLabel
var summary_label: Label
var next_button: Button
var model_holder: Node3D
var probe_model: Node3D
var camera_pivot: Node3D
var camera: Camera3D
var camera_distance = 12.0
var wanted_distance = 12.0
var dragging = false
var turning_by_itself = true
var show_my_parts = false
var lookalike_label: Label
var view_button: Button

func _ready():
	GameState.fill_missing_choices()
	# The old panel from the scene is replaced by the new screen
	var old_layer = get_node_or_null("CanvasLayer")
	if old_layer:
		old_layer.visible = false
	build_clean_room()
	build_screen()
	rebuild()

# ---------------------------------------------------------------------------
# The clean room and the 3D probe
# ---------------------------------------------------------------------------
func build_clean_room():
	# The room itself (walls of air filters, crane, work stands, the team in their suits, lights) is a scene you can
	# open and edit: res://scenes/places/clean_room.tscn
	add_child(CLEAN_ROOM_SCENE.instantiate())
	# A low turntable on the floor, like the ones spacecraft are tested on
	ProbeModel.cylinder(self, 4.0, 4.2, 0.3, Vector3(0, -2.85, 0), ProbeModel.material(Color(0.32, 0.34, 0.38), 0.6, 0.4), Vector3.ZERO, 64)
	model_holder = Node3D.new()
	add_child(model_holder)
	camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(0, 1.0, 0)
	camera_pivot.rotation_degrees = Vector3(-18, 35, 0)
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 400.0
	camera_pivot.add_child(camera)
	camera.current = true

func rebuild_model():
	if probe_model:
		probe_model.queue_free()
		probe_model = null
	var key = closest_real_spacecraft()
	var lookalike = LOOKALIKES.get(key, {})
	if lookalike.is_empty():
		lookalike_label.text = "No NASA spacecraft has been built like this one yet!"
	else:
		lookalike_label.text = "Closest real spacecraft: %s %s,\nbecause %s" % [lookalike["name"], lookalike.get("mission", ""), lookalike["why"]]
	if not show_my_parts and not lookalike.is_empty():
		var real_model = load_real_model(lookalike)
		if real_model:
			probe_model = real_model["root"]
			model_holder.add_child(probe_model)
			probe_model.position.y = TABLE_TOP
			aim_camera(real_model["height"], lookalike["size"])
			view_button.text = "Show my parts"
			return
	var built = ProbeModel.build(GameState.choices, GameState.instruments)
	probe_model = built["root"]
	model_holder.add_child(probe_model)
	probe_model.position.y = TABLE_TOP - built["bottom"]   # its lowest point rests on the turntable
	aim_camera(built["top"] - built["bottom"], built["size"])
	view_button.text = "Show the real look-alike"

# Points the camera at the middle of the probe, far enough back to see all of it
func aim_camera(height, size):
	camera_pivot.position.y = TABLE_TOP + height * 0.5
	wanted_distance = size * 1.5 + 4.0

# Which real spacecraft your design is most like
func closest_real_spacecraft():
	return SpacecraftLookalike.closest()

# Loads a NASA model, centers it and scales it to the real spacecraft's size. Returns null if the file is missing.
func load_real_model(lookalike):
	var path = Spacecraft.find_model(lookalike["file"])
	if path == "":
		return null
	var scene = load(path)
	if not scene is PackedScene:
		return null
	var model = scene.instantiate()
	var holder = Node3D.new()
	holder.add_child(model)
	var box = Spacecraft.model_bounds(model, Transform3D.IDENTITY, null)
	if box == null:
		return null
	var shrink = lookalike["size"] / max(box.size.x, max(box.size.y, box.size.z), 0.001)
	var center = Spacecraft.body_center(model) * shrink   # the body sits on the turntable's middle, not the box
	model.scale = model.scale * shrink
	model.position = Vector3(-center.x, -box.position.y * shrink, -center.z)   # bottom of the model at the holder
	return {"root": holder, "height": box.size.y * shrink}

func _on_view_pressed():
	show_my_parts = not show_my_parts
	rebuild_model()

func _process(delta):
	if turning_by_itself and model_holder:
		model_holder.rotation.y += delta * 0.18
	camera_distance = lerp(camera_distance, wanted_distance, min(1.0, delta * 4.0))
	camera.position = Vector3(0, 0, camera_distance)
	# Shift the view so the probe sits between the two side panels
	camera.h_offset = 0.0

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			if event.pressed:
				turning_by_itself = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			wanted_distance = max(3.0, wanted_distance * 0.88)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			wanted_distance = min(70.0, wanted_distance * 1.14)   # stays inside the clean room walls
	elif event is InputEventMouseMotion and dragging:
		model_holder.rotation.y += event.relative.x * 0.008
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - event.relative.y * 0.005, deg_to_rad(-70), deg_to_rad(20))

# ---------------------------------------------------------------------------
# The screen
# ---------------------------------------------------------------------------
func make_label(text, font_size = 14, color = Color.WHITE):
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func make_panel(left_side):
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.13, 0.93)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = PANEL_WIDTH
	if left_side:
		panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	else:
		panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -64
	return panel

func build_screen():
	var layer = CanvasLayer.new()
	add_child(layer)

	# Left: the parts
	var left_panel = make_panel(true)
	layer.add_child(left_panel)
	var left_column = VBoxContainer.new()
	left_panel.add_child(left_column)
	left_column.add_child(make_label("SPACECRAFT DESIGN", 19))
	left_column.add_child(make_label("Destination: " + SolarSystemData.BODIES.get(GameState.destination, {}).get("label", GameState.destination), 15, Color(0.6, 0.85, 1.0)))
	var goal = SolarSystemScript.MISSION_GOALS.get(GameState.destination, "")
	if goal != "":
		left_column.add_child(make_label("Goal: " + goal, 12, NOTE))
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_column.add_child(scroll)
	var parts_column = VBoxContainer.new()
	parts_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts_column.add_theme_constant_override("separation", 3)
	scroll.add_child(parts_column)
	for slot in GameState.SLOT_ORDER:
		parts_column.add_child(make_label(GameState.SLOT_NAMES[slot].to_upper(), 12, Color(0.6, 0.85, 1.0)))
		var dropdown = OptionButton.new()
		dropdown.focus_mode = Control.FOCUS_NONE
		dropdown.clip_text = true
		dropdown.fit_to_longest_item = false   # otherwise the longest choice would stretch the panel
		dropdown.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		dropdown.add_theme_font_size_override("font_size", 13)
		dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		part_ids_by_slot[slot] = []
		for part_id in GameState.PARTS:
			if GameState.PARTS[part_id]["slot"] == slot:
				dropdown.add_item(part_label(part_id))
				part_ids_by_slot[slot].append(part_id)
		dropdown.select(max(0, part_ids_by_slot[slot].find(GameState.choices[slot])))
		dropdown.item_selected.connect(_on_part_selected.bind(slot))
		parts_column.add_child(dropdown)
		var note = make_label("", 11, NOTE)
		parts_column.add_child(note)
		part_notes[slot] = note
		parts_column.add_child(HSeparator.new())
	parts_column.add_child(make_label("SCIENCE INSTRUMENTS (pick any)", 12, Color(0.6, 0.85, 1.0)))
	for part_id in GameState.PARTS:
		if GameState.PARTS[part_id]["slot"] != "instrument":
			continue
		var checkbox = CheckBox.new()
		checkbox.focus_mode = Control.FOCUS_NONE
		checkbox.text = part_label(part_id)
		checkbox.clip_text = true
		checkbox.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		checkbox.add_theme_font_size_override("font_size", 13)
		checkbox.button_pressed = part_id in GameState.instruments
		checkbox.toggled.connect(_on_instrument_toggled.bind(part_id))
		parts_column.add_child(checkbox)
		var part = GameState.PARTS[part_id]
		parts_column.add_child(make_label("%s. %s" % [part["like"], part["about"]], 11, NOTE))

	# Right: the review and the briefing
	var right_panel = make_panel(false)
	layer.add_child(right_panel)
	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(tabs)
	readiness_label = RichTextLabel.new()
	readiness_label.name = "Readiness"
	readiness_label.bbcode_enabled = true
	readiness_label.scroll_active = true
	readiness_label.add_theme_font_size_override("normal_font_size", 12)
	readiness_label.add_theme_font_size_override("bold_font_size", 13)
	tabs.add_child(readiness_label)
	briefing_label = RichTextLabel.new()
	briefing_label.name = "Briefing"
	briefing_label.bbcode_enabled = true
	briefing_label.scroll_active = true
	briefing_label.add_theme_font_size_override("normal_font_size", 12)
	briefing_label.add_theme_font_size_override("bold_font_size", 13)
	tabs.add_child(briefing_label)

	# Above the 3D view: which real spacecraft your design is like, and a button to switch views
	var view_box = VBoxContainer.new()
	view_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	view_box.offset_top = 10
	view_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	view_box.custom_minimum_size.x = 400
	view_box.offset_left = -200
	view_box.offset_right = 200
	layer.add_child(view_box)
	lookalike_label = make_label("", 12, Color(0.1, 0.13, 0.18))
	lookalike_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view_box.add_child(lookalike_label)
	view_button = Button.new()
	view_button.focus_mode = Control.FOCUS_NONE
	view_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	view_button.pressed.connect(_on_view_pressed)
	view_box.add_child(view_button)

	# Bottom: summary and buttons
	var bottom_background = ColorRect.new()   # a dark strip, so the bar is readable over the bright clean room
	bottom_background.color = Color(0.02, 0.03, 0.06, 0.82)
	bottom_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_background.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_background.offset_top = -66
	layer.add_child(bottom_background)
	var bottom_bar = HBoxContainer.new()
	bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_top = -56
	bottom_bar.offset_bottom = -10
	bottom_bar.offset_left = 12
	bottom_bar.offset_right = -12
	bottom_bar.add_theme_constant_override("separation", 14)
	layer.add_child(bottom_bar)
	var back_button = Button.new()
	back_button.text = "Back to the solar system"
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.pressed.connect(_on_back_pressed)
	bottom_bar.add_child(back_button)
	summary_label = make_label("", 14)
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	summary_label.clip_text = true   # on a narrow screen the summary gets cut short ("...") instead of pushing the buttons off
	summary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bottom_bar.add_child(summary_label)
	var hint = make_label("Drag to turn the probe, scroll to zoom", 12, Color(0.25, 0.28, 0.33))
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom_bar.add_child(hint)
	next_button = Button.new()
	next_button.text = "Next: build your rocket"
	next_button.focus_mode = Control.FOCUS_NONE
	next_button.pressed.connect(_on_next_pressed)
	bottom_bar.add_child(next_button)

	# This mission's bonus goals, low over the clean room (res://scenes/directives_card.tscn)
	add_directives_card(layer)

func add_directives_card(layer):
	var card = DIRECTIVES_CARD_SCENE.instantiate()
	card.show_descriptions = false
	layer.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	card.custom_minimum_size.x = 340
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_left = -170
	card.offset_right = 170
	card.offset_bottom = -76
	UiMotion.slide_in(card, 0.6, Vector2(0, 24), 0.7)

func part_label(part_id):
	var part = GameState.PARTS[part_id]
	var text = "%s   %d kg, %s" % [part["name"], part["mass"], GameState.money_text(part["cost"])]
	if part.has("power_at_earth"):
		text += ", %s W at Earth" % format_number(part["power_at_earth"])
	elif part.has("power_anywhere"):
		text += ", %d W" % part["power_anywhere"]
	elif part.get("power_used", 0) > 0:
		text += ", uses %d W" % part["power_used"]
	return text

func format_number(number):
	var digits = str(int(round(number)))
	var result = ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return digits + result

# ---------------------------------------------------------------------------
# Picking parts
# ---------------------------------------------------------------------------
func _on_part_selected(dropdown_index, slot):
	GameState.choices[slot] = part_ids_by_slot[slot][dropdown_index]
	rebuild()

func _on_instrument_toggled(is_checked, part_id):
	if is_checked and not part_id in GameState.instruments:
		GameState.instruments.append(part_id)
	elif not is_checked:
		GameState.instruments.erase(part_id)
	rebuild()

func rebuild():
	for slot in part_notes:
		var part = GameState.PARTS[GameState.choices[slot]]
		part_notes[slot].text = "%s. %s" % [part["like"], part["about"]]
	rebuild_model()
	update_review()
	update_briefing()

# ---------------------------------------------------------------------------
# Flight Readiness Review: each line is GO (green), WATCH (yellow) or NO-GO (red)
# ---------------------------------------------------------------------------
func line(status, title, text):
	var color = GO if status == "go" else (WATCH if status == "watch" else NO_GO)
	var word = "GO" if status == "go" else ("WATCH" if status == "watch" else "NO-GO")
	return "[color=#%s]● %s[/color]  [b]%s[/b]\n%s\n" % [color.to_html(false), word, title, text]

func trip_text():
	var years = GameState.trip_years()
	if years < 0.05:
		return "%d days" % int(round(years * 365.25))
	if years < 1.5:
		return "%d months" % int(round(years * 12.0))
	return "%s years" % str(snapped(years, 0.1))

func time_text(minutes):
	if minutes < 1.0:
		return "%.1f seconds" % (minutes * 60.0)
	if minutes < 90.0:
		return "%d minutes" % int(round(minutes))
	return "%s hours" % str(snapped(minutes / 60.0, 0.1))

func update_review():
	var destination = GameState.destination
	var choices = GameState.choices
	var has_lander = choices["landing"] != "landing_none"
	var distance = GameState.DESTINATIONS[destination]["distance_from_sun_au"]
	var lines = []
	var reds = 0
	var yellows = 0

	# Budget
	var cost = GameState.probe_cost()
	var budget = GameState.budget()
	var status = "go" if cost <= budget * 0.7 else ("watch" if cost <= budget else "no-go")
	lines.append(line(status, "Budget", "The probe costs %s of your %s. The rocket still has to be paid for too." % [GameState.money_text(cost), GameState.money_text(budget)]))

	# Power when it gets there
	var made = GameState.power_made()
	var needed = GameState.power_needed()
	var power_part = GameState.PARTS[choices["power"]]
	var power_reason = ""
	if power_part.has("power_anywhere"):
		power_reason = "Your RTG power fades from %d W at launch to %d W during the %s trip." % [power_part["power_anywhere"], made, trip_text()]
	else:
		power_reason = "%s gets %s of Earth's sunlight, so panels rated %s W at Earth make %s W there." % [destination, sunlight_text(), format_number(power_part["power_at_earth"]), format_number(made)]
	status = "go" if made >= needed * 1.2 else ("watch" if made >= needed else "no-go")
	var advice = ""
	if status == "watch":
		advice = " Real missions keep at least 20% spare."
	elif status == "no-go":
		advice = " The probe would shut down when it arrives."
	lines.append(line(status, "Power at %s: %s W made, %d W needed" % [destination, format_number(made), needed], power_reason + advice))

	# Shadows and nights
	var battery_hours = GameState.PARTS[choices["battery"]]["capacity_wh"] / max(needed, 1.0)
	var dark_hours = 1.2
	var dark_reason = "orbiting through %s's shadow (about an hour)" % destination
	if has_lander:
		var night_hours = {"Moon": 354.0, "Mercury": 2112.0, "Mars": 12.3, "Titan": 192.0, "Pluto": 76.7, "Ceres": 4.5, "Europa": 42.6, "Phobos": 3.8}
		if night_hours.has(destination):
			dark_hours = night_hours[destination]
			dark_reason = "a night on %s's surface (%s)" % [destination, time_text(dark_hours * 60.0)]
	if power_part.has("power_anywhere"):
		lines.append(line("go", "Shadows and nights", "RTGs work in the dark, so night and shadow don't matter. The battery covers power peaks."))
	else:
		status = "go" if battery_hours >= dark_hours else ("watch" if battery_hours >= dark_hours * 0.5 else "no-go")
		lines.append(line(status, "Shadows and nights", "Solar panels make nothing in the dark. Your battery lasts about %s at full use, and the probe must survive %s." % [time_text(battery_hours * 60.0), dark_reason]))

	# Data home
	var photos = GameState.photos_per_day()
	var rate = GameState.data_rate_kilobits()
	var rate_text = ""
	if rate >= 1000.0:
		rate_text = "%s megabits per second" % str(snapped(rate / 1000.0, 0.1))
	elif rate >= 10.0:
		rate_text = "%d kilobits per second" % int(round(rate))
	elif rate >= 0.1:
		rate_text = "%s kilobits per second" % str(snapped(rate, 0.01))
	else:
		rate_text = "%d bits per second" % int(round(rate * 1000.0))
	var photo_text = ""
	if photos >= 1.5:
		photo_text = "about %s high-resolution photos a day" % format_number(photos)
	elif photos >= 0.75:
		photo_text = "about 1 high-resolution photo a day"
	elif photos > 0.0:
		photo_text = "one photo every %s days" % format_number(1.0 / photos)
	status = "go" if photos >= 10.0 else ("watch" if photos >= 1.0 else "no-go")
	var best_antenna = GameState.choices["antenna"] == "antenna_large"
	var data_advice = ""
	if best_antenna and status != "go":
		# The biggest dish is already fitted: a slow link this far out is normal, not something to fix
		status = "go"
		data_advice = " That's slow, but it's the best any probe can do from this far away: New Horizons sent Pluto's pictures home at 1 to 2 kilobits per second, and it took 15 months."
	elif status != "go":
		data_advice = " A high-gain dish would send about 2,000 times more."
	lines.append(line(status, "Data home: %s" % rate_text, "Radio signals take %s each way. Using an 8-hour contact a day with NASA's Deep Space Network dishes, that's %s.%s" % [time_text(GameState.radio_delay_minutes()), photo_text, data_advice]))

	# Braking into orbit
	var can_do = GameState.probe_speed_change_km_s()
	var must_do = GameState.arrival_burn_needed_km_s()
	if GameState.direct_entry():
		lines.append(line("go", "Getting there", "Your lander dives straight into %s's air behind its heat shield, like Perseverance at Mars. No braking burn needed." % destination))
	elif choices["engine"] == "engine_ion" and not GameState.ion_engines_have_power():
		lines.append(line("no-go", "Braking into orbit: engines can't run", "Ion engines need at least 500 W to spare, but you'd only have %d W at %s. Real outer-planet ion missions would need nuclear power." % [max(0, made - GameState.PROBE_BODY["power_needed"]), destination]))
	else:
		status = "go" if can_do >= must_do * 1.1 else ("watch" if can_do >= must_do else "no-go")
		var burn_reason = "To stay at %s, the probe must slow down by %.2f km/s with its own engine. With %d kg of propellant it can manage %.2f km/s." % [destination, must_do, GameState.propellant_mass(), can_do]
		if status != "no-go":
			burn_reason += " That's %s." % GameState.arrival_burn_time_text()
		else:
			burn_reason += " It would fly right past, like New Horizons did at Pluto. Try more propellant, a lighter probe, or ion engines."
		lines.append(line(status, "Braking into orbit: %.2f of %.2f km/s" % [can_do, must_do], burn_reason))

	# Temperature
	if distance < 0.8:
		status = "go" if choices["thermal"] in ["thermal_radiators", "thermal_both"] else "no-go"
		lines.append(line(status, "Temperature", "%s gets %s of Earth's sunlight. %s" % [destination, sunlight_text(), "Your radiators shed the extra heat." if status == "go" else "Without radiators the probe will overheat."]))
	elif distance > 3.0:
		var warm = choices["thermal"] in ["thermal_heaters", "thermal_both"] or power_part.has("power_anywhere")
		lines.append(line("go" if warm else "no-go", "Temperature", "Far from the Sun it's colder than -150 °C. " + ("Heaters (or an RTG's spare heat, like on New Horizons) keep the probe warm." if warm else "Add heaters or an RTG, or the fuel and electronics will freeze.")))
	else:
		lines.append(line("go", "Temperature", "Sunlight here is close to Earth's, so temperature control is easy."))

	# Radiation
	var radiation = GameState.RADIATION.get(destination, "")
	if radiation.begins_with("Extreme") or radiation.begins_with("Very high") or radiation.begins_with("High"):
		var vault = choices["shield"] == "shield_radiation"
		var hardened = choices["computer"] == "computer_radiation_hardened"
		status = "go" if vault and hardened else ("watch" if vault or hardened else "no-go")
		lines.append(line(status, "Radiation", radiation + " " + ("Vault and hardened computer: protected." if status == "go" else "A radiation vault and a radiation-hardened computer protect the electronics.")))
	else:
		lines.append(line("go", "Radiation", radiation if radiation != "" else "Low. No special protection needed."))

	# Landing
	if has_lander:
		var landing_status = "go"
		var landing_text = ""
		if destination in GameState.NO_SURFACE:
			landing_status = "no-go"
			landing_text = "%s has no solid surface. A lander would just sink until it's crushed." % destination
		elif destination in GameState.AIRLESS_WORLDS:
			landing_status = "go" if choices["landing"] == "landing_legs" else "no-go"
			landing_text = "No air here, so parachutes, airbags and sky cranes can't work. " + ("Thrusters and legs: correct." if landing_status == "go" else "Use landing legs and thrusters.")
		elif destination == "Mars":
			landing_status = "go" if choices["shield"] == "shield_heat" else "no-go"
			landing_text = "Mars landers need a heat shield and parachute first (Perseverance's shield hit about 1,300 °C), then legs, airbags or a sky crane." + ("" if landing_status == "go" else " Add a heat shield.")
		elif destination == "Venus":
			landing_status = "go" if choices["shield"] == "shield_venus" else "no-go"
			landing_text = "The surface is 465 °C with 92 times Earth's air pressure. " + ("Your pressure hull should last a couple of hours, like Venera 13." if landing_status == "go" else "Only a pressure and heat hull survives there.")
		elif destination in ["Titan", "Saturn"]:
			landing_status = "go" if choices["shield"] == "shield_heat" else "no-go"
			landing_text = "Your lander goes to Titan, whose thick air makes parachutes work wonderfully (Huygens floated down for over 2 hours)." + ("" if landing_status == "go" else " It needs a heat shield to get through the air.")
		else:
			landing_text = "Landing systems ready."
		lines.append(line(landing_status, "Landing", landing_text))

	# Pointing: aiming the dish and cameras
	var attitude = choices.get("attitude", "attitude_wheels")
	if attitude == "attitude_thrusters":
		status = "watch" if choices["antenna"] == "antenna_large" else "go"
		lines.append(line(status, "Pointing", "Thrusters alone turn the probe in rough little pushes, using propellant (5% less speed change)." + (" They can't hold a narrow dish beam on Earth for long, so the high-gain dish sends only half as much." if status == "watch" else "")))
	elif attitude == "attitude_wheels":
		lines.append(line("watch", "Pointing", "Reaction wheels point precisely, but there's no backup if one fails: Kepler and Dawn each lost two wheels. Real flagships carry thrusters as a backup."))
	else:
		lines.append(line("go", "Pointing", "Reaction wheels with thrusters as a backup, like Cassini and Juno."))

	# Data recorder: can it hold what the instruments make until the radio sends it home?
	var made_per_day = GameState.data_made_mb_per_day()
	var sent_per_day = GameState.data_sent_mb_per_day()
	var recorder_days = GameState.recorder_days()
	status = "go" if recorder_days >= 30.0 else ("watch" if recorder_days >= 7.0 else "no-go")
	var recorder_text = "Your instruments make about %s MB a day, and the radio sends about %s MB a day home. " % [format_number(made_per_day), format_number(sent_per_day)]
	if recorder_days >= 9999.0:
		recorder_text += "Everything gets sent the same day: the recorder never fills up."
	else:
		recorder_text += "The %d GB recorder fills up in about %s, then new science is lost." % [GameState.PARTS[choices.get("storage", "storage_small")]["capacity_gb"], time_text(recorder_days * 1440.0) if recorder_days < 2.0 else "%d days" % int(recorder_days)]
		if status != "go":
			recorder_text += " A bigger recorder, a better antenna or fewer data-hungry instruments (cameras and radar) would help."
	lines.append(line(status, "Data recorder", recorder_text))

	# Structure: launch shaking and landings
	var structure = choices.get("structure", "structure_aluminum")
	if structure == "structure_composite" and GameState.total_mass() > 2500:
		lines.append(line("no-go", "Structure", "A composite frame under a %s kg probe would crack in the shaking of launch. Use an aluminum or titanium frame, or lighten the probe." % format_number(GameState.total_mass())))
	elif has_lander and structure != "structure_reinforced" and choices["landing"] == "landing_legs":
		lines.append(line("watch", "Structure", "Legged landers hit the ground hard. A reinforced frame would make a rough touchdown survivable."))
	else:
		lines.append(line("go", "Structure", {"structure_aluminum": "Aluminum honeycomb: strong and proven.", "structure_composite": "A light composite frame, fine for a probe this size.", "structure_reinforced": "A reinforced titanium frame: tough enough for launch and landing."}.get(structure, "")))

	# Science match: the right instruments for this place
	var fitting = []
	var weak = []
	for instrument_id in GameState.instruments:
		if GameState.instrument_science(instrument_id) >= 12:
			fitting.append(GameState.PARTS[instrument_id]["name"].split(" (")[0])
		else:
			weak.append(GameState.PARTS[instrument_id]["name"].split(" (")[0])
	status = "go" if fitting.size() >= 3 else ("watch" if fitting.size() >= 1 else "no-go")
	var match_text = "Good tools for %s: %s." % [destination, ", ".join(fitting) if not fitting.is_empty() else "none yet"]
	if not weak.is_empty():
		match_text += " Doing little here: %s." % ", ".join(weak)
	if status != "go":
		match_text += " Real missions carry 3 or more instruments chosen for their target."
	lines.append(line(status, "Science match", match_text))

	# Science
	var instrument_count = GameState.instruments.size()
	var lander_only_without_lander = not has_lander and (GameState.is_chosen("instrument_drill") or GameState.is_chosen("instrument_seismometer") or GameState.is_chosen("instrument_arm"))
	status = "no-go" if instrument_count == 0 else ("watch" if lander_only_without_lander or instrument_count == 1 else "go")
	var science_text = "%d instrument%s on board." % [instrument_count, "" if instrument_count == 1 else "s"]
	if instrument_count == 0:
		science_text = "No instruments means almost no science."
	if lander_only_without_lander:
		science_text += " The drill, seismometer and robotic arm only work on a lander."
	lines.append(line(status, "Science", science_text))

	# Launch mass
	lines.append(line("go", "Launch mass: %s kg" % format_number(GameState.total_mass()), "%d kg of that is propellant. A heavier probe needs a bigger rocket, which you'll design next." % GameState.propellant_mass()))

	for each_line in lines:
		if each_line.contains("NO-GO"):
			reds += 1
		elif each_line.contains("WATCH"):
			yellows += 1
	var verdict = ""
	if reds > 0:
		verdict = "[color=#%s][b]%d NO-GO item%s. Fix the red items before launch.[/b][/color]" % [NO_GO.to_html(false), reds, "" if reds == 1 else "s"]
	elif yellows > 0:
		verdict = "[color=#%s][b]GO, with %d item%s to watch.[/b][/color]" % [WATCH.to_html(false), yellows, "" if yellows == 1 else "s"]
	else:
		verdict = "[color=#%s][b]ALL SYSTEMS GO![/b][/color]" % GO.to_html(false)
	readiness_label.text = "[b]FLIGHT READINESS REVIEW[/b]\n" + verdict + "\n\n" + "\n".join(lines)
	# The mission score counts NO-GO and WATCH items flown with (GameState.finish_mission)
	GameState.readiness["probe_no_go"] = reds
	GameState.readiness["probe_watch"] = yellows

	summary_label.text = "%s kg   |   %s W at %s   |   %s of %s" % [format_number(GameState.total_mass()), format_number(made), destination, GameState.money_text(cost), GameState.money_text(budget)]
	summary_label.add_theme_color_override("font_color", Color(0.1, 0.12, 0.16))
	next_button.disabled = cost > budget
	next_button.tooltip_text = "The probe is over budget." if cost > budget else ""

func sunlight_text():
	var share = GameState.sunlight_factor()
	if share >= 1.5:
		return "%s times" % str(snapped(share, 0.1))
	if share >= 0.1:
		return "%d%%" % int(round(share * 100.0))
	if share >= 0.001:
		return "%s%%" % str(snapped(share * 100.0, 0.01))
	return "1/%s" % format_number(1.0 / share)

# ---------------------------------------------------------------------------
# Destination briefing
# ---------------------------------------------------------------------------
func update_briefing():
	var destination = GameState.destination
	var data = SolarSystemData.BODIES.get(destination, {})
	var facts = data.get("facts", {})
	var lines = []
	lines.append("[b]%s[/b]" % data.get("label", destination).to_upper())
	if facts.has("type"):
		lines.append(facts["type"])
	lines.append("")
	var goal = SolarSystemScript.MISSION_GOALS.get(destination, "")
	if goal != "":
		lines.append("[b]Mission goal[/b]\n" + goal + "\n")
	lines.append("[b]Distance[/b]\n" + facts.get("distance", ""))
	lines.append("[b]Sunlight[/b]\n%s of Earth's" % sunlight_text())
	lines.append("[b]Radio delay[/b]\nAbout %s each way, so a question and answer takes %s. The probe has to look after itself." % [time_text(GameState.radio_delay_minutes()), time_text(GameState.radio_delay_minutes() * 2.0)])
	lines.append("[b]Trip[/b]\nAbout %s, based on real missions." % trip_text())
	if facts.has("gravity"):
		lines.append("[b]Gravity[/b]\n%s m/s² (%s × Earth's)" % [str(snapped(facts["gravity"], 0.001 if facts["gravity"] < 0.1 else 0.01)), str(snapped(facts["gravity"] / 9.81, 0.001 if facts["gravity"] < 0.1 else 0.01))])
	if facts.has("temperature"):
		lines.append("[b]Temperature[/b]\n" + facts["temperature"])
	lines.append("[b]Air[/b]\n" + GameState.AIR.get(destination, "None, so there's nothing to slow a lander down: landers need rocket thrusters."))
	lines.append("[b]Radiation[/b]\n" + GameState.RADIATION.get(destination, "Low."))
	if GameState.direct_entry():
		lines.append("[b]Getting into orbit[/b]\nYour lander dives straight into the air, like Perseverance.")
	else:
		lines.append("[b]Getting into orbit[/b]\nThe probe must slow down by about %.2f km/s when it arrives." % GameState.arrival_burn_needed_km_s())
	lines.append("")
	lines.append("[b]Real missions[/b]\n" + GameState.REAL_MISSIONS.get(destination, ""))
	briefing_label.text = "\n".join(lines)

# ---------------------------------------------------------------------------
# Leaving
# ---------------------------------------------------------------------------
func _on_next_pressed():
	if next_button.disabled:
		return
	GameState.go_to_scene(ROCKET_SCENE)

func _on_back_pressed():
	GameState.go_to_scene(SOLAR_SYSTEM_SCENE)
