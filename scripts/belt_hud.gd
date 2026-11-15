extends PanelContainer

# The piloting panel for crossing an asteroid or Kuiper belt (res://scenes/belt_hud.tscn): how much thruster fuel
# is left, how many science shards you've grabbed, your combo, and your close calls. launch.gd updates it.

@onready var fuel_bar: ProgressBar = $Column/Row/FuelBar
@onready var shards_label: Label = $Column/Row/Shards
@onready var combo_label: Label = $Column/Row/Combo
@onready var close_calls_label: Label = $Column/Row/CloseCalls
@onready var hint_label: Label = $Column/Hint

var shown_combo = 0

func show_values(fuel_share, shards, combo, close_calls):
	fuel_bar.value = fuel_share * 100.0
	fuel_bar.modulate = Color(1.0, 0.45, 0.4) if fuel_share < 0.2 else Color.WHITE
	shards_label.text = "SHARDS %d" % shards
	close_calls_label.text = "CLOSE CALLS %d" % close_calls
	combo_label.visible = combo >= 2
	if combo != shown_combo and combo >= 2:
		combo_label.text = "%d× COMBO" % combo
		combo_label.pivot_offset = combo_label.size / 2.0
		combo_label.scale = Vector2.ONE * 1.6
		combo_label.create_tween().tween_property(combo_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	shown_combo = combo
	hint_label.text = "Out of thruster fuel: you can only drift now!" if fuel_share <= 0.0 else "WASD / arrows fire the thrusters. You keep drifting until you push the other way."
