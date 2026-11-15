extends RefCounted

# Every minigame opens on its own canvas layer: above the screen it was opened from (the builders, the flight
# and its event panels, the rover's drive screen) and below the pause menu (110) and toasts (118), so nothing
# from underneath ever draws over it. The layer goes away when the minigame closes.
# The minigame fades and scales in as it opens.
#   MinigameLayer.show_minigame(self, SOME_SCENE.instantiate())

const LAYER = 60

static func show_minigame(parent: Node, minigame: Control, layer_number := LAYER) -> CanvasLayer:
	var minigame_layer = CanvasLayer.new()
	minigame_layer.name = "MinigameLayer"
	minigame_layer.layer = layer_number
	parent.add_child(minigame_layer)
	minigame_layer.add_child(minigame)
	minigame.tree_exited.connect(minigame_layer.queue_free)
	# Opening: a quick fade and a slight zoom
	minigame.modulate.a = 0.0
	minigame.pivot_offset = minigame.get_viewport_rect().size / 2.0
	minigame.scale = Vector2.ONE * 1.03
	var opening = minigame.create_tween().set_parallel(true)
	opening.tween_property(minigame, "modulate:a", 1.0, 0.3)
	opening.tween_property(minigame, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	return minigame_layer
