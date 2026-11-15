extends Control

# The map of the Gravity-Assist Planner (res://scenes/gravity_assist.tscn): the Sun, the planets' orbits, the
# destination's orbit (gold), the spacecraft's path in (dim) and the path the flyby sends it on (bright).
# gravity_assist.gd fills in the numbers; this only draws. Distances are km from the Sun, drawn to scale.

const ORBITS = {"Mercury": 0.387, "Venus": 0.723, "Earth": 1.0, "Mars": 1.524, "Jupiter": 5.203, "Saturn": 9.537, "Uranus": 19.19, "Neptune": 30.07, "Pluto": 39.48}
const AU_KM = 149597870.7

var span_km = 8.0 * AU_KM         # the distance from the Sun to the edge of the map
var flyby_planet = "Venus"
var flyby_radius_km = 0.723 * AU_KM
var target_radius_km = 5.2 * AU_KM
var target_name = "Jupiter"
var path_in = PackedVector2Array()
var path_out = PackedVector2Array()
var reaches = false
var pulse = 0.0
var planet_disc: TextureRect      # the flyby planet, drawn as a little textured globe (gravity_assist.gd sets it)
var travel = -1.0                 # the flyby playing out: 0 to 1 along the path in, 1 to 2 along the path out
var stars = []                    # [place (share of the map), brightness]

func _ready():
	var random = RandomNumberGenerator.new()
	random.seed = 4242
	for index in 160:
		stars.append([Vector2(random.randf(), random.randf()), random.randf_range(0.15, 0.6)])

func _process(delta):
	pulse += delta
	if is_visible_in_tree():
		queue_redraw()

func to_screen(place_km):
	var middle = size / 2.0
	var scale_factor = min(size.x, size.y) * 0.47 / span_km
	return middle + Vector2(place_km.x, -place_km.y) * scale_factor

func _draw():
	var middle = size / 2.0
	var scale_factor = min(size.x, size.y) * 0.47 / span_km
	var font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06))
	for star in stars:
		draw_circle(star[0] * size, 0.8, Color(1, 1, 1, star[1] * (0.75 + 0.25 * sin(pulse * 2.0 + star[1] * 20.0))))
	for planet in ORBITS:
		var radius = ORBITS[planet] * AU_KM * scale_factor
		if radius > min(size.x, size.y) * 0.6 or radius < 4.0:
			continue
		draw_arc(middle, radius, 0.0, TAU, 128, Color(1, 1, 1, 0.12), 1.0, true)
		# (no name where the orbits crowd together near the Sun, or where the flyby planet and target have labels)
		if radius < 34.0 or planet == flyby_planet or abs(ORBITS[planet] * AU_KM - target_radius_km) < 0.05 * AU_KM:
			continue
		draw_string(font, middle + Vector2(radius * 0.71, -radius * 0.71) + Vector2(4, 0), planet, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.35))
	# The destination's orbit
	var target_radius = target_radius_km * scale_factor
	draw_arc(middle, target_radius, 0.0, TAU, 160, Color(1.0, 0.82, 0.35, 0.55 + 0.2 * sin(pulse * 3.0)), 2.0, true)
	draw_string(font, middle + Vector2(-target_radius * 0.71, -target_radius * 0.71) + Vector2(-40, -6), target_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.82, 0.35))
	# The Sun, with a soft glow
	for ring in 6:
		draw_circle(middle, 9.0 + ring * 5.0, Color(1.0, 0.65, 0.25, 0.06))
	draw_circle(middle, 7.0, Color(1.0, 0.88, 0.5))
	# The paths
	if path_in.size() >= 2:
		var screen_in = PackedVector2Array()
		for point in path_in:
			screen_in.append(to_screen(point))
		draw_polyline(screen_in, Color(0.6, 0.7, 0.85, 0.45), 1.5, true)
	if path_out.size() >= 2:
		var screen_out = PackedVector2Array()
		for point in path_out:
			screen_out.append(to_screen(point))
		var path_color = Color(0.45, 1.0, 0.6) if reaches else Color(1.0, 0.55, 0.45)
		draw_polyline(screen_out, Color(path_color, 0.25), 7.0, true)
		draw_polyline(screen_out, path_color, 2.5, true)
		# A spacecraft running along the new path, so you can see which way it goes (unless the flyby is playing)
		if travel < 0.0:
			var running = fmod(pulse * 0.25, 1.0)
			draw_craft(point_along(screen_out, running), path_color)
	# The flyby playing out after Execute
	if travel >= 0.0 and path_in.size() >= 2 and path_out.size() >= 2:
		var screen_path = PackedVector2Array()
		if travel <= 1.0:
			var reversed = PackedVector2Array()
			for index in range(path_in.size() - 1, -1, -1):
				reversed.append(to_screen(path_in[index]))
			draw_craft(point_along(reversed, travel), Color(1.0, 1.0, 1.0))
		else:
			for point in path_out:
				screen_path.append(to_screen(point))
			draw_craft(point_along(screen_path, travel - 1.0), Color(1.0, 1.0, 1.0))
	# The flyby planet (a little textured globe on top), with a ring where the spacecraft meets it
	var planet_place = to_screen(Vector2(flyby_radius_km, 0))
	if planet_disc:
		planet_disc.size = Vector2(14, 14)
		planet_disc.position = planet_place - Vector2(7, 7)
	else:
		draw_circle(planet_place, 5.0, Color(0.85, 0.9, 1.0))
	draw_arc(planet_place, 11.0 + 3.0 * sin(pulse * 4.0), 0.0, TAU, 32, Color(0.45, 0.8, 1.0, 0.7), 1.5, true)
	draw_string(font, planet_place + Vector2(10, 16), flyby_planet.to_upper() + " FLYBY", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.8, 1.0))
	draw_string(font, Vector2(10, size.y - 10), "To scale · circular orbits in one plane", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.55, 0.62))

# A point a share of the way along a line of points (by length)
func point_along(points, share):
	var total = 0.0
	for index in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	var wanted = total * clamp(share, 0.0, 1.0)
	for index in range(1, points.size()):
		var piece = points[index - 1].distance_to(points[index])
		if wanted <= piece:
			return points[index - 1].lerp(points[index], wanted / max(piece, 0.0001))
		wanted -= piece
	return points[points.size() - 1]

func draw_craft(place, color):
	draw_circle(place, 7.0, Color(color, 0.18))
	draw_circle(place, 3.2, color)
