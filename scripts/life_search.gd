extends Control

# MINIGAME: SIGNS OF LIFE (res://scenes/life_search.tscn)
# On worlds where life could exist (Mars, Europa, Enceladus, Titan, Ceres), one of the rover's targets is a place
# worth searching for life. Opened from surface_view.gd like the Sample Lab. Built on real findings
# (scripts/life_signs.gd) and on how NASA scientists judge a claim of life: the Confidence of Life Detection
# (CoLD) scale. Nobody has found life beyond Earth yet, and this minigame never pretends otherwise.
#
# 1. SCAN: move the scanner over the close-up (W A S D or the mouse) and hold SPACE (or the left mouse button) to
#    map that spot with the selected instrument (1 camera, 2 UV laser for organics, 3 X-ray chemistry). Each
#    instrument sees different things, and mapping uses power, so you can't map everything with everything.
#    Features you map well enough become evidence.
# 2. WEIGH: for each piece of evidence, decide: does it point to life, could life or plain chemistry have made it,
#    or is it not a sign of life at all (water, salts, contamination from your own spacecraft...)?
# 3. VERDICT: the CoLD ladder shows how high your evidence climbs, then you choose what the team tells the world.
#    Overclaiming is the classic mistake: a rover can reach rung 3 at most; the rest needs labs on Earth.
#
# SCORE (0-100): 6 per feature found (30), 8 per correct judgment (40), 30 for an honest verdict.
# Gold 85, silver 65, bronze 40, with research points for each medal, and the best score is kept.
# Sends finished({"science", "score", "medal", "verdict", "levels"}).

signal finished(result)

const LifeSigns = preload("res://scripts/life_signs.gd")
const Career = preload("res://scripts/career.gd")
const POWER = [160.0, 110.0, 80.0]    # power for mapping, by difficulty
const SCANNER_SPEED = 0.32            # shares of the view per second
const FOUND_COVERAGE = 0.5            # how much of a feature an instrument must map to see it
const MEDALS = [[85, "GOLD", Color(1.0, 0.82, 0.35), 8], [65, "SILVER", Color(0.8, 0.85, 0.92), 5], [40, "BRONZE", Color(0.85, 0.55, 0.35), 2]]
const LETTERS = ["A", "B", "C", "D", "E", "F"]
const JUDGMENTS = [["life", "Points to life"], ["either", "Life or chemistry"], ["not", "Not a sign of life"]]
const VERDICTS = [
	["life", "We found alien life!"],
	["potential", "A potential biosignature: save it for labs on Earth"],
	["habitable", "A habitable place, but no sign of life here"],
	["contamination", "Only contamination from our own spacecraft"],
]

@onready var title_label: Label = $Header/Title
@onready var stage_label: Label = $Header/Stage
@onready var scan_stage: Control = $ScanStage
@onready var scan_view: Control = $ScanStage/ScanView
@onready var brief_label: Label = $ScanStage/Side/Column/Brief
@onready var instrument_row: HBoxContainer = $ScanStage/Side/Column/Instruments
@onready var instrument_note: Label = $ScanStage/Side/Column/InstrumentNote
@onready var power_bar: ProgressBar = $ScanStage/Side/Column/PowerBar
@onready var found_label: Label = $ScanStage/Side/Column/Found
@onready var scan_status: Label = $ScanStage/Side/Column/Status
@onready var done_button: Button = $ScanStage/Side/Column/DoneButton
@onready var weigh_stage: Control = $WeighStage
@onready var cards_list: VBoxContainer = $WeighStage/Panel/Column/Scroll/Cards
@onready var weigh_note: Label = $WeighStage/Panel/Column/Note
@onready var verdict_next_button: Button = $WeighStage/Panel/Column/NextButton
@onready var verdict_stage: Control = $VerdictStage
@onready var ladder_label: RichTextLabel = $VerdictStage/Ladder/Column/Rungs
@onready var verdict_buttons: VBoxContainer = $VerdictStage/Verdict/Column/Buttons
@onready var verdict_text: Label = $VerdictStage/Verdict/Column/Result
@onready var continue_button: Button = $VerdictStage/Verdict/Column/ContinueButton

var world = "Mars"
var scenario = {}
var instrument = "camera"
var power = 100.0
var power_total = 100.0
var found = {}                # feature index → {instrument: true} for each instrument that has mapped it
var found_order = []          # feature indexes, in the order found
var judged = {}               # feature index → the judgment chosen
var levels = 0
var verdict = ""
var score = 0
var medal_name = ""
var science = 0
var training = false          # opened from the career screen's Training tab (research only for beating your best medal)
var inputs_override = {}      # (the automatic tests drive the scanner with this instead of the keyboard)

func _ready():
	weigh_stage.visible = false
	verdict_stage.visible = false
	continue_button.visible = false
	verdict_next_button.visible = false
	done_button.pressed.connect(go_to_weigh)
	verdict_next_button.pressed.connect(go_to_verdict)
	continue_button.pressed.connect(_on_continue_pressed)

func held(key):
	if inputs_override.has(key):
		return inputs_override[key]
	return Input.is_key_pressed(key)

func start(target_name, world_name):
	get_viewport().gui_release_focus()
	if training:
		continue_button.text = "Done"
		# In training you can leave any time
		var close_button = Button.new()
		close_button.text = "Close (Esc)"
		close_button.focus_mode = Control.FOCUS_NONE
		close_button.custom_minimum_size = Vector2(110, 34)
		close_button.pressed.connect(queue_free)
		$Header.add_child(close_button)
	world = world_name if LifeSigns.has_scenario(world_name) else "Mars"
	scenario = LifeSigns.SCENARIOS[world]
	title_label.text = "SIGNS OF LIFE  ·  %s" % target_name.to_upper()
	brief_label.text = scenario["brief"]
	var colors = {}
	for instrument_id in LifeSigns.INSTRUMENTS:
		colors[instrument_id] = LifeSigns.INSTRUMENTS[instrument_id]["color"]
	scan_view.set_up(scenario, colors)
	power_total = POWER[clamp(GameState.difficulty, 0, 2)]
	power = power_total
	# The instrument buttons
	var number = 1
	for instrument_id in LifeSigns.INSTRUMENTS:
		var button = Button.new()
		button.text = "%d  %s" % [number, LifeSigns.INSTRUMENTS[instrument_id]["short"]]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 34)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(choose_instrument.bind(instrument_id))
		button.name = instrument_id
		instrument_row.add_child(button)
		number += 1
	choose_instrument("camera")
	update_found()
	UiMotion.reveal_text(title_label, 0.1, 0.6, 0.4)
	UiMotion.slide_in($ScanStage/Side, 0.15, Vector2(30, 0), 0.5)

func choose_instrument(instrument_id):
	instrument = instrument_id
	scan_view.instrument = instrument_id
	var info = LifeSigns.INSTRUMENTS[instrument_id]
	instrument_note.text = "%s: %s Uses %d power per second." % [info["name"], info["what"], int(info["cost"])]
	for button in instrument_row.get_children():
		button.button_pressed = button.name == instrument_id
		button.add_theme_color_override("font_color", LifeSigns.INSTRUMENTS[button.name]["color"] if button.name == instrument_id else Color(0.75, 0.8, 0.88))

# Every key belongs to the minigame while it's open (so focused buttons underneath never react)
func _input(event):
	if training and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
		return
	if not scan_stage.visible:
		return
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo:
			var keys = {KEY_1: "camera", KEY_2: "organics", KEY_3: "chemistry"}
			if keys.has(event.keycode):
				choose_instrument(keys[event.keycode])

# ---------------------------------------------------------------------------
# Stage 1: scan
# ---------------------------------------------------------------------------
func _process(delta):
	if not scan_stage.visible:
		return
	var move = Vector2.ZERO
	if held(KEY_A):
		move.x -= 1.0
	if held(KEY_D):
		move.x += 1.0
	if held(KEY_W):
		move.y -= 1.0
	if held(KEY_S):
		move.y += 1.0
	var aspect = scan_view.size.x / max(scan_view.size.y, 1.0)
	scan_view.scanner += Vector2(move.x, move.y * aspect) * SCANNER_SPEED * delta
	# The mouse: hold the left button on the close-up to scan where it points
	var mouse_scanning = false
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and inputs_override.is_empty():
		var local = scan_view.get_local_mouse_position()
		if Rect2(Vector2.ZERO, scan_view.size).has_point(local):
			scan_view.scanner = local / scan_view.size
			mouse_scanning = true
	scan_view.scanner = scan_view.scanner.clamp(Vector2(0.02, 0.03), Vector2(0.98, 0.97))
	var scanning = (held(KEY_SPACE) or mouse_scanning) and power > 0.0
	scan_view.scanning = scanning
	if scanning:
		power = max(power - LifeSigns.INSTRUMENTS[instrument]["cost"] * delta, 0.0)
		scan_view.scan_here()
		check_finds()
		if power <= 0.0:
			scan_status.text = "Out of power for mapping. Time to weigh the evidence."
			done_button.text = "Weigh the evidence  ›"
	power_bar.value = 100.0 * power / power_total

# Any feature an instrument has now mapped well enough becomes evidence (or adds to it)
func check_finds():
	for index in scan_view.features.size():
		var feature = scan_view.features[index]
		if not feature["signals"].has(instrument) or found.get(index, {}).has(instrument):
			continue
		if scan_view.coverage(feature, instrument) >= FOUND_COVERAGE:
			var seen = found.get(index, {})
			seen[instrument] = true
			found[index] = seen
			if not index in found_order:
				found_order.append(index)
				scan_view.found_labels[index] = LETTERS[found_order.size() - 1]
			scan_status.text = "%s · %s: %s" % [scan_view.found_labels[index], LifeSigns.INSTRUMENTS[instrument]["short"], feature["signals"][instrument]]
			play_sound("confirm")
			update_found()

func update_found():
	if found_order.is_empty():
		found_label.text = "Nothing found yet. The team wants: textures, organics, chemistry, and a check that nothing came from the rover."
		return
	var lines = []
	for index in found_order:
		var feature = scan_view.features[index]
		var seen_by = found[index].keys().map(func(instrument_id): return LifeSigns.INSTRUMENTS[instrument_id]["short"])
		var missing = feature["signals"].size() - found[index].size()
		lines.append("%s  %s%s" % [scan_view.found_labels[index], " + ".join(seen_by), ("  (%d more instrument%s could add to it)" % [missing, "" if missing == 1 else "s"]) if missing > 0 else ""])
	found_label.text = "\n".join(lines)

# ---------------------------------------------------------------------------
# Stage 2: weigh the evidence
# ---------------------------------------------------------------------------
func go_to_weigh():
	scan_stage.visible = false
	weigh_stage.visible = true
	stage_label.text = "1  SCAN  ✓     ›     2  WEIGH     ›     3  VERDICT"
	if found_order.is_empty():
		weigh_note.text = "You didn't map any features well enough to call them evidence."
		verdict_next_button.visible = true
	else:
		weigh_note.text = "For each piece of evidence: could it be life, or something else?"
	for index in found_order:
		cards_list.add_child(make_card(index))
	UiMotion.stagger(cards_list.get_children(), 0.1, 0.08, Vector2(0, 16), 0.45)

func make_card(index):
	var feature = scan_view.features[index]
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.15, 0.95)
	style.border_color = Color(1.0, 0.86, 0.5, 0.5)
	style.border_width_left = 3
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var heading = Label.new()
	heading.text = "EVIDENCE %s" % scan_view.found_labels[index]
	heading.theme_type_variation = "DataLabel"
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	column.add_child(heading)
	for instrument_id in found[index]:
		var words = Label.new()
		words.text = "%s: %s" % [LifeSigns.INSTRUMENTS[instrument_id]["name"], feature["signals"][instrument_id]]
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_theme_font_size_override("font_size", 13)
		column.add_child(words)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	var explanation = Label.new()
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_theme_font_size_override("font_size", 12)
	explanation.visible = false
	for judgment in JUDGMENTS:
		var button = Button.new()
		button.text = judgment[1]
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 32)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(judge.bind(index, judgment[0], row, explanation))
		row.add_child(button)
	column.add_child(explanation)
	return card

func judge(index, choice, row, explanation):
	if judged.has(index):
		return
	judged[index] = choice
	var feature = scan_view.features[index]
	var right = choice == feature["answer"]
	for button_index in row.get_child_count():
		var button = row.get_child(button_index)
		button.disabled = true
		# your choice and the right one stay lit: green if right, red if not
		if JUDGMENTS[button_index][0] == feature["answer"]:
			button.add_theme_color_override("font_disabled_color", Color(0.45, 1.0, 0.6))
		elif JUDGMENTS[button_index][0] == choice:
			button.add_theme_color_override("font_disabled_color", Color(1.0, 0.5, 0.45))
	var right_name = ""
	for judgment in JUDGMENTS:
		if judgment[0] == feature["answer"]:
			right_name = judgment[1]
	explanation.text = ("Right. " if right else "The team says: %s. " % right_name.to_lower()) + feature["why"]
	explanation.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8) if right else Color(1.0, 0.85, 0.8))
	explanation.visible = true
	UiMotion.slide_in(explanation, 0.0, Vector2(0, 10), 0.35)
	play_sound("confirm" if right else "glitch")
	if judged.size() >= found_order.size():
		verdict_next_button.visible = true
		UiMotion.pop_in(verdict_next_button, 0.1, 0.4)

# ---------------------------------------------------------------------------
# Stage 3: the verdict
# ---------------------------------------------------------------------------
func go_to_verdict():
	weigh_stage.visible = false
	verdict_stage.visible = true
	stage_label.text = "1  SCAN  ✓     ›     2  WEIGH  ✓     ›     3  VERDICT"
	levels = cold_levels()
	show_ladder(false)
	for entry in VERDICTS:
		var button = Button.new()
		button.text = entry[1]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 40)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(choose_verdict.bind(entry[0]))
		verdict_buttons.add_child(button)
	UiMotion.stagger([$VerdictStage/Ladder, $VerdictStage/Verdict], 0.05, 0.1, Vector2(0, 20), 0.5)

# How high up the CoLD scale the evidence reaches: a possible signal found (1), contamination spotted and ruled
# out (2), and the place shown to be habitable so life could have made it here (3). Rungs 4 to 7 can't be
# reached by a rover alone.
func cold_levels():
	var has_signal = false
	var contamination_ruled_out = false
	var habitat_shown = false
	for index in found_order:
		var feature = scan_view.features[index]
		match feature["role"]:
			"signal":
				has_signal = true
			"contamination":
				contamination_ruled_out = judged.get(index, "") == "not"
			"habitat":
				habitat_shown = habitat_shown or judged.get(index, "") == "not"
	if not has_signal:
		return 0
	if not contamination_ruled_out:
		return 1
	return 3 if habitat_shown else 2

func show_ladder(with_verdict):
	var lines = []
	for rung in range(LifeSigns.COLD_LEVELS.size() - 1, -1, -1):
		var reached = rung < levels
		var color = "#7dff9a" if reached else ("#8892a0" if rung >= 3 else "#ffb070")
		var note = ""
		if rung >= 3:
			note = "   [i](labs on Earth)[/i]"
		elif not reached:
			note = "   [i](not reached)[/i]"
		lines.append("[color=%s]%s  %s%s[/color]" % [color, "■" if reached else "□", LifeSigns.COLD_LEVELS[rung], note])
	var summary = "\n[font_size=12]Your evidence reaches rung %d of 7.%s[/font_size]" % [levels, " Even the most promising real find, Cheyava Falls on Mars, is waiting for rungs 4 and up: they need the sample in a lab on Earth." if with_verdict else ""]
	ladder_label.text = "\n".join(lines) + "\n" + summary

func best_verdict():
	var has_signal = false
	var has_contamination = false
	for index in found_order:
		var role = scan_view.features[index]["role"]
		has_signal = has_signal or role == "signal"
		has_contamination = has_contamination or role == "contamination"
	if has_signal:
		return "potential"
	if has_contamination and found_order.size() == 1:
		return "contamination"
	return "habitable"

func choose_verdict(choice):
	if verdict != "":
		return
	verdict = choice
	var best = best_verdict()
	for button_index in verdict_buttons.get_child_count():
		var button = verdict_buttons.get_child(button_index)
		button.disabled = true
		if VERDICTS[button_index][0] == best:
			button.add_theme_color_override("font_disabled_color", Color(0.45, 1.0, 0.6))
		elif VERDICTS[button_index][0] == choice:
			button.add_theme_color_override("font_disabled_color", Color(1.0, 0.5, 0.45))
	var honest = choice == best
	var correct_judgments = 0
	for index in judged:
		if judged[index] == scan_view.features[index]["answer"]:
			correct_judgments += 1
	score = 6 * found_order.size() + 8 * correct_judgments + (30 if honest else 0)
	score = clamp(score, 0, 100)
	var lesson = ""
	match choice:
		"life":
			lesson = "Too far! No mission has ever found life beyond Earth, and a rover alone can't prove it: claims need several independent lines of evidence, labs on Earth and other teams checking. This is the mistake the CoLD scale exists to prevent."
		"potential":
			lesson = "Exactly how NASA described Cheyava Falls: a potential biosignature, worth bringing home." if honest else "Careful: you didn't find a possible sign of life to back that up. Only the habitability evidence."
		"habitable":
			lesson = "An honest call: this place could support life, but your evidence doesn't point to life itself." if honest else "Too cautious: one of your finds is a possible biosignature, worth saving for labs on Earth."
		"contamination":
			lesson = "Right: the only organic signal came from your own spacecraft." if honest else "Not quite: contamination was only part of the story."
	var medal = null
	for entry in MEDALS:
		if score >= entry[0]:
			medal = entry
			break
	science = 4 + int(round(score / 8.0))
	var science_text = "" if training else " · +%d science" % science
	var reward = "\n\n%d / 100%s" % [score, science_text]
	if medal:
		medal_name = medal[1]
		var bests = GameState.career.get("life_best", {})
		var research = research_for(medal, bests.get(world, 0))
		GameState.career["research"] = GameState.career.get("research", 0) + research
		var new_best = score > bests.get(world, -1)
		bests[world] = max(bests.get(world, 0), score)
		GameState.career["life_best"] = bests
		Career.save_data(GameState.career)
		if medal[1] == "GOLD":
			GameState.note_gold_medal()
		reward = "\n\n%s · %d / 100%s%s · +%d research points" % [medal[1], score, " (new best!)" if new_best else "", science_text, research]
		if research > 0:
			GameState.show_toast("%s life search" % medal[1].capitalize(), "+%d research points." % research, "research")
	if honest and choice == "potential" and levels >= 3:
		GameState.award_achievement("astrobiologist")
	verdict_text.text = lesson + reward
	verdict_text.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8) if honest else Color(1.0, 0.85, 0.8))
	show_ladder(true)
	continue_button.visible = true
	UiMotion.slide_in(verdict_text, 0.0, Vector2(0, 12), 0.4)
	play_sound("confirm" if honest else "glitch")
	print("LIFE SEARCH %s" % [{"world": world, "found": found_order.size(), "judged_right": correct_judgments, "levels": levels, "verdict": choice, "best": best, "score": score}])

# On a mission every medal earns its research points; in training only beating your best medal does (like the
# other simulators), so the same site can't be farmed
func research_for(medal, previous_best):
	if not training:
		return medal[3]
	var previous_points = 0
	for entry in MEDALS:
		if previous_best >= entry[0]:
			previous_points = entry[3]
			break
	return max(medal[3] - previous_points, 0)

func _on_continue_pressed():
	finished.emit({"science": science, "score": score, "medal": medal_name, "verdict": verdict, "levels": levels})
	queue_free()

func play_sound(sound_name):
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_effect(sound_name, -6.0)
