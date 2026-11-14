extends CanvasLayer

# The pause menu (res://scenes/pause_menu.tscn): press Esc, or the "Menu" button, in any part of the game except the
# main menu. It pauses the game and has Resume, Settings, Controls, Main menu and Quit.
# GameState adds it when the game starts, so it's there in every scene.
#
# It also puts a "Menu" button into each scene's own row of buttons (next to "Back to the solar system" and the
# like), so nobody has to know about the Esc key. MENU_BUTTON_SPOTS says where, for each scene.

const MAIN_MENU_FALLBACK = "res://assets/main_menu (2).tscn"
const PLACE_NAMES = {
	"solar_system": "Solar system", "probe_builder": "Spacecraft clean room", "rocket_builder": "Vehicle Assembly Building",
	"launch": "Mission in progress", "results": "Mission report",
}
# Where each scene's "Menu" button goes: next to the button with this text, or inside the node with this name
const MENU_BUTTON_SPOTS = {
	"solar_system": {"after_text": "Reset"},
	"probe_builder": {"after_text": "Back to the solar system"},
	"rocket_builder": {"after_text": "Back to the probe"},
	"results": {"inside_node": "Buttons"},
	"launch": {"after_text": "Abort mission"},
}
const CONTROLS = {
	"solar_system": "MOVE: WASD or arrow keys, Space up, Ctrl down, hold Shift to go faster\nLOOK AROUND: hold the right mouse button and drag\nZOOM: mouse wheel\nPLANETS: click one for its facts, click a name to fly there, F to follow it, R to reset the view\nTIME: P pauses, + and - change the speed, T switches to true scale, H hides the controls\nGO TO...: every world's record. W/S choose, Q/E turn the page, Enter travel, F follow, M plan a mission\nSTART A MISSION: click a planet or moon, then \"Plan a mission\"",
	"probe_builder": "Pick each part from the lists on the left: every choice changes the weight, power, cost and what the probe can do.\nThe panel on the right checks your design like NASA's Flight Readiness Review: everything has to be GO or WATCH.\nDrag the 3D view to turn the probe, scroll to zoom. \"Show my parts\" labels each part.",
	"rocket_builder": "Start from a real rocket or design your own on the left: engines, tanks, boosters and an upper stage.\nThe right panel is the Launch Readiness Review: thrust, speed, budget and how hard the launch squeezes your probe.\nDrag the 3D view to look around the Vehicle Assembly Building, scroll to zoom.",
	"launch": "LAUNCH: watch it fly, or press Skip launch.\nCRUISE: the time buttons speed up or slow down the trip. In the asteroid and Kuiper belts you steer with WASD or the arrow keys.\nEVENTS: pick what the team should do; every choice has a real trade-off.\nORBIT: SPACE photographs the place below you, C switches between close-up and whole-world views.\nON THE GROUND: W/S drive, A/D steer, E studies a glowing target, right-drag to look around, V for the view from behind.\nAbort mission (bottom left) ends the mission.",
	"results": "Your mission report: how the mission went in NASA's four mission segments, and every decision and event along the way.\nTry again with a better design, or pick a new destination.",
}

@onready var screen: Control = $Screen
@onready var where_label: Label = $Screen/Center/Panel/Column/Where
@onready var buttons: VBoxContainer = $Screen/Center/Panel/Column/Buttons
@onready var settings_button: Button = $Screen/Center/Panel/Column/Buttons/SettingsButton
@onready var controls_button: Button = $Screen/Center/Panel/Column/Buttons/ControlsButton
@onready var settings_box: VBoxContainer = $Screen/Center/Panel/Column/Settings
@onready var quality_picker: OptionButton = $Screen/Center/Panel/Column/Settings/QualityRow/Quality
@onready var fullscreen_switch: CheckButton = $Screen/Center/Panel/Column/Settings/FullscreenRow/Fullscreen
@onready var volumes_box: VBoxContainer = $Screen/Center/Panel/Column/Settings/Volumes
@onready var controls_label: Label = $Screen/Center/Panel/Column/Controls
@onready var confirm_box: VBoxContainer = $Screen/Center/Panel/Column/Confirm

var paused_by_me = false
var last_scene = null

func _ready():
	$Screen/Center/Panel/Column/Buttons/ResumeButton.pressed.connect(close)
	settings_button.toggled.connect(func(on): show_section("settings" if on else ""))
	controls_button.toggled.connect(func(on): show_section("controls" if on else ""))
	$Screen/Center/Panel/Column/Buttons/MainMenuButton.pressed.connect(_on_main_menu_pressed)
	$Screen/Center/Panel/Column/Buttons/QuitButton.pressed.connect(func(): get_tree().quit())
	$Screen/Center/Panel/Column/Confirm/Row/YesButton.pressed.connect(go_to_main_menu)
	$Screen/Center/Panel/Column/Confirm/Row/NoButton.pressed.connect(_on_keep_playing_pressed)
	build_settings()

func scene_name():
	var scene = get_tree().current_scene
	return scene.scene_file_path.get_file().get_basename() if scene else ""

func in_main_menu():
	return scene_name().begins_with("main_menu")

func is_open():
	return screen.visible

# ---------------------------------------------------------------------------
# Opening and closing
# ---------------------------------------------------------------------------
func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if in_main_menu() or loading():
			return
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()

func open():
	if in_main_menu() or loading():
		return
	where_label.text = PLACE_NAMES.get(scene_name(), "Orbit Lab")
	controls_label.text = CONTROLS.get(scene_name(), "")
	controls_button.visible = controls_label.text != ""
	show_section("")
	confirm_box.visible = false
	buttons.visible = true
	screen.visible = true
	# The screen dims, the panel pops in and its buttons come up one after another (scripts/ui_motion.gd)
	screen.modulate.a = 0.0
	screen.create_tween().tween_property(screen, "modulate:a", 1.0, 0.2)
	UiMotion.pop_in($Screen/Center/Panel, 0.0, 0.4)
	UiMotion.stagger(buttons.get_children(), 0.08, 0.04, Vector2(0, 12), 0.45)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not get_tree().paused:
		get_tree().paused = true
		paused_by_me = true

func close():
	screen.visible = false
	if paused_by_me:
		get_tree().paused = false
		paused_by_me = false

func show_section(which):
	settings_box.visible = which == "settings"
	controls_label.visible = which == "controls"
	settings_button.set_pressed_no_signal(which == "settings")
	controls_button.set_pressed_no_signal(which == "controls")

func loading():
	var loading_screen = get_tree().root.get_node_or_null("LoadingScreen")
	return loading_screen != null and loading_screen.is_busy()

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------
func _on_main_menu_pressed():
	if scene_name() == "launch":
		# Leaving in the middle of a mission loses it: ask first
		buttons.visible = false
		show_section("")
		confirm_box.visible = true
		return
	go_to_main_menu()

func _on_keep_playing_pressed():
	confirm_box.visible = false
	buttons.visible = true

func go_to_main_menu():
	close()
	var audio = get_tree().root.get_node_or_null("AudioManager")
	if audio:
		audio.cancel_delayed_sounds()
		audio.stop_engine(0.3)
		audio.stop_voice()
		audio.stop_ambience(0.3)
		audio.set_air(1.0)
	GameState.go_to_scene(main_menu_path())

func main_menu_path():
	var main_scene = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene.begins_with("uid://"):
		var id = ResourceUID.text_to_id(main_scene)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	if main_scene != "" and ResourceLoader.exists(main_scene):
		return main_scene
	return MAIN_MENU_FALLBACK

# ---------------------------------------------------------------------------
# Settings (the same ones as on the main menu, kept by scripts/game_settings.gd)
# ---------------------------------------------------------------------------
func build_settings():
	var settings = get_tree().root.get_node_or_null("GameSettings")
	if settings == null:
		settings = GameState.settings
	if settings == null:
		settings_button.visible = false
		return
	for quality_name in settings.QUALITY_NAMES:
		quality_picker.add_item(quality_name)
	quality_picker.selected = settings.quality
	quality_picker.item_selected.connect(func(index): settings.set_quality(index))
	settings.changed.connect(func():
		quality_picker.selected = settings.quality
		fullscreen_switch.set_pressed_no_signal(settings.fullscreen))
	fullscreen_switch.button_pressed = settings.fullscreen
	fullscreen_switch.toggled.connect(func(on): settings.set_fullscreen(on))
	for channel in settings.SOUND_CHANNELS:
		var row = HBoxContainer.new()
		var label = Label.new()
		label.text = {"Master": "Volume", "Music": "Music", "Effects": "Sound effects", "Voice": "Mission radio"}[channel]
		label.custom_minimum_size = Vector2(170, 0)
		row.add_child(label)
		var slider = HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = settings.volumes[channel]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(value): settings.set_volume(channel, value))
		row.add_child(slider)
		volumes_box.add_child(row)

# ---------------------------------------------------------------------------
# A "Menu" button in each scene's own button row
# ---------------------------------------------------------------------------
func _process(_delta):
	var scene = get_tree().current_scene
	if scene == last_scene:
		return
	last_scene = scene
	if scene == null or in_main_menu():
		return
	# Give the scene a moment to build its buttons, then add ours
	for frame in 3:
		await get_tree().process_frame
	if is_instance_valid(scene) and scene == get_tree().current_scene:
		add_menu_button(scene)

func add_menu_button(scene):
	var spot = MENU_BUTTON_SPOTS.get(scene_name(), {})
	if spot.is_empty() or scene.find_child("PauseMenuButton", true, false):
		return
	var menu_button = Button.new()
	menu_button.name = "PauseMenuButton"
	menu_button.text = "Menu"
	menu_button.tooltip_text = "Pause, settings, controls and the main menu (Esc)"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.pressed.connect(open)
	if spot.has("inside_node"):
		var holder = scene.find_child(spot["inside_node"], true, false)
		if holder:
			holder.add_child(menu_button)
			return
	if spot.has("after_text"):
		var neighbor = find_button_with_text(scene, spot["after_text"])
		if neighbor and neighbor.get_parent() is BoxContainer:
			neighbor.get_parent().add_child(menu_button)
			neighbor.get_parent().move_child(menu_button, neighbor.get_index() + 1)
			return
		if neighbor:
			# A button on its own (like Abort mission): put ours just to the right of it
			neighbor.get_parent().add_child(menu_button)
			menu_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 14)
			menu_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
			menu_button.position.x = neighbor.position.x + neighbor.size.x + 10.0
			return
	menu_button.queue_free()

func find_button_with_text(node, text):
	for button in node.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null
