extends PanelContainer

# The piloting panel for crossing an asteroid or Kuiper belt (res://scenes/belt_hud.tscn): how much thruster fuel
# is left, science shards grabbed, close calls, rock strikes and your combo, plus the steering keys (they light
# up while held). launch.gd updates it every frame and slides it in and out with set_shown.

@onready var fuel_bar: ProgressBar = $Column/Row/FuelBar
@onready var shards_label: Label = $Column/Row/Shards
@onready var combo_label: Label = $Column/Row/Combo
@onready var close_calls_label: Label = $Column/Row/CloseCalls
@onready var strikes_label: Label = $Column/Row/Strikes
@onready var hint_label: Label = $Column/Hint
@onready var keys: Control = $Column/Keys

var shown_combo = 0
var shown_shards = 0
var shown_strikes = 0
var showing = false
var slide: Tween
var clock = 0.0

func _ready():
	modulate.a = 0.0
	visible = false

# Slides up and fades in when a belt starts, and back down when it ends
func set_shown(on):
	if on == showing:
		return
	showing = on
	if slide:
		slide.kill()
	pivot_offset = size / 2.0
	if on:
		visible = true
		position.y += 40.0
		slide = create_tween().set_parallel(true)
		slide.tween_property(self, "modulate:a", 1.0, 0.35)
		slide.tween_property(self, "position:y", position.y - 40.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		var resting_y = position.y
		slide = create_tween().set_parallel(true)
		slide.tween_property(self, "modulate:a", 0.0, 0.3)
		slide.tween_property(self, "position:y", resting_y + 40.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		slide.chain().tween_callback(func():
			visible = false
			position.y = resting_y)

func _process(delta):
	clock += delta
	if not visible:
		return
	for key in ["W", "A", "S", "D"]:
		var arrow = {"W": KEY_UP, "A": KEY_LEFT, "S": KEY_DOWN, "D": KEY_RIGHT}[key]
		keys.light_key(key, Input.is_key_pressed(OS.find_keycode_from_string(key)) or Input.is_key_pressed(arrow))

func bump(label):
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2.ONE * 1.35
	label.create_tween().tween_property(label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func show_values(fuel_share, shards, combo, close_calls, strikes := 0):
	fuel_bar.value = fuel_share * 100.0
	# Low fuel pulses red
	if fuel_share < 0.2:
		fuel_bar.modulate = Color(1.0, 0.45, 0.4).lerp(Color.WHITE, 0.5 + 0.5 * sin(clock * 9.0))
	else:
		fuel_bar.modulate = Color.WHITE
	shards_label.text = "SHARDS %d" % shards
	close_calls_label.text = "CLOSE CALLS %d" % close_calls
	strikes_label.text = "STRIKES %d" % strikes
	if shards != shown_shards:
		bump(shards_label)
	if strikes != shown_strikes:
		bump(strikes_label)
	shown_shards = shards
	shown_strikes = strikes
	combo_label.visible = combo >= 2
	if combo != shown_combo and combo >= 2:
		combo_label.text = "%d× COMBO" % combo
		combo_label.pivot_offset = combo_label.size / 2.0
		combo_label.scale = Vector2.ONE * 1.6
		combo_label.create_tween().tween_property(combo_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	shown_combo = combo
	var refills = GameState.difficulty < 2
	if fuel_share <= 0.0:
		hint_label.text = "Thruster tank empty: the autopilot holds your line while it refills." if refills else "Thruster fuel gone: you can only drift now!"
	elif fuel_share < 0.2:
		hint_label.text = "Fuel low: tap the keys instead of holding them."
	else:
		hint_label.text = "Let go and the autopilot slows your drift.%s" % (" The tank refills while you coast." if refills else "")
