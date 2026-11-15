extends Control

# The pictures for the Seismic Station minigame (res://scenes/seismometer.tscn): the bubble level while you level
# the seismometer, then the seismogram as it's recorded, with your picks of the P and S waves. seismometer.gd
# fills in the numbers; this only draws.

const TRACE_COLOR = Color(0.55, 0.95, 1.0)
const P_COLOR = Color(0.45, 1.0, 0.6)
const S_COLOR = Color(1.0, 0.7, 0.35)

var mode = "level"                # "level" or "trace"
# Leveling
var tilt = Vector2.ZERO           # degrees (right, forward)
var level_limit = 0.3             # degrees: inside this the instrument counts as level
var shield_down = false
var has_wind = false
# The seismogram
var samples = PackedFloat32Array()    # ground motion, one sample every 1 / sample_rate seconds
var sample_rate = 20.0
var shown_seconds = 0.0           # how much of the recording has come in so far
var total_seconds = 120.0
var p_pick = -1.0                 # seconds, or -1 if not picked yet
var s_pick = -1.0
var selected = "p"
var true_p = -1.0                 # shown after the answer
var true_s = -1.0
var clock = 0.0

func _process(delta):
	clock += delta
	if is_visible_in_tree():
		queue_redraw()

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.92))
	if mode == "level":
		draw_level()
	else:
		draw_trace()

# The bubble level, seen from above, with the seismometer's three feet around it
func draw_level():
	var center = size / 2.0
	var radius = min(size.x, size.y) * 0.33
	# The instrument: a round housing on three legs (like InSight's SEIS and the Apollo seismometers)
	for leg in 3:
		var angle = TAU * leg / 3.0 - PI / 2.0
		var foot = center + Vector2(cos(angle), sin(angle)) * radius * 1.3
		draw_line(center + Vector2(cos(angle), sin(angle)) * radius * 0.9, foot, Color(0.6, 0.62, 0.66), 6.0, true)
		draw_circle(foot, 10.0, Color(0.45, 0.47, 0.5))
	draw_circle(center, radius, Color(0.12, 0.14, 0.18))
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.75, 0.78, 0.82), 3.0, true)
	# The bull's-eye and the bubble (the bubble floats to the high side)
	var limit_radius = radius * 0.18
	draw_arc(center, limit_radius, 0.0, TAU, 48, Color(P_COLOR, 0.8), 2.0, true)
	draw_arc(center, radius * 0.55, 0.0, TAU, 48, Color(1, 1, 1, 0.15), 1.0, true)
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color(1, 1, 1, 0.12), 1.0)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color(1, 1, 1, 0.12), 1.0)
	# (it moves less and less as the tilt grows, like a real bull's-eye level: inside the green circle exactly when
	# the tilt is within the limit, near the rim when it's way off)
	var bubble_offset = Vector2.ZERO
	if tilt.length() > 0.0001:
		var reach = radius * 0.85 * (1.0 - exp(-tilt.length() / (level_limit * 5.78)))
		bubble_offset = Vector2(-tilt.x, tilt.y).normalized() * reach
	var level = tilt.length() <= level_limit
	var bubble_color = P_COLOR if level else Color(1.0, 0.85, 0.4)
	draw_circle(center + bubble_offset, limit_radius * 0.75, Color(bubble_color, 0.35))
	draw_arc(center + bubble_offset, limit_radius * 0.75, 0.0, TAU, 32, bubble_color, 2.0, true)
	draw_circle(center + bubble_offset + Vector2(-4, -4), 3.0, Color(1, 1, 1, 0.6))
	var font = get_theme_default_font()
	draw_string(font, Vector2(20, 30), "TILT  %.2f°  (level within %.1f°)" % [tilt.length(), level_limit], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, bubble_color)
	if has_wind:
		draw_string(font, Vector2(20, 54), "WIND SHIELD: %s" % ("DOWN" if shield_down else "UP (the wind will shake the trace)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.85, 0.9))
	if shield_down:
		draw_arc(center, radius * 1.55, PI, TAU, 64, Color(0.85, 0.75, 0.55, 0.7), 8.0, true)

# The seismogram: time across, ground motion up and down, with the picks
func draw_trace():
	var font = get_theme_default_font()
	var left = 50.0
	var right = size.x - 20.0
	var middle = size.y * 0.5
	var height = size.y * 0.38
	# Time ticks every 10 s
	var seconds_per_pixel = total_seconds / (right - left)
	for tick in range(0, int(total_seconds) + 1, 10):
		var x = left + tick / seconds_per_pixel
		draw_line(Vector2(x, 24), Vector2(x, size.y - 30), Color(1, 1, 1, 0.06 if tick % 60 != 0 else 0.14), 1.0)
		if tick % 20 == 0:
			draw_string(font, Vector2(x - 8, size.y - 12), "%d s" % tick, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
	draw_line(Vector2(left, middle), Vector2(right, middle), Color(1, 1, 1, 0.1), 1.0)
	# The trace so far: for each pixel column, the highest and lowest motion in it (the way seismograms are drawn)
	if not samples.is_empty():
		var peak = 0.001
		for value in samples:
			peak = max(peak, abs(value))
		var last_x = left + shown_seconds / seconds_per_pixel
		var column = left
		while column < last_x:
			var from_index = int((column - left) * seconds_per_pixel * sample_rate)
			var to_index = min(int((column + 1.0 - left) * seconds_per_pixel * sample_rate) + 1, samples.size())
			var high = -INF
			var low = INF
			for index in range(from_index, to_index):
				high = max(high, samples[index])
				low = min(low, samples[index])
			if high > -INF:
				draw_line(Vector2(column, middle - high / peak * height), Vector2(column, middle - low / peak * height + 0.5), TRACE_COLOR, 1.0)
			column += 1.0
		# the pen
		if shown_seconds < total_seconds:
			draw_circle(Vector2(last_x, middle), 4.0, Color(TRACE_COLOR, 0.6 + 0.4 * sin(clock * 10.0)))
	# The picks (and the real arrivals, once the answer is in)
	for entry in [[true_p, P_COLOR, "real P", true], [true_s, S_COLOR, "real S", true], [p_pick, P_COLOR, "P", false], [s_pick, S_COLOR, "S", false]]:
		if entry[0] < 0.0:
			continue
		var x = left + entry[0] / seconds_per_pixel
		if entry[3]:
			for dash in range(24, int(size.y) - 30, 10):
				draw_line(Vector2(x, dash), Vector2(x, dash + 5), Color(entry[1], 0.6), 1.0)
			draw_string(font, Vector2(x + 4, size.y - 40), entry[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, entry[1])
		else:
			var thick = 3.0 if selected == entry[2].to_lower() else 2.0
			draw_line(Vector2(x, 24), Vector2(x, size.y - 30), entry[1], thick)
			draw_string(font, Vector2(x + 5, 40), entry[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, entry[1])
	draw_string(font, Vector2(left, 18), "GROUND MOTION (vertical)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.66, 0.75))
