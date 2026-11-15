extends Control

# A big announcement across the middle of the screen for a moment (res://scenes/title_card.tscn): entering an
# asteroid belt, clearing it, a gravity-assist flyby. The title rises in letter by letter, holds, then fades out
# and the card frees itself. It never takes the mouse.
#   var card = TITLE_CARD_SCENE.instantiate(); some_canvas_layer.add_child(card); card.play("ASTEROID BELT", "You have control")

@onready var title_label: Label = $Column/Title
@onready var subtitle_label: Label = $Column/Subtitle
@onready var line: ColorRect = $Column/Line

func play(title, subtitle := "", color := Color(1.0, 0.82, 0.35), seconds := 2.6):
	title_label.text = title
	subtitle_label.text = subtitle
	subtitle_label.visible = subtitle != ""
	title_label.add_theme_color_override("font_color", color)
	line.color = Color(color, 0.8)
	modulate.a = 1.0
	UiMotion.reveal_text(title_label, 0.0, 0.6, 0.35)
	line.scale.x = 0.0
	line.pivot_offset = Vector2(line.size.x / 2.0, 0.0)
	var motion = create_tween()
	motion.tween_property(line, "scale:x", 1.0, 0.5).set_delay(0.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	subtitle_label.modulate.a = 0.0
	motion.parallel().tween_property(subtitle_label, "modulate:a", 1.0, 0.4).set_delay(0.45)
	motion.tween_interval(seconds)
	motion.tween_property(self, "modulate:a", 0.0, 0.5)
	motion.tween_callback(queue_free)
