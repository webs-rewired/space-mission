extends Control

# A live strip chart for the Engine Test Lab: the last few seconds of one reading (thrust, chamber pressure,
# wall temperature...), with an optional red limit line and an optional gold target band to stay inside.

@export var title := "THRUST"
@export var unit := "kN"
@export var line_color := Color(0.45, 0.85, 1.0)
@export var window_seconds := 20.0

var top_value = 1000.0       # the value at the top of the chart
var samples = []             # [time, value]
var band = []                # [time, low, high]: the target band, if there is one
var limit = -1.0             # a red line (for example the wall temperature limit)
var now = 0.0

func clear():
	samples.clear()
	band.clear()
	now = 0.0
	queue_redraw()

func add_sample(time, value, band_low := -1.0, band_high := -1.0):
	now = time
	samples.append([time, value])
	if band_low >= 0.0:
		band.append([time, band_low, band_high])
	while samples.size() > 0 and samples[0][0] < time - window_seconds:
		samples.remove_at(0)
	while band.size() > 0 and band[0][0] < time - window_seconds:
		band.remove_at(0)
	queue_redraw()

func to_point(plot, time, value):
	var x = plot.end.x - (now - time) / window_seconds * plot.size.x
	return Vector2(x, plot.end.y - clamp(value / max(top_value, 0.001), 0.0, 1.05) * plot.size.y)

func _draw():
	var font = get_theme_default_font()
	var plot = Rect2(Vector2(6, 20), size - Vector2(12, 26))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.09, 0.9))
	draw_rect(plot, Color(0.05, 0.08, 0.13))
	for line in 4:
		var y = plot.position.y + plot.size.y * line / 4.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.05), 1.0)
	# The target band
	if band.size() >= 2:
		var upper = PackedVector2Array()
		var lower = PackedVector2Array()
		for entry in band:
			upper.append(to_point(plot, entry[0], entry[2]))
			lower.append(to_point(plot, entry[0], entry[1]))
		lower.reverse()
		draw_colored_polygon(upper + lower, Color(1.0, 0.82, 0.35, 0.16))
		draw_polyline(upper, Color(1.0, 0.82, 0.35, 0.5), 1.0)
	# The limit
	if limit > 0.0:
		var y = to_point(plot, now, limit).y
		var x = plot.position.x
		while x < plot.end.x:
			draw_line(Vector2(x, y), Vector2(min(x + 6, plot.end.x), y), Color(1.0, 0.4, 0.35, 0.8), 1.0)
			x += 10
		draw_string(font, Vector2(plot.end.x - 60, y - 3), "LIMIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.45, 0.4))
	# The reading
	if samples.size() >= 2:
		var points = PackedVector2Array()
		for entry in samples:
			points.append(to_point(plot, entry[0], entry[1]))
		draw_polyline(points, line_color, 2.0, true)
	var current = samples[-1][1] if samples.size() > 0 else 0.0
	draw_string(font, Vector2(6, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.68, 0.78))
	var reading = "%s %s" % [format_value(current), unit]
	draw_string(font, Vector2(size.x - 6 - font.get_string_size(reading, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 15), reading, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, line_color)

static func format_value(value):
	if abs(value) >= 100.0:
		return str(int(round(value)))
	return str(snapped(value, 0.1))
