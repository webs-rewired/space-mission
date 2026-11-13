extends Node

# Music, sound effects and real NASA audio for the whole game. It's a scene (res://scenes/audio_manager.tscn)
# that GameState adds when the game starts, so the music keeps playing from one scene to the next.
# The volume channels (Music, Effects, Ambience, Voice) are in res://default_bus_layout.tres.
#
# Sound files can be anywhere in the project: each sound below lists the file names it looks for.
# Missing files are skipped quietly, so the game still runs without them.
#
# Real physics in the sound:
#   - sound takes time to travel (343 m/s on Earth), so you see liftoff before you hear it
#   - thin air muffles sound and fades high pitches; in space there's no air at all, so no sound outside
#   - on Mars sound is about 20 decibels quieter than on Earth and travels slower (Perseverance measured 240 m/s)

const SOUNDS = {
	# Music (CC0): "Space Music: Out There" by yd, "Outer Space Loop" by wipics (OpenGameArt)
	"music_menu": ["out_there.ogg", "outthere.ogg"],
	"music_cruise": ["outer_space_loop.mp3", "outer_space.mp3"],
	# Real NASA audio (public domain)
	"countdown_apollo": ["apollo11_countdown.mp3", "590320main_ringtone_apollo11_countdown.mp3"],
	"countdown_artemis": ["artemis1_liftoff.mp3", "liftoff1.mp3"],
	"launch_roar": ["shuttle_launch_roar_loop.ogg", "590189main_ringtone_131_launchnats.mp3"],
	"launch_atlas": ["atlas_v_launch_roar_loop.ogg", "590329main_ringtone_sdo_launchnats.mp3"],
	"call_meco": ["discovery_main_engine_cutoff.mp3", "640166main_meco.mp3"],
	"eagle_has_landed": ["apollo11_eagle_has_landed.mp3", "569462main_eagle_has_landed.mp3"],
	"houston_problem": ["apollo13_houston_problem.mp3", "574928main_houston_problem.mp3"],
	"mars_wind": ["perseverance_mars_wind_loop.ogg", "scam-mic-sol004-run001.wav"],
	"mars_rover_drive": ["perseverance_rover_driving_loop.ogg", "filtered-highlights-sol16roverdrivehighlights.wav"],
	"marsquake": ["insight_marsquake.ogg", "quake-sol-173.wav"],
	"jupiter_radio": ["juno_ganymede_radio_loop.ogg", "e2-wave-ganymede-flyby-compressed.wav"],
	# Game sounds (Kenney, CC0)
	"click": ["click_002.ogg"],
	"select": ["select_001.ogg"],
	"confirm": ["confirmation_001.ogg"],
	"error": ["error_004.ogg"],
	"alarm": ["forcefield_001.ogg"],
	"static": ["computernoise_000.ogg"],
	"glitch": ["glitch_001.ogg"],
	"impact": ["impactmetal_000.ogg"],
	"thump": ["lowfrequency_explosion_000.ogg"],
	"thruster": ["thrusterfire_000.ogg"],
	"engine_loop": ["spaceenginelow_000.ogg"],
	"laser": ["lasersmall_000.ogg"],
	"jingle_success": ["jingles_pizzi02.ogg"],
	"jingle_failure": ["jingles_steel01.ogg"],
}

# Which music goes with which scene ("" = this scene handles its own sound)
const SCENE_MUSIC = {
	"solar_system": "music_menu", "solarsystem": "music_menu", "probe_builder": "music_menu",
	"rocket_builder": "music_menu", "launch": "", "results": "",
}

const LOOPING = ["music_menu", "music_cruise", "launch_roar", "launch_atlas", "mars_wind", "mars_rover_drive", "jupiter_radio", "engine_loop"]
const SPEED_OF_SOUND_EARTH = 343.0

@onready var music_players = [$MusicA, $MusicB]
@onready var ambience: AudioStreamPlayer = $Ambience
@onready var engine: AudioStreamPlayer = $Engine
@onready var voice: AudioStreamPlayer = $Voice
@onready var effect_players = [$Effect1, $Effect2, $Effect3, $Effect4, $Effect5, $Effect6]

var file_paths = {}          # file name (lowercase) -> path in the project
var stream_cache = {}
var current_music = ""
var music_player_index = 0
var next_effect_player = 0
var last_scene = ""
var music_muted = false

func _ready():
	find_sound_files("res://")
	get_tree().node_added.connect(_on_node_added)

# Remember where every sound file in the project is
func find_sound_files(folder):
	var directory = DirAccess.open(folder)
	if directory == null:
		return
	for file_name in directory.get_files():
		var lower = file_name.to_lower()
		for extension in [".ogg", ".mp3", ".wav"]:
			if lower.ends_with(extension):
				file_paths[lower] = folder.path_join(file_name)
			elif lower.ends_with(extension + ".import"):
				# In an exported game only the .import files are listed
				file_paths[lower.trim_suffix(".import")] = folder.path_join(file_name.trim_suffix(".import"))
	for sub_folder in directory.get_directories():
		if not sub_folder.begins_with("."):
			find_sound_files(folder.path_join(sub_folder))

func has_sound(sound_name):
	return get_stream(sound_name) != null

func get_stream(sound_name):
	if stream_cache.has(sound_name):
		return stream_cache[sound_name]
	var stream = null
	for file_name in SOUNDS.get(sound_name, []):
		if file_paths.has(file_name) and ResourceLoader.exists(file_paths[file_name]):
			stream = load(file_paths[file_name])
			break
	if stream != null and sound_name in LOOPING:
		stream = stream.duplicate()
		if "loop" in stream:
			stream.loop = true
		elif stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
	stream_cache[sound_name] = stream
	return stream

func sound_length(sound_name):
	var stream = get_stream(sound_name)
	return stream.get_length() if stream else 0.0

# ---------------------------------------------------------------------------
# Music: fades from one track to the next
# ---------------------------------------------------------------------------
func play_music(sound_name, fade_seconds = 2.0):
	if sound_name == current_music:
		return
	current_music = sound_name
	var old_player = music_players[music_player_index]
	music_player_index = 1 - music_player_index
	var new_player = music_players[music_player_index]
	fade(old_player, -60.0, fade_seconds, true)
	var stream = get_stream(sound_name)
	if stream == null:
		return
	new_player.stream = stream
	new_player.volume_db = -60.0
	new_player.play()
	fade(new_player, 0.0, fade_seconds, false)

func stop_music(fade_seconds = 2.0):
	current_music = ""
	for player in music_players:
		fade(player, -60.0, fade_seconds, true)

func fade(player, volume_db, seconds, stop_after):
	var tween = create_tween()
	tween.tween_property(player, "volume_db", volume_db, seconds)
	if stop_after:
		tween.tween_callback(player.stop)

# ---------------------------------------------------------------------------
# Sounds
# ---------------------------------------------------------------------------
func play_effect(sound_name, volume_db = 0.0, pitch = 1.0, delay_seconds = 0.0):
	var stream = get_stream(sound_name)
	if stream == null:
		return
	if delay_seconds > 0.0:
		await get_tree().create_timer(delay_seconds).timeout
	var player = effect_players[next_effect_player]
	next_effect_player = (next_effect_player + 1) % effect_players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()

# Radio calls from Mission Control and the crews
func play_voice(sound_name, volume_db = 0.0, delay_seconds = 0.0, from_seconds = 0.0):
	var stream = get_stream(sound_name)
	if stream == null:
		return
	if delay_seconds > 0.0:
		await get_tree().create_timer(delay_seconds).timeout
	voice.stream = stream
	voice.volume_db = volume_db
	voice.play(from_seconds)

func stop_voice():
	voice.stop()

# A long, looping background sound (wind, radio hiss)
func play_ambience(sound_name, volume_db = 0.0, pitch = 1.0):
	var stream = get_stream(sound_name)
	if stream == null:
		ambience.stop()
		return
	if ambience.stream != stream or not ambience.playing:
		ambience.stream = stream
		ambience.play()
	ambience.volume_db = volume_db
	ambience.pitch_scale = pitch

func stop_ambience(fade_seconds = 1.5):
	fade(ambience, -60.0, fade_seconds, true)

# The engine sound (launch roar, rover motors), changed every frame by whoever is using it
func start_engine(sound_name, volume_db = 0.0, pitch = 1.0, delay_seconds = 0.0):
	var stream = get_stream(sound_name)
	if stream == null:
		return
	if delay_seconds > 0.0:
		await get_tree().create_timer(delay_seconds).timeout
	engine.stream = stream
	engine.volume_db = volume_db
	engine.pitch_scale = pitch
	engine.play()

func set_engine(volume_db, pitch = 1.0):
	engine.volume_db = volume_db
	engine.pitch_scale = max(pitch, 0.05)

func stop_engine(fade_seconds = 1.0):
	fade(engine, -60.0, fade_seconds, true)

# How much air there is to carry sound: 1 = Earth at sea level, 0 = space.
# Thin air muffles high pitches; this sets the muffling on the Effects and Ambience channels.
func set_air(thickness):
	var cutoff = 20000.0 if thickness >= 1.0 else lerp(250.0, 20000.0, pow(clamp(thickness, 0.0, 1.0), 0.6))
	for bus_name in ["Effects", "Ambience"]:
		var bus = AudioServer.get_bus_index(bus_name)
		if bus >= 0 and AudioServer.get_bus_effect_count(bus) > 0:
			var filter = AudioServer.get_bus_effect(bus, 0)
			if filter is AudioEffectLowPassFilter:
				filter.cutoff_hz = cutoff

# How long sound takes to travel a distance, in seconds
func sound_delay(distance_meters, speed_of_sound = SPEED_OF_SOUND_EARTH):
	return distance_meters / speed_of_sound

# ---------------------------------------------------------------------------
# Every scene: its music, and a click for every button
# ---------------------------------------------------------------------------
func _process(_delta):
	var scene = get_tree().current_scene
	if scene == null:
		return
	var scene_name = scene.scene_file_path.get_file().get_basename()
	if scene_name == last_scene:
		return
	last_scene = scene_name
	set_air(1.0)
	stop_engine(0.5)
	if scene_name != "launch":
		stop_ambience(1.0)
	if SCENE_MUSIC.has(scene_name) and SCENE_MUSIC[scene_name] != "":
		play_music(SCENE_MUSIC[scene_name])
	elif scene_name == "launch":
		stop_music(1.5)   # the launch has its own sound: the countdown and the roar

func _on_node_added(node):
	if node is OptionButton:
		node.item_selected.connect(func(_index): play_effect("select", -8.0))
	elif node is BaseButton:
		node.pressed.connect(func(): play_effect("click", -6.0))

func _unhandled_input(event):
	# M turns the music on and off
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		music_muted = not music_muted
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), music_muted)
