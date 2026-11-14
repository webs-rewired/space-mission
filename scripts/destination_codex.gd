extends Control

# The solar system's "Go to..." menu (res://scenes/destination_codex.tscn): a codex of every world, laid out
# like the menus of Lies of P: dark, with engraved gold rules, a numbered list on the left, the world itself
# turning in the middle, and its record (numbers) and account (story) on the right.
#
# The globe in the middle is the real world from the solar system, not a stand-in: the same surface, clouds,
# air glow and rings you see out there (res://scenes/world_globe.tscn copies it from the Bodies node).
#
# space_controls.gd makes this menu, calls set_up() once and open() / close(). It listens for:
#   travel_requested(body_name, follow)   fly there (and keep following it if follow is true)
#   mission_requested(body_name)          plan a mission there (the probe builder)
#   closed                                the menu was closed
#
# Keys: W/S or Up/Down choose, Q/E or Left/Right turn the page, Enter travels, F follows, M plans a mission,
# Esc goes back. Everything also works with the mouse.

signal travel_requested(body_name, follow)
signal mission_requested(body_name)
signal closed

const ENTRY_SCENE = preload("res://scenes/codex_entry.tscn")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const SpaceTextures = preload("res://scripts/space_textures.gd")
const LoadingScreenScript = preload("res://scripts/loading_screen.gd")
const OrbitMath = preload("res://scripts/orbit_math.gd")
const GOLD = Color(0.78, 0.65, 0.42)
const LIVE_REFRESH_SECONDS = 0.5

# The pages of the codex: [kind of body, page title, the tab's node name]
const PAGES = [
	["planet", "PLANETS", "PlanetsTab"],
	["moon", "MOONS", "MoonsTab"],
	["dwarf", "DWARF PLANETS", "DwarfTab"],
	["comet", "COMETS", "CometsTab"],
	["spacecraft", "SPACECRAFT", "SpacecraftTab"],
]

@onready var backdrop: ColorRect = $Backdrop
@onready var dust: CPUParticles2D = $Dust
@onready var globe_stage: Control = $Frame/Layout/Body/CenterColumn/GlobeStage   # (scripts/world_globe.gd)
@onready var name_rule: Control = $Frame/Layout/Body/CenterColumn/NameRule
@onready var frame: Control = $Frame
@onready var title_label: Label = $Frame/Layout/Header/TitleBlock/Title
@onready var date_value: Label = $Frame/Layout/Header/DateBlock/DateValue
@onready var tabs_box: HBoxContainer = $Frame/Layout/TabsStage/TabsRow/Tabs
@onready var tab_marker: Control = $Frame/Layout/TabsStage/TabMarker
@onready var tabs_stage: Control = $Frame/Layout/TabsStage
@onready var category_name: Label = $Frame/Layout/Body/ListColumn/ListHeading/CategoryName
@onready var entry_count: Label = $Frame/Layout/Body/ListColumn/ListHeading/EntryCount
@onready var list_scroll: ScrollContainer = $Frame/Layout/Body/ListColumn/ListScroll
@onready var entry_list: VBoxContainer = $Frame/Layout/Body/ListColumn/ListScroll/EntryList
@onready var name_label: Label = $Frame/Layout/Body/CenterColumn/NameLabel
@onready var kind_label: Label = $Frame/Layout/Body/CenterColumn/KindLabel
@onready var record_scroll: ScrollContainer = $Frame/Layout/Body/RecordColumn/RecordScroll
@onready var record_content: VBoxContainer = $Frame/Layout/Body/RecordColumn/RecordScroll/RecordContent
@onready var live_label: Label = $Frame/Layout/Body/RecordColumn/RecordScroll/RecordContent/LiveLabel
@onready var stats_grid: GridContainer = $Frame/Layout/Body/RecordColumn/RecordScroll/RecordContent/StatsGrid
@onready var account_text: RichTextLabel = $Frame/Layout/Body/RecordColumn/RecordScroll/RecordContent/AccountText
@onready var travel_prompt: Button = $Frame/Layout/Footer/TravelPrompt
@onready var follow_prompt: Button = $Frame/Layout/Footer/FollowPrompt
@onready var mission_prompt: Button = $Frame/Layout/Footer/MissionPrompt
@onready var back_prompt: Button = $Frame/Layout/Footer/BackPrompt

var bodies_node = null       # the solar system's Bodies node, for the real worlds, the date and live facts
var scene_root = null        # the solar system scene (for its mission goals and the camera)
var page_index = 0
var entries = []             # the list's lines (codex_entry.gd), in order
var chosen_name = ""
var chosen_on_page = {}      # which world was chosen last on each page, to come back to it
var live_seconds = 0.0
var paused_camera = null     # the camera stops flying around while the codex is open
var map_cache = {}
var closing = false

func _ready():
	visible = false
	for index in PAGES.size():
		var tab: Button = tabs_box.get_node(PAGES[index][2])
		tab.pressed.connect(turn_to_page.bind(index))
	travel_prompt.pressed.connect(travel.bind(false))
	follow_prompt.pressed.connect(travel.bind(true))
	mission_prompt.pressed.connect(plan_mission)
	back_prompt.pressed.connect(close)
	for prompt in [travel_prompt, follow_prompt, mission_prompt, back_prompt]:
		var action_label: Label = prompt.get_node("Row/Action")
		prompt.mouse_entered.connect(func(): action_label.add_theme_color_override("font_color", Color(0.98, 0.93, 0.83)))
		prompt.mouse_exited.connect(func(): action_label.remove_theme_color_override("font_color"))
	tabs_stage.resized.connect(place_tab_marker.bind(false))

func set_up(world_bodies, solar_system_scene):
	bodies_node = world_bodies
	scene_root = solar_system_scene

func is_open():
	return visible and not closing

# ---------------------------------------------------------------------------
# Opening and closing
# ---------------------------------------------------------------------------
func open(kind := ""):
	if visible and not closing:
		return
	closing = false
	modulate.a = 1.0
	visible = true
	if kind != "":
		for index in PAGES.size():
			if PAGES[index][0] == kind:
				page_index = index
	if bodies_node and "julian_date" in bodies_node:
		date_value.text = OrbitMath.date_text(bodies_node.julian_date)
	hold_camera(true)
	# The page darkens, the title's letters rise, and the list slides in line by line (scripts/ui_motion.gd)
	backdrop.modulate.a = 0.0
	backdrop.create_tween().tween_property(backdrop, "modulate:a", 1.0, 0.3)
	frame.modulate.a = 0.0
	frame.create_tween().tween_property(frame, "modulate:a", 1.0, 0.35).set_delay(0.05)
	UiMotion.reveal_text(title_label, 0.1, 0.9, 0.6)
	# Every gold rule draws itself out from the middle, the rings sweep in around the globe, and dust drifts
	var rule_number = 0
	for rule in frame.find_children("*", "Control", true, false):
		if rule.has_method("draw_in") and not globe_stage.is_ancestor_of(rule) and rule != globe_stage:
			rule.draw_in(0.08 + rule_number * 0.05, 0.8)
			rule_number += 1
	globe_stage.draw_in(0.15, 1.2)
	dust.position = size / 2.0
	dust.emission_rect_extents = size / 2.0
	dust.restart()
	turn_to_page(page_index, true)

func close():
	if not visible or closing:
		return
	closing = true
	hold_camera(false)
	var fade = create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.15)
	fade.tween_callback(func():
		visible = false
		closing = false
		modulate.a = 1.0)
	closed.emit()

# While the codex is open the camera doesn't move (W and S choose in the list instead of flying)
func hold_camera(hold):
	var camera_pivot = scene_root.find_child("CameraPivot", true, false) if scene_root else null
	if camera_pivot == null:
		return
	if hold:
		paused_camera = camera_pivot
		camera_pivot.process_mode = Node.PROCESS_MODE_DISABLED
	elif paused_camera and is_instance_valid(paused_camera):
		paused_camera.process_mode = Node.PROCESS_MODE_INHERIT
		paused_camera = null

# ---------------------------------------------------------------------------
# Keys
# ---------------------------------------------------------------------------
func _input(event):
	if not visible or closing or not (event is InputEventKey) or not event.pressed:
		return
	var used = true
	match event.keycode:
		KEY_ESCAPE, KEY_BACKSPACE:
			close()
		KEY_W, KEY_UP:
			choose_step(-1)
		KEY_S, KEY_DOWN:
			choose_step(1)
		KEY_Q, KEY_LEFT, KEY_A:
			turn_to_page(wrapi(page_index - 1, 0, PAGES.size()))
		KEY_E, KEY_RIGHT, KEY_D:
			turn_to_page(wrapi(page_index + 1, 0, PAGES.size()))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not event.echo:
				travel(false)
		KEY_F:
			if not event.echo:
				travel(true)
		KEY_M:
			if not event.echo:
				plan_mission()
		_:
			used = false
	if used:
		get_viewport().set_input_as_handled()

func choose_step(step):
	if entries.is_empty():
		return
	var index = 0
	for entry_index in entries.size():
		if entries[entry_index].body_name == chosen_name:
			index = entry_index
	choose(entries[wrapi(index + step, 0, entries.size())].body_name)

# ---------------------------------------------------------------------------
# Pages (the tabs) and the list
# ---------------------------------------------------------------------------
func turn_to_page(index, opening := false):
	var page_changed = index != page_index or opening
	page_index = index
	var kind = PAGES[index][0]
	for page_number in PAGES.size():
		var tab: Button = tabs_box.get_node(PAGES[page_number][2])
		tab.add_theme_color_override("font_color", Color(0.96, 0.91, 0.8) if page_number == index else Color(0.58, 0.53, 0.45))
	place_tab_marker(not opening)
	category_name.text = PAGES[index][1]
	if not page_changed and not entries.is_empty():
		return
	fill_list(kind)
	var wanted = chosen_on_page.get(kind, "")
	if wanted == "" and not entries.is_empty():
		wanted = entries[0].body_name
	if wanted != "":
		choose(wanted, true)
	# The new page's lines slide in one after another from the left
	UiMotion.stagger(entries, 0.05 if opening else 0.0, 0.03, Vector2(-26, 0), 0.5)

# The gold underline with a diamond slides under the chosen tab
func place_tab_marker(animate := true):
	if not is_inside_tree():
		return
	var tab: Button = tabs_box.get_node(PAGES[page_index][2])
	await get_tree().process_frame   # (after the tabs have been laid out)
	var tab_rect = tab.get_global_rect()
	var stage_origin = tabs_stage.get_global_rect().position
	var wanted_position = Vector2(tab_rect.position.x - stage_origin.x - 10.0, tabs_stage.size.y - 10.0)
	var wanted_size = Vector2(tab_rect.size.x + 20.0, 10.0)
	if animate:
		var slide = tab_marker.create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		slide.tween_property(tab_marker, "position", wanted_position, 0.35)
		slide.tween_property(tab_marker, "size", wanted_size, 0.35)
	else:
		tab_marker.position = wanted_position
		tab_marker.size = wanted_size

func fill_list(kind):
	for entry in entries:
		entry_list.remove_child(entry)   # (right away, so the new lines are laid out from the top)
		entry.queue_free()
	entries.clear()
	var names = []
	if kind == "planet":
		names.append("Sun")
	for body_name in SolarSystemData.BODY_ORDER:
		if SolarSystemData.BODIES.has(body_name) and SolarSystemData.BODIES[body_name]["kind"] == kind:
			names.append(body_name)
	for index in names.size():
		var body_name = names[index]
		var data = SolarSystemData.BODIES[body_name]
		var entry = ENTRY_SCENE.instantiate()
		entry_list.add_child(entry)
		entry.set_up(body_name, index + 1, data["label"], list_detail(body_name), map_for(body_name), data.get("label_color", data.get("color", Color.WHITE)))
		entry.chosen.connect(choose)
		entries.append(entry)
	entry_count.text = "%d RECORDS" % entries.size()

# The short note on the right of each line: how far out it orbits, or which planet a moon belongs to
func list_detail(body_name):
	var data = SolarSystemData.BODIES[body_name]
	match data["kind"]:
		"star":
			return "Star"
		"moon":
			return str(data.get("parent", ""))
		"spacecraft":
			# The year it launched, from "September 5, 1977, on a Titan IIIE rocket..."
			for word in str(data.get("facts", {}).get("launched", "")).split(" "):
				var number = word.trim_suffix(",")
				if number.is_valid_int() and number.length() == 4:
					return number
			return ""
	var orbit = data.get("orbit", {})
	if orbit.has("jpl"):
		return "%.2f AU" % orbit["jpl"][0]
	if orbit.has("a"):
		return "%.1f AU" % orbit["a"] if orbit["a"] >= 10.0 else "%.2f AU" % orbit["a"]
	return ""

# The world's map for its little ball in the list: the same picture the world wears in the solar system
func map_for(body_name):
	if map_cache.has(body_name):
		return map_cache[body_name]
	var map_texture = null
	var info = real_world(body_name)
	if info.has("mesh") and info["mesh"] is MeshInstance3D:
		var surface = info["mesh"].material_override
		if surface is StandardMaterial3D:
			map_texture = surface.albedo_texture
		elif surface is ShaderMaterial:
			for parameter in ["day_map", "surface_image"]:
				var found = surface.get_shader_parameter(parameter)
				if found is Texture2D:
					map_texture = found
					break
	if map_texture == null and SolarSystemData.BODIES[body_name].get("images", []).size() > 0:
		map_texture = SpaceTextures.find_texture(SolarSystemData.BODIES[body_name]["images"])
	map_cache[body_name] = map_texture
	return map_texture

func real_world(body_name) -> Dictionary:
	if bodies_node and "bodies" in bodies_node and bodies_node.bodies.has(body_name):
		return bodies_node.bodies[body_name]
	return {}

# ---------------------------------------------------------------------------
# Choosing a world: the globe, its name, its record and its account
# ---------------------------------------------------------------------------
func choose(body_name, quietly := false):
	if not SolarSystemData.BODIES.has(body_name):
		return
	var same = body_name == chosen_name
	chosen_name = body_name
	chosen_on_page[PAGES[page_index][0]] = body_name
	for entry in entries:
		entry.show_chosen(entry.body_name == body_name)
		if entry.body_name == body_name:
			list_scroll.ensure_control_visible.call_deferred(entry)
	if same and not quietly:
		travel(false)   # clicking the chosen world again flies there
		return
	var data = SolarSystemData.BODIES[body_name]
	name_label.text = data["label"].to_upper()
	kind_label.text = str(data["facts"].get("type", ""))
	globe_stage.show_world(bodies_node, body_name)
	fill_record(body_name)
	update_prompts()
	# The name rises into place, the rings flash, the globe swells in, and the record comes in line by line
	UiMotion.reveal_text(name_label, 0.0, 0.6, 0.4)
	UiMotion.slide_in(kind_label, 0.12, Vector2(0, 10), 0.5)
	name_rule.draw_in(0.1, 0.6)
	globe_stage.pulse()
	globe_stage.swell()
	record_scroll.scroll_vertical = 0

func update_prompts():
	var shown = true
	if bodies_node and bodies_node.has_method("is_body_shown"):
		shown = bodies_node.is_body_shown(chosen_name)
	travel_prompt.disabled = not shown
	follow_prompt.disabled = not shown
	for prompt in [travel_prompt, follow_prompt]:
		prompt.modulate.a = 1.0 if shown else 0.35
	mission_prompt.visible = GameState.DESTINATIONS.has(chosen_name)

func _process(delta):
	if not visible:
		return
	live_seconds -= delta
	if live_seconds <= 0.0:
		live_seconds = LIVE_REFRESH_SECONDS
		live_label.text = live_line(chosen_name)
		live_label.visible = live_label.text != ""

func live_line(body_name):
	if body_name == "" or bodies_node == null or not bodies_node.has_method("live_facts"):
		return ""
	if bodies_node.has_method("is_body_shown") and not bodies_node.is_body_shown(body_name):
		return "Not in the sky on this date."
	return str(bodies_node.live_facts(body_name)).strip_edges()

# The numbers (the record) and the story (the account)
func fill_record(body_name):
	for old in stats_grid.get_children():
		stats_grid.remove_child(old)
		old.queue_free()
	var data = SolarSystemData.BODIES[body_name]
	var facts = data["facts"]
	live_label.text = live_line(body_name)
	live_label.visible = live_label.text != ""
	var account = []
	if data["kind"] == "spacecraft":
		add_record_row("Launched", facts.get("launched", ""))
		add_record_row("Size", facts.get("size", ""))
		add_record_row("Mass", facts.get("mass", ""))
		add_record_row("Power", facts.get("power", ""))
		add_record_row("Status", facts.get("status", ""))
		account.append(str(facts.get("mission", "")))
		if facts.has("did_you_know"):
			account.append("[i]" + str(facts["did_you_know"]) + "[/i]")
	else:
		add_record_row("Distance", facts.get("distance", ""))
		add_record_row("Diameter", "%s km" % format_number(facts.get("diameter_km", 0)))
		add_record_row("Mass", facts.get("mass", ""))
		var gravity = float(facts.get("gravity", 0.0))
		var gravity_text = "%s m/s²" % str(snapped(gravity, 0.0001 if gravity < 0.01 else 0.01))
		if gravity >= 0.01 and data["kind"] != "star":
			gravity_text += "\nYou would weigh %.2f× your Earth weight" % (gravity / 9.81)
		add_record_row("Gravity", gravity_text)
		add_record_row("Escape speed", facts.get("escape_speed", ""))
		add_record_row("Orbital speed", facts.get("orbital_speed", ""))
		add_record_row("Day", facts.get("day", ""))
		add_record_row("Year", facts.get("year", ""))
		add_record_row("Temperature", facts.get("temperature", ""))
		if facts.has("moons"):
			add_record_row("Moons", facts["moons"])
		if str(facts.get("sunlight", "")) != "":
			add_record_row("Sunlight", facts["sunlight"])
		account.append(str(facts.get("explored", "")))
		for place_fact in LoadingScreenScript.PLACE_FACTS.get(body_name, []).slice(0, 2):
			account.append("[i]" + place_fact + "[/i]")
		var goals = scene_root.get_script().get_script_constant_map().get("MISSION_GOALS", {}) if scene_root else {}
		if goals.has(body_name):
			account.append("[color=#c9a76b]A MISSION HERE[/color]\n" + str(goals[body_name]))
	account_text.text = "\n\n".join(account.filter(func(paragraph): return paragraph.strip_edges() != ""))
	# Each row of the record slides in from the right, one after another, then the account
	var rows = [live_label] + stats_grid.get_children()
	UiMotion.stagger(rows, 0.05, 0.03, Vector2(18, 0), 0.45)
	UiMotion.slide_in(account_text, 0.1 + rows.size() * 0.03, Vector2(0, 12), 0.5)

func add_record_row(title, value):
	if str(value).strip_edges() == "":
		return
	var key = Label.new()
	key.theme_type_variation = "CodexKey"
	key.text = title.to_upper()
	key.custom_minimum_size = Vector2(96, 0)
	key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stats_grid.add_child(key)
	var shown_value = Label.new()
	shown_value.theme_type_variation = "CodexValue"
	shown_value.text = with_superscripts(str(value))
	shown_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shown_value.custom_minimum_size = Vector2(200, 0)
	shown_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_child(shown_value)

# "10^26" becomes "10²⁶", the way it's printed in books
static func with_superscripts(text):
	var raised = {"0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"}
	var pattern = RegEx.new()
	pattern.compile("\\^(-?[0-9]+)")
	for found in pattern.search_all(text):
		var power = ""
		for character in found.get_string(1):
			power += raised[character]
		text = text.replace(found.get_string(0), power)
	return text

static func format_number(number):
	var digits = str(int(number))
	var result = ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return digits + result

# ---------------------------------------------------------------------------
# Going there
# ---------------------------------------------------------------------------
func travel(follow):
	if chosen_name == "" or travel_prompt.disabled:
		return
	var body_name = chosen_name
	close()
	travel_requested.emit(body_name, follow)

func plan_mission():
	if chosen_name == "" or not GameState.DESTINATIONS.has(chosen_name):
		return
	var body_name = chosen_name
	close()
	mission_requested.emit(body_name)
