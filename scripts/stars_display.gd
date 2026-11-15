@tool
extends Control

# A row of stars: filled for each directive completed (or the best ever on a destination), hollow for the rest.
# pop_stars() fills them in one at a time with a bounce, for the mission report.

@export var star_count := 3
@export var filled := 0:
	set(value):
		filled = value
		queue_redraw()
@export var star_color := Color(1.0, 0.82, 0.35)

var star_scales = [1.0, 1.0, 1.0, 1.0, 1.0]

func pop_stars(how_many, delay := 0.0):
	filled = 0
	for index in how_many:
		var tween = create_tween()
		tween.tween_interval(delay + index * 0.35)
		tween.tween_callback(func():
			filled = index + 1
			star_scales[index] = 1.8)
		tween.tween_method(func(value):
			star_scales[index] = value
			queue_redraw(), 1.8, 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _draw():
	var gap = size.x / max(star_count, 1)
	var radius = min(gap * 0.42, size.y * 0.48)
	for index in star_count:
		var middle = Vector2(gap * (index + 0.5), size.y / 2.0)
		var points = PackedVector2Array()
		var star_radius = radius * star_scales[min(index, star_scales.size() - 1)]
		for point in 10:
			var angle = -PI / 2.0 + point * PI / 5.0
			var reach = star_radius if point % 2 == 0 else star_radius * 0.45
			points.append(middle + Vector2(cos(angle), sin(angle)) * reach)
		if index < filled:
			draw_colored_polygon(points, star_color)
		points.append(points[0])
		draw_polyline(points, star_color if index < filled else Color(star_color, 0.45), 1.3, true)
