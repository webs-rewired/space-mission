extends Control

# The pictures for the Radio Science minigame (res://scenes/radio_science.tscn). During the pass: a "waterfall"
# display like the ones in Deep Space Network control rooms, with frequency across and time running down, the
# signal as a bright line and the receiver's window as a blue band. After the pass: what the data shows, either the
# atmosphere's profile (pressure against height, or temperature against pressure for a giant planet) or the gravity
# along the track, with a point for every stretch you stayed locked on.

const ROWS = 260
const SIGNAL_COLOR = Color(1.0, 0.95, 0.7)
const WINDOW_COLOR = Color(0.35, 0.75, 1.0)
const DATA_COLOR = Color(0.45, 1.0, 0.6)

var info = {}
var lock_width = 0.15
var rows = []                 # [signal, strength, receiver, locked], newest first
var noise = []                # per-row speckle, made once
var mode = "waterfall"        # or "profile"
var measured = []             # for the profile: which data points were measured
var clock = 0.0
var preview = []              # before the pass starts: [where the signal is, where the receiver is]

func set_up(world_info, window_width):
	info = world_info
	lock_width = window_width
	var random = RandomNumberGenerator.new()
	random.seed = 1965
	for index in ROWS:
		var dots = []
		for dot in 10:
			dots.append(Vector2(random.randf_range(-1.0, 1.0), random.randf()))
		noise.append(dots)

func add_row(signal_place, strength, receiver, locked):
	rows.push_front([signal_place, strength, receiver, locked])
	if rows.size() > ROWS:
		rows.pop_back()

func show_profile(new_measured):
	measured = new_measured
	mode = "profile"

func _process(delta):
	clock += delta
	if is_visible_in_tree():
		queue_redraw()

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.04, 0.95))
	if mode == "waterfall":
		draw_waterfall()
	else:
		draw_profile()

func to_x(place, area):
	return area.position.x + (place + 1.0) * 0.5 * area.size.x

func draw_waterfall():
	var font = get_theme_default_font()
	var area = Rect2(Vector2(30, 34), Vector2(size.x - 60, size.y - 70))
	draw_rect(area, Color(0.0, 0.03, 0.06))
	var row_height = area.size.y / ROWS
	for index in rows.size():
		var row = rows[index]
		var y = area.position.y + index * row_height
		# speckle (the receiver's noise), stronger as the signal weakens
		for dot in noise[index % noise.size()]:
			var shade = 0.08 + 0.25 * (1.0 - row[1]) * dot.y
			draw_rect(Rect2(Vector2(to_x(dot.x, area), y), Vector2(2, max(row_height, 1.0))), Color(0.5, 0.7, 1.0, shade))
		# the receiver's window
		var half = lock_width * 0.5
		var left = to_x(row[2] - half, area)
		var right = to_x(row[2] + half, area)
		draw_rect(Rect2(Vector2(left, y), Vector2(right - left, max(row_height, 1.0))), Color(WINDOW_COLOR, 0.16 if row[3] else 0.07))
		# the signal
		var x = to_x(row[0], area)
		draw_rect(Rect2(Vector2(x - 2, y), Vector2(4, max(row_height, 1.0) + 0.5)), Color(SIGNAL_COLOR, 0.25 + 0.75 * row[1]))
	# The receiver's window now, at the top
	if not rows.is_empty():
		var now = rows[0]
		var half = lock_width * 0.5
		var left = to_x(now[2] - half, area)
		var right = to_x(now[2] + half, area)
		var color = DATA_COLOR if now[3] else Color(1.0, 0.5, 0.45)
		draw_rect(Rect2(Vector2(left, area.position.y - 10), Vector2(right - left, 8)), color)
		draw_line(Vector2(left, area.position.y), Vector2(left, area.end.y), Color(WINDOW_COLOR, 0.45), 1.0)
		draw_line(Vector2(right, area.position.y), Vector2(right, area.end.y), Color(WINDOW_COLOR, 0.45), 1.0)
	# Before the pass: where the signal and the receiver are, labeled
	if rows.is_empty() and not preview.is_empty():
		var signal_x = to_x(preview[0], area)
		var pulse = 0.5 + 0.5 * sin(clock * 3.0)
		draw_rect(Rect2(Vector2(signal_x - 2, area.position.y), Vector2(4, area.size.y)), Color(SIGNAL_COLOR, 0.25 + 0.35 * pulse))
		var half = lock_width * 0.5
		var left = to_x(preview[1] - half, area)
		var right = to_x(preview[1] + half, area)
		draw_rect(Rect2(Vector2(left, area.position.y), Vector2(right - left, area.size.y)), Color(WINDOW_COLOR, 0.1))
		draw_string(font, Vector2(signal_x + 8, area.position.y + area.size.y * 0.45), "the signal", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SIGNAL_COLOR)
		draw_string(font, Vector2(right + 8, area.position.y + area.size.y * 0.55), "your receiver's window", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, WINDOW_COLOR)
	draw_string(font, Vector2(area.position.x, 20), "FREQUENCY SHIFT  →", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
	draw_string(font, Vector2(area.position.x, area.end.y + 20), "time runs down: the newest signal is at the top", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))

# What the measured data says
func draw_profile():
	var font = get_theme_default_font()
	var area = Rect2(Vector2(80, 40), Vector2(size.x - 120, size.y - 110))
	draw_rect(area, Color(0.03, 0.05, 0.09))
	var count = measured.size()
	if info["mode"] == "gravity":
		draw_string(font, Vector2(area.position.x, 26), "GRAVITY ALONG YOUR TRACK (extra pull from heavier rock below)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.85, 1.0))
		var middle = area.position.y + area.size.y * 0.55
		draw_line(Vector2(area.position.x, middle), Vector2(area.end.x, middle), Color(1, 1, 1, 0.2), 1.0)
		draw_string(font, Vector2(16, middle - 40), "heavier", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
		draw_string(font, Vector2(16, middle + 48), "lighter", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
		var curve = PackedVector2Array()
		for step in 121:
			var share = step / 120.0
			curve.append(Vector2(area.position.x + share * area.size.x, middle - gravity_at(share) * area.size.y * 0.4))
		draw_polyline(curve, Color(1, 1, 1, 0.12), 1.0, true)
		for index in count:
			var share = (index + 0.5) / count
			var point = Vector2(area.position.x + share * area.size.x, middle - gravity_at(share) * area.size.y * 0.4)
			draw_point(point, measured[index])
		draw_string(font, Vector2(area.position.x, area.end.y + 24), "start of track", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
		draw_string(font, Vector2(area.end.x - 70, area.end.y + 24), "end", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
	elif info["profile"] == "temperature":
		draw_string(font, Vector2(area.position.x, 26), "TEMPERATURE AGAINST PRESSURE (higher pressure = deeper)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.85, 1.0))
		var coldest = info["coldest_k"]
		var lowest_k = coldest - 15.0
		var highest_k = max(info["one_bar_k"], info["top_k"]) + 15.0
		for decade in 4:
			var y = area.position.y + decade / 3.0 * area.size.y
			draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(1, 1, 1, 0.07), 1.0)
			draw_string(font, Vector2(8, y + 4), ["1 mbar", "10 mbar", "0.1 bar", "1 bar"][decade], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
		var curve = PackedVector2Array()
		for step in 121:
			var share = step / 120.0
			curve.append(Vector2(area.position.x + (temperature_at(share) - lowest_k) / (highest_k - lowest_k) * area.size.x, area.position.y + share * area.size.y))
		draw_polyline(curve, Color(1, 1, 1, 0.12), 1.0, true)
		for index in count:
			var share = (index + 0.5) / count
			draw_point(Vector2(area.position.x + (temperature_at(share) - lowest_k) / (highest_k - lowest_k) * area.size.x, area.position.y + share * area.size.y), measured[index])
		draw_string(font, Vector2(area.position.x, area.end.y + 24), "%d K (colder)" % int(lowest_k), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
		draw_string(font, Vector2(area.end.x - 100, area.end.y + 24), "%d K (warmer)" % int(highest_k), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
	else:
		draw_string(font, Vector2(area.position.x, 26), "AIR PRESSURE AGAINST HEIGHT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.85, 1.0))
		var surface = info["surface_bar"]
		var lowest = info["lowest_km"]
		var top = info["top_km"]
		var low_pressure = surface * exp(-top / info["scale_km"])
		var high_pressure = surface * 1.6
		var log_low = log(low_pressure)
		var log_high = log(high_pressure)
		var curve = PackedVector2Array()
		for step in 121:
			var height = top * (1.0 - step / 120.0)
			var pressure = surface * exp(-height / info["scale_km"])
			curve.append(Vector2(area.position.x + (log(pressure) - log_low) / (log_high - log_low) * area.size.x, area.position.y + (1.0 - height / top) * area.size.y))
		draw_polyline(curve, Color(1, 1, 1, 0.12), 1.0, true)
		# A gridline and label at every power of ten of pressure, so the values can be read off
		var decade = int(floor(log(low_pressure) / log(10.0)))
		while pow(10.0, decade) <= high_pressure:
			var value = pow(10.0, decade)
			if value >= low_pressure:
				var x = area.position.x + (log(value) - log_low) / (log_high - log_low) * area.size.x
				draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), Color(1, 1, 1, 0.07), 1.0)
				draw_string(font, Vector2(x - 24, area.end.y + 40), pressure_words(value), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.66, 0.75))
			decade += 1
		if high_pressure < 1.013:
			draw_string(font, Vector2(area.end.x - 300, area.position.y + 18), "(Earth's air at the ground: 1,013 millibar, far off to the right)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
		for index in count:
			var share = (index + 0.5) / count
			var height = top - (top - lowest) * share
			var pressure = surface * exp(-height / info["scale_km"])
			draw_point(Vector2(area.position.x + (log(pressure) - log_low) / (log_high - log_low) * area.size.x, area.position.y + (1.0 - height / top) * area.size.y), measured[index])
		# The deepest measured point, labeled
		var deepest = -1
		for index in count:
			if measured[index]:
				deepest = index
		if deepest >= 0:
			var share = (deepest + 0.5) / count
			var height = top - (top - lowest) * share
			var pressure = surface * exp(-height / info["scale_km"])
			var point = Vector2(area.position.x + (log(pressure) - log_low) / (log_high - log_low) * area.size.x, area.position.y + (1.0 - height / top) * area.size.y)
			draw_string(font, point + Vector2(-230, -10), "deepest point: %s at %d km" % [pressure_words(pressure), int(round(height))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DATA_COLOR)
		var ground_y = area.position.y + area.size.y
		draw_line(Vector2(area.position.x, ground_y), Vector2(area.end.x, ground_y), Color(0.8, 0.6, 0.4, 0.5), 2.0)
		draw_string(font, Vector2(8, area.position.y + 6), "%d km" % int(top), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
		draw_string(font, Vector2(8, ground_y + 4), "ground", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
		if lowest > 0.0:
			var cut_y = area.position.y + (1.0 - lowest / top) * area.size.y
			draw_line(Vector2(area.position.x, cut_y), Vector2(area.end.x, cut_y), Color(1.0, 0.5, 0.45, 0.6), 1.0)
			draw_string(font, Vector2(area.position.x + 8, cut_y + 16), "the signal could go no deeper than %d km" % int(lowest), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.6, 0.5))
		draw_string(font, Vector2(area.position.x, area.end.y + 22), "thinner air  ←  pressure (log scale)  →  thicker air", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
	var got = measured.count(true)
	var got_text = "%d of %d points measured" % [got, count]
	var got_width = font.get_string_size(got_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(area.end.x - got_width, size.y - 10), got_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DATA_COLOR)

func draw_point(point, was_measured):
	if was_measured:
		draw_circle(point, 4.0, DATA_COLOR)
	else:
		draw_arc(point, 3.5, 0.0, TAU, 12, Color(1.0, 0.5, 0.45, 0.6), 1.0, true)

# The gravity's shape along the track (the same bumps the signal followed)
func gravity_at(share):
	var total = 0.0
	for bump in info["bumps"]:
		total += bump[1] * exp(-pow((share - bump[0]) / 0.06, 2))
	return total

# A giant planet's temperature at a point of the pass (pressure from 1 millibar at the start to 1 bar at the end):
# warmer high up (sunlight on the haze), coldest at 0.1 bar, warmer again deeper down
func temperature_at(share):
	var log_pressure = -3.0 + 3.0 * share   # log10 of the pressure in bar
	var coldest = info["coldest_k"]
	if log_pressure < -1.0:
		return coldest + (info["top_k"] - coldest) * pow((-1.0 - log_pressure) / 2.0, 1.2)
	return coldest + (info["one_bar_k"] - coldest) * (log_pressure + 1.0)

static func pressure_words(bar):
	if bar >= 1.0:
		return "%.1f bar" % bar
	if bar >= 0.001:
		return "%.1f millibar" % (bar * 1000.0)
	return "%.1f microbar" % (bar * 1000000.0)
