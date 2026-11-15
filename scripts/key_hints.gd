extends HFlowContainer

# A row of key caps with what each key does, the same look in every minigame (res://scenes/key_hints.tscn):
#   [W] [S] throttle    [Space] ignite
# Set hints to a list of [keys, what they do], where keys are separated by spaces ("W S", "Space", "← →").
# A key can be lit up while it's held (light_key) so players see their input landing.

@export var hints: Array = []:
	set(value):
		hints = value
		if is_inside_tree():
			rebuild()

const KEY_COLOR = Color(0.11, 0.13, 0.19, 0.95)
const KEY_EDGE = Color(0.55, 0.65, 0.8, 0.8)
const LIT_COLOR = Color(1.0, 0.82, 0.35, 1.0)

var key_panels = {}   # key text → its PanelContainer

func _ready():
	add_theme_constant_override("h_separation", 14)
	add_theme_constant_override("v_separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rebuild()

func rebuild():
	for old in get_children():
		remove_child(old)
		old.queue_free()
	key_panels = {}
	for hint in hints:
		var group = HBoxContainer.new()
		group.add_theme_constant_override("separation", 4)
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for key in str(hint[0]).split(" ", false):
			group.add_child(make_key(key))
		var words = Label.new()
		words.text = hint[1]
		words.add_theme_font_size_override("font_size", 12)
		words.add_theme_color_override("font_color", Color(0.75, 0.8, 0.88))
		words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		group.add_child(words)
		add_child(group)

func make_key(key):
	var cap = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = KEY_COLOR
	style.border_color = KEY_EDGE
	style.set_border_width_all(1)
	style.border_width_bottom = 2
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", style)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label = Label.new()
	label.text = key
	label.theme_type_variation = "DataLabel"
	label.add_theme_font_size_override("font_size", 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = 12
	cap.add_child(label)
	key_panels[key] = cap
	return cap

# Lights a key cap while its key is held
func light_key(key, lit):
	if not key_panels.has(key):
		return
	var style = key_panels[key].get_theme_stylebox("panel")
	style.border_color = LIT_COLOR if lit else KEY_EDGE
	style.bg_color = Color(0.35, 0.27, 0.08, 0.95) if lit else KEY_COLOR
