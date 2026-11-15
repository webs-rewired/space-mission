extends Control

# The close-up of the rock (or ice) in the Signs of Life minigame (res://scenes/life_search.tscn). life_search.gd
# moves the scanner and says which instrument is mapping; this draws the surface, its features, the maps each
# instrument has made so far, and the scanner.
#
# The maps work like the real ones Perseverance makes with SHERLOC and PIXL: the surface is split into a grid, and
# each cell an instrument has scanned shows that instrument's false-color reading there (organic molecules glow
# green under the UV laser; the X-ray map shows elements in orange). The camera's map sharpens what it scans.

const GRID_WIDTH = 32
const GRID_HEIGHT = 18
const SCANNER_RADIUS = 0.055          # share of the width

var base_color = Color(0.5, 0.3, 0.22)
var speck_color = Color(0.65, 0.45, 0.32)
var features = []                     # the scenario's features (scripts/life_signs.gd)
var instrument_colors = {}            # instrument → color
var maps = {}                         # instrument → PackedFloat32Array of GRID_WIDTH × GRID_HEIGHT (1 = scanned)
var scanner = Vector2(0.5, 0.5)       # where the scanner is (0 to 1 across and down)
var instrument = "camera"
var scanning = false
var found_labels = {}                 # feature index → its letter, once found
var clock = 0.0
var specks = []                       # [place, size, shade] for the rock's grain

func _ready():
	var random = RandomNumberGenerator.new()
	random.seed = 2024
	for index in 420:
		specks.append([Vector2(random.randf(), random.randf()), random.randf_range(0.6, 2.4), random.randf_range(-1.0, 1.0)])

func set_up(scenario, colors):
	base_color = scenario["base"]
	speck_color = scenario["speck"]
	features = scenario["features"]
	instrument_colors = colors
	maps = {}
	for instrument_id in colors:
		var cells = PackedFloat32Array()
		cells.resize(GRID_WIDTH * GRID_HEIGHT)
		maps[instrument_id] = cells

func _process(delta):
	clock += delta
	if is_visible_in_tree():
		queue_redraw()

# The pixel place of a point given as shares of the view (0 to 1 across and down)
func to_pixels(share):
	return Vector2(share.x * size.x, share.y * size.y)

func cell_center(column, row):
	return Vector2((column + 0.5) / GRID_WIDTH, (row + 0.5) / GRID_HEIGHT)

# Marks the cells under the scanner as scanned by the current instrument
func scan_here():
	var radius_pixels = SCANNER_RADIUS * size.x
	var center = to_pixels(scanner)
	var cells = maps[instrument]
	for row in GRID_HEIGHT:
		for column in GRID_WIDTH:
			if to_pixels(cell_center(column, row)).distance_to(center) <= radius_pixels:
				cells[row * GRID_WIDTH + column] = 1.0
	maps[instrument] = cells

# How much of a feature an instrument has mapped (0 to 1)
func coverage(feature, instrument_id):
	var center = to_pixels(feature["place"])
	var radius_pixels = feature["size"] * size.x
	var inside = 0
	var scanned = 0
	var cells = maps[instrument_id]
	for row in GRID_HEIGHT:
		for column in GRID_WIDTH:
			if to_pixels(cell_center(column, row)).distance_to(center) <= max(radius_pixels, size.x / GRID_WIDTH * 0.75):
				inside += 1
				scanned += 1 if cells[row * GRID_WIDTH + column] > 0.0 else 0
	return float(scanned) / max(inside, 1)

# How strong an instrument's signal is at a point (features that instrument sees, fading out from their middles)
func signal_at(share, instrument_id):
	var total = 0.0
	for feature in features:
		if not feature["signals"].has(instrument_id):
			continue
		var distance = to_pixels(share).distance_to(to_pixels(feature["place"])) / (feature["size"] * size.x)
		total += exp(-distance * distance * 1.6)
	return clamp(total, 0.0, 1.0)

func _draw():
	# The surface: base color, shaded top to bottom, with grains
	draw_rect(Rect2(Vector2.ZERO, size), base_color)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)]),
		PackedColorArray([Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.03), Color(0, 0, 0, 0.18), Color(0, 0, 0, 0.22)]))
	for speck in specks:
		var shade = speck_color.lightened(speck[2] * 0.2) if speck[2] > 0.0 else base_color.darkened(-speck[2] * 0.35)
		draw_circle(to_pixels(speck[0]), speck[1], Color(shade, 0.7))
	# The features: faint until the camera maps them (and invisible to the eye if the camera can't see them)
	for index in features.size():
		var feature = features[index]
		var camera_seen = coverage(feature, "camera") if maps.has("camera") else 0.0
		var strength = 0.0
		if feature["signals"].has("camera"):
			strength = 0.3 + 0.7 * camera_seen
		elif feature["draw"] == "smear":
			strength = 0.12   # a brush or scoop mark is faintly visible
		if strength > 0.0:
			draw_feature(feature, strength)
	# The instruments' maps
	var cell_size = Vector2(size.x / GRID_WIDTH, size.y / GRID_HEIGHT)
	for instrument_id in ["organics", "chemistry"]:
		if not maps.has(instrument_id):
			continue
		var cells = maps[instrument_id]
		var color = instrument_colors[instrument_id]
		for row in GRID_HEIGHT:
			for column in GRID_WIDTH:
				if cells[row * GRID_WIDTH + column] <= 0.0:
					continue
				var strength = signal_at(cell_center(column, row), instrument_id)
				var cell = Rect2(Vector2(column, row) * cell_size, cell_size)
				draw_rect(cell, Color(0.0, 0.02, 0.05, 0.35))
				if strength > 0.05:
					draw_rect(cell, Color(color, 0.15 + 0.6 * strength))
				draw_rect(cell, Color(color, 0.12), false, 1.0)
	# Camera map: a faint grid where the camera has looked
	if maps.has("camera"):
		var cells = maps["camera"]
		for row in GRID_HEIGHT:
			for column in GRID_WIDTH:
				if cells[row * GRID_WIDTH + column] > 0.0:
					draw_rect(Rect2(Vector2(column, row) * cell_size, cell_size), Color(1, 1, 1, 0.05), false, 1.0)
	# Letters on the features found so far
	for index in found_labels:
		var place = to_pixels(features[index]["place"]) + Vector2(features[index]["size"] * size.x * 0.75, -features[index]["size"] * size.x * 0.75)
		draw_circle(place, 11.0, Color(0.02, 0.04, 0.08, 0.85))
		draw_arc(place, 11.0, 0.0, TAU, 24, Color(1.0, 0.86, 0.5), 1.5, true)
		draw_string(get_theme_default_font(), place + Vector2(-4, 5), found_labels[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.86, 0.5))
	# The scanner
	var color = instrument_colors.get(instrument, Color.WHITE)
	var center = to_pixels(scanner)
	var radius = SCANNER_RADIUS * size.x
	draw_arc(center, radius, 0.0, TAU, 48, Color(color, 0.9 if scanning else 0.6), 2.0, true)
	draw_line(center - Vector2(radius + 8, 0), center - Vector2(radius - 6, 0), color, 1.5)
	draw_line(center + Vector2(radius - 6, 0), center + Vector2(radius + 8, 0), color, 1.5)
	draw_line(center - Vector2(0, radius + 8), center - Vector2(0, radius - 6), color, 1.5)
	draw_line(center + Vector2(0, radius - 6), center + Vector2(0, radius + 8), color, 1.5)
	if scanning:
		var sweep = fmod(clock * 3.0, 1.0)
		draw_arc(center, radius * sweep, 0.0, TAU, 32, Color(color, 0.5 * (1.0 - sweep)), 2.0, true)
	# A scale bar, like on rover close-ups
	draw_line(Vector2(16, size.y - 16), Vector2(16 + size.x * 0.1, size.y - 16), Color(1, 1, 1, 0.7), 2.0)
	draw_string(get_theme_default_font(), Vector2(16, size.y - 22), "1 cm", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.7))

func draw_feature(feature, strength):
	var center = to_pixels(feature["place"])
	var radius = feature["size"] * size.x
	var random = RandomNumberGenerator.new()
	random.seed = int(feature["place"].x * 1000.0) * 31 + int(feature["place"].y * 1000.0)
	match feature["draw"]:
		"spots":
			for spot in 9:
				var place = center + Vector2(random.randf_range(-1.0, 1.0), random.randf_range(-0.7, 0.7)) * radius
				var spot_radius = random.randf_range(4.0, 9.0)
				draw_circle(place, spot_radius + 2.5, Color(0.08, 0.06, 0.06, 0.8 * strength))
				draw_circle(place, spot_radius, Color(0.92, 0.88, 0.78, 0.85 * strength))
		"vein":
			var vein = PackedVector2Array()
			for step in 12:
				var along = step / 11.0
				vein.append(center + Vector2(lerp(-radius * 1.6, radius * 1.6, along), lerp(radius * 0.8, -radius * 0.8, along) + sin(along * 13.0) * 5.0))
			draw_polyline(vein, Color(0.96, 0.95, 0.9, strength), 7.0, true)
		"layers":
			for layer in 7:
				var y = center.y - radius + layer * radius / 3.5
				draw_line(Vector2(center.x - radius * 1.5, y), Vector2(center.x + radius * 1.5, y + 3.0), Color(base_color.lightened(0.3), 0.7 * strength), 2.0, true)
		"grains":
			for grain in 26:
				var place = center + Vector2(random.randf_range(-1.0, 1.0), random.randf_range(-1.0, 1.0)) * radius
				draw_circle(place, random.randf_range(1.5, 3.5), Color(base_color.darkened(0.3), 0.8 * strength))
		"patch":
			for blob in 7:
				var place = center + Vector2(random.randf_range(-0.7, 0.7), random.randf_range(-0.5, 0.5)) * radius
				draw_circle(place, radius * random.randf_range(0.3, 0.6), Color(speck_color.lightened(0.25), 0.35 * strength))
		"haze":
			for ring in 4:
				draw_circle(center, radius * (1.0 - ring * 0.2), Color(base_color.lightened(0.15), 0.12 * strength))
		"smear":
			draw_line(center - Vector2(radius * 1.2, radius * 0.3), center + Vector2(radius * 1.2, radius * 0.3), Color(base_color.lightened(0.35), 0.8 * strength), radius * 0.5, true)
