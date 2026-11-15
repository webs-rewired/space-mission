extends Control

# The docking camera overlay in the Docking Trainer (res://scenes/docking.tscn): the boresight cross in the
# middle of the camera view (line it up with the cross on the docking target), the predicted contact point (where
# the spacecraft will touch the port if it coasts from here), and pitch, yaw and roll gauges.
# scripts/docking.gd fills in the numbers; this only draws.

var pitch = 0.0             # degrees
var yaw = 0.0
var roll = 0.0
var angle_limit = 4.0       # degrees allowed at contact
var offset_limit = 0.2      # meters allowed at contact
var show_prediction = true
var port_on_screen = Vector2.ZERO        # where the port's center is in the camera view
var port_visible = true
var capture_radius_pixels = 20.0          # the capture zone around the port's center, at its distance
var predicted_on_screen = Vector2.ZERO    # where on the port plane the spacecraft touches if it coasts
var prediction_valid = false
var flash = 0.0             # red flash when something goes wrong
var good_color = Color(0.45, 1.0, 0.6)
var warn_color = Color(1.0, 0.78, 0.3)
var bad_color = Color(1.0, 0.45, 0.4)

func _process(delta):
	flash = max(flash - delta * 1.5, 0.0)
	if is_visible_in_tree():
		queue_redraw()

func color_for(value, limit):
	if abs(value) <= limit:
		return good_color
	if abs(value) <= limit * 2.5:
		return warn_color
	return bad_color

func _draw():
	var middle = size / 2.0
	var font = get_theme_default_font()
	var line_color = Color(0.75, 0.95, 1.0, 0.85)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.2, 0.15, flash * 0.25))
	# The boresight: a cross with a gap in the middle (the camera's own center line)
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(middle + direction * 14.0, middle + direction * 60.0, line_color, 1.5, true)
	# The capture zone around the port's center: the docking ring has to touch inside it
	if port_visible:
		var radius = clamp(capture_radius_pixels, 4.0, size.y)
		draw_arc(port_on_screen, radius, 0.0, TAU, 48, Color(good_color, 0.55), 1.2, true)
		if radius > 14.0:
			draw_string(font, port_on_screen + Vector2(radius + 4, -4), "%d cm" % int(round(offset_limit * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(good_color, 0.7))
	# Where it will touch the port plane if nobody fires a thruster from here
	if show_prediction and prediction_valid and port_visible:
		var edge = size / 2.0 - Vector2(30, 30)
		var clamped = middle + (predicted_on_screen - middle).clamp(-edge, edge)
		var miss = (predicted_on_screen - port_on_screen).length() / max(capture_radius_pixels, 1.0)
		var marker_color = good_color if miss <= 1.0 else (warn_color if miss <= 2.5 else bad_color)
		if clamped != predicted_on_screen:
			draw_circle(clamped, 6.0, marker_color)
		else:
			draw_arc(clamped, 9.0, 0.0, TAU, 24, marker_color, 2.0, true)
			draw_line(clamped + Vector2(-5, 0), clamped + Vector2(5, 0), marker_color, 1.5)
			draw_line(clamped + Vector2(0, -5), clamped + Vector2(0, 5), marker_color, 1.5)
		draw_string(font, clamped + Vector2(12, 4), "contact if you coast", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(marker_color, 0.8))
	# Pitch, yaw and roll gauges along the bottom of the camera view
	var gauge_width = 150.0
	var start_x = middle.x - gauge_width * 1.5 - 20.0
	var gauge_y = size.y - 48.0
	var gauges = [["PITCH", pitch], ["YAW", yaw], ["ROLL", roll]]
	for index in gauges.size():
		var left = start_x + index * (gauge_width + 20.0)
		var value = gauges[index][1]
		var gauge_color = color_for(value, angle_limit)
		draw_rect(Rect2(left, gauge_y, gauge_width, 6), Color(1, 1, 1, 0.12))
		var limit_width = gauge_width * angle_limit / 20.0
		draw_rect(Rect2(left + gauge_width / 2.0 - limit_width, gauge_y, limit_width * 2.0, 6), Color(good_color, 0.25))
		var marker_x = left + gauge_width / 2.0 + clamp(value / 10.0, -1.0, 1.0) * gauge_width / 2.0
		draw_rect(Rect2(marker_x - 2, gauge_y - 5, 4, 16), gauge_color)
		draw_string(font, Vector2(left, gauge_y - 9), "%s %+.1f°" % [gauges[index][0], value], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, gauge_color)
