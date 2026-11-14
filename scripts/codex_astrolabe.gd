@tool
extends Control

# The engraved rings behind the globe in the destination codex: two thin circles with tick marks like an
# astrolabe or a clock face, and a diamond at each quarter. They turn very slowly.
# draw_in() sweeps the rings in around the circle; pulse() makes them flash and swell once (a new world chosen).

@export var ring_color := Color(0.78, 0.65, 0.42, 0.55)
@export var turn_speed := 0.02   # radians per second

var turn = 0.0
var drawn := 1.0     # how much of the circle is drawn (0 to 1)
var glow := 0.0      # extra brightness and size from a pulse (0 to 1)

func _process(delta):
	if not is_visible_in_tree():
		return
	turn = fmod(turn + delta * turn_speed, TAU)
	queue_redraw()

func draw_in(delay := 0.0, duration := 1.1):
	drawn = 0.0
	var tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_interval(delay)
	tween.tween_property(self, "drawn", 1.0, duration)

func pulse():
	glow = 1.0
	create_tween().tween_property(self, "glow", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _draw():
	var center = size / 2.0
	var radius = (min(size.x, size.y) / 2.0 - 8.0) * (1.0 + glow * 0.025)
	var color = Color(ring_color, min(ring_color.a * (1.0 + glow * 0.9), 1.0))
	var sweep = TAU * drawn
	var start = -PI / 2.0 + turn
	draw_arc(center, radius, start, start + sweep, 128, color, 1.0 + glow, true)
	draw_arc(center, radius * 0.93, start, start + sweep, 128, Color(color, color.a * 0.5), 1.0, true)
	draw_arc(center, radius * 0.7, -start, -start - sweep, 128, Color(color, color.a * 0.25), 1.0, true)
	# Tick marks between the two outer rings: long ones every 30 degrees, short ones every 5
	var ticks_shown = int(72 * drawn)
	for tick in ticks_shown:
		var angle = start + tick * TAU / 72.0
		var direction = Vector2(cos(angle), sin(angle))
		var inner = radius * (0.93 if tick % 6 == 0 else 0.965)
		draw_line(center + direction * inner, center + direction * radius, Color(color, color.a * (0.9 if tick % 6 == 0 else 0.45)), 1.0, true)
	# A diamond at each quarter of the inner ring, turning the other way
	if drawn > 0.95:
		for quarter in 4:
			var angle = -turn * 1.5 + quarter * TAU / 4.0
			var place = center + Vector2(cos(angle), sin(angle)) * radius * 0.7
			var half_size = 4.0 + glow * 2.0
			var corners = PackedVector2Array([place + Vector2(0, -half_size), place + Vector2(half_size, 0), place + Vector2(0, half_size), place + Vector2(-half_size, 0), place + Vector2(0, -half_size)])
			draw_polyline(corners, color, 1.0, true)
