extends Node

# The player's settings: graphics quality, fullscreen and sound volumes.
# GameState adds this node when the game starts (it's at /root/GameSettings), and the main menu's Settings panel
# changes it. The settings are saved in user://settings.cfg, so they're still there next time.
#
# Graphics quality is what to change when a computer runs the game slowly:
#   Low     for laptops without a gaming graphics card: draws the 3D picture at 60 % size, no shadows,
#           no glow / reflections / fog effects, a third of the rocks, fewer particles
#   Medium  draws at 80 % size, simple shadows, glow, two thirds of the rocks
#   High    everything
# The first time the game runs, it watches its own speed for a few seconds and turns the quality down by itself
# if the computer can't keep up.

signal changed

const SAVE_FILE = "user://settings.cfg"
const QUALITY_NAMES = ["Low", "Medium", "High"]
const SOUND_CHANNELS = ["Master", "Music", "Effects", "Voice"]
# The sound channels the game uses. They are normally in res://default_bus_layout.tres; if that file is missing
# they are made here instead, so the volume sliders and the music switch always work.
const CHANNEL_SETUP = {"Music": -5.0, "Effects": 0.0, "Ambience": -2.0, "Voice": 0.0}
const SLOW_FRAMES_PER_SECOND = 24.0      # slower than this at the start means the quality is too high for this computer
const SPEED_CHECK_SECONDS = 4.0

var quality = 2                          # 0 = Low, 1 = Medium, 2 = High
var fullscreen = false
var volumes = {"Master": 1.0, "Music": 1.0, "Effects": 1.0, "Voice": 1.0}   # 0 to 1
var quality_chosen_by_player = false
var speed_check_seconds = 0.0
var speed_check_frames = 0
var notice = ""                          # a message for the menu to show once ("graphics turned down")

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	make_sound_channels()
	load_settings()
	apply_all()
	get_tree().node_added.connect(_on_node_added)

# ---------------------------------------------------------------------------
# Saving and loading
# ---------------------------------------------------------------------------
func load_settings():
	var file = ConfigFile.new()
	if file.load(SAVE_FILE) != OK:
		return
	quality = clamp(int(file.get_value("graphics", "quality", quality)), 0, 2)
	quality_chosen_by_player = file.get_value("graphics", "chosen_by_player", false)
	fullscreen = file.get_value("graphics", "fullscreen", false)
	for channel in SOUND_CHANNELS:
		volumes[channel] = clamp(float(file.get_value("sound", channel, 1.0)), 0.0, 1.0)

func save_settings():
	var file = ConfigFile.new()
	file.set_value("graphics", "quality", quality)
	file.set_value("graphics", "chosen_by_player", quality_chosen_by_player)
	file.set_value("graphics", "fullscreen", fullscreen)
	for channel in SOUND_CHANNELS:
		file.set_value("sound", channel, volumes[channel])
	file.save(SAVE_FILE)

# ---------------------------------------------------------------------------
# Changing a setting (the Settings panel calls these)
# ---------------------------------------------------------------------------
func set_quality(new_quality, by_player = true):
	quality = clamp(new_quality, 0, 2)
	if by_player:
		quality_chosen_by_player = true
	apply_graphics()
	save_settings()
	changed.emit()

func set_fullscreen(on):
	fullscreen = on
	apply_window()
	save_settings()
	changed.emit()

func set_volume(channel, share):
	volumes[channel] = clamp(share, 0.0, 1.0)
	apply_sound()
	save_settings()

# ---------------------------------------------------------------------------
# What other scripts ask
# ---------------------------------------------------------------------------
# How much scattered detail to make (rocks, pebbles, background asteroids): 1 = all of it
func detail_share():
	return [0.3, 0.65, 1.0][quality]

func particle_share():
	return [0.35, 0.7, 1.0][quality]

func shadows_on():
	return quality >= 1

func fancy_effects_on():
	return quality >= 2

func quality_name():
	return QUALITY_NAMES[quality]

# ---------------------------------------------------------------------------
# Applying
# ---------------------------------------------------------------------------
func apply_all():
	apply_window()
	apply_sound()
	apply_graphics()

func apply_window():
	var wanted = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var now = DisplayServer.window_get_mode()
	var is_full = now in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if fullscreen != is_full:
		DisplayServer.window_set_mode(wanted)

func apply_sound():
	for channel in SOUND_CHANNELS:
		var bus = AudioServer.get_bus_index(channel)
		if bus < 0:
			continue
		var base = CHANNEL_SETUP.get(channel, 0.0)
		var share = volumes[channel]
		AudioServer.set_bus_volume_db(bus, base + linear_to_db(max(share, 0.0001)))
		if channel != "Music" or share <= 0.0:
			AudioServer.set_bus_mute(bus, share <= 0.0)
	# Ambience follows the Effects slider
	var ambience = AudioServer.get_bus_index("Ambience")
	if ambience >= 0:
		AudioServer.set_bus_volume_db(ambience, CHANNEL_SETUP["Ambience"] + linear_to_db(max(volumes["Effects"], 0.0001)))

func make_sound_channels():
	for channel in CHANNEL_SETUP:
		if AudioServer.get_bus_index(channel) >= 0:
			continue
		AudioServer.add_bus()
		var bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, channel)
		AudioServer.set_bus_send(bus, "Master")
		AudioServer.set_bus_volume_db(bus, CHANNEL_SETUP[channel])
		if channel in ["Effects", "Ambience"]:
			# Thin air muffles sound: the audio manager turns this filter down on Mars and off in space
			var filter = AudioEffectLowPassFilter.new()
			filter.cutoff_hz = 20000.0
			AudioServer.add_bus_effect(bus, filter)

func apply_graphics():
	var window = get_tree().root
	window.scaling_3d_scale = [0.6, 0.8, 1.0][quality]
	window.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][quality], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][quality])
	for node in get_tree().root.find_children("*", "", true, false):
		tune_node(node)

# Every light, environment and particle effect that joins the game gets the current quality
func _on_node_added(node):
	if node is WorldEnvironment or node is Light3D or node is GPUParticles3D or node is CPUParticles3D or node is SubViewport:
		tune_node.call_deferred(node)

func tune_node(node):
	if not is_instance_valid(node):
		return
	if node is WorldEnvironment and node.environment:
		var environment: Environment = node.environment
		if not node.has_meta("made_for_high"):
			# Remember what the scene asked for, so turning the quality back up brings it back
			node.set_meta("made_for_high", [environment.glow_enabled, environment.ssao_enabled, environment.ssr_enabled, environment.volumetric_fog_enabled, environment.sdfgi_enabled])
		var wanted = node.get_meta("made_for_high")
		environment.glow_enabled = wanted[0] and quality >= 1
		environment.ssao_enabled = wanted[1] and quality >= 2
		environment.ssr_enabled = wanted[2] and quality >= 2
		environment.volumetric_fog_enabled = wanted[3] and quality >= 2
		environment.sdfgi_enabled = wanted[4] and quality >= 2
	elif node is DirectionalLight3D:
		if not node.has_meta("made_with_shadow"):
			node.set_meta("made_with_shadow", node.shadow_enabled)
		node.shadow_enabled = node.get_meta("made_with_shadow") and shadows_on()
	elif node is Light3D:
		if not node.has_meta("made_with_shadow"):
			node.set_meta("made_with_shadow", node.shadow_enabled)
		node.shadow_enabled = node.get_meta("made_with_shadow") and quality >= 2
	elif node is GPUParticles3D:
		node.amount_ratio = particle_share()
	elif node is SubViewport:
		# (the main menu draws its launch scene in one of these)
		node.scaling_3d_scale = [0.6, 0.8, 1.0][quality]
		node.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]

# ---------------------------------------------------------------------------
# The first few seconds: is this computer keeping up?
# ---------------------------------------------------------------------------
func _process(delta):
	if quality_chosen_by_player or quality == 0 or speed_check_seconds < 0.0:
		return
	if Engine.get_process_frames() < 30:
		return   # (the first frames are always slow: things are still loading)
	speed_check_seconds += delta
	speed_check_frames += 1
	if speed_check_seconds >= SPEED_CHECK_SECONDS:
		var frames_per_second = speed_check_frames / speed_check_seconds
		if frames_per_second < SLOW_FRAMES_PER_SECOND:
			set_quality(quality - 1, false)
			notice = "This computer was running at %d frames a second, so graphics were turned down to %s. You can change it in Settings." % [int(frames_per_second), quality_name()]
			speed_check_seconds = 0.0
			speed_check_frames = 0
		else:
			speed_check_seconds = -1.0   # fast enough: stop checking
