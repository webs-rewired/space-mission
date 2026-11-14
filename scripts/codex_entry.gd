extends Button

# One line in the destination codex's list (res://scenes/codex_entry.tscn): its number, the world's map on a
# little ball, its name, and a short detail on the right (how far from the Sun, or which planet a moon circles).
# The codex (scripts/destination_codex.gd) makes one for each world and says which one is chosen.
# On hover the line slides a little to the right and a gold glow fades in behind it.

signal chosen(body_name)

const GOLD = Color(0.78, 0.65, 0.42)

@onready var number_label: Label = $Row/Number
@onready var thumbnail: TextureRect = $Row/Thumbnail
@onready var name_label: Label = $Row/Name
@onready var detail_label: Label = $Row/Detail

@onready var row: HBoxContainer = $Row

var body_name = ""
var is_chosen = false
var spin = 0.0
var glow := 0.0:     # how strong the gold glow behind the line is right now
	set(value):
		glow = value
		queue_redraw()
var glow_tween: Tween = null
var row_resting_left = 12.0

func _ready():
	row_resting_left = row.offset_left
	mouse_entered.connect(hover.bind(true))
	mouse_exited.connect(hover.bind(false))
	pressed.connect(func(): chosen.emit(body_name))
	thumbnail.material = thumbnail.material.duplicate()   # each ball turns on its own

func set_up(new_body_name, number, shown_name, detail, map_texture, tint):
	body_name = new_body_name
	number_label.text = "%02d" % number
	name_label.text = shown_name
	detail_label.text = detail
	thumbnail.texture = map_texture if map_texture else PlaceholderTexture2D.new()
	thumbnail.material.set_shader_parameter("has_map", map_texture != null)
	thumbnail.material.set_shader_parameter("tint", Color.WHITE if map_texture else tint)
	show_chosen(false)

func show_chosen(on):
	is_chosen = on
	name_label.add_theme_color_override("font_color", Color(0.98, 0.93, 0.83) if on else Color(0.8, 0.76, 0.68))
	number_label.add_theme_color_override("font_color", GOLD if on else Color(0.5, 0.44, 0.35))
	fade_glow()

func hover(on):
	fade_glow()
	var slide = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	slide.tween_property(row, "offset_left", row_resting_left + (8.0 if on else 0.0), 0.3)

# The glow fades to its new strength instead of popping on and off
func fade_glow():
	var wanted = 0.24 if is_chosen else (0.08 if is_hovered() else 0.0)
	if glow_tween:
		glow_tween.kill()
	glow_tween = create_tween()
	glow_tween.tween_property(self, "glow", wanted, 0.25)

func _process(delta):
	if is_chosen:
		spin = fmod(spin + delta * 0.05, 1.0)
		thumbnail.material.set_shader_parameter("turn", spin)

func _draw():
	var strength = glow
	if strength > 0.001:
		# A gold glow that fades out to the right, like light on a brass plate
		var glow = PackedVector2Array([Vector2(0, 1), Vector2(size.x, 1), Vector2(size.x, size.y - 1), Vector2(0, size.y - 1)])
		var bright = Color(GOLD, strength)
		var faded = Color(GOLD, 0.0)
		draw_polygon(glow, PackedColorArray([bright, faded, faded, bright]))
	if is_chosen:
		draw_line(Vector2(1, 2), Vector2(1, size.y - 2), GOLD, 2.0)
		var middle = Vector2(size.x - 12.0, size.y / 2.0)
		var corners = PackedVector2Array([middle + Vector2(0, -4), middle + Vector2(4, 0), middle + Vector2(0, 4), middle + Vector2(-4, 0), middle + Vector2(0, -4)])
		draw_polyline(corners, GOLD, 1.0, true)
	# A faint engraved line under every entry
	draw_line(Vector2(8, size.y - 0.5), Vector2(size.x - 8, size.y - 0.5), Color(GOLD, 0.12), 1.0)
