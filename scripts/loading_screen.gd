extends CanvasLayer

# The loading screen between scenes (res://scenes/loading_screen.tscn). GameState adds it when the game starts and
# every scene change goes through GameState.go_to_scene(), which calls go_to() here.
#
# The next scene loads in the background while this screen shows a progress bar, mission-control style status
# lines and a real space fact. The old scene stays on screen underneath until the new one is ready, and this
# screen only fades away once the new scene has drawn its first frames, so there is never a blank grey frame.

const STATUS_LINES = {
	"solar_system": ["Loading JPL planetary positions", "Placing the planets and their moons", "Scattering the asteroid belt", "Switching on the Sun"],
	"probe_builder": ["Opening the clean room", "Unpacking instruments", "Checking the parts catalog"],
	"rocket_builder": ["Rolling out to the launch pad", "Stacking the stages", "Checking engines and tanks"],
	"launch": ["Fueling the rocket", "Computing the trajectory", "Pointing the Deep Space Network dishes", "Polling the launch team: GO / NO-GO"],
	"results": ["Downlinking mission data", "Scoring the science"],
	"main_menu (2)": ["Returning to the main menu"],
}
const DEFAULT_LINES = ["Loading assets", "Warming up the engines"]
const FACTS = [
	"Voyager 1 is so far away that its radio signals take about 23 hours to reach Earth, at the speed of light.",
	"A day on Venus is longer than its year: it turns once every 243 Earth days.",
	"Perseverance landed on Mars with a sky crane: a rocket-powered jetpack that lowered it on cables.",
	"The Saturn V stood 110 meters tall and pushed with 34.5 million newtons of thrust at liftoff.",
	"NASA's Deep Space Network has three sites, in California, Spain and Australia, so one always faces any spacecraft.",
	"New Horizons took 9.5 years to reach Pluto, and 15 months to send all its pictures home.",
	"Jupiter's moon Io has over 400 active volcanoes: the most volcanic place we know.",
	"Enceladus sprays its ocean into space through cracks at its south pole. Cassini flew through the spray.",
	"A launch window opens when the planets line up. For Mars that happens every 26 months.",
	"Space missions have four parts: the launch, the spacecraft, the ground stations, and the scientists who use the data.",
	"On Titan the air is so thick and gravity so weak that a person could fly by flapping wings strapped to their arms.",
	"Mission designers grade an idea's readiness with Concept Maturity Levels, from a sketch (CML 1) to a full design.",
]
const SHORTEST_SECONDS = 0.9        # the screen stays at least this long, so it never just flickers
const SETTLE_FRAMES = 8             # frames the new scene gets to draw before the screen fades away

@onready var cover: Control = $Cover
@onready var status_label: Label = $Cover/Center/Column/Status
@onready var progress_bar: ProgressBar = $Cover/Center/Column/Progress
@onready var fact_label: Label = $Cover/Center/Column/Fact
@onready var title_label: Label = $Cover/Center/Column/Title

var wanted_scene = ""
var loading = false
var seconds_shown = 0.0
var status_lines = DEFAULT_LINES
var shown_progress = 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	cover.visible = false
	cover.modulate.a = 0.0

func is_busy():
	return loading

func go_to(scene_path):
	if loading:
		return
	if not ResourceLoader.exists(scene_path):
		push_error("Scene not found: " + scene_path)
		return
	get_tree().paused = false
	wanted_scene = scene_path
	loading = true
	seconds_shown = 0.0
	shown_progress = 0.0
	var scene_name = scene_path.get_file().get_basename()
	status_lines = STATUS_LINES.get(scene_name, DEFAULT_LINES)
	title_label.text = {"solar_system": "SOLAR SYSTEM", "probe_builder": "SPACECRAFT ASSEMBLY", "rocket_builder": "LAUNCH VEHICLE", "launch": "LAUNCH CONTROL", "results": "MISSION REPORT", "main_menu (2)": "ORBIT LAB"}.get(scene_name, "ORBIT LAB")
	fact_label.text = FACTS[randi() % FACTS.size()]
	status_label.text = status_lines[0] + "..."
	progress_bar.value = 0.0
	cover.visible = true
	var tween = create_tween()
	tween.tween_property(cover, "modulate:a", 1.0, 0.25)
	await tween.finished
	ResourceLoader.load_threaded_request(scene_path)

func _process(delta):
	if not loading or cover.modulate.a < 1.0:
		return
	seconds_shown += delta
	var progress = []
	var status = ResourceLoader.load_threaded_get_status(wanted_scene, progress)
	var real_progress = progress[0] if progress.size() > 0 else 0.0
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		real_progress = 1.0
	# The bar never jumps backwards and always creeps a little, so it's clear the game hasn't frozen
	shown_progress = max(shown_progress, min(real_progress, shown_progress + delta * 1.5))
	progress_bar.value = shown_progress * 100.0
	var line_index = min(int(shown_progress * status_lines.size()), status_lines.size() - 1)
	status_label.text = status_lines[line_index] + ".".repeat(1 + int(seconds_shown * 3.0) % 3)
	if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_error("Could not load " + wanted_scene)
		loading = false
		cover.visible = false
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED and seconds_shown >= SHORTEST_SECONDS and shown_progress >= 1.0:
		loading = false
		finish()

func finish():
	var scene = ResourceLoader.load_threaded_get(wanted_scene)
	status_label.text = "Ready"
	get_tree().change_scene_to_packed(scene)
	# Let the new scene build itself and draw a few frames behind this screen before showing it
	for frame in SETTLE_FRAMES:
		await get_tree().process_frame
	var tween = create_tween()
	tween.tween_property(cover, "modulate:a", 0.0, 0.45)
	await tween.finished
	if not loading:
		cover.visible = false
