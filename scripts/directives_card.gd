extends PanelContainer

# The mission directives card (res://scenes/directives_card.tscn): this mission's three bonus goals with a mark
# for each (open, done or failed), how far along each one is, and stars for the ones done.
# The probe builder, the rocket builder and the flight all show it. It checks the goals twice a second, and
# when one is done its line flashes green and a chime plays.

const MissionDirectives = preload("res://scripts/mission_directives.gd")
const ROW_SCENE = preload("res://scenes/directive_row.tscn")

@export var show_descriptions := true   # the longer "what to do" line under each title

@onready var stars: Control = $Column/Header/Stars
@onready var rows_box: VBoxContainer = $Column/Rows
@onready var footer: Label = $Column/Footer

var rows = {}            # directive id -> its row
var last_states = {}
var seconds_until_check = 0.0

func _ready():
	GameState.plan_directives()
	build_rows()

func build_rows():
	for old in rows_box.get_children():
		rows_box.remove_child(old)
		old.queue_free()
	rows.clear()
	last_states.clear()
	for directive_id in GameState.directives:
		var row = ROW_SCENE.instantiate()
		rows_box.add_child(row)
		row.get_node("Words/Title").text = MissionDirectives.title(directive_id)
		row.get_node("Words/Detail").text = MissionDirectives.description(directive_id)
		row.get_node("Words/Detail").visible = show_descriptions
		rows[directive_id] = row
	footer.text = "+%d XP each   ·   %s" % [int(MissionDirectives.BONUS_XP * GameState.DIFFICULTY_XP[GameState.difficulty]), GameState.DIFFICULTY_NAMES[GameState.difficulty]]
	check(true)

# A shorter card (titles and progress only) for when the screen is crowded, like during an orbiter's mapping
func set_compact(compact):
	show_descriptions = not compact
	for row in rows.values():
		row.get_node("Words/Detail").visible = show_descriptions
	footer.visible = not compact
	reset_size()

func _process(delta):
	seconds_until_check -= delta
	if seconds_until_check <= 0.0:
		seconds_until_check = 0.5
		check(false)

func check(quietly):
	var done = 0
	for directive_id in rows:
		var row = rows[directive_id]
		var status = MissionDirectives.status(directive_id)
		row.get_node("Icon").state = status["state"]
		row.get_node("Progress").text = status["progress"]
		if status["state"] == "done":
			done += 1
		if not quietly and last_states.get(directive_id, "") != status["state"]:
			celebrate(row, status["state"])
		last_states[directive_id] = status["state"]
	stars.filled = done

# A directive just got done (or failed): its line flashes and its mark pops
func celebrate(row, state):
	var flash_color = Color(0.5, 1.0, 0.65) if state == "done" else (Color(1.0, 0.5, 0.45) if state == "failed" else Color.WHITE)
	row.modulate = flash_color * 1.6
	row.create_tween().tween_property(row, "modulate", Color.WHITE, 0.8)
	var icon = row.get_node("Icon")
	icon.pivot_offset = icon.size / 2.0
	icon.scale = Vector2.ONE * 1.7
	icon.create_tween().tween_property(icon, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var audio = get_node_or_null("/root/AudioManager")
	if audio and state == "done":
		audio.play_effect("confirm", -6.0)
