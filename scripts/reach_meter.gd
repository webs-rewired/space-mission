extends Control

# "Does it reach?" in the Gravity-Assist Planner (res://scenes/gravity_assist.tscn): a bar from the Sun out past
# the destination's orbit. The gold tick is the destination; the marker is how far the planned orbit goes (or, for
# Mercury, how close to the Sun it falls). Green when it reaches, gold when it reaches but overshoots a lot,
# red when it falls short. gravity_assist.gd sets the numbers.

var reach_au = 0.0        # farthest point of the new orbit (or closest point, going inward)
var target_au = 5.2
var start_au = 1.0        # where the flyby happens
var going_inward = false
var escapes = false
var reaches = false
var on_target = false
var shown_reach = 0.0     # (eases toward reach_au so the marker glides)
var clock = 0.0

func _process(delta):
	clock += delta
	shown_reach = lerp(shown_reach, reach_au, 1.0 - exp(-10.0 * delta))
	if is_visible_in_tree():
		queue_redraw()

func _draw():
	var font = get_theme_default_font()
	var left = 8.0
	var right = size.x - 8.0
	var bar_y = 22.0
	# The scale runs from the Sun (0) to 1.5 times the destination's orbit (or the flyby planet's, going inward)
	var top_au = (start_au if going_inward else target_au) * 1.5
	var to_x = func(au): return left + (right - left) * clamp(au / top_au, 0.0, 1.0)
	draw_rect(Rect2(left, bar_y - 3, right - left, 6), Color(1, 1, 1, 0.08))
	draw_circle(Vector2(left, bar_y), 6.0, Color(1.0, 0.85, 0.4))
	# The destination
	var target_x = to_x.call(target_au)
	draw_rect(Rect2(target_x - 1.5, bar_y - 11, 3, 22), Color(1.0, 0.82, 0.35))
	draw_string(font, Vector2(target_x - 30, bar_y + 22), "need %.2f AU" % target_au, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.82, 0.35))
	# The flyby planet
	var start_x = to_x.call(start_au)
	draw_circle(Vector2(start_x, bar_y), 3.5, Color(0.6, 0.8, 1.0))
	# The orbit's reach, filled from the flyby planet to it
	var color = Color(0.45, 1.0, 0.6) if reaches and on_target else (Color(1.0, 0.82, 0.35) if reaches else Color(1.0, 0.5, 0.42))
	var reach_x = right + 6.0 if escapes and not going_inward else to_x.call(shown_reach)
	var fill_from = min(start_x, reach_x)
	draw_rect(Rect2(fill_from, bar_y - 3, abs(reach_x - start_x), 6), Color(color, 0.55))
	var glow = 0.6 + 0.4 * sin(clock * 5.0)
	draw_circle(Vector2(min(reach_x, right), bar_y), 6.0, Color(color, glow))
	var words = "escapes the Sun" if escapes and not going_inward else "%.2f AU" % shown_reach
	draw_string(font, Vector2(clamp(min(reach_x, right) - 24, 0, size.x - 90), bar_y - 9), words, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
