extends Control

# The rover's terrain map (on the drive screen in res://scenes/surface_view.tscn): the planned driving area, the
# soft sand patches to stay out of, the science targets (blue rock samples, a green place to search for life, an
# orange seismometer site; gray once studied), the lander, the rover's tracks, and
# the rover itself, always pointing up the map. surface_view.gd fills in the numbers; this only draws.

var area_radius = 215.0          # meters: the mission's planned driving area around the landing spot
var view_radius = 45.0           # meters from the rover to the edge of the map
var rover_place = Vector2.ZERO   # meters (world x, z)
var rover_heading = 0.0          # radians (the rover faces sin(heading), cos(heading) in x, z)
var targets = []                 # [place (Vector2), studied (bool), name, kind ("sample", "life", "seismic")]
const KIND_COLORS = {"sample": Color(0.4, 0.9, 1.0), "life": Color(0.45, 1.0, 0.55), "seismic": Color(1.0, 0.7, 0.3)}
var sand_patches = []            # [place (Vector2), radius]
var track = PackedVector2Array() # places the rover has been
var sand_color = Color(0.85, 0.68, 0.38, 0.45)

func _process(_delta):
	if is_visible_in_tree():
		queue_redraw()

# A world place on the map: heading-up, centered on the rover
func to_map(place):
	var forward = Vector2(sin(rover_heading), cos(rover_heading))
	var right = Vector2(-cos(rover_heading), sin(rover_heading))
	var offset = place - rover_place
	var radius = min(size.x, size.y) / 2.0 - 6.0
	return size / 2.0 + Vector2(offset.dot(right), -offset.dot(forward)) * radius / view_radius

func _draw():
	var middle = size / 2.0
	var radius = min(size.x, size.y) / 2.0 - 6.0
	var font = get_theme_default_font()
	var pixels_per_meter = radius / view_radius
	draw_circle(middle, radius + 4.0, Color(0.03, 0.05, 0.08, 0.85))
	# Only what fits inside the round map is drawn
	var inside = func(point): return point.distance_to(middle) <= radius
	for patch in sand_patches:
		var center = to_map(patch[0])
		if center.distance_to(middle) - patch[1] * pixels_per_meter < radius:
			var patch_radius = min(patch[1] * pixels_per_meter, radius)
			draw_circle(center, patch_radius, sand_color)
	# The edge of the planned driving area
	var edge = PackedVector2Array()
	for step in 97:
		var angle = TAU * step / 96.0
		var point = to_map(Vector2(cos(angle), sin(angle)) * area_radius)
		if inside.call(point):
			edge.append(point)
		elif edge.size() >= 2:
			draw_polyline(edge, Color(1.0, 0.45, 0.35, 0.8), 2.0, true)
			edge = PackedVector2Array()
		else:
			edge = PackedVector2Array()
	if edge.size() >= 2:
		draw_polyline(edge, Color(1.0, 0.45, 0.35, 0.8), 2.0, true)
	# Tracks
	var trail = PackedVector2Array()
	for place in track:
		var point = to_map(place)
		if inside.call(point):
			trail.append(point)
	if trail.size() >= 2:
		draw_polyline(trail, Color(0.75, 0.85, 1.0, 0.45), 1.5, true)
	# The lander, where the mission started
	var lander = to_map(Vector2.ZERO)
	if inside.call(lander):
		draw_rect(Rect2(lander - Vector2(4, 4), Vector2(8, 8)), Color(0.75, 0.8, 0.9))
	# Science targets: diamonds colored like their beacons, gray once studied; an arrow at the edge for ones off the map
	for target in targets:
		var point = to_map(target[0])
		var color = Color(0.55, 0.58, 0.62) if target[1] else KIND_COLORS.get(target[3] if target.size() > 3 else "sample", Color(1.0, 0.82, 0.35))
		if inside.call(point):
			var diamond = PackedVector2Array([point + Vector2(0, -6), point + Vector2(6, 0), point + Vector2(0, 6), point + Vector2(-6, 0)])
			draw_colored_polygon(diamond, color)
		elif not target[1]:
			var direction = (point - middle).normalized()
			var tip = middle + direction * (radius - 2.0)
			var side = Vector2(-direction.y, direction.x)
			draw_colored_polygon(PackedVector2Array([tip, tip - direction * 9.0 + side * 5.0, tip - direction * 9.0 - side * 5.0]), color)
	# The rover, pointing up
	draw_colored_polygon(PackedVector2Array([middle + Vector2(0, -9), middle + Vector2(6, 7), middle + Vector2(0, 3), middle + Vector2(-6, 7)]), Color(0.45, 1.0, 0.6))
	draw_arc(middle, radius + 4.0, 0.0, TAU, 64, Color(0.45, 0.8, 1.0, 0.5), 1.5, true)
	draw_string(font, Vector2(middle.x - radius, size.y - 2.0), "%d m" % int(view_radius), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.65, 0.72))
