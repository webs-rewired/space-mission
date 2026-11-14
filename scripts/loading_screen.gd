extends CanvasLayer

# The loading screen between scenes (res://scenes/loading_screen.tscn). GameState adds it when the game starts and
# every scene change goes through GameState.go_to_scene(), which calls go_to() here.
#
# The next scene loads in the background while this screen shows a progress bar, mission-control call-outs and
# real space facts (about the place you're going, when there is one). The old scene stays on screen underneath
# until the new one is ready.
#
# It moves like a page change on the Webs With U site: a blue sheet sweeps up the screen with the dark loading
# screen right behind it, the title's letters rise into place, and when the new scene is ready the whole loading
# screen lifts away upward while the new scene's panels glide in (scripts/ui_motion.gd).

# What mission control is doing while each scene loads ({destination} becomes the place you picked)
const STATUS_LINES = {
	"solar_system": ["Flight dynamics: loading JPL positions for today", "Placing the planets, dwarf planets and moons", "Scattering the asteroid belt and the Kuiper belt", "Switching on the Sun"],
	"probe_builder": ["Suiting up: gowns, gloves, hoods and masks on", "Opening the clean room", "Unpacking flight instruments for {destination}", "Loading the parts catalog"],
	"rocket_builder": ["Rolling the mobile launcher into the Vehicle Assembly Building", "Stacking the boosters and the core stage", "Checking engines, tanks and the upper stage", "Lifting your spacecraft onto the rocket"],
	"launch": ["Range: weather and airspace are GO", "Propellant: loading the tanks", "Flight dynamics: trajectory to {destination} locked", "Network: Goldstone, Madrid and Canberra standing by", "Launch director: polling the team, GO / NO-GO"],
	"results": ["Downlinking science data from {destination}", "Calibrating the instruments", "Scoring the mission"],
	"main_menu (2)": ["Returning to the main menu"],
}
const DEFAULT_LINES = ["Loading assets", "Warming up the engines"]

# The big title and the line under it, for each scene
const TITLES = {
	"solar_system": ["SOLAR SYSTEM", "Every world is where it really is today, from NASA JPL's orbit data"],
	"probe_builder": ["SPACECRAFT ASSEMBLY", "The clean room: build a spacecraft for {destination}"],
	"rocket_builder": ["LAUNCH VEHICLE", "Vehicle Assembly Building, Kennedy Space Center, Florida"],
	"launch": ["LAUNCH CONTROL", "Kennedy Space Center, Florida. Destination: {destination}"],
	"results": ["MISSION REPORT", "The science return from {destination}"],
	"main_menu (2)": ["ORBIT LAB", "Design a space mission. Launch it. Fly it."],
}

# Where each scene sits in the five steps of a mission. The steps follow how NASA builds a science mission
# ("Design and Develop Science Missions"): the mission concept, the space segment (the spacecraft), the launch
# segment (the rocket), the ground segment (the dishes that keep in touch), and the user segment (the scientists).
const MISSION_STEPS = {
	"solar_system": "STEP 1 OF 5   |   CHOOSE A DESTINATION: THE MISSION CONCEPT",
	"probe_builder": "STEP 2 OF 5   |   DESIGN THE SPACECRAFT: THE SPACE SEGMENT",
	"rocket_builder": "STEP 3 OF 5   |   PICK A ROCKET: THE LAUNCH SEGMENT",
	"launch": "STEP 4 OF 5   |   LAUNCH AND FLY: THE GROUND SEGMENT KEEPS IN TOUCH",
	"results": "STEP 5 OF 5   |   THE SCIENCE: THE USER SEGMENT",
}

# Real facts about spaceflight and the solar system, shown at random
const FACTS = [
	"This year Voyager 1 reaches about one light-day from Earth: its radio signals take about a full day to get home.",
	"A day on Venus is longer than its year: it turns once every 243 Earth days, and goes around the Sun in 225.",
	"Perseverance landed on Mars with a sky crane: a rocket-powered jetpack that lowered it to the ground on cables.",
	"The Saturn V stood 110 meters tall and pushed with 34.5 million newtons of thrust at liftoff.",
	"NASA's Deep Space Network has three sites, in California, Spain and Australia, so one of them always faces any spacecraft.",
	"New Horizons took 9.5 years to reach Pluto, and about 15 months to send all its pictures home.",
	"Jupiter's moon Io has over 400 active volcanoes: the most volcanic place we know.",
	"Enceladus sprays its ocean into space through cracks at its south pole. Cassini flew right through the spray.",
	"A launch window opens when the planets line up. For Mars that happens about every 26 months.",
	"Space missions have four parts: the launch, the spacecraft, the ground stations, and the scientists who use the data.",
	"On Titan the air is so thick and gravity so weak that a person could fly by flapping wings strapped to their arms.",
	"Mission designers grade an idea's readiness with Concept Maturity Levels, from a sketch (CML 1) to a full design.",
	"The International Space Station goes around Earth about every 90 minutes, so its crew sees 16 sunrises a day.",
	"Sunlight takes about 8 minutes and 20 seconds to reach Earth, and about 5 and a half hours to reach Pluto.",
	"Parker Solar Probe is the fastest thing people have ever built: about 690,000 km/h as it skims past the Sun.",
	"The Apollo Guidance Computer that flew astronauts to the Moon had about 4 kilobytes of working memory.",
	"The Moon drifts about 3.8 centimeters farther from Earth every year. Apollo astronauts left mirrors there to measure it.",
	"To stay in orbit just above the air, a spacecraft has to fly about 7.8 km every second. To leave Earth for good: 11.2.",
	"Ingenuity, a 1.8 kg helicopter, made 72 flights on Mars: the first powered flights on another world.",
	"Saturn is so light for its size that it would float in a bathtub big enough to hold it.",
	"Uranus is tipped over on its side, so each pole gets 42 years of daylight and then 42 years of darkness.",
	"Voyager 2 used the pull of Jupiter, Saturn and Uranus to swing on to Neptune: a planetary grand tour that only lines up every 175 years.",
	"Spacecraft far from the Sun run on RTGs: the heat of decaying plutonium-238 is turned straight into electricity.",
	"Dawn was the first spacecraft to orbit two different worlds: the asteroid Vesta, then the dwarf planet Ceres.",
	"In 2022 NASA's DART spacecraft crashed into the asteroid moon Dimorphos on purpose and changed its orbit by 32 minutes.",
	"The James Webb Space Telescope works 1.5 million km from Earth, at a balance point called L2.",
	"Coming home from the Moon, Orion's heat shield faces about 2,760 °C: around half as hot as the surface of the Sun.",
	"Cassini ended its mission by diving into Saturn in 2017, so it could never crash into and contaminate Titan or Enceladus.",
	"The average distance between asteroids in the asteroid belt is about a million kilometers.",
	"Mars has the tallest volcano in the solar system: Olympus Mons is about 22 km high, two and a half times Mount Everest.",
	"Neptune was found with math before anyone saw it: its pull on Uranus showed astronomers where to point their telescopes in 1846.",
	"Jupiter's Great Red Spot is a storm wider than the whole Earth that has been raging for at least 150 years.",
	"Spacecraft are built in clean rooms with filtered air, by people in head-to-toe 'bunny suits' so no hair, skin or dust lands on the hardware.",
	"The Vehicle Assembly Building is one of the biggest buildings in the world by volume: 160 meters tall, built to stack the Saturn V.",
	"Europa Clipper launched in 2024 and arrives at Jupiter in 2030 to find out if Europa's hidden ocean could support life.",
]

# Facts about the place you're going (shown more often while you plan and fly a mission there)
const PLACE_FACTS = {
	"Mercury": ["A year on Mercury lasts only 88 Earth days.", "Mercury swings from about 430 °C in the day to -180 °C at night: there's no air to hold the heat.", "MESSENGER found water ice hiding in craters at Mercury's poles that never see sunlight."],
	"Venus": ["Venus's surface is about 465 °C: hotter than Mercury, even though it's twice as far from the Sun.", "The air pressure on Venus is about 92 times Earth's, like being 900 meters under the sea.", "The Soviet lander Venera 13 survived 127 minutes on Venus in 1982 and sent back color pictures."],
	"Moon": ["Twelve astronauts walked on the Moon between 1969 and 1972.", "Radio signals take about 1.3 seconds to reach the Moon.", "The Moon's gravity is about one sixth of Earth's."],
	"Mars": ["Radio signals take between 3 and 22 minutes to reach Mars, so rovers have to drive themselves between commands.", "Landing on Mars takes about seven minutes from the top of the air to the ground: engineers call it the seven minutes of terror.", "A day on Mars, called a sol, is 24 hours and 39 minutes long."],
	"Phobos": ["Phobos creeps about 1.8 meters closer to Mars every century. In about 50 million years it will break apart.", "Phobos goes around Mars three times a day, faster than Mars turns."],
	"Deimos": ["Deimos is only about 12 km across: from Mars it looks like a bright star.", "Deimos and Phobos may be captured asteroids, or pieces thrown up by a giant impact on Mars."],
	"Ceres": ["Ceres holds about a quarter of all the mass in the asteroid belt.", "The bright spots in Ceres's Occator crater are salt left behind by salty water from inside.", "Dawn orbited Ceres from 2015 to 2018 and is still circling it, silent."],
	"Jupiter": ["Jupiter is more than twice as massive as all the other planets put together.", "Jupiter's radiation is so strong that Juno keeps its electronics in a titanium vault.", "A day on Jupiter lasts less than 10 hours: the fastest spin of any planet."],
	"Io": ["Io's volcanoes throw plumes of gas and dust up to about 400 km above the surface.", "Io is squeezed by Jupiter's gravity like a stress ball, and the squeezing heats it from inside."],
	"Europa": ["Europa's ocean may hold about twice as much water as all of Earth's oceans.", "Europa Clipper will fly past Europa about 49 times, dipping in and out of Jupiter's radiation.", "Europa's ice shell is thought to be about 15 to 25 km thick."],
	"Ganymede": ["Ganymede is the biggest moon in the solar system: bigger than the planet Mercury.", "Ganymede is the only moon with its own magnetic field.", "ESA's JUICE spacecraft is on its way to orbit Ganymede in 2034."],
	"Callisto": ["Callisto is one of the most heavily cratered places in the solar system.", "Callisto orbits outside Jupiter's worst radiation, so it's the safest big moon there for people to visit one day."],
	"Saturn": ["Saturn's main rings are about 280,000 km across but mostly only about 10 meters thick.", "Cassini spent 13 years at Saturn and found new moons, lakes on Titan and geysers on Enceladus.", "Saturn has more known moons than any other planet: well over 200."],
	"Titan": ["Titan has lakes and seas of liquid methane and ethane, and it rains methane there.", "Titan's air is about one and a half times as thick as Earth's.", "NASA's Dragonfly, a nuclear-powered drone, is planned to launch in 2028 and fly from place to place on Titan."],
	"Enceladus": ["Enceladus reflects almost all the sunlight that hits it: it's one of the brightest things in the solar system.", "The spray from Enceladus's geysers forms one of Saturn's rings, the E ring."],
	"Uranus": ["Voyager 2 is the only spacecraft ever to visit Uranus, in 1986.", "Uranus is tipped on its side, so it rolls around the Sun like a ball.", "Uranus is the coldest planet: its clouds get down to about -224 °C."],
	"Titania": ["Titania is the largest moon of Uranus, about 1,580 km across.", "Titania is named after the queen of the fairies in Shakespeare's A Midsummer Night's Dream."],
	"Neptune": ["Neptune has the fastest winds in the solar system: over 2,000 km/h.", "Voyager 2 flew past Neptune in 1989: still the only spacecraft to go there.", "Neptune takes 165 years to go around the Sun once."],
	"Triton": ["Triton orbits Neptune backwards, so it was probably a Kuiper belt world that Neptune captured.", "Voyager 2 saw geysers of nitrogen gas shooting up from Triton's frozen surface."],
	"Pluto": ["New Horizons flew past Pluto in July 2015 at about 50,000 km/h.", "Pluto's heart is a huge glacier of frozen nitrogen.", "A year on Pluto lasts 248 Earth years."],
	"Charon": ["Charon is half as wide as Pluto, so the two circle a point in space between them.", "Charon has a dark red cap at its north pole, made from gas that escaped Pluto."],
	"Eris": ["Eris is about as wide as Pluto but about a quarter heavier. Its discovery in 2005 led to Pluto being called a dwarf planet.", "Eris takes about 560 years to go around the Sun."],
	"Haumea": ["Haumea spins once every 4 hours, so fast that it's stretched into an egg shape.", "Haumea has a thin ring and two small moons."],
	"Makemake": ["Makemake was discovered just after Easter in 2005 and is named after a creator god of Rapa Nui (Easter Island).", "Makemake is one of the brightest worlds in the Kuiper belt."],
	"Sun": ["The Sun holds 99.8 percent of all the mass in the solar system.", "Parker Solar Probe flies through the Sun's outer atmosphere, the corona, protected by a heat shield 11.4 cm thick."],
}
# Scenes where the facts are about your destination more often than not
const PLACE_FACT_SCENES = ["probe_builder", "rocket_builder", "launch", "results"]

const SHORTEST_SECONDS = 1.1        # the screen stays at least this long, so it never just flickers
const SETTLE_FRAMES = 8             # frames the new scene gets to draw before the screen lifts away
const NEXT_FACT_SECONDS = 7.0       # a long load shows a new fact this often

@onready var cover: Control = $Cover
@onready var wipe: ColorRect = $Wipe
@onready var status_label: Label = $Cover/Center/Column/Status
@onready var progress_bar: ProgressBar = $Cover/Center/Column/Progress
@onready var fact_heading: Label = $Cover/Center/Column/FactHeading
@onready var fact_label: Label = $Cover/Center/Column/Fact
@onready var title_label: Label = $Cover/Center/Column/Title
@onready var subtitle_label: Label = $Cover/Center/Column/Subtitle
@onready var kicker_label: Label = $Cover/Center/Column/Kicker

var wanted_scene = ""
var loading = false
var covering = false          # the sheets are still sweeping up the screen
var seconds_shown = 0.0
var seconds_on_fact = 0.0
var status_lines = DEFAULT_LINES
var shown_progress = 0.0
var scene_name = ""
var transition: Tween = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	cover.visible = false
	wipe.visible = false

func is_busy():
	return loading

func destination():
	var place = str(GameState.destination) if "destination" in GameState else ""
	return place if place != "" else "your destination"

func with_destination(text):
	return text.replace("{destination}", destination())

func go_to(scene_path):
	if loading:
		return
	if not ResourceLoader.exists(scene_path):
		push_error("Scene not found: " + scene_path)
		return
	get_tree().paused = false
	wanted_scene = scene_path
	loading = true
	covering = true
	seconds_shown = 0.0
	shown_progress = 0.0
	scene_name = scene_path.get_file().get_basename()
	status_lines = STATUS_LINES.get(scene_name, DEFAULT_LINES).map(with_destination)
	var title = TITLES.get(scene_name, ["ORBIT LAB", ""])
	title_label.text = title[0]
	subtitle_label.text = with_destination(title[1])
	kicker_label.text = MISSION_STEPS.get(scene_name, "ORBIT LAB   |   MISSION CONTROL")
	pick_fact()
	status_label.text = status_lines[0] + "..."
	progress_bar.value = 0.0
	# Start loading right away; the sweep plays while it loads
	ResourceLoader.load_threaded_request(scene_path)
	# A blue sheet sweeps up the screen with the dark loading screen right behind it
	if transition:
		transition.kill()
	var screen_height = cover.get_viewport_rect().size.y
	cover.modulate.a = 1.0
	cover.visible = true
	cover.position = Vector2(0, screen_height)
	wipe.visible = true
	wipe.position = Vector2(0, screen_height)
	for label in [kicker_label, title_label, subtitle_label]:
		label.material = null
	transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	transition.tween_property(wipe, "position:y", -screen_height, 0.75)
	transition.tween_property(cover, "position:y", 0.0, 0.55).set_delay(0.1)
	await transition.finished
	wipe.visible = false
	covering = false
	# Then the words come in like the Webs With U site: letters rise from behind an edge, one after another
	UiMotion.reveal_text(kicker_label, 0.0, 0.6, 0.3)
	UiMotion.reveal_text(title_label, 0.05, 0.85, 0.6)
	UiMotion.reveal_text(subtitle_label, 0.2, 0.7, 0.3)
	UiMotion.slide_in(fact_heading, 0.3, Vector2(0, 14), 0.6)
	UiMotion.slide_in(fact_label, 0.36, Vector2(0, 14), 0.6)

# A fact about where you're going (most of the time, while planning and flying a mission), or a general one
func pick_fact():
	seconds_on_fact = 0.0
	var place = str(GameState.destination) if "destination" in GameState else ""
	var place_facts = PLACE_FACTS.get(place, [])
	if scene_name in PLACE_FACT_SCENES and not place_facts.is_empty() and randf() < 0.7:
		fact_heading.text = "ABOUT " + place.to_upper()
		fact_label.text = place_facts[randi() % place_facts.size()]
	else:
		fact_heading.text = "DID YOU KNOW?"
		var fact = fact_label.text
		while fact == fact_label.text:
			fact = FACTS[randi() % FACTS.size()]
		fact_label.text = fact

func _process(delta):
	if not loading or covering:
		return
	seconds_shown += delta
	seconds_on_fact += delta
	if seconds_on_fact > NEXT_FACT_SECONDS:
		pick_fact()
		UiMotion.slide_in(fact_label, 0.0, Vector2(0, 14), 0.6)
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
	status_label.text = "GO"
	get_tree().change_scene_to_packed(scene)
	# Let the new scene build itself and draw a few frames behind this screen before showing it
	for frame in SETTLE_FRAMES:
		await get_tree().process_frame
	if loading:
		return   # (another scene change started meanwhile)
	# The loading screen lifts away upward while the new scene's panels glide in
	UiMotion.enter_scene(get_tree().current_scene)
	var screen_height = cover.get_viewport_rect().size.y
	transition = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	transition.tween_property(cover, "position:y", -screen_height, 0.7)
	await transition.finished
	if not loading:
		cover.visible = false
		cover.position = Vector2.ZERO
