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
var rock_points = PackedVector2Array()  # the rock's outline (meters)
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

func _process(_delta):
	if is_visible_in_tree():
		queue_redraw()

func _draw():
	# Sky gradient and ground
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.09))
	var ground_top = to_screen(Vector2(0, 0)).y
	draw_rect(Rect2(Vector2(0, ground_top), Vector2(size.x, size.y - ground_top)), ground_color.darkened(0.35))
	draw_line(Vector2(0, ground_top), Vector2(size.x, ground_top), ground_color, 2.0)
	# A ruler along the ground every 0.5 m, like the scale bars in rover pictures
	for mark in range(-2, 7):
		var place = to_screen(Vector2(mark * 0.5, 0))
		draw_line(place, place + Vector2(0, 6), Color(1, 1, 1, 0.25), 1.0)
	# The rock
	if rock_points.size() >= 3:
		var screen_rock = PackedVector2Array()
		for point in rock_points:
			screen_rock.append(to_screen(point))
		draw_colored_polygon(screen_rock, rock_color)
		screen_rock.append(screen_rock[0])
		draw_polyline(screen_rock, rock_color.lightened(0.3), 1.5, true)
	# The sample spot (it pulses until the sample is taken)
	if not spot_taken:
		var pulse = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
		draw_arc(to_screen(spot), 9.0, 0.0, TAU, 24, Color(SPOT_COLOR, pulse), 2.0, true)
		draw_line(to_screen(spot), to_screen(spot + spot_normal * 0.18), Color(SPOT_COLOR, 0.5), 1.0, true)
	# The rover's body and the sample inlet
	var deck_left = to_screen(Vector2(-1.4, 1.05))
	draw_rect(Rect2(deck_left, Vector2(1.8 * pixels_per_meter, 0.5 * pixels_per_meter)), Color(0.75, 0.77, 0.8))
	draw_rect(Rect2(deck_left + Vector2(0, 0.5 * pixels_per_meter), Vector2(1.8 * pixels_per_meter, 0.1 * pixels_per_meter)), Color(0.3, 0.32, 0.36))
	for wheel_x in [-1.15, -0.5, 0.15]:
		draw_circle(to_screen(Vector2(wheel_x, 0.25)), 0.25 * pixels_per_meter, Color(0.15, 0.15, 0.17))
		draw_circle(to_screen(Vector2(wheel_x, 0.25)), 0.1 * pixels_per_meter, Color(0.5, 0.52, 0.56))
	var inlet_screen = to_screen(inlet)
	draw_rect(Rect2(inlet_screen - Vector2(14, 8), Vector2(28, 12)), Color(0.2, 0.22, 0.26))
	draw_rect(Rect2(inlet_screen - Vector2(14, 8), Vector2(28, 12)), Color(1.0, 0.82, 0.35, 0.9 if holding_sample else 0.4), false, 1.5)
	draw_string(get_theme_default_font(), inlet_screen + Vector2(-26, -14), "SAMPLE INLET", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.82, 0.35, 0.8))
	# The arm: shoulder, upper arm, elbow, forearm, wrist and the tool turret
	var shoulder = to_screen(base)
	var elbow = to_screen(elbow_position())
	var wrist = to_screen(wrist_position())
	var tip = to_screen(tool_tip())
	var arm_color = ARM_COLOR.lerp(Color(1.0, 0.4, 0.35), clamp(stress / 100.0, 0.0, 1.0))
	draw_line(shoulder, elbow, arm_color, 7.0, true)
	draw_line(elbow, wrist, arm_color, 6.0, true)
	draw_line(wrist, tip, Color(0.9, 0.75, 0.4), 4.0, true)
	for joint in [shoulder, elbow, wrist]:
		draw_circle(joint, 6.0, JOINT_COLOR)
		draw_arc(joint, 6.0, 0.0, TAU, 16, arm_color, 1.5, true)
	if holding_sample:
		draw_circle(tip, 5.0, Color(1.0, 0.82, 0.35))
	if tool_active:
		for spark in 4:
			var spray = Vector2(randf_range(-1, 1), randf_range(-1, 0.2)).normalized() * randf_range(4, 14)
			draw_circle(tip + spray, 1.5, Color(1.0, 0.85, 0.5))
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.3, 0.25, flash * 0.25))
	draw_string(get_theme_default_font(), tip + Vector2(10, 4), tool_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.75, 0.4))
