extends Control

# The close-up of the flyby in the Gravity-Assist Planner: the planet, the spacecraft coming in on one straight
# line (its v-infinity direction, seen from the planet), swinging around the closest point, and leaving on
# another, bent by the angle δ. The arrow shows the planet's own motion around the Sun.

var planet_color = Color(0.85, 0.8, 0.6)
var planet_radius_km = 6051.8
var closest_km = 6351.8
var incoming_direction = Vector2(0, 1)   # the spacecraft's velocity relative to the planet, coming in
var outgoing_direction = Vector2(1, 0)   # ...and going out
var planet_motion = Vector2(0, 1)         # which way the planet moves around the Sun (screen up)
var turn_side = 1.0

func _process(_delta):
	if is_visible_in_tree():
		queue_redraw()

func _draw():
	var middle = size / 2.0
	var font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.07))
	# Scale: the closest pass sits at a fixed size on screen, with the planet drawn in proportion inside it
	var pass_pixels = min(size.x, size.y) * 0.18
	var planet_pixels = clamp(pass_pixels * planet_radius_km / closest_km, 3.0, pass_pixels)
	draw_circle(middle, planet_pixels, planet_color.darkened(0.3))
	draw_circle(middle - Vector2(planet_pixels, planet_pixels) * 0.2, planet_pixels * 0.8, planet_color)
	# The path: in along one line, around the closest point, out along the other
	var screen_in = Vector2(incoming_direction.x, -incoming_direction.y).normalized()
	var screen_out = Vector2(outgoing_direction.x, -outgoing_direction.y).normalized()
	# The closest point is on the side away from the bend: the planet pulls the path around toward itself
	var bisector = (screen_in - screen_out).normalized()
	var closest_point = middle + bisector * pass_pixels
	var far = min(size.x, size.y) * 0.6
	var start = closest_point - screen_in * far
	var finish = closest_point + screen_out * far
	var curve = PackedVector2Array()
	for step in 41:
		var t = step / 40.0
		# A smooth curve through the closest point (the real path is a hyperbola)
		var control = closest_point * 2.0 - (start + finish) * 0.5
		var a = start.lerp(control, t)
		var b = control.lerp(finish, t)
		curve.append(a.lerp(b, t))
	draw_polyline(curve, Color(0.45, 0.85, 1.0), 2.0, true)
	draw_circle(closest_point, 3.0, Color(1.0, 0.82, 0.35))
	draw_string(font, closest_point + bisector * 10.0 + Vector2(4, 4), "closest", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.82, 0.35))
	# Arrow heads
	for pair in [[start.lerp(closest_point, 0.4), screen_in], [closest_point.lerp(finish, 0.6), screen_out]]:
		var tip = pair[0]
		var direction = pair[1]
		draw_line(tip, tip - direction.rotated(0.4) * 9.0, Color(0.45, 0.85, 1.0), 2.0, true)
		draw_line(tip, tip - direction.rotated(-0.4) * 9.0, Color(0.45, 0.85, 1.0), 2.0, true)
	# The planet's motion
	var motion = Vector2(planet_motion.x, -planet_motion.y).normalized()
	var arrow_start = Vector2(18, size.y - 20)
	draw_line(arrow_start, arrow_start + motion * 30.0, Color(1, 1, 1, 0.5), 2.0, true)
	draw_line(arrow_start + motion * 30.0, arrow_start + motion * 30.0 - motion.rotated(0.5) * 7.0, Color(1, 1, 1, 0.5), 2.0, true)
	draw_line(arrow_start + motion * 30.0, arrow_start + motion * 30.0 - motion.rotated(-0.5) * 7.0, Color(1, 1, 1, 0.5), 2.0, true)
	draw_string(font, arrow_start + Vector2(36, 4), "planet's motion", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.5))
