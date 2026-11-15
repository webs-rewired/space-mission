extends Control

# The map of the Orbital Insertion minigame (res://scenes/orbital_insertion.tscn): the world in the middle,
# the target orbit as a dashed gold band, the path the spacecraft is on right now (cyan, updating live as the
# engine fires), where it has been, and the spacecraft with its engine flame. orbital_insertion.gd fills in the
# numbers; this only draws them. Distances are in km; km_per_pixel sets the zoom.

const PATH_COLOR = Color(0.45, 0.85, 1.0)
const TARGET_COLOR = Color(1.0, 0.82, 0.35)
const ESCAPE_COLOR = Color(1.0, 0.5, 0.4)
const CRAFT_COLOR = Color(1.0, 0.95, 0.85)

@onready var planet_disk: TextureRect = $Planet

var world_radius = 3389.5
var air_height = 0.0
var km_per_pixel = 50.0
var craft_position = Vector2.ZERO
var craft_velocity = Vector2.ZERO
var orbit = {}
var target_low = 3500.0      # the target band: periapsis no lower than this (km from the center)...
var target_high = 15000.0    # ...and apoapsis no higher than this
var target_periapsis = 3700.0
var trail = PackedVector2Array()
var burning = false
var interlock_warning = 0.0

func center():
	return size / 2.0 + Vector2(-size.x * 0.06, 0.0)

func to_screen(place):
	return center() + Vector2(place.x, -place.y) / km_per_pixel

func _process(_delta):
	if not is_visible_in_tree():
		return
	# The world's real map on a ball, the right size for the zoom
	var disk_size = Vector2.ONE * world_radius * 2.0 / km_per_pixel
	planet_disk.size = disk_size
	planet_disk.position = center() - disk_size / 2.0
	queue_redraw()

func _draw():
	var middle = center()
	# Faint distance rings, like a radar screen
	for ring in [2.0, 4.0, 8.0]:
		draw_arc(middle, world_radius * ring / km_per_pixel, 0.0, TAU, 96, Color(1, 1, 1, 0.05), 1.0, true)
	# The air: a thin glow around the world, and the safety line the flight computer won't let you go below
	if air_height > 0.0:
		draw_arc(middle, (world_radius + air_height) / km_per_pixel, 0.0, TAU, 96, Color(0.5, 0.75, 1.0, 0.35), 2.0, true)
	# The target: a gold band between the lowest periapsis and the highest apoapsis allowed
	draw_dashed_circle(middle, target_periapsis / km_per_pixel, TARGET_COLOR, 0.9)
	draw_dashed_circle(middle, target_high / km_per_pixel, Color(TARGET_COLOR, 0.35), 0.9)
	# Where the spacecraft has been
	if trail.size() >= 2:
		var screen_trail = PackedVector2Array()
		for point in trail:
			screen_trail.append(to_screen(point))
		draw_polyline(screen_trail, Color(1, 1, 1, 0.25), 1.5, true)
	# The path it's on now: cyan if gravity has caught it, red while it would still escape
	if not orbit.is_empty():
		var farthest = max(size.length() * km_per_pixel, world_radius * 3.0)
		var points = load("res://scripts/orbit_physics.gd").conic_points(orbit, farthest)
		if points.size() >= 2:
			var screen_points = PackedVector2Array()
			for point in points:
				screen_points.append(to_screen(point))
			draw_polyline(screen_points, PATH_COLOR if orbit["captured"] else ESCAPE_COLOR, 2.0, true)
		# Periapsis and apoapsis markers
		var turn = orbit["periapsis_angle"]
		draw_marker(to_screen(Vector2(cos(turn), sin(turn)) * orbit["periapsis"]), "Pe %s km" % format_km(orbit["periapsis"] - world_radius), PATH_COLOR)
		if orbit["captured"] and orbit["apoapsis"] < farthest:
			draw_marker(to_screen(-Vector2(cos(turn), sin(turn)) * orbit["apoapsis"]), "Ap %s km" % format_km(orbit["apoapsis"] - world_radius), PATH_COLOR)
	# The spacecraft: a small diamond pointing the way it's going, and a flame behind it while the engine fires
	var craft = to_screen(craft_position)
	var heading = Vector2(craft_velocity.x, -craft_velocity.y).normalized()
	var side = Vector2(-heading.y, heading.x)
	if burning:
		var flicker = 18.0 + randf() * 8.0
		draw_colored_polygon(PackedVector2Array([craft + heading * 6.0 + side * 4.0, craft + heading * (6.0 + flicker), craft + heading * 6.0 - side * 4.0]), Color(1.0, 0.7, 0.3, 0.9))
	draw_colored_polygon(PackedVector2Array([craft + heading * 8.0, craft + side * 5.0, craft - heading * 6.0, craft - side * 5.0]), CRAFT_COLOR)
	draw_line(craft, craft + heading * 34.0, Color(1, 1, 1, 0.4), 1.0, true)
	if interlock_warning > 0.0:
		draw_arc(middle, (world_radius + air_height) / km_per_pixel, 0.0, TAU, 96, Color(1.0, 0.4, 0.3, interlock_warning), 3.0, true)

func draw_dashed_circle(middle, radius, color, strength):
	var dashes = 72
	for dash in dashes:
		if dash % 2 == 0:
			var start = dash * TAU / dashes
			draw_arc(middle, radius, start, start + TAU / dashes, 4, Color(color, color.a * strength), 1.5, true)

func draw_marker(place, words, color):
	draw_circle(place, 3.5, color)
	draw_string(get_theme_default_font(), place + Vector2(8, -6), words, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

static func format_km(kilometers):
	if kilometers >= 100000.0:
		return "%s thousand" % str(int(round(kilometers / 1000.0)))
	var digits = str(int(round(kilometers)))
	var result = ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return digits + result
