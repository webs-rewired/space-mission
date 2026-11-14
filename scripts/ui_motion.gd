class_name UiMotion
extends RefCounted

# Screen animations in the style of the Webs With U website: headlines whose letters rise into place from behind
# an invisible edge (one after another, left to right), panels that glide in and fade up one after another,
# menu items that slide over with an accent bar when the mouse is on them, and numbers that count up.
#
# Every function here is static, so any script can call them without making anything first:
#   UiMotion.reveal_text($Title)                      the letters of a Label (or Button) rise into place
#   UiMotion.slide_in($Panel, 0.2)                    a panel glides up and fades in, after 0.2 seconds
#   UiMotion.stagger($List.get_children(), 0.3)       the same for each item of a list, one after another
#   UiMotion.count_up($Score, 87, func(value): return "%d%%" % value)
#   UiMotion.pop_in($Grade, 0.5)                      grows from a little smaller with a small bounce
#   UiMotion.add_hover_slide(button)                  the text slides right and an accent bar shows on hover
#   UiMotion.enter_scene(scene)                       every panel on screen glides in from its nearest edge
#
# All the timing uses one easing curve (fast at first, then settling slowly), like the website.

const ACCENT = Color(0.45, 0.8, 1.0)

# The letter-rise effect. Each letter starts below its place and rises, letters further right starting a little
# later; anything below the label's bottom edge is hidden, so the letters seem to come up from behind an edge.
const REVEAL_SHADER_CODE = """
shader_type canvas_item;
uniform float progress = 1.0;        // 0: hidden below the edge, 1: in place
uniform float rise = 40.0;           // how far below its place each letter starts, in pixels
uniform float label_width = 600.0;   // the label's width, for the left-to-right wave
uniform float spread = 0.55;         // 0: every letter together, higher: more of a wave
uniform float edge = 9999.0;         // the hidden edge: the bottom of the label
varying float height_here;
void vertex() {
	float wave = clamp(progress * (1.0 + spread) - (VERTEX.x / max(label_width, 1.0)) * spread, 0.0, 1.0);
	float settled = 1.0 - pow(1.0 - wave, 4.0);
	VERTEX.y += (1.0 - settled) * rise;
	COLOR.a *= clamp(settled * 1.6, 0.0, 1.0);
	height_here = VERTEX.y;
}
void fragment() {
	if (height_here > edge) {
		discard;
	}
}
"""

static var reveal_shader: Shader = null

# The letters of a Label, RichTextLabel or flat Button rise into place
static func reveal_text(control: Control, delay := 0.0, duration := 0.9, spread := 0.55) -> void:
	if not is_instance_valid(control):
		return
	if reveal_shader == null:
		reveal_shader = Shader.new()
		reveal_shader.code = REVEAL_SHADER_CODE
	var reveal_material := ShaderMaterial.new()
	reveal_material.shader = reveal_shader
	reveal_material.set_shader_parameter("progress", 0.0)
	control.material = reveal_material
	var tween := control.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_callback(func():
		# Sizes are only known once the screen has been laid out, so they are read when the animation starts
		reveal_material.set_shader_parameter("label_width", max(control.size.x, 1.0))
		reveal_material.set_shader_parameter("rise", max(control.size.y, 20.0) * 0.9)
		reveal_material.set_shader_parameter("edge", control.size.y + 6.0)
		reveal_material.set_shader_parameter("spread", spread))
	tween.tween_method(func(value): reveal_material.set_shader_parameter("progress", value), 0.0, 1.0, duration)
	tween.tween_callback(func():
		if is_instance_valid(control) and control.material == reveal_material:
			control.material = null)   # done: nothing left to draw specially

# A control glides from a little way off (offset) back to its place while fading in
static func slide_in(control: Control, delay := 0.0, offset := Vector2(0, 26), duration := 0.7) -> void:
	if not is_instance_valid(control):
		return
	control.modulate.a = 0.0
	var tween := control.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	else:
		tween.tween_interval(0.01)   # (wait for the layout, so the resting place is known)
	tween.tween_callback(func():
		var resting_place := control.position
		control.position = resting_place + offset
		var glide := control.create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		glide.tween_property(control, "position", resting_place, duration)
		glide.tween_property(control, "modulate:a", 1.0, duration * 0.7)
		# Inside a container (a list), let the container put it back exactly in its place afterwards, in case
		# the list changed while it was gliding
		glide.chain().tween_callback(func():
			if is_instance_valid(control) and control.get_parent() is Container:
				control.get_parent().queue_sort()))

# slide_in for several controls, one after another
static func stagger(controls: Array, delay := 0.0, step := 0.07, offset := Vector2(0, 22), duration := 0.7) -> void:
	var index := 0
	for control in controls:
		if control is Control and control.visible:
			slide_in(control, delay + index * step, offset, duration)
			index += 1

# A number counts up from zero. make_text turns the number into what the label shows.
static func count_up(label: Control, to_value: float, make_text: Callable, delay := 0.0, duration := 1.2) -> void:
	if not is_instance_valid(label):
		return
	label.set("text", make_text.call(0.0))
	var tween := label.create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(func(value): label.set("text", make_text.call(value)), 0.0, to_value, duration)

# Grows from a little smaller, with a small bounce at the end
static func pop_in(control: Control, delay := 0.0, duration := 0.55) -> void:
	if not is_instance_valid(control):
		return
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.tween_interval(max(delay, 0.01))
	tween.tween_callback(func():
		control.pivot_offset = control.size / 2.0
		control.scale = Vector2.ONE * 0.8
		var grow := control.create_tween().set_parallel(true)
		grow.tween_property(control, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		grow.tween_property(control, "modulate:a", 1.0, duration * 0.5))

# For flat text buttons (like the main menu's): on hover the text slides right and a thin accent bar grows at
# its left. Uses its own empty style box for every state, so the text can be moved by changing the margin.
static func add_hover_slide(button: Button, accent := ACCENT, slide := 18.0) -> void:
	var style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(style_name, style)
	var bar := ColorRect.new()
	bar.color = accent
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size = Vector2(3, 1)
	bar.scale = Vector2(1, 0)
	button.add_child(bar)
	var move := func(on: bool):
		var height := button.size.y * 0.5
		bar.size = Vector2(3, height)
		bar.position = Vector2(0, (button.size.y - height) / 2.0)
		bar.pivot_offset = Vector2(0, height / 2.0)
		var tween := button.create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(style, "content_margin_left", slide if on else 0.0, 0.35)
		tween.tween_property(bar, "scale:y", 1.0 if on else 0.0, 0.3)
	button.mouse_entered.connect(move.bind(true))
	button.mouse_exited.connect(move.bind(false))
	button.focus_entered.connect(move.bind(true))
	button.focus_exited.connect(move.bind(false))

# A new screen's panels glide in from the nearest edge of the screen, one after another: called by the loading
# screen as it lifts away. Only panels sitting straight on a CanvasLayer (the screen's own panels) move, and
# anything filling the whole screen is left alone. A scene can skip this by having a method plays_own_entrance().
static func enter_scene(scene: Node) -> void:
	if scene == null or scene.has_method("plays_own_entrance"):
		return
	var panels := []
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		if not layer.visible:
			continue
		for child in layer.get_children():
			if not (child is Control) or not child.visible or child.name.begins_with("Pause"):
				continue
			if not (child is PanelContainer or child is Panel or child is BoxContainer or child is GridContainer or child is MarginContainer or child is Button):
				continue
			var screen_size: Vector2 = child.get_viewport_rect().size
			if child.size.x >= screen_size.x * 0.9 and child.size.y >= screen_size.y * 0.9:
				continue
			panels.append(child)
	panels.sort_custom(func(first, second): return first.position.y + first.position.x * 0.2 < second.position.y + second.position.x * 0.2)
	var index := 0
	for panel in panels:
		var screen_size: Vector2 = panel.get_viewport_rect().size
		var middle: Vector2 = panel.position + panel.size / 2.0
		var offset := Vector2.ZERO
		var to_sides: float = min(middle.x, screen_size.x - middle.x)
		var to_top_bottom: float = min(middle.y, screen_size.y - middle.y)
		if to_sides < to_top_bottom:
			offset.x = -40.0 if middle.x < screen_size.x / 2.0 else 40.0
		else:
			offset.y = -30.0 if middle.y < screen_size.y / 2.0 else 30.0
		slide_in(panel, 0.05 + index * 0.06, offset, 0.8)
		index += 1
