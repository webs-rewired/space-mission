extends Control

# The moment of flying to a world picked in the Go to... menu (res://scenes/travel_screen.tscn): the real world
# turning in its rings, its name rising into place, and a gold line drawing across as the trip goes on.
# space_controls.gd calls go(); when the trip is done this sends arrived(body_name, follow) and fades away.

signal arrived(body_name, follow)

const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const TRIP_SECONDS = 2.2
# What mission control says along the way ({name} becomes the world's name)
const STEPS = ["Plotting a course to {name}", "Engines firing", "Coasting through space", "Matching speed with {name}", "Arriving at {name}"]

@onready var backdrop: ColorRect = $Backdrop
@onready var dust: CPUParticles2D = $Dust
@onready var globe: Control = $Center/Column/Globe
@onready var kicker_label: Label = $Center/Column/Kicker
@onready var name_label: Label = $Center/Column/NameLabel
@onready var kind_label: Label = $Center/Column/KindLabel
@onready var progress_line: Control = $Center/Column/Progress
@onready var status_label: Label = $Center/Column/Status

var travelling = false

func is_busy():
	return travelling

func go(bodies_node, body_name, follow):
	if travelling or not SolarSystemData.BODIES.has(body_name):
		return
	travelling = true
	var data = SolarSystemData.BODIES[body_name]
	var shown_name = str(data["label"])
	name_label.text = shown_name.to_upper()
	kind_label.text = str(data.get("facts", {}).get("type", ""))
	status_label.text = STEPS[0].replace("{name}", shown_name)
	visible = true
	modulate.a = 1.0
	dust.position = size / 2.0
	dust.emission_rect_extents = size / 2.0
	dust.restart()
	globe.show_world(bodies_node, body_name)
	# Everything comes in: the backdrop darkens, the rings sweep in, the world swells, the name rises
	backdrop.modulate.a = 0.0
	backdrop.create_tween().tween_property(backdrop, "modulate:a", 1.0, 0.25)
	globe.draw_in(0.0, 0.9)
	globe.swell()
	UiMotion.reveal_text(kicker_label, 0.05, 0.5, 0.3)
	UiMotion.reveal_text(name_label, 0.12, 0.7, 0.5)
	UiMotion.slide_in(kind_label, 0.25, Vector2(0, 10), 0.5)
	# The gold line draws out from the middle as the trip goes on, and the status changes along the way
	progress_line.drawn = 0.0
	var trip = create_tween()
	trip.tween_property(progress_line, "drawn", 1.0, TRIP_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for step in range(1, STEPS.size()):
		get_tree().create_timer(TRIP_SECONDS * step / STEPS.size()).timeout.connect(func():
			if travelling:
				status_label.text = STEPS[step].replace("{name}", shown_name)
				UiMotion.slide_in(status_label, 0.0, Vector2(0, 6), 0.3))
	await trip.finished
	globe.pulse()
	var fade = create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.35)
	await get_tree().create_timer(0.1).timeout
	arrived.emit(body_name, follow)   # the camera starts flying while this fades away
	await fade.finished
	visible = false
	travelling = false
