extends CanvasLayer

# The cut from the journey to the landing site (res://scenes/landing_cut.tscn). Building a landing site (its ground,
# rocks, sky and collision shape) takes a moment, so instead of the picture freezing, the screen fades to black with
# the name of the landing and a real fact about landing there, the site is built behind it, and then it lifts away.
#
# launch.gd: var cut = LANDING_CUT_SCENE.instantiate(); add_child(cut); await cut.cover(world) ... build ...
# cut.lift()

const FACTS = {
	"Mars": "Entry, descent and landing on Mars takes about seven minutes, often less time than a radio signal needs to reach Earth. Nobody can steer it: the spacecraft lands itself.",
	"Moon": "There's no air on the Moon to slow down in, so rocket engines do all the braking, the way Apollo's lunar modules and China's Chang'e landers came down.",
	"Venus": "Venus's air is so thick that a lander floats down for about an hour. The Soviet Venera landers were the only spacecraft ever to send pictures from its surface.",
	"Titan": "In 2005 ESA's Huygens probe took about two and a half hours to drift down through Titan's orange haze under its parachutes.",
	"Mercury": "No spacecraft has ever landed on Mercury. MESSENGER ended its mission in 2015 by crashing into it, out of fuel after four years in orbit.",
	"Europa": "No spacecraft has landed on Europa yet. NASA's Europa Clipper, launched in 2024, arrives at Jupiter in 2030 to study Europa's ice from close flybys.",
	"Enceladus": "No spacecraft has landed on Enceladus. Cassini flew through its geysers instead, tasting the ocean spray from space.",
	"Ceres": "No spacecraft has landed on Ceres. Dawn ended its mission in 2018 in a low orbit, after getting as close as 35 km above the surface.",
	"Io": "No spacecraft has landed on Io. Juno flew about 1,500 km above it in 2023 and 2024 and photographed its volcanoes.",
	"Pluto": "No spacecraft has landed on Pluto. New Horizons flew past in 2015, about 12,500 km above the surface.",
}
const DEFAULT_FACT = "With little or no air to slow down in, the engines do all the braking. Landers like this come down on radar, measuring the distance to the ground many times a second."

@onready var curtain: ColorRect = $Curtain
@onready var title_label: Label = $Column/Title
@onready var place_label: Label = $Column/Place
@onready var fact_label: Label = $Column/Fact

func _ready():
	layer = 119
	process_mode = Node.PROCESS_MODE_ALWAYS
	curtain.modulate.a = 0.0
	$Column.modulate.a = 0.0

# Fades to black with the landing's name and a fact; returns once the screen is covered and has been drawn,
# so the heavy work after it happens behind the curtain
func cover(world):
	place_label.text = world.to_upper()
	fact_label.text = FACTS.get(world, DEFAULT_FACT)
	var fade = create_tween()
	fade.tween_property(curtain, "modulate:a", 1.0, 0.45)
	fade.parallel().tween_property($Column, "modulate:a", 1.0, 0.45).set_delay(0.15)
	await fade.finished
	# (two frames, so the covered screen is actually on the monitor before the work starts)
	await get_tree().process_frame
	await get_tree().process_frame

# Lifts the curtain once the site is ready (after a few frames, so its first drawing happens behind the curtain)
# and removes itself
func lift():
	for frame in 3:
		await get_tree().process_frame
	var fade = create_tween()
	fade.tween_interval(0.6)   # time to read the fact
	fade.tween_property($Column, "modulate:a", 0.0, 0.4)
	fade.parallel().tween_property(curtain, "modulate:a", 0.0, 0.8)
	await fade.finished
	queue_free()
