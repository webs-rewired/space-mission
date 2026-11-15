extends Control

# MINIGAMES: ROBOTIC SAMPLE COLLECTION and GEOLOGICAL IDENTIFICATION (res://scenes/sample_lab.tscn)
# Opened when the rover studies a glowing target on the ground (surface_view.gd, the E key).
#
# 1. COLLECT: drive the robotic arm's joints (shoulder, elbow, turret) to put the tool on the marked spot,
#    square to the surface. Joints move at real arm speeds and have real limits, and the whole arm collides with
#    the rocks and the ground, not just the tool. The spot is different every time:
#      boulder top    drill straight down into the top of a rock
#      rock face      the spot is on a sloping face: turn the tool square to it
#      behind a rock  another rock sits in the way: lift the arm over it
#      between rocks  loose soil squeezed between two rocks: come straight down into the gap
#    With the Drill it works like Perseverance's coring drill: first ABRADE a patch (grind off the dusty,
#    weathered rind to see fresh rock; the bit skates on the hard surface, so keep it square with Q/E), then
#    DRILL the core while holding the arm still (Curiosity's drill had a real fault from this in 2016).
#    Without the Drill it scoops loose soil like Phoenix and Curiosity did: SCOOP, then SIEVE it by shaking the
#    scoop (tap Q and E in turn) so only the fine grains go to the instruments, like Curiosity's CHIMRA sieve.
#    Last, carry the sample to the inlet on the deck. With the Robotic arm instrument it's a long 2 m arm like
#    Curiosity's; without it, a short sampling arm.
#    STRAIN: bumping things or moving while the drill turns strains the arm. At 100% the arm FAULTS: its motors
#    cut out for a few seconds, a sample in the tool falls out, and the sample gets worse. Three faults and the
#    arm team calls off the collection to protect the arm.
#    On Standard and Veteran the arm has a time window, like a rover's plan for the day; when it runs out the team
#    on Earth finishes the job (roughly).
# 2. IDENTIFY: run your probe's instruments on the sample (only the ones you built it with), read the results,
#    and decide what it is. There's only enough power for a few instrument runs, so choose wisely. Abrading the
#    rock first gives a free look at the fresh rock (like Perseverance's close-up camera on its abrasion patches).
#    Every sample is a real material found on this world (scripts/geology_samples.gd).
#
# SCORE (0-100): collection (clean 40, rough 20, damaged 5) + identification (40, +10 with two instrument runs or
# fewer) + up to 10 for finishing inside the time window. Gold 85, silver 65, bronze 40; every medal earns
# research points right away, and the best score on each world is kept.
#
# start(target_name, sample_id = ""): sample_id picks the material (surface_view.gd gives each target its own);
# empty picks one at random for this world.
# Sends finished(result): {"sample", "name", "correct", "science", "collection", "instruments_used", "score", "medal"}

signal finished(result)

const GeologySamples = preload("res://scripts/geology_samples.gd")
const Career = preload("res://scripts/career.gd")
const JOINT_SPEED = 0.45              # radians per second (robot arms move slowly and carefully)
const ABRADE_SECONDS = 1.8
const DRILL_SECONDS = 3.0
const SCOOP_SECONDS = 1.2
const SIEVE_SHAKES = 6                # Q, E, Q, E... to shake the fine grains through the sieve
const SPOT_REACH = 0.07               # meters: how close the tool must be to the spot
const SQUARE_TOLERANCE = deg_to_rad(20.0)
const INSTRUMENT_RUNS = [5, 3, 2]     # instrument runs the battery allows: Cadet, Standard, Veteran
const ARM_WINDOW = [0.0, 150.0, 100.0]   # seconds of arm time (0: no limit), by difficulty
const FAULT_SECONDS = 3.0
const MEDALS = [[85, "GOLD", Color(1.0, 0.82, 0.35), 5], [65, "SILVER", Color(0.8, 0.85, 0.92), 3], [40, "BRONZE", Color(0.85, 0.55, 0.35), 1]]
# Which sites each tool can get, most common first; harder difficulties get more of the awkward ones
const DRILL_SITES = [["top", "face", "behind"], ["top", "face", "behind"], ["face", "behind", "top"]]
const SCOOP_SITES = [["soil", "between", "behind"], ["between", "soil", "behind"], ["between", "behind", "soil"]]
const SITE_NAMES = {"top": "Boulder top", "face": "Sloping rock face", "behind": "Behind another rock", "soil": "Loose soil", "between": "Soil between two rocks"}
const INSTRUMENT_NAMES = {"camera": "Camera", "arm": "Hand lens (arm)", "spectrometer": "Infrared spectrometer",
	"thermal": "Thermal imager", "mass_spec": "Mass spectrometer", "drill": "Drill"}
const INSTRUMENT_PARTS = {"arm": "instrument_arm", "spectrometer": "instrument_spectrometer", "thermal": "instrument_thermal",
	"mass_spec": "instrument_mass_spec", "drill": "instrument_drill"}

@onready var title_label: Label = $Header/Title
@onready var stage_label: Label = $Header/Stage
@onready var collect_stage: Control = $CollectStage
@onready var arm_view: Control = $CollectStage/ArmView
@onready var kicker_label: Label = $CollectStage/Side/Column/Kicker
@onready var collect_help: Label = $CollectStage/Side/Column/Help
@onready var steps_label: Label = $CollectStage/Side/Column/Steps
@onready var collect_status: Label = $CollectStage/Side/Column/Status
@onready var work_title: Label = $CollectStage/Side/Column/WorkTitle
@onready var work_bar: ProgressBar = $CollectStage/Side/Column/WorkBar
@onready var stress_bar: ProgressBar = $CollectStage/Side/Column/StressBar
@onready var keys_row: Control = $CollectStage/Side/Column/KeyHints
@onready var skip_button: Button = $CollectStage/Side/Column/SkipButton
@onready var identify_stage: Control = $IdentifyStage
@onready var instrument_buttons: VBoxContainer = $IdentifyStage/Instruments/Column/Buttons
@onready var runs_label: Label = $IdentifyStage/Instruments/Column/Runs
@onready var readings_list: VBoxContainer = $IdentifyStage/Readings/Scroll/List
@onready var candidate_buttons: VBoxContainer = $IdentifyStage/Answers/Column/Buttons
@onready var answer_text: Label = $IdentifyStage/Answers/Column/AnswerText
@onready var continue_button: Button = $IdentifyStage/Answers/Column/ContinueButton

var sample_id = ""
var sample = {}
var target_name = ""
var has_drill = false
var site_kind = "top"
var step = "reach"            # "abrade" → "drill" (drill) or "scoop" → "sieve" (scoop), then "deliver"
var work = 0.0                # progress of the current step, 0 to 1
var abraded = false
var shakes = 0
var last_shake_key = 0
var skate = 0.0               # how fast the abrading bit is skating sideways (radians per second)
var jammed = false
var collected = false
var collection = "clean"
var fault_seconds = 0.0       # an arm fault: the arm is frozen while it recovers
var faults = 0                # three faults and the arm team calls off the collection
var arm_seconds = 0.0         # time spent at the arm (for the time window)
var window_seconds = 0.0
var time_points = 10
var runs_left = 3
var instruments_used = []
var answered = false
var was_correct = false
var science = 0
var score = 0
var medal_name = ""
var inputs_override = {}      # (the automatic tests drive the arm with this instead of the keyboard)
var site_override = ""        # (and can ask for one kind of site)

func _ready():
	identify_stage.visible = false
	continue_button.visible = false
	skip_button.pressed.connect(collect_automatically)
	continue_button.pressed.connect(_on_continue_pressed)

func held(key):
	if inputs_override.has(key):
		return inputs_override[key]
	return Input.is_key_pressed(key)

func start(new_target_name, chosen_sample := ""):
	get_viewport().gui_release_focus()
	target_name = new_target_name
	var world = GameState.destination
	var choices_here = GeologySamples.samples_for(world)
	sample_id = chosen_sample if GeologySamples.SAMPLES.has(chosen_sample) else choices_here[randi() % choices_here.size()]
	sample = GeologySamples.SAMPLES[sample_id]
	has_drill = "instrument_drill" in GameState.instruments
	var long_arm = "instrument_arm" in GameState.instruments
	title_label.text = "SAMPLE LAB  ·  %s" % target_name.to_upper()
	stage_label.text = "1  COLLECT     ›     2  IDENTIFY"
	# The arm: a 2 m arm like Curiosity's, or a short sampling arm
	arm_view.upper_length = 1.05 if long_arm else 0.7
	arm_view.lower_length = 0.95 if long_arm else 0.6
	arm_view.tool_length = 0.25 if long_arm else 0.2
	# Colors: the ground and sky of this world
	if world in ["Europa", "Enceladus", "Titan", "Pluto", "Triton", "Charon", "Ganymede", "Callisto", "Eris", "Haumea", "Makemake", "Titania"]:
		arm_view.ground_color = Color(0.55, 0.6, 0.68)
	elif world in ["Moon", "Mercury", "Ceres"]:
		arm_view.ground_color = Color(0.42, 0.42, 0.44)
	elif world == "Io":
		arm_view.ground_color = Color(0.7, 0.6, 0.25)
	# The sky over the rock: butterscotch on Mars (dust in the air), orange haze on Titan, black everywhere airless
	var skies = {"Mars": [Color(0.42, 0.3, 0.22), Color(0.78, 0.6, 0.42), false], "Titan": [Color(0.35, 0.22, 0.08), Color(0.75, 0.5, 0.2), false],
		"Venus": [Color(0.4, 0.3, 0.12), Color(0.8, 0.62, 0.3), false]}
	var sky = skies.get(world, [Color(0.01, 0.01, 0.02), Color(0.04, 0.045, 0.06), true])
	arm_view.sky_top = sky[0]
	arm_view.sky_horizon = sky[1]
	arm_view.airless = sky[2]
	plan_site()   # (after the ground color, which the other rocks are tinted with)
	step = "abrade" if has_drill else "scoop"
	arm_view.tool_name = "ABRADER" if has_drill else "SCOOP"
	collect_help.text = "%s. Put the %s on the glowing spot, pointing straight into the surface." % [SITE_NAMES[site_kind], "drill" if has_drill else "scoop"] + ("" if has_drill else " (No drill on board: scoop the loose soil.)")
	if site_kind == "behind":
		collect_help.text += " Another rock is in the way: lift the arm over it."
	elif site_kind == "face":
		collect_help.text += " The face slopes: turn the tool (Q/E) square to it."
	elif site_kind == "between":
		collect_help.text += " The gap is narrow: come straight down."
	keys_row.hints = [["A D", "shoulder"], ["W S", "elbow"], ["Q E", "tool"], ["Space", "work / drop"]]
	runs_left = INSTRUMENT_RUNS[GameState.difficulty] + (1 if GameState.has_upgrade("lab_power") else 0)
	GameState.note_tech("lab_power", "an extra instrument run in the sample lab")
	window_seconds = ARM_WINDOW[clamp(GameState.difficulty, 0, 2)]
	update_steps()
	UiMotion.reveal_text(title_label, 0.1, 0.6, 0.4)
	UiMotion.slide_in($CollectStage/Side, 0.15, Vector2(30, 0), 0.5)

# ---------------------------------------------------------------------------
# The site: where the rocks are and where the sample spot is
# ---------------------------------------------------------------------------
func reach():
	return arm_view.upper_length + arm_view.lower_length

# A rock outline: five corners, its left face rising to a flat-ish top. steep makes the left face a slope you can
# drill into (for the "face" site).
func rock_outline(middle, width, height, steep := false):
	if steep:
		return PackedVector2Array([Vector2(middle - width, 0), Vector2(middle - width * 0.45, height * 0.92), Vector2(middle - width * 0.05, height),
			Vector2(middle + width * 0.5, height * 0.85), Vector2(middle + width, 0)])
	return PackedVector2Array([Vector2(middle - width, 0), Vector2(middle - width * 0.7, height * 0.8), Vector2(middle - width * 0.1, height),
		Vector2(middle + width * 0.5, height * 0.85), Vector2(middle + width, 0)])

# Picks this sample's site: tries the kinds this tool can get (DRILL_SITES / SCOOP_SITES) until one has a spot
# the arm can really reach without hitting anything (worked out with the arm's geometry, see pose_for)
func plan_site():
	var kinds = (DRILL_SITES if has_drill else SCOOP_SITES)[clamp(GameState.difficulty, 0, 2)].duplicate()
	# (mostly the first kind in the list, sometimes another)
	if randf() < 0.45:
		kinds.shuffle()
	if site_override != "":
		kinds = [site_override]
	var look = GeologySamples.look_of(sample_id)
	var other_color = arm_view.ground_color.lerp(Color(0.35, 0.33, 0.32), 0.5)
	for kind in kinds:
		for attempt in 70:
			var plan = try_site(kind, look, other_color)
			if not plan.is_empty():
				use_site(kind, plan)
				return
	# A placement every arm can always reach
	var middle = 1.0 if has_drill else 1.25
	var rock = {"points": rock_outline(middle, 0.4 if has_drill else 0.35, 0.2), "color": look[0] if has_drill else other_color, "look": look[1] if has_drill else "layers"}
	var spot = Vector2(middle - 0.04, 0.194) if has_drill else Vector2(middle - 0.5, 0.0)
	use_site("top" if has_drill else "soil", {"rocks": [rock], "spot": spot, "normal": Vector2(0, 1)})

func try_site(kind, look, other_color):
	var arm_reach = reach()
	var rocks = []
	var spot = Vector2.ZERO
	var normal = Vector2(0, 1)
	var target_rock = {}
	match kind:
		"top":
			var middle = randf_range(0.9, arm_reach * 0.85 + 0.35)
			var width = randf_range(0.3, 0.55)
			var height = randf_range(0.12, 0.42)
			target_rock = {"points": rock_outline(middle, width, height), "color": look[0], "look": look[1]}
			rocks.append(target_rock)
			spot = Vector2(middle - width * 0.1 + randf_range(-0.05, 0.12), height * 0.97)
		"face":
			var middle = randf_range(1.1, arm_reach * 0.85 + 0.6)
			var width = randf_range(0.4, 0.6)
			var height = randf_range(0.4, 0.7)
			var outline = rock_outline(middle, width, height, true)
			target_rock = {"points": outline, "color": look[0], "look": look[1]}
			rocks.append(target_rock)
			spot = outline[0].lerp(outline[1], randf_range(0.45, 0.7))
			var edge = outline[1] - outline[0]
			normal = Vector2(-edge.y, edge.x).normalized()   # out of the face, toward the rover and up
		"behind":
			# The target past a low rock that's in the way
			var spot_x = randf_range(1.1, arm_reach * 0.9 + 0.3)
			if has_drill:
				var width = randf_range(0.28, 0.42)
				var height = randf_range(0.1, 0.25)
				var middle = spot_x + width * 0.1
				target_rock = {"points": rock_outline(middle, width, height), "color": look[0], "look": look[1]}
				rocks.append(target_rock)
				spot = Vector2(spot_x, height * 0.97)
				var blocker_width = randf_range(0.15, 0.25)
				var blocker_middle = middle - width - blocker_width - randf_range(0.08, 0.2)
				rocks.append({"points": rock_outline(blocker_middle, blocker_width, height + randf_range(0.15, 0.3)), "color": other_color, "look": "fragments"})
			else:
				spot = Vector2(spot_x, 0.0)
				var blocker_width = randf_range(0.15, 0.25)
				var blocker_middle = spot_x - 0.12 - blocker_width - randf_range(0.0, 0.12)
				rocks.append({"points": rock_outline(blocker_middle, blocker_width, randf_range(0.25, 0.42)), "color": other_color, "look": "fragments"})
				rocks.append({"points": rock_outline(spot_x + 0.5, 0.3, 0.3), "color": other_color, "look": "layers"})
		"soil":
			var middle = randf_range(1.0, arm_reach * 0.85 + 0.5)
			var width = randf_range(0.3, 0.5)
			rocks.append({"points": rock_outline(middle, width, randf_range(0.15, 0.4)), "color": other_color, "look": "layers"})
			spot = Vector2(middle - width - randf_range(0.12, 0.25), 0.0)
		"between":
			var spot_x = randf_range(0.9, arm_reach * 0.85 + 0.3)
			var gap = randf_range(0.13, 0.2)
			var left_width = randf_range(0.15, 0.25)
			var right_width = randf_range(0.2, 0.35)
			rocks.append({"points": rock_outline(spot_x - gap - left_width, left_width, randf_range(0.15, 0.3)), "color": other_color, "look": "fragments"})
			rocks.append({"points": rock_outline(spot_x + gap + right_width, right_width, randf_range(0.2, 0.4)), "color": other_color, "look": "layers"})
			spot = Vector2(spot_x, 0.0)
	# The tool has to reach the spot pointing straight into it, with the whole arm clear of everything
	var wrist_needed = spot + normal * arm_view.tool_length
	if spot.x < 0.6 or wrist_needed.y < 0.05:
		return {}
	for rock in rocks:
		if rock["points"][0].x < 0.45:
			return {}   # (too close to the rover's own wheels)
	var pose = pose_for(wrist_needed)
	if pose.is_empty():
		return {}
	var plan = {"rocks": rocks, "spot": spot, "normal": normal}
	if arm_blocked(pose[0], pose[1], atan2(-normal.y, -normal.x), plan):
		return {}
	return plan

# The shoulder and elbow angles that put the wrist at a place (the elbow-up solution, within the joints' limits and
# comfortably inside the arm's stretch), or empty if there are none
func pose_for(wrist_place):
	var upper = arm_view.upper_length
	var lower = arm_view.lower_length
	var to_wrist = wrist_place - arm_view.base
	var distance = to_wrist.length()
	if distance > reach() * 0.88 or distance < abs(upper - lower) + 0.15:
		return []
	var inner = acos(clamp((upper * upper + distance * distance - lower * lower) / (2.0 * upper * distance), -1.0, 1.0))
	var shoulder = atan2(to_wrist.y, to_wrist.x) + inner
	var elbow_place = arm_view.base + Vector2(cos(shoulder), sin(shoulder)) * upper
	var forearm = wrist_place - elbow_place
	var elbow = wrapf(atan2(forearm.y, forearm.x) - shoulder, -PI, PI)
	if shoulder < deg_to_rad(-10.0) or shoulder > deg_to_rad(170.0) or elbow < deg_to_rad(-165.0) or elbow > 0.0:
		return []
	return [shoulder, elbow]

# Would the arm in this pose hit a rock or the ground? Checks points all along the forearm and the tool.
func arm_blocked(shoulder, elbow, tool_angle, plan):
	var elbow_place = arm_view.base + Vector2(cos(shoulder), sin(shoulder)) * arm_view.upper_length
	var wrist_place = elbow_place + Vector2(cos(shoulder + elbow), sin(shoulder + elbow)) * arm_view.lower_length
	var tip = wrist_place + Vector2(cos(tool_angle), sin(tool_angle)) * arm_view.tool_length
	for index in 13:
		var along = index / 12.0
		if point_hits(elbow_place.lerp(wrist_place, along), plan["rocks"], plan["spot"]) or point_hits(wrist_place.lerp(tip, along * 0.85), plan["rocks"], plan["spot"]):
			return true
	return point_hits(elbow_place, plan["rocks"], plan["spot"])

func use_site(kind, plan):
	site_kind = kind
	arm_view.spot = plan["spot"]
	arm_view.spot_normal = plan["normal"]
	arm_view.set_rocks(plan["rocks"])
	arm_view.rock_points = plan["rocks"][0]["points"]
	var look = GeologySamples.look_of(sample_id)
	arm_view.fresh_color = look[0].lightened(0.1)
	if not has_drill:
		arm_view.soil_patch = {"color": look[0], "look": look[1]}

# ---------------------------------------------------------------------------
# Stage 1: collect
# ---------------------------------------------------------------------------
func _process(delta):
	if not collect_stage.visible:
		return
	delta = min(delta, 0.05)   # (a slow frame doesn't throw the arm a long way)
	arm_seconds += delta
	# An arm fault: too much strain and the arm's motors cut out to protect themselves. It backs away from what
	# it hit and nothing moves for a few seconds; each fault makes the sample worse, and the third ends the
	# collection (the arm team won't risk breaking a one-of-a-kind arm for one rock)
	if fault_seconds > 0.0:
		fault_seconds -= delta
		arm_view.flash = 0.5 + 0.3 * sin(fault_seconds * 12.0)
		arm_view.shoulder_angle = min(arm_view.shoulder_angle + 0.25 * delta, deg_to_rad(150.0))
		collect_status.text = "ARM FAULT %d of 3: the motors cut out to protect the arm.\nRecovering... %d s" % [faults, int(ceil(fault_seconds))]
		stress_bar.value = arm_view.stress
		if fault_seconds <= 0.0:
			arm_view.flash = 0.0
			if faults >= 3:
				collect_status.text = "Three arm faults: the arm team called off the collection to protect the arm."
				collection = "damaged"
				collected = true
				go_to_identify()
		return
	# The arm's time window for today
	if window_seconds > 0.0:
		var left = window_seconds - arm_seconds
		kicker_label.text = "STEP 1  ·  ROBOTIC ARM  ·  %d:%02d LEFT" % [int(max(left, 0.0)) / 60, int(max(left, 0.0)) % 60]
		kicker_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45) if left < 20.0 else Color(0.45, 0.8, 1.0))
		if left <= 0.0:
			collect_status.text = "The arm's time window ran out: the team on Earth finished the job, roughly."
			time_points = 0
			collection = "rough" if collection == "clean" else collection
			collected = true
			play_sound("error")
			go_to_identify()
			return
	var turning = 0.0
	var bending = 0.0
	var twisting = 0.0
	if held(KEY_A):
		turning += 1.0
	if held(KEY_D):
		turning -= 1.0
	if held(KEY_W):
		bending += 1.0
	if held(KEY_S):
		bending -= 1.0
	if held(KEY_Q):
		twisting += 1.0
	if held(KEY_E):
		twisting -= 1.0
	var moving_arm = turning != 0.0 or bending != 0.0
	var moving = moving_arm or twisting != 0.0
	var before = [arm_view.shoulder_angle, arm_view.elbow_angle, arm_view.tool_angle]
	var hits_before = arm_hit_count()   # (already touching something: moves that don't push it in deeper are allowed)
	# While sieving, Q and E shake the scoop instead of turning it
	if step != "sieve":
		arm_view.tool_angle = arm_view.tool_angle + twisting * JOINT_SPEED * 1.4 * delta
	arm_view.shoulder_angle = clamp(arm_view.shoulder_angle + turning * JOINT_SPEED * delta, deg_to_rad(-10.0), deg_to_rad(170.0))
	arm_view.elbow_angle = clamp(arm_view.elbow_angle + bending * JOINT_SPEED * delta, deg_to_rad(-165.0), deg_to_rad(0.0))
	# The arm can't go into the ground or the rocks: it stops, and a hard bump strains it
	if arm_hit_count() > hits_before:
		arm_view.shoulder_angle = before[0]
		arm_view.elbow_angle = before[1]
		arm_view.tool_angle = before[2]
		if moving:
			arm_view.stress = min(arm_view.stress + 30.0 * strain_factor() * delta, 100.0)
			arm_view.flash = 0.6
			if arm_view.stress > 25.0 and collection == "clean":
				collection = "rough"
	arm_view.flash = max(arm_view.flash - delta * 2.0, 0.0)
	var tip = arm_view.tool_tip()
	var pointing = Vector2(cos(arm_view.tool_angle), sin(arm_view.tool_angle))
	var square = pointing.angle_to(-arm_view.spot_normal)
	var at_spot = tip.distance_to(arm_view.spot) < SPOT_REACH + 0.04
	var squared_up = abs(square) < SQUARE_TOLERANCE
	var working = held(KEY_SPACE)
	arm_view.tool_active = false
	arm_view.tool_wiggle = move_toward(arm_view.tool_wiggle, 0.0, delta * 2.0)
	match step:
		"abrade":
			# Grinding the rind: the bit skates on the hard surface and pushes the tool crooked, so keep correcting
			if at_spot and squared_up and working:
				arm_view.tool_active = true
				skate = clamp(skate + randf_range(-1.2, 1.2) * delta, -0.35, 0.35)
				if abs(skate) < 0.12:
					skate = 0.12 * (1.0 if skate >= 0.0 else -1.0)
				arm_view.tool_angle += skate * delta
				if arm_hits():
					arm_view.tool_angle -= skate * delta   # (it can't skate into the rock)
					skate = -skate
				work += delta / ABRADE_SECONDS
				if moving_arm:
					arm_view.stress = min(arm_view.stress + 25.0 * strain_factor() * delta, 100.0)
				if work >= 1.0:
					abraded = true
					arm_view.abraded = true
					work = 0.0
					step = "drill"
					arm_view.tool_name = "DRILL"
					play_sound("confirm")
		"drill":
			if at_spot and squared_up and working:
				arm_view.tool_active = true
				work += delta / DRILL_SECONDS
				if moving:
					# Moving the arm while the drill is turning bends the bit
					arm_view.stress = min(arm_view.stress + 45.0 * strain_factor() * delta, 100.0)
					if arm_view.stress >= 90.0 and not jammed:
						jammed = true
						collection = "damaged"
				if work >= 1.0:
					take_sample()
		"scoop":
			if at_spot and squared_up and working:
				arm_view.tool_active = true
				work += delta / SCOOP_SECONDS
				if work >= 1.0:
					work = 0.0
					step = "sieve"
					arm_view.tool_name = "SIEVE"
					arm_view.holding_sample = true
					arm_view.spot_taken = true
					keys_row.hints = [["Q", "shake"], ["E", "shake"], ["A D", "shoulder"], ["W S", "elbow"]]
					play_sound("confirm")
		"sieve":
			# Shake the scoop: Q and E in turn
			for pair in [[KEY_Q, 1.0], [KEY_E, -1.0]]:
				if held(pair[0]) and last_shake_key != pair[0]:
					last_shake_key = pair[0]
					shakes += 1
					arm_view.tool_wiggle = 0.35 * pair[1]
					play_sound("select")
			work = shakes / float(SIEVE_SHAKES)
			if shakes >= SIEVE_SHAKES:
				take_sample()
		"deliver":
			var at_inlet = tip.distance_to(arm_view.inlet) < 0.12
			if at_inlet and working:
				go_to_identify()
				return
	collect_status.text = status_text(at_spot, squared_up, square)
	work_bar.value = work * 100.0
	stress_bar.value = arm_view.stress
	arm_view.stress = max(arm_view.stress - 4.0 * delta, 0.0) if not moving else arm_view.stress
	if arm_view.stress >= 100.0:
		arm_fault()
	update_steps()

func take_sample():
	collected = true
	step = "deliver"
	work = 1.0
	arm_view.holding_sample = true
	arm_view.spot_taken = true
	arm_view.tool_name = "DRILL" if has_drill else "SCOOP"
	keys_row.hints = [["A D", "shoulder"], ["W S", "elbow"], ["Q E", "tool"], ["Space", "drop in"]]
	play_sound("confirm")

# Too much strain (see _process). A sample in the tool falls out, and the sample quality drops.
func arm_fault():
	faults += 1
	fault_seconds = FAULT_SECONDS
	arm_view.stress = 55.0
	collection = "rough" if faults == 1 else "damaged"   # (the first fault leaves a rough sample, a second ruins it)
	if step in ["deliver", "sieve"]:
		arm_view.holding_sample = false
		arm_view.spot_taken = false
		collected = false
		shakes = 0
		last_shake_key = 0
		if has_drill:
			step = "drill"
			work = 0.35   # some of the hole is already drilled
		else:
			step = "scoop"
			work = 0.0
	play_sound("error")
	var shake = create_tween()
	for index in 6:
		shake.tween_property(arm_view, "position:x", 6.0 if index % 2 == 0 else -6.0, 0.04)
	shake.tween_property(arm_view, "position:x", 0.0, 0.04)

# Is any part of the arm inside a rock or the ground? (points along the forearm and the tool, and the elbow)
func arm_hits():
	return arm_hit_count() > 0

# How many of those points are inside something (more means pushed in deeper)
func arm_hit_count():
	var elbow_place = arm_view.elbow_position()
	var wrist_place = arm_view.wrist_position()
	var tip = arm_view.tool_tip()
	var count = 0
	for index in 9:
		var along = index / 8.0
		count += 1 if point_hits(elbow_place.lerp(wrist_place, along), arm_view.rocks, arm_view.spot) else 0
		count += 1 if point_hits(wrist_place.lerp(tip, along), arm_view.rocks, arm_view.spot) else 0
	return count

func point_hits(place, rocks, spot):
	if place.y < -0.01 and place.distance_to(spot) > SPOT_REACH:
		return true
	if place.distance_to(spot) <= SPOT_REACH:
		return false   # (the tool working at the spot)
	for rock in rocks:
		if Geometry2D.is_point_in_polygon(place + Vector2(0, 0.02), rock["points"]):
			return true
	return false

# The procedure on the side panel: done steps ticked, the current one marked
func update_steps():
	var steps = []
	if has_drill:
		steps = [["reach", "Tool on the spot, square to the surface"], ["abrade", "Abrade the dusty rind (SPACE; Q/E keep it square)"],
			["drill", "Drill the core (SPACE; keep the arm still)"], ["deliver", "Drop it in the sample inlet (SPACE)"]]
	else:
		steps = [["reach", "Scoop on the spot, square to the surface"], ["scoop", "Scoop the soil (hold SPACE)"],
			["sieve", "Sieve it: tap Q and E in turn"], ["deliver", "Drop it in the sample inlet (SPACE)"]]
	var order = steps.map(func(entry): return entry[0])
	var now = order.find(step)
	var reached = arm_view.tool_tip().distance_to(arm_view.spot) < SPOT_REACH + 0.04 or now > 1 or work > 0.0
	var lines = []
	for index in steps.size():
		var done = reached if index == 0 else index < now
		var current = (index == 0 and not reached) or (reached and index == now)
		lines.append("%s  %s" % ["✓" if done else ("▶" if current else "·"), steps[index][1]])
	steps_label.text = "\n".join(lines)
	work_title.text = {"abrade": "ABRASION PATCH", "drill": "CORE DRILLED", "scoop": "SOIL SCOOPED", "sieve": "SIEVED", "deliver": "SAMPLE READY"}.get(step, "PROGRESS")

func status_text(at_spot, squared_up, square):
	var distance = arm_view.tool_tip().distance_to(arm_view.spot)
	var lines = []
	match step:
		"sieve":
			lines.append("Shaking the fine grains through the sieve: %d of %d (tap Q, then E)." % [shakes, SIEVE_SHAKES])
		"deliver":
			var at_inlet = arm_view.tool_tip().distance_to(arm_view.inlet) < 0.12
			lines.append("Sample in the tool. Carry it to the SAMPLE INLET on the deck.")
			lines.append("Over the inlet: press SPACE." if at_inlet else "Inlet: %d cm away." % int(round(arm_view.tool_tip().distance_to(arm_view.inlet) * 100.0)))
		_:
			lines.append("Tool to the spot: %d cm" % int(round(distance * 100.0)))
			lines.append("Tool angle to the surface: %d° off square" % int(round(abs(rad_to_deg(square)))))
			if at_spot and squared_up:
				lines.append({"abrade": "READY: hold SPACE to abrade. The bit skates: Q/E to stay square.", "drill": "READY: hold SPACE to drill. Keep still!", "scoop": "READY: hold SPACE to scoop."}.get(step, ""))
			elif at_spot:
				lines.append("On the spot, but not square: turn the tool with Q/E")
	if jammed:
		lines.append("The bit bent! The sample will be poor.")
	return "\n".join(lines)

# The arm team does it for you: slower and not as careful, but it gets a sample
func collect_automatically():
	collection = "rough" if collection == "clean" else collection
	time_points = 0
	collected = true
	go_to_identify()

# ---------------------------------------------------------------------------
# Stage 2: identify
# ---------------------------------------------------------------------------
func go_to_identify():
	if identify_stage.visible:
		return
	collect_stage.visible = false
	identify_stage.visible = true
	if time_points > 0 and window_seconds > 0.0:
		time_points = 10 if arm_seconds <= window_seconds * 0.7 else 5
	stage_label.text = "1  COLLECT  ✓     ›     2  IDENTIFY"
	for old in instrument_buttons.get_children():
		old.queue_free()
	for instrument_key in INSTRUMENT_NAMES:
		var part_id = INSTRUMENT_PARTS.get(instrument_key, "")
		if part_id != "" and not part_id in GameState.instruments:
			continue
		var button = Button.new()
		button.text = INSTRUMENT_NAMES[instrument_key]
		button.custom_minimum_size = Vector2(0, 36)
		button.pressed.connect(run_instrument.bind(instrument_key, button))
		instrument_buttons.add_child(button)
	var options = [sample_id]
	var pool = GeologySamples.samples_for(GameState.destination).duplicate()
	pool.shuffle()
	for other in pool + GeologySamples.ROCKY_SET + GeologySamples.ICY_SET:
		if options.size() >= 4:
			break
		if not other in options:
			options.append(other)
	options.shuffle()
	for option_id in options:
		var button = Button.new()
		button.text = GeologySamples.SAMPLES[option_id]["name"]
		button.custom_minimum_size = Vector2(0, 38)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(answer.bind(option_id))
		candidate_buttons.add_child(button)
	update_runs()
	add_reading("THE SAMPLE", "Collected from %s on %s%s." % [target_name.to_lower(), GameState.destination, {"clean": ", cleanly", "rough": ", a little roughly", "damaged": ", with a bent drill bit or a faulted arm (a poor sample)"}[collection]])
	if abraded:
		# The abrasion patch, seen up close for free: the fresh rock under the weathered rind
		add_reading("ABRASION PATCH (FREE)", "Under the dusty rind: " + sample["arm"].substr(0, 1).to_lower() + sample["arm"].substr(1))
	UiMotion.stagger([$IdentifyStage/Instruments, $IdentifyStage/Readings, $IdentifyStage/Answers], 0.05, 0.08, Vector2(0, 20), 0.5)

func run_instrument(instrument_key, button):
	if runs_left <= 0 or answered:
		return
	runs_left -= 1
	instruments_used.append(instrument_key)
	button.disabled = true
	if instrument_key == "spectrometer":
		var chart = Control.new()
		chart.set_script(load("res://scripts/spectrum_chart.gd"))
		chart.custom_minimum_size = Vector2(0, 170)
		add_reading("INFRARED SPECTROMETER", "Dips in the curve are absorption bands: each mineral or ice absorbs at its own wavelengths." if not sample["bands"].is_empty() else "No clear absorption bands: a flat, featureless spectrum.", chart)
		chart.show_spectrum(sample["brightness"], sample["bands"])
	else:
		add_reading(INSTRUMENT_NAMES[instrument_key].to_upper(), sample[instrument_key])
	update_runs()
	play_sound("select")

func add_reading(title, text, extra = null):
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.15, 0.95)
	style.border_color = Color(0.45, 0.8, 1.0, 0.4)
	style.border_width_left = 3
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	var column = VBoxContainer.new()
	card.add_child(column)
	var heading = Label.new()
	heading.text = title
	heading.theme_type_variation = "DataLabel"
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Color(0.45, 0.8, 1.0))
	column.add_child(heading)
	var words = Label.new()
	words.text = text
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_theme_font_size_override("font_size", 14)
	column.add_child(words)
	if extra:
		column.add_child(extra)
	readings_list.add_child(card)
	UiMotion.slide_in(card, 0.0, Vector2(0, 14), 0.4)

func update_runs():
	runs_label.text = "Power for %d more instrument run%s" % [runs_left, "" if runs_left == 1 else "s"]
	if runs_left <= 0:
		for button in instrument_buttons.get_children():
			button.disabled = true

func answer(option_id):
	if answered:
		return
	answered = true
	var correct = option_id == sample_id
	was_correct = correct
	science = (8 if correct else 2) + {"clean": 2, "rough": 0, "damaged": -1}[collection]
	if correct and instruments_used.size() <= 2:
		science += 2   # a sharp, efficient identification
	for button in candidate_buttons.get_children():
		button.disabled = true
		if button.text == sample["name"]:
			button.add_theme_color_override("font_disabled_color", Color(0.45, 1.0, 0.6))
		elif button.text == GeologySamples.SAMPLES[option_id]["name"]:
			button.add_theme_color_override("font_disabled_color", Color(1.0, 0.5, 0.45))
	# The score, medal and research points
	score = {"clean": 40, "rough": 20, "damaged": 5}[collection] + (40 if correct else 0) + (10 if correct and instruments_used.size() <= 2 else 0) + time_points
	var medal = null
	for entry in MEDALS:
		if score >= entry[0]:
			medal = entry
			break
	var reward_line = "\n+%d science." % science
	if medal:
		medal_name = medal[1]
		GameState.career["research"] = GameState.career.get("research", 0) + medal[3]
		var bests = GameState.career.get("sample_best", {})
		var new_best = score > bests.get(GameState.destination, -1)
		bests[GameState.destination] = max(bests.get(GameState.destination, 0), score)
		GameState.career["sample_best"] = bests
		Career.save_data(GameState.career)
		if medal[1] == "GOLD":
			GameState.note_gold_medal()
		reward_line = "\n%s · %d / 100%s\n+%d science, +%d research points." % [medal[1], score, "  (new best here!)" if new_best else "", science, medal[3]]
		GameState.show_toast("%s sample" % medal[1].capitalize(), "%s: +%d research points." % [sample["name"], medal[3]], "research")
	else:
		reward_line = "\n%d / 100 (no medal).\n+%d science." % [score, science]
	answer_text.text = ("Correct! " if correct else "Not quite: it's %s. " % sample["name"].to_lower()) + sample["about"] + reward_line
	answer_text.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8) if correct else Color(1.0, 0.85, 0.8))
	continue_button.visible = true
	UiMotion.slide_in(answer_text, 0.0, Vector2(0, 12), 0.4)
	play_sound("confirm" if correct else "glitch")

func _on_continue_pressed():
	finished.emit({"sample": sample_id, "name": sample["name"], "correct": was_correct, "science": science,
		"collection": collection, "instruments_used": instruments_used, "score": score, "medal": medal_name})
	queue_free()

func play_sound(sound_name):
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_effect(sound_name, -6.0)

# Arm force sensors (a research upgrade) make the strain build more slowly
func strain_factor():
	GameState.note_tech("force_sensors", "the arm's strain built 40% slower")
	return 0.6 if GameState.has_upgrade("force_sensors") else 1.0
