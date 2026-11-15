@tool
extends Control

# The little mark beside each mission directive: an empty diamond while it's still open, a green circle with a
# tick when it's done, a red circle with a cross when it can't be done any more.

@export_enum("open", "done", "failed") var state := "open":
	set(value):
		state = value
		queue_redraw()

const OPEN_COLOR = Color(0.6, 0.68, 0.78)
const DONE_COLOR = Color(0.35, 0.95, 0.55)
const FAILED_COLOR = Color(1.0, 0.42, 0.38)

func _draw():
	var middle = size / 2.0
	var radius = min(size.x, size.y) / 2.0 - 1.0
	match state:
		"done":
			draw_circle(middle, radius, Color(DONE_COLOR, 0.2))
			draw_arc(middle, radius, 0.0, TAU, 32, DONE_COLOR, 1.5, true)
			draw_polyline(PackedVector2Array([middle + Vector2(-radius * 0.45, 0.0), middle + Vector2(-radius * 0.1, radius * 0.38), middle + Vector2(radius * 0.5, -radius * 0.35)]), DONE_COLOR, 2.0, true)
		"failed":
			draw_circle(middle, radius, Color(FAILED_COLOR, 0.15))
			draw_arc(middle, radius, 0.0, TAU, 32, FAILED_COLOR, 1.5, true)
			var reach = radius * 0.38
			draw_line(middle + Vector2(-reach, -reach), middle + Vector2(reach, reach), FAILED_COLOR, 2.0, true)
			draw_line(middle + Vector2(-reach, reach), middle + Vector2(reach, -reach), FAILED_COLOR, 2.0, true)
		_:
			var corners = PackedVector2Array([middle + Vector2(0, -radius * 0.8), middle + Vector2(radius * 0.8, 0), middle + Vector2(0, radius * 0.8), middle + Vector2(-radius * 0.8, 0), middle + Vector2(0, -radius * 0.8)])
			draw_polyline(corners, OPEN_COLOR, 1.5, true)
