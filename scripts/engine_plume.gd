extends Control

# The engine on the test stand in the Engine Test Lab, seen from the side: the nozzle bell and its exhaust.
# The flame follows the real physics loosely: longer with more thrust; at sea level the outside air squeezes it
# into a narrow column with bright "shock diamonds" (Mach diamonds); in a vacuum it spreads out wide and fades.
# Kerosene burns orange and sooty, hydrogen almost invisible blue, methane blue-violet.

var thrust_share = 0.0     # 0 (off) to about 1.1
var in_vacuum = false
var fuel = "kerosene"
var shake = 0.0
var nozzle_wide = 1.0      # top-stage engines have much bigger nozzles

func _process(_delta):
	if is_visible_in_tree():
		queue_redraw()

func flame_colors():
	match fuel:
		"hydrogen":
			return [Color(0.75, 0.85, 1.0, 0.9), Color(0.45, 0.6, 1.0, 0.35)]
		"methane":
			return [Color(0.85, 0.75, 1.0, 0.95), Color(0.5, 0.45, 1.0, 0.4)]
	return [Color(1.0, 0.9, 0.55, 1.0), Color(1.0, 0.5, 0.15, 0.55)]

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07))
	var throat = Vector2(size.x * 0.18, size.y * 0.5)
	var bell_length = size.y * 0.32 * nozzle_wide
	var exit_half = size.y * 0.17 * nozzle_wide
	# The test stand's steel frame
	draw_rect(Rect2(Vector2(0, throat.y - size.y * 0.38), Vector2(throat.x - 10, size.y * 0.76)), Color(0.16, 0.17, 0.2))
	for brace in 4:
		var y = throat.y - size.y * 0.38 + brace * size.y * 0.25
		draw_line(Vector2(0, y), Vector2(throat.x - 10, y + size.y * 0.12), Color(0.26, 0.28, 0.32), 3.0)
	# The flame (drawn before the nozzle so the bell sits on top)
	if thrust_share > 0.01:
		var jitter = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 4.0
		var exit_point = throat + Vector2(bell_length, 0) + jitter
		var length = size.x * (0.55 if not in_vacuum else 0.7) * clamp(thrust_share, 0.0, 1.2)
		var colors = flame_colors()
		var spread = exit_half * (0.85 if not in_vacuum else 2.6)
		var flicker = 1.0 + randf_range(-0.04, 0.04) * (1.0 + shake * 3.0)
		var outer = PackedVector2Array([exit_point + Vector2(0, -exit_half), exit_point + Vector2(length * 0.5 * flicker, -spread), exit_point + Vector2(length * flicker, 0), exit_point + Vector2(length * 0.5 * flicker, spread), exit_point + Vector2(0, exit_half)])
		draw_colored_polygon(outer, colors[1])
		var core = PackedVector2Array([exit_point + Vector2(0, -exit_half * 0.6), exit_point + Vector2(length * 0.6 * flicker, -spread * 0.25), exit_point + Vector2(length * 0.75 * flicker, 0), exit_point + Vector2(length * 0.6 * flicker, spread * 0.25), exit_point + Vector2(0, exit_half * 0.6)])
		draw_colored_polygon(core, colors[0])
		if not in_vacuum:
			# Shock diamonds: the exhaust bounces between too much and too little pressure as it meets the air
			for diamond in 5:
				var place = exit_point + Vector2(length * (0.12 + diamond * 0.13), 0)
				var half = exit_half * 0.32 * (1.0 - diamond * 0.13)
				draw_colored_polygon(PackedVector2Array([place + Vector2(-half, 0), place + Vector2(0, -half * 0.7), place + Vector2(half, 0), place + Vector2(0, half * 0.7)]), Color(1, 1, 1, 0.55 * clamp(thrust_share, 0.0, 1.0)))
	# The nozzle bell and the combustion chamber
	var bell = PackedVector2Array([throat + Vector2(-8, -size.y * 0.05), throat + Vector2(bell_length, -exit_half), throat + Vector2(bell_length, exit_half), throat + Vector2(-8, size.y * 0.05)])
	draw_colored_polygon(bell, Color(0.32, 0.28, 0.26))
	draw_polyline(PackedVector2Array([bell[0], bell[1]]), Color(0.6, 0.55, 0.5), 2.0, true)
	draw_polyline(PackedVector2Array([bell[3], bell[2]]), Color(0.6, 0.55, 0.5), 2.0, true)
	draw_rect(Rect2(throat + Vector2(-38, -size.y * 0.09), Vector2(32, size.y * 0.18)), Color(0.55, 0.57, 0.62))
	# A glow on the bell's lip when it's hot
	if thrust_share > 0.01:
		draw_line(bell[1], bell[2], Color(1.0, 0.55, 0.25, 0.6 * clamp(thrust_share, 0.0, 1.0)), 3.0)
	draw_string(get_theme_default_font(), Vector2(10, size.y - 8), "VACUUM CHAMBER" if in_vacuum else "SEA-LEVEL TEST STAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.66, 0.75))
