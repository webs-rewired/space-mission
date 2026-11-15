extends Control

# The side view of the robotic arm in the Sample Lab (res://scenes/sample_lab.tscn): the rover's deck, the arm's
# two joints and its tool turret, the ground, the target rock with the marked sample spot, and the sample inlet
# on the deck. sample_lab.gd moves the joints and fills in the numbers; this only draws. Lengths are in meters.

const ARM_COLOR = Color(0.82, 0.85, 0.9)
const JOINT_COLOR = Color(0.3, 0.33, 0.4)
const SPOT_COLOR = Color(0.45, 1.0, 0.85)
const GROUND_COLOR = Color(0.45, 0.28, 0.18)

var pixels_per_meter = 170.0
var ground_color = GROUND_COLOR
var rock_color = Color(0.35, 0.3, 0.28)
var base = Vector2(0.0, 0.9)          # the arm's shoulder, on the rover deck (meters: x forward, y up)
var shoulder_angle = 1.2              # radians, measured up from straight ahead
var elbow_angle = -1.6
var tool_angle = -1.57                # the turret's direction (radians, world angle)
var upper_length = 1.0
var lower_length = 0.8
var tool_length = 0.25
var rock_points = PackedVector2Array()  # the target rock's outline (meters)
var rocks = []                          # every rock in view: {"points", "color", "look", "features"} (set_rocks)
var soil_patch = {}                     # a scoop site's soil heap at the spot: {"color", "look"} (empty for rock sites)
var abraded = false                     # the abrasion patch is ground: fresh rock shows at the spot
var fresh_color = Color(0.5, 0.5, 0.5)  # the rock's true color under its dusty rind
var tool_wiggle = 0.0                   # the scoop shaking its sieve (radians)
var spot = Vector2(1.4, 0.3)          # the sample spot (meters)
var spot_normal = Vector2(0, 1)   # straight up (in these meters y points up, unlike the screen)
var inlet = Vector2(0.25, 1.05)       # where the sample goes in, on the front of the deck (within the arm's reach,
                                      # like the sample inlets on the front of Curiosity's deck)
var tool_name = "DRILL"
var tool_active = false
var holding_sample = false
var spot_taken = false
var stress = 0.0
var flash = 0.0

func origin():
	return Vector2(size.x * 0.3, size.y * 0.78)

func to_screen(place):
	return origin() + Vector2(place.x, -place.y) * pixels_per_meter

func elbow_position():
	return base + Vector2(cos(shoulder_angle), sin(shoulder_angle)) * upper_length

func wrist_position():
	return elbow_position() + Vector2(cos(shoulder_angle + elbow_angle), sin(shoulder_angle + elbow_angle)) * lower_length

func tool_tip():
	return wrist_position() + Vector2(cos(tool_angle), sin(tool_angle)) * tool_length

var sky_top = Color(0.02, 0.03, 0.05)     # the sky (sample_lab.gd sets it for the world: butterscotch on Mars,
var sky_horizon = Color(0.06, 0.07, 0.1)  # black on airless worlds, orange haze on Titan)
var airless = true                        # stars show in a black sky
var clock = 0.0
var pebbles = []                          # [place (meters), size, shade] scattered on the ground
var hills = PackedFloat32Array()          # heights of the far hills across the view
var stars = []

func _ready():
	var random = RandomNumberGenerator.new()
	random.seed = 913
	for index in 90:
		pebbles.append([Vector2(random.randf_range(-3.0, 5.0), random.randf_range(-0.02, -0.9)), random.randf_range(0.015, 0.06), random.randf_range(-0.15, 0.15)])
	for index in 65:
		hills.append(random.randf())
	for index in 80:
		stars.append([Vector2(random.randf(), random.randf() * 0.6), random.randf_range(0.2, 0.7)])

func _process(delta):
	clock += delta
	if is_visible_in_tree():
		queue_redraw()

func _draw():
	var ground_top = to_screen(Vector2(0, 0)).y
	# The sky: a gradient from the top down to the horizon, with stars where there's no air
	var sky = PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, ground_top), Vector2(0, ground_top)])
	draw_polygon(sky, PackedColorArray([sky_top, sky_top, sky_horizon, sky_horizon]))
	if airless:
		for star in stars:
			draw_circle(star[0] * Vector2(size.x, ground_top), 0.9, Color(1, 1, 1, star[1]))
	# Far hills, a little lighter than the ground (hazy with distance)
	var hill_line = PackedVector2Array()
	var hill_colors = PackedColorArray()
	var far_color = ground_color.lerp(sky_horizon, 0.45)
	hill_line.append(Vector2(0, ground_top))
	for index in hills.size():
		var x = size.x * index / float(hills.size() - 1)
		var wave = sin(index * 0.35) * 0.5 + 0.5
		hill_line.append(Vector2(x, ground_top - 10.0 - (wave * 0.7 + hills[index] * 0.3) * 34.0))
	hill_line.append(Vector2(size.x, ground_top))
	for point in hill_line:
		hill_colors.append(far_color)
	draw_polygon(hill_line, hill_colors)
	# The ground: darker with depth, scattered pebbles, and a ruler every 0.5 m like the scale bars in rover pictures
	var ground = PackedVector2Array([Vector2(0, ground_top), Vector2(size.x, ground_top), Vector2(size.x, size.y), Vector2(0, size.y)])
	draw_polygon(ground, PackedColorArray([ground_color, ground_color, ground_color.darkened(0.55), ground_color.darkened(0.55)]))
	for pebble in pebbles:
		var place = to_screen(pebble[0])
		if place.y > size.y:
			continue
		var pebble_color = ground_color.lightened(0.15 + pebble[2]) if pebble[2] > 0 else ground_color.darkened(-pebble[2] * 2.0 + 0.1)
		draw_circle(place + Vector2(1.5, 1.5), pebble[1] * pixels_per_meter, Color(0, 0, 0, 0.25))
		draw_circle(place, pebble[1] * pixels_per_meter, pebble_color)
	draw_line(Vector2(0, ground_top), Vector2(size.x, ground_top), ground_color.lightened(0.2), 2.0)
	for mark in range(-2, 7):
		var place = to_screen(Vector2(mark * 0.5, 0))
		draw_line(place, place + Vector2(0, 6), Color(1, 1, 1, 0.25), 1.0)
	# The rocks, each with its own texture (geology_samples.gd LOOKS), and a scoop site's soil heap
	for rock in rocks:
		draw_rock(rock, ground_top)
	if not soil_patch.is_empty():
		draw_soil_patch(ground_top)
	if rocks.is_empty() and rock_points.size() >= 3:
		var screen_rock = PackedVector2Array()
		var left_x = INF
		var right_x = -INF
		for point in rock_points:
			var place = to_screen(point)
			screen_rock.append(place)
			left_x = min(left_x, place.x)
			right_x = max(right_x, place.x)
		var shadow = PackedVector2Array()
		for step in 24:
			var angle = TAU * step / 24.0
			shadow.append(Vector2((left_x + right_x) / 2.0 + 18.0, ground_top + 3.0) + Vector2(cos(angle) * (right_x - left_x) * 0.62, sin(angle) * 7.0))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.3))
		draw_colored_polygon(screen_rock, rock_color.darkened(0.25))
		# the sunlit upper left part
		var lit = PackedVector2Array()
		for place in screen_rock:
			lit.append(place.lerp(Vector2(left_x, ground_top - (right_x - left_x) * 0.6), 0.18))
		draw_colored_polygon(lit, rock_color)
		for layer in 4:
			var layer_y = lerp(ground_top, screen_rock[1].y, (layer + 1) / 5.0)
			draw_line(Vector2(left_x + 6, layer_y), Vector2(right_x - 6, layer_y + 2), Color(rock_color.lightened(0.2), 0.35), 1.0, true)
		screen_rock.append(screen_rock[0])
		draw_polyline(screen_rock, rock_color.lightened(0.3), 1.5, true)
	# The abrasion patch: a stripe of fresh, unweathered rock where the abrader ground the rind away
	if abraded:
		var patch_center = to_screen(spot)
		var across = Vector2(spot_normal.y, spot_normal.x) * 0.045 * pixels_per_meter
		draw_line(patch_center - across, patch_center + across, fresh_color.lightened(0.15), 4.0, true)
	# The sample spot (it pulses until the sample is taken)
	if not spot_taken:
		var pulse = 0.6 + 0.4 * sin(clock * 4.0)
		draw_arc(to_screen(spot), 9.0, 0.0, TAU, 24, Color(SPOT_COLOR, pulse), 2.0, true)
		draw_arc(to_screen(spot), 14.0 + 4.0 * pulse, 0.0, TAU, 24, Color(SPOT_COLOR, 0.25 * pulse), 1.0, true)
		draw_line(to_screen(spot), to_screen(spot + spot_normal * 0.18), Color(SPOT_COLOR, 0.5), 1.0, true)
	draw_rover()
	var inlet_screen = to_screen(inlet)
	draw_rect(Rect2(inlet_screen - Vector2(14, 8), Vector2(28, 12)), Color(0.2, 0.22, 0.26))
	draw_rect(Rect2(inlet_screen - Vector2(14, 8), Vector2(28, 12)), Color(1.0, 0.82, 0.35, 0.9 if holding_sample else 0.4 + 0.2 * sin(clock * 3.0)), false, 1.5)
	draw_string(get_theme_default_font(), inlet_screen + Vector2(-26, -14), "SAMPLE INLET", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.82, 0.35, 0.8))
	draw_arm()

# The rover, side on: rocker-bogie wheels, the chassis, the RTG at the back, the mast with its camera head
func draw_rover():
	var unit = pixels_per_meter
	var ground_top = to_screen(Vector2(0, 0)).y
	# Shadow
	var shadow = PackedVector2Array()
	for step in 24:
		var angle = TAU * step / 24.0
		shadow.append(to_screen(Vector2(-0.5, 0)) + Vector2(cos(angle) * 1.1 * unit, sin(angle) * 0.06 * unit + 2.0))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	# Suspension (rocker and bogie) behind the wheels
	var hub_points = [Vector2(-1.15, 0.25), Vector2(-0.5, 0.25), Vector2(0.15, 0.25)]
	var pivot = Vector2(-0.6, 0.72)
	var bogie = Vector2(-0.83, 0.5)
	var suspension_color = Color(0.55, 0.57, 0.6)
	draw_line(to_screen(pivot), to_screen(hub_points[2]), suspension_color, 0.05 * unit, true)
	draw_line(to_screen(pivot), to_screen(bogie), suspension_color, 0.05 * unit, true)
	draw_line(to_screen(bogie), to_screen(hub_points[0]), suspension_color, 0.045 * unit, true)
	draw_line(to_screen(bogie), to_screen(hub_points[1]), suspension_color, 0.045 * unit, true)
	# Chassis: a warm white box with panel lines, and a dark underside
	var deck_left = to_screen(Vector2(-1.4, 1.05))
	var body = Rect2(deck_left, Vector2(1.8 * unit, 0.42 * unit))
	draw_rect(Rect2(body.position + Vector2(0, body.size.y), Vector2(body.size.x, 0.12 * unit)), Color(0.22, 0.23, 0.26))
	draw_rect(body, Color(0.86, 0.85, 0.82))
	draw_rect(Rect2(body.position, Vector2(body.size.x, 0.05 * unit)), Color(0.95, 0.94, 0.9))
	for panel in 5:
		var x = body.position.x + body.size.x * (panel + 1) / 6.0
		draw_line(Vector2(x, body.position.y + 4), Vector2(x, body.end.y - 3), Color(0.6, 0.6, 0.62, 0.6), 1.0)
	draw_rect(body, Color(0.5, 0.5, 0.52), false, 1.0)
	# RTG at the back: a dark finned cylinder angled up
	var rtg_base = to_screen(Vector2(-1.4, 1.25))
	var rtg_end = to_screen(Vector2(-1.85, 1.55))
	draw_line(rtg_base, rtg_end, Color(0.25, 0.25, 0.27), 0.22 * unit, true)
	for fin in 5:
		var along = rtg_base.lerp(rtg_end, (fin + 0.5) / 5.0)
		var across = (rtg_end - rtg_base).normalized().rotated(PI / 2.0) * 0.17 * unit
		draw_line(along - across, along + across, Color(0.18, 0.18, 0.2), 2.0, true)
	# Mast with the camera head at the front left
	var mast_foot = to_screen(Vector2(-0.15, 1.47))
	var mast_top = to_screen(Vector2(-0.15, 2.05))
	draw_line(mast_foot, mast_top, Color(0.75, 0.76, 0.78), 0.06 * unit, true)
	draw_rect(Rect2(mast_top - Vector2(0.14, 0.08) * unit, Vector2(0.3, 0.16) * unit), Color(0.82, 0.82, 0.8))
	draw_circle(mast_top + Vector2(0.1 * unit, 0), 0.035 * unit, Color(0.1, 0.12, 0.2))
	# Wheels with grousers, slowly settling
	for hub in hub_points:
		var center = to_screen(hub)
		var radius = 0.25 * unit
		draw_circle(center, radius, Color(0.62, 0.63, 0.66))
		draw_circle(center, radius * 0.82, Color(0.3, 0.31, 0.34))
		for spoke in 8:
			var angle = TAU * spoke / 8.0
			draw_line(center + Vector2(cos(angle), sin(angle)) * radius * 0.2, center + Vector2(cos(angle), sin(angle)) * radius * 0.8, Color(0.62, 0.63, 0.66), 2.0, true)
		for grouser in 16:
			var angle = TAU * grouser / 16.0
			draw_line(center + Vector2(cos(angle), sin(angle)) * radius * 0.9, center + Vector2(cos(angle), sin(angle)) * radius * 1.05, Color(0.45, 0.46, 0.5), 2.0, true)
		draw_circle(center, radius * 0.18, Color(0.75, 0.76, 0.8))

# The rocks: set by sample_lab.gd as [{"points": PackedVector2Array (meters), "color", "look"}]. The texture
# marks (gas holes, crystals, layers...) are placed once here, inside each outline.
func set_rocks(new_rocks):
	rocks = new_rocks
	var random = RandomNumberGenerator.new()
	random.seed = 4711 + new_rocks.size()
	for rock in rocks:
		var points = rock["points"]
		var low = Vector2(INF, INF)
		var high = Vector2(-INF, -INF)
		for point in points:
			low = Vector2(min(low.x, point.x), min(low.y, point.y))
			high = Vector2(max(high.x, point.x), max(high.y, point.y))
		var features = []
		for attempt in 120:
			var place = Vector2(random.randf_range(low.x, high.x), random.randf_range(low.y, high.y))
			if Geometry2D.is_point_in_polygon(place, points) and features.size() < 26:
				features.append([place, random.randf_range(0.6, 1.4), random.randf_range(-1.0, 1.0)])
		rock["features"] = features

func draw_rock(rock, ground_top):
	var screen_rock = PackedVector2Array()
	var left_x = INF
	var right_x = -INF
	var top_y = INF
	for point in rock["points"]:
		var place = to_screen(point)
		screen_rock.append(place)
		left_x = min(left_x, place.x)
		right_x = max(right_x, place.x)
		top_y = min(top_y, place.y)
	var color = rock["color"]
	var shadow = PackedVector2Array()
	for step in 24:
		var angle = TAU * step / 24.0
		shadow.append(Vector2((left_x + right_x) / 2.0 + 18.0, ground_top + 3.0) + Vector2(cos(angle) * (right_x - left_x) * 0.62, sin(angle) * 7.0))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.3))
	draw_colored_polygon(screen_rock, color.darkened(0.25))
	# the sunlit upper left part
	var lit = PackedVector2Array()
	for place in screen_rock:
		lit.append(place.lerp(Vector2(left_x, ground_top - (right_x - left_x) * 0.6), 0.18))
	draw_colored_polygon(lit, color)
	var look = rock["look"]
	if look == "vesicles":
		for feature in rock["features"]:
			draw_circle(to_screen(feature[0]), 1.6 * feature[1], color.darkened(0.55))
	elif look == "crystals":
		for feature in rock["features"]:
			var place = to_screen(feature[0])
			var glint = Color(color.lightened(0.5), 0.6 + 0.4 * sin(clock * 2.0 + feature[2] * 6.0))
			draw_line(place - Vector2(2.5, 0) * feature[1], place + Vector2(2.5, 0) * feature[1], glint, 1.2)
			draw_line(place - Vector2(0, 2.5) * feature[1], place + Vector2(0, 2.5) * feature[1], glint, 1.2)
	elif look == "spheres":
		for feature in rock["features"]:
			var place = to_screen(feature[0])
			draw_circle(place, 2.4 * feature[1], color.darkened(0.35))
			draw_circle(place - Vector2(0.7, 0.7), 0.9 * feature[1], color.lightened(0.35))
	elif look == "vein":
		var vein = PackedVector2Array()
		for step in 9:
			var along = step / 8.0
			vein.append(Vector2(lerp(left_x + 4.0, right_x - 4.0, along), lerp(ground_top - 4.0, top_y + 8.0, along) + sin(along * 17.0) * 3.0))
		draw_polyline(vein, Color(0.95, 0.93, 0.88), 3.0, true)
	elif look in ["layers", "soil"]:
		for layer in 6:
			var layer_y = lerp(ground_top, top_y, (layer + 1) / 7.0)
			draw_line(Vector2(left_x + 5, layer_y), Vector2(right_x - 5, layer_y + 1.5), Color(color.lightened(0.25), 0.4), 1.0, true)
	elif look == "fragments":
		for feature in rock["features"].slice(0, 12):
			var place = to_screen(feature[0])
			var piece = 3.5 * feature[1]
			draw_colored_polygon(PackedVector2Array([place + Vector2(-piece, 0), place + Vector2(0, -piece * 0.8), place + Vector2(piece, piece * 0.3), place + Vector2(0, piece)]),
				color.lightened(0.25) if feature[2] > 0.0 else color.darkened(0.35))
	elif look == "crust":
		var coat = PackedVector2Array()
		for index in range(1, screen_rock.size() - 1):
			coat.append(screen_rock[index])
		draw_polyline(coat, color.lightened(0.45), 4.0, true)
	elif look == "ice":
		draw_line(Vector2(left_x + (right_x - left_x) * 0.25, top_y + 6.0), Vector2(left_x + (right_x - left_x) * 0.55, top_y + 10.0), Color(1, 1, 1, 0.55), 2.0, true)
	var outline = screen_rock.duplicate()
	outline.append(screen_rock[0])
	draw_polyline(outline, color.lightened(0.3), 1.5, true)

# A scoop site's sample: a low heap of loose soil, colored like the material it is
func draw_soil_patch(ground_top):
	var center = to_screen(spot)
	var color = soil_patch["color"]
	var heap = PackedVector2Array()
	for step in 17:
		var along = step / 16.0
		heap.append(Vector2(center.x - 30.0 + 60.0 * along, ground_top + 1.0 - sin(along * PI) * 8.0))
	draw_colored_polygon(heap, color)
	for grain in 14:
		var x = center.x - 24.0 + fmod(grain * 37.0, 48.0)
		draw_circle(Vector2(x, ground_top - 2.0 - fmod(grain * 13.0, 4.0)), 1.1, color.lightened(0.3) if grain % 2 == 0 else color.darkened(0.3))

func draw_arm():
	# The arm: shoulder, upper arm, elbow, forearm, wrist and the tool turret (shaking when it sieves)
	var shoulder = to_screen(base)
	var elbow = to_screen(elbow_position())
	var wrist = to_screen(wrist_position())
	var tip = to_screen(wrist_position() + Vector2(cos(tool_angle + tool_wiggle), sin(tool_angle + tool_wiggle)) * tool_length)
	var arm_color = ARM_COLOR.lerp(Color(1.0, 0.4, 0.35), clamp(stress / 100.0, 0.0, 1.0))
	draw_line(shoulder + Vector2(3, 3), elbow + Vector2(3, 3), Color(0, 0, 0, 0.25), 9.0, true)
	draw_line(elbow + Vector2(3, 3), wrist + Vector2(3, 3), Color(0, 0, 0, 0.25), 8.0, true)
	draw_line(shoulder, elbow, arm_color.darkened(0.35), 10.0, true)
	draw_line(shoulder, elbow, arm_color, 7.0, true)
	draw_line(elbow, wrist, arm_color.darkened(0.35), 9.0, true)
	draw_line(elbow, wrist, arm_color, 6.0, true)
	draw_line(wrist, tip, Color(0.9, 0.75, 0.4), 4.0, true)
	for joint in [shoulder, elbow, wrist]:
		draw_circle(joint, 6.0, JOINT_COLOR)
		draw_arc(joint, 6.0, 0.0, TAU, 16, arm_color, 1.5, true)
	if holding_sample:
		draw_circle(tip, 5.0, Color(1.0, 0.82, 0.35))
	if tool_active:
		for spark in 10:
			var spray = Vector2(randf_range(-1, 1), randf_range(-1, 0.1)).normalized() * randf_range(4, 22)
			draw_circle(tip + spray, randf_range(1.0, 2.5), Color(ground_color.lightened(0.4), randf_range(0.4, 0.9)))
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.3, 0.25, flash * 0.25))
	draw_string(get_theme_default_font(), tip + Vector2(10, 4), tool_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.75, 0.4))
