@tool
extends Control

# A thin gold rule with a diamond in the middle, fading out toward both ends: the dividers of the destination
# codex (res://scenes/destination_codex.tscn), in the style of the menus in Lies of P.
# draw_in() makes it draw itself outward from the middle.

@export var line_color := Color(0.78, 0.65, 0.42, 0.85)
@export var diamond_in_middle := true
@export var diamonds_at_ends := false
@export var fade_toward_ends := true

var drawn := 1.0:   # how much of the line is drawn, from the middle out (0 to 1)
	set(value):
		drawn = value
		queue_redraw()

func _ready():
	resized.connect(queue_redraw)

func draw_in(delay := 0.0, duration := 0.7):
	drawn = 0.0
	var tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_interval(delay)
	tween.tween_property(self, "drawn", 1.0, duration)

func _draw():
	var middle_height = size.y / 2.0
	var width = size.x
	var reach = width / 2.0 * drawn
	# The line: drawn in short pieces so it can fade out toward the ends
	var pieces = 48
	for piece in pieces:
		var start = width * piece / pieces
		var finish = width * (piece + 1) / pieces
		start = clamp(start, width / 2.0 - reach, width / 2.0 + reach)
		finish = clamp(finish, width / 2.0 - reach, width / 2.0 + reach)
		if finish <= start:
			continue
		var distance_from_middle = abs((start + finish) / 2.0 - width / 2.0) / (width / 2.0)
		var strength = 1.0 - pow(distance_from_middle, 2.0) if fade_toward_ends else 1.0
		draw_line(Vector2(start, middle_height), Vector2(finish, middle_height), Color(line_color, line_color.a * strength), 1.0)
	var diamond_strength = clamp(drawn * 2.0 - 0.4, 0.0, 1.0)
	if diamond_in_middle and diamond_strength > 0.0:
		draw_diamond(Vector2(width / 2.0, middle_height), 5.0 * diamond_strength, true)
		draw_diamond(Vector2(width / 2.0 - 14.0, middle_height), 2.0 * diamond_strength, true)
		draw_diamond(Vector2(width / 2.0 + 14.0, middle_height), 2.0 * diamond_strength, true)
	if diamonds_at_ends and drawn >= 0.98:
		draw_diamond(Vector2(3.0, middle_height), 3.0, false)
		draw_diamond(Vector2(width - 3.0, middle_height), 3.0, false)

func draw_diamond(center, half_size, filled):
	if half_size < 0.5:
		return
	var corners = PackedVector2Array([center + Vector2(0, -half_size), center + Vector2(half_size, 0), center + Vector2(0, half_size), center + Vector2(-half_size, 0)])
	if filled:
		# A dark middle with a gold edge, like an inlay
		draw_colored_polygon(corners, Color(0.06, 0.05, 0.04, 1.0))
	corners.append(corners[0])
	draw_polyline(corners, line_color, 1.0, true)
	if filled and half_size > 3.0:
		draw_circle(center, 1.3, line_color)
