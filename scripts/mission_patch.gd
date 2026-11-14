extends Control

# A mission patch, like the cloth patches every NASA crew and mission team wears: a round badge with the mission
# name around the top, the year around the bottom, and the world you went to in the middle.
# results.gd fills in mission_name, destination_color and year; the rest is drawn here.

var mission_name = "ORBIT LAB"
var bottom_text = "2026"
var destination_color = Color(0.8, 0.5, 0.3)
var ring_color = Color(0.45, 0.8, 1.0)
var success = true
var spin = 0.0

func _process(delta):
	spin += delta * 0.15
	queue_redraw()

func _draw():
	var center = size / 2.0
	var radius = min(size.x, size.y) / 2.0 - 4.0
	var font = get_theme_default_font()
	# The badge: dark blue cloth with a colored edge
	draw_circle(center, radius, Color(0.04, 0.07, 0.16))
	draw_arc(center, radius, 0.0, TAU, 96, ring_color, 4.0, true)
	draw_arc(center, radius * 0.72, 0.0, TAU, 96, ring_color.darkened(0.3), 1.5, true)
	# Stars in the background
	var random = RandomNumberGenerator.new()
	random.seed = hash(mission_name)
	for index in 26:
		var angle = random.randf() * TAU
		var distance = sqrt(random.randf()) * radius * 0.68
		draw_circle(center + Vector2(cos(angle), sin(angle)) * distance, random.randf_range(0.6, 1.6), Color(1, 1, 1, random.randf_range(0.4, 0.9)))
	# The world, lit from one side, with an orbit around it and the spacecraft on the orbit
	var world_radius = radius * 0.3
	draw_circle(center, world_radius, destination_color.darkened(0.45))
	draw_circle(center + Vector2(-world_radius * 0.18, -world_radius * 0.18), world_radius * 0.8, destination_color)
	draw_arc(center, world_radius * 1.65, 0.0, TAU, 64, Color(1, 1, 1, 0.55), 1.5, true)
	var craft = center + Vector2(cos(spin), sin(spin) * 0.95) * world_radius * 1.65
	draw_rect(Rect2(craft - Vector2(3, 3), Vector2(6, 6)), Color(1, 0.85, 0.4))
	draw_line(craft - Vector2(10, 0), craft + Vector2(10, 0), Color(0.55, 0.75, 1.0), 2.0)
	# Words around the edge
	draw_text_on_arc(font, mission_name.to_upper(), center, radius * 0.86, -PI / 2.0, 17, Color.WHITE, true)
	draw_text_on_arc(font, bottom_text.to_upper(), center, radius * 0.86, PI / 2.0, 13, Color(0.8, 0.86, 0.95), false)

# Writes text along a circle, centered on an angle: along the top (reading clockwise) or along the bottom
# (reading counterclockwise, so it isn't upside down)
func draw_text_on_arc(font, text, center, radius, middle_angle, font_size, color, along_top):
	var widths = []
	var total = 0.0
	for character in text:
		var width = font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 1.5
		widths.append(width)
		total += width
	var direction = 1.0 if along_top else -1.0
	var angle = middle_angle - direction * (total / radius) / 2.0
	for index in text.length():
		var step = widths[index] / radius
		var character_angle = angle + direction * step / 2.0
		var place = center + Vector2(cos(character_angle), sin(character_angle)) * radius
		var turn = character_angle + PI / 2.0 if along_top else character_angle - PI / 2.0
		draw_set_transform(place, turn, Vector2.ONE)
		draw_string(font, Vector2(-widths[index] / 2.0, font_size * 0.35), text[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		angle += direction * step
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
