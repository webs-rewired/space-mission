extends Control

# A small moving drawing for the loading screen (res://scenes/loading_screen.tscn): a planet with a tilted orbit
# around it and a spacecraft going around, leaving a fading trail, so the screen never looks frozen.

const ACCENT = Color(0.45, 0.8, 1.0)
const TRAIL_POINTS = 40

var angle = 0.0

func _process(delta):
	if not is_visible_in_tree():
		return
	angle = fmod(angle + delta * 1.6, TAU)
	queue_redraw()

func orbit_point(at_angle, center, radius):
	# A tilted circle: wide and flat, so it looks like an orbit seen from a little above
	return center + Vector2(cos(at_angle) * radius, sin(at_angle) * radius * 0.32).rotated(-0.22)

func _draw():
	var center = size / 2.0
	var radius = min(size.x * 0.45, size.y * 1.2)
	var planet_radius = min(size.y * 0.22, radius * 0.25)
	# The back half of the orbit goes behind the planet
	var back_half = PackedVector2Array()
	var front_half = PackedVector2Array()
	for step in 49:
		var point_angle = PI + step / 48.0 * PI
		back_half.append(orbit_point(point_angle, center, radius))
		front_half.append(orbit_point(step / 48.0 * PI, center, radius))
	draw_polyline(back_half, Color(ACCENT, 0.25), 1.2, true)
	# The planet: lit from the upper left
	draw_circle(center, planet_radius, Color(0.08, 0.16, 0.28))
	draw_circle(center + Vector2(-planet_radius, -planet_radius) * 0.18, planet_radius * 0.82, Color(0.16, 0.34, 0.55))
	draw_arc(center, planet_radius, 0.0, TAU, 48, Color(ACCENT, 0.5), 1.0, true)
	draw_polyline(front_half, Color(ACCENT, 0.4), 1.2, true)
	# The trail and the spacecraft (hidden while it's behind the planet)
	for index in TRAIL_POINTS:
		var trail_angle = angle - index * 0.035
		var place = orbit_point(trail_angle, center, radius)
		if sin(trail_angle) < 0.0 and place.distance_to(center) < planet_radius:
			continue
		draw_circle(place, 2.2 * (1.0 - float(index) / TRAIL_POINTS), Color(ACCENT, 0.7 * (1.0 - float(index) / TRAIL_POINTS)))
	var craft = orbit_point(angle, center, radius)
	if not (sin(angle) < 0.0 and craft.distance_to(center) < planet_radius):
		draw_circle(craft, 3.5, Color(1.0, 0.92, 0.7))
		draw_circle(craft, 7.0, Color(1.0, 0.9, 0.6, 0.18))
