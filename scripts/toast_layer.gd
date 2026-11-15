extends CanvasLayer

# Pop-up notes in the top right corner: "Achievement unlocked", "Rank up", "New personal best"
# (res://scenes/toast_layer.tscn). GameState adds this when the game starts; anything can call
# GameState.show_toast(title, text, kind). They slide in one at a time, stay a few seconds and slide away.

const TOAST_SCENE = preload("res://scenes/toast.tscn")
const SHOW_SECONDS = 3.6
const KIND_COLORS = {"achievement": Color(1.0, 0.82, 0.35), "rank": Color(0.45, 0.8, 1.0), "best": Color(0.5, 1.0, 0.65), "research": Color(0.75, 0.6, 1.0)}
const KIND_TITLES = {"achievement": "ACHIEVEMENT UNLOCKED", "rank": "PROMOTED", "best": "NEW PERSONAL BEST", "research": "RESEARCH"}

@onready var column: VBoxContainer = $Column

var waiting = []
var showing = 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_toast(title, text, kind = "achievement"):
	waiting.append([title, text, kind])
	if showing < 3:
		show_next()

func show_next():
	if waiting.is_empty():
		return
	var next = waiting.pop_front()
	var toast = TOAST_SCENE.instantiate()
	column.add_child(toast)
	showing += 1
	var color = KIND_COLORS.get(next[2], Color.WHITE)
	toast.get_node("Row/Badge").color = color
	toast.get_node("Row/Words/Kind").text = KIND_TITLES.get(next[2], "")
	toast.get_node("Row/Words/Kind").add_theme_color_override("font_color", color)
	toast.get_node("Row/Words/Title").text = next[0]
	toast.get_node("Row/Words/Text").text = next[1]
	# Slides in from the right, waits, then slides back out
	toast.modulate.a = 0.0
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_effect("confirm", -4.0)
	await get_tree().process_frame
	var resting_x = toast.position.x
	toast.position.x = resting_x + 360.0
	var slide = toast.create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	slide.tween_property(toast, "position:x", resting_x, 0.6)
	slide.tween_property(toast, "modulate:a", 1.0, 0.3)
	# The colored badge flashes bright as it arrives
	var badge: ColorRect = toast.get_node("Row/Badge")
	badge.modulate = Color(2.5, 2.5, 2.5)
	slide.tween_property(badge, "modulate", Color.WHITE, 0.8).set_delay(0.2)
	await get_tree().create_timer(SHOW_SECONDS).timeout
	var leave = toast.create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	leave.tween_property(toast, "position:x", resting_x + 360.0, 0.45)
	leave.tween_property(toast, "modulate:a", 0.0, 0.45)
	await leave.finished
	toast.queue_free()
	showing -= 1
	show_next()
