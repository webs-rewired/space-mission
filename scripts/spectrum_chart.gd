extends Control

# An infrared spectrum for the Sample Lab: how much light the sample reflects at each wavelength from 0.4 to
# 4.2 micrometers. Minerals and ices absorb light at their own wavelengths, so the dips ("absorption bands")
# are fingerprints. Each band is drawn as a smooth dip: reflectance × (1 − depth × e^(−((λ − center) / half width)²)).

const LOW = 0.4
const HIGH = 4.2

var brightness = 0.3
var bands = []      # [center µm, depth 0 to 1, width µm]

func show_spectrum(sample_brightness, sample_bands):
	brightness = sample_brightness
	bands = sample_bands
	queue_redraw()

func reflectance(wavelength):
	var value = brightness * (0.92 + 0.08 * (wavelength - LOW) / (HIGH - LOW))
	for band in bands:
		var half_width = max(band[2] / 2.0, 0.01)
		value *= 1.0 - band[1] * exp(-pow((wavelength - band[0]) / half_width, 2.0))
	return value

func _draw():
	var plot = Rect2(Vector2(34, 8), size - Vector2(44, 34))
	draw_rect(plot, Color(0.04, 0.06, 0.1))
	var font = get_theme_default_font()
	for tick in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]:
		var x = plot.position.x + (tick - LOW) / (HIGH - LOW) * plot.size.x
		draw_line(Vector2(x, plot.end.y), Vector2(x, plot.end.y + 4), Color(1, 1, 1, 0.4), 1.0)
		draw_string(font, Vector2(x - 8, plot.end.y + 15), str(tick), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.75, 0.82))
	draw_string(font, Vector2(plot.position.x, size.y - 1), "wavelength (micrometers)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.6, 0.68))
	draw_string(font, Vector2(0, plot.position.y + 10), "more", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.6, 0.68))
	draw_string(font, Vector2(0, plot.end.y), "less", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.6, 0.68))
	draw_string(font, Vector2(plot.end.x - 150, plot.position.y + 12), "light reflected (relative)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.6, 0.68))
	# Scaled so the brightest part of the curve sits near the top: dark rocks show their dips as clearly as bright
	# ices (the labels say "relative": this compares wavelengths within one sample, not one sample with another)
	var values = []
	var brightest = 0.001
	for step in 241:
		var value = reflectance(LOW + (HIGH - LOW) * step / 240.0)
		values.append(value)
		brightest = max(brightest, value)
	var points = PackedVector2Array()
	for step in 241:
		var height = clamp(values[step] / brightest * 0.85, 0.0, 1.0)
		points.append(Vector2(plot.position.x + step / 240.0 * plot.size.x, plot.end.y - height * plot.size.y))
	draw_polyline(points, Color(0.45, 0.85, 1.0), 2.0, true)
	# Label each dip with its wavelength
	for band in bands:
		if band[1] < 0.08:
			continue
		var x = plot.position.x + (band[0] - LOW) / (HIGH - LOW) * plot.size.x
		var y = plot.end.y - clamp(reflectance(band[0]) / brightest * 0.85, 0.0, 1.0) * plot.size.y
		# The label goes under the dip, or above it when the dip is near the bottom
		var below = y + 28 < plot.end.y
		draw_line(Vector2(x, y + (4 if below else -4)), Vector2(x, y + (14 if below else -14)), Color(1.0, 0.82, 0.35, 0.8), 1.0)
		draw_string(font, Vector2(x - 12, y + (26 if below else -18)), "%s µm" % str(snapped(band[0], 0.01)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.82, 0.35))
