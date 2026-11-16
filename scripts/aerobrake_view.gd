extends Control

# The pictures for the Aerobraking minigame (res://scenes/aerobraking.tscn): the orbit around the planet, shrinking
# as the air brakes it, and a chart of how hot each step's hottest pass got. aerobraking.gd does the physics.
#
# The orbit is drawn to scale (it zooms in as it shrinks), except the atmosphere: the air that matters is only about
# 100 to 200 km up, too thin to see at this scale, so that band is drawn much thicker than it really is.

const AIR_BAND = 26.0                 # pixels the drawn atmosphere band is thick (it stands for 60 km of air)
const AIR_KM = 60.0
const HEAT_LIMIT_COLOR = Color(1.0, 0.45, 0.4)

var planet = {}
var apoapsis = 40000.0
var periapsis = 120.0
var heat_preview = 50.0
var days_left = 150.0
var history = []
var meters_per_pixel_shown = 0.0      # the zoom, eased toward the current orbit
var probe_angle = PI                  # where the spacecraft is drawn on the orbit (0 = the low point)
var animating = false
var glow = 0.0                        # heat glow at the low point during a pass
var clock = 0.0

func set_up(new_planet):
	planet = new_planet
	apoapsis = planet["start_apoapsis"]

func _process(delta):
	clock += delta
	glow = max(glow - delta * 1.5, 0.0)
	if not animating:
		probe_angle = fmod(probe_angle + delta * 0.4, TAU)
	if is_visible_in_tree():
		queue_redraw()

func orbit_area():
	return Rect2(Vector2(0, 0), Vector2(size.x, size.y * 0.7))

func chart_area():
	return Rect2(Vector2(46, size.y * 0.74), Vector2(size.x - 66, size.y * 0.22))

# Pixels for a distance from the planet's center, given the zoom (the air band is stretched, see above)
func radius_pixels(altitude_km, kilometers_per_pixel):
	var planet_pixels = planet["radius"] / kilometers_per_pixel
	var air_bottom = planet["reference_altitude"] - AIR_KM * 0.5
	if altitude_km <= air_bottom + AIR_KM:
		return planet_pixels + clamp((altitude_km - air_bottom) / AIR_KM, 0.0, 1.0) * AIR_BAND
	return planet_pixels + AIR_BAND + (altitude_km - air_bottom - AIR_KM) / kilometers_per_pixel

# Shrinks the orbit over a step: the spacecraft swings round a few times, glowing at each pass through the air
func animate_step(from_apoapsis, to_apoapsis, at_periapsis, passes, peak_heat, overheated):
	animating = true
	periapsis = at_periapsis
	var loops = clamp(int(passes / 12), 2, 5)
	var seconds = 1.6
	var elapsed = 0.0
	while elapsed < seconds:
		var delta = get_process_delta_time()
		elapsed += delta
		var share = clamp(elapsed / seconds, 0.0, 1.0)
		apoapsis = lerp(from_apoapsis, to_apoapsis, share)
		var before = probe_angle
		probe_angle = fmod(probe_angle + delta * TAU * loops / seconds, TAU)
		if before > probe_angle:   # passed the low point
			glow = clamp(peak_heat / 100.0, 0.2, 1.2)
		await get_tree().process_frame
	apoapsis = to_apoapsis
	if overheated:
		glow = 1.5
	animating = false

func _draw():
	if planet.is_empty():
		return
	var area = orbit_area()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.03, 0.95))
	var font = get_theme_default_font()
	# The zoom: the whole orbit fits, with the planet off to the right so the long far end has room
	var far = planet["radius"] + apoapsis
	var near = planet["radius"] + periapsis
	var semi_major = (far + near) / 2.0
	var wanted = (2.0 * semi_major) / (area.size.x - 160.0)   # (room for the low point's label on the right)
	var stretch = (far - near) / (far + near)
	wanted = max(wanted, 2.0 * semi_major * sqrt(1.0 - stretch * stretch) / (area.size.y * 0.84), planet["radius"] * 2.6 / area.size.y)
	meters_per_pixel_shown = wanted if meters_per_pixel_shown <= 0.0 else lerp(meters_per_pixel_shown, wanted, 0.08)
	var scale_km = meters_per_pixel_shown
	var near_pixels = radius_pixels(periapsis, scale_km)
	var far_pixels = radius_pixels(apoapsis, scale_km)
	var center = Vector2(area.end.x - max(near_pixels, planet["radius"] / scale_km + AIR_BAND) - 112.0, area.position.y + area.size.y * 0.5)
	var planet_pixels = planet["radius"] / scale_km
	# The air (stretched), then the planet
	for ring in 6:
		var share = ring / 6.0
		draw_circle(center, planet_pixels + AIR_BAND * (1.0 - share), Color(planet["air"], 0.05 + share * 0.05))
	draw_circle(center, planet_pixels, planet["color"])
	draw_circle(center + Vector2(planet_pixels * 0.2, -planet_pixels * 0.15), planet_pixels * 0.8, Color(planet["color"].lightened(0.1), 0.18))
	draw_arc(center, planet_pixels + AIR_BAND * 0.5, 0.0, TAU, 96, Color(planet["air"], 0.25), 1.0, true)
	# The orbit: an ellipse with the planet at one focus, the low point to the right
	var semi_major_pixels = (near_pixels + far_pixels) / 2.0
	var eccentricity = (far_pixels - near_pixels) / (far_pixels + near_pixels)
	var points = PackedVector2Array()
	for step in 241:
		var angle = TAU * step / 240.0
		var distance = semi_major_pixels * (1.0 - eccentricity * eccentricity) / (1.0 + eccentricity * cos(angle))
		points.append(center + Vector2(cos(angle), sin(angle)) * distance)
	draw_polyline(points, Color(0.55, 0.85, 1.0, 0.7), 1.5, true)
	# The spacecraft
	var probe_distance = semi_major_pixels * (1.0 - eccentricity * eccentricity) / (1.0 + eccentricity * cos(probe_angle))
	var probe = center + Vector2(cos(probe_angle), sin(probe_angle)) * probe_distance
	draw_circle(probe, 4.0, Color(1, 1, 1))
	# Heat at the low point
	var low_point = center + Vector2(near_pixels, 0)
	if glow > 0.0:
		var heat_color = Color(1.0, 0.6, 0.2).lerp(HEAT_LIMIT_COLOR, clamp(glow - 0.8, 0.0, 1.0))
		draw_circle(low_point, 8.0 + glow * 10.0, Color(heat_color, 0.35 * min(glow, 1.0)))
	draw_line(low_point + Vector2(0, -14), low_point + Vector2(0, 14), Color(1.0, 0.86, 0.5, 0.8), 1.0)
	draw_string(font, low_point + Vector2(8, -16), "low point %d km" % int(round(periapsis)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.86, 0.5))
	var far_point = center + Vector2(-far_pixels, 0)
	var far_text = "far end %s km" % format_km(apoapsis)
	var far_width = font.get_string_size(far_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(max(far_point.x - far_width - 6.0, 4.0), far_point.y - 10.0), far_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.85, 1.0))
	var goal_pixels = radius_pixels(planet["target_apoapsis"], scale_km)
	draw_arc(center, goal_pixels, PI * 0.75, PI * 1.25, 24, Color(0.45, 1.0, 0.6, 0.6), 1.5, true)
	draw_string(font, center + Vector2(-goal_pixels - 8, -planet_pixels * 0.7 - 6), "goal", HORIZONTAL_ALIGNMENT_RIGHT, -1, 11, Color(0.45, 1.0, 0.6))
	draw_string(font, Vector2(14, area.end.y - 6), "Orbit to scale. The air band is drawn %d× thicker than it is." % int(round(max(AIR_BAND * scale_km / AIR_KM, 1.0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
	draw_chart(font)

# The hottest pass of each step, against the solar panels' limit
func draw_chart(font):
	var chart = chart_area()
	draw_rect(chart, Color(0.04, 0.06, 0.1, 0.9))
	var limit_y = chart.position.y + chart.size.y * (1.0 - 100.0 / 130.0)
	draw_line(Vector2(chart.position.x, limit_y), Vector2(chart.end.x, limit_y), HEAT_LIMIT_COLOR, 1.0)
	draw_string(font, Vector2(chart.position.x - 42, limit_y + 4), "limit", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HEAT_LIMIT_COLOR)
	draw_string(font, Vector2(chart.position.x, chart.position.y - 4), "HOTTEST PASS OF EACH STEP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
	var slots = max(history.size() + 1, 22)
	var width = chart.size.x / slots
	for index in history.size():
		var entry = history[index]
		var height = clamp(entry["heat"] / 130.0, 0.0, 1.0) * chart.size.y
		var color = HEAT_LIMIT_COLOR if entry["overheat"] else (Color(1.0, 0.85, 0.4) if entry["heat"] > 75.0 else Color(0.45, 0.9, 0.6))
		draw_rect(Rect2(Vector2(chart.position.x + index * width + 2, chart.end.y - height), Vector2(max(width - 4, 2), height)), color)
	# The planned next step, from the forecast
	var preview_height = clamp(heat_preview / 130.0, 0.0, 1.0) * chart.size.y
	var preview = Rect2(Vector2(chart.position.x + history.size() * width + 2, chart.end.y - preview_height), Vector2(max(width - 4, 2), preview_height))
	draw_rect(preview, Color(1, 1, 1, 0.25 + 0.15 * sin(clock * 4.0)), false, 1.5)

static func format_km(value):
	var whole = str(int(round(value)))
	var grouped = ""
	for index in whole.length():
		if index > 0 and (whole.length() - index) % 3 == 0:
			grouped += ","
		grouped += whole[index]
	return grouped
