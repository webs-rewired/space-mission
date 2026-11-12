extends RefCounted

# The real NASA spacecraft a player's design is most like, and its 3D model (the files are anywhere in the project).
# The launch puts it inside the fairing, and the journey flies it to its destination.
# "size" is the real spacecraft's biggest measurement in meters.

const Spacecraft = preload("res://scripts/spacecraft.gd")

const LOOKALIKES = {
	"perseverance": {"file": "perseverance.glb", "size": 3.0, "name": "Perseverance"},
	"opportunity": {"file": "opportunity.glb", "size": 2.3, "name": "Opportunity"},
	"viking_lander": {"file": "viking_lander.glb", "size": 3.0, "name": "Viking 1 lander"},
	"insight": {"file": "insight.glb", "size": 6.0, "name": "InSight"},
	"apollo_lunar_module": {"file": "apollo_lunar_module.glb", "size": 9.4, "name": "Apollo Lunar Module"},
	"dawn": {"file": "dawn.glb", "size": 19.7, "name": "Dawn"},
	"cassini_huygens": {"file": "cassini_huygens.glb", "size": 11.0, "name": "Cassini-Huygens"},
	"cassini": {"file": "cassini.glb", "size": 11.0, "name": "Cassini"},
	"new_horizons": {"file": "new_horizons.glb", "size": 2.7, "name": "New Horizons"},
	"juno": {"file": "juno.glb", "size": 20.1, "name": "Juno"},
	"messenger": {"file": "messenger.glb", "size": 6.1, "name": "MESSENGER"},
	"magellan": {"file": "magellan.glb", "size": 9.0, "name": "Magellan"},
	"mars_reconnaissance_orbiter": {"file": "mars_reconnaissance_orbiter.glb", "size": 13.6, "name": "Mars Reconnaissance Orbiter"},
}

# Same choices as the probe builder's "closest real spacecraft"
static func closest():
	var choices = GameState.choices
	if choices["landing"] == "landing_skycrane":
		return "perseverance"
	if choices["landing"] == "landing_airbags":
		return "opportunity"
	if choices["landing"] == "landing_legs":
		if GameState.destination == "Moon":
			return "apollo_lunar_module"
		return "viking_lander" if choices["power"] in ["rtg", "rtg_triple"] else "insight"
	if choices["engine"] == "engine_ion":
		return "dawn"
	if choices["power"] == "rtg_triple":
		return "cassini_huygens" if choices["shield"] == "shield_heat" else "cassini"
	if choices["power"] == "rtg":
		return "new_horizons"
	if choices["power"] == "solar_large":
		return "juno"
	if choices["thermal"] == "thermal_radiators":
		return "messenger"
	if "instrument_radar" in GameState.instruments:
		return "magellan"
	return "mars_reconnaissance_orbiter"

# The spacecraft that cruises through space. Landers fly folded inside their cruise shell, so a lander mission
# shows the orbiter that best matches the power choice until it's time to land.
static func cruise_model_id():
	var lookalike = closest()
	if lookalike in ["perseverance", "opportunity", "viking_lander", "insight", "apollo_lunar_module"]:
		return ""
	return lookalike

# Loads a spacecraft model, centered with its bottom at y = 0, with its biggest side "size" long. Null if missing.
static func load_model(lookalike_id, size):
	if not LOOKALIKES.has(lookalike_id):
		return null
	var path = Spacecraft.find_model(LOOKALIKES[lookalike_id]["file"])
	if path == "":
		return null
	var scene = load(path)
	if not scene is PackedScene:
		return null
	var model = scene.instantiate()
	var box = Spacecraft.model_bounds(model, Transform3D.IDENTITY, null)
	if box == null:
		model.free()
		return null
	var shrink = size / max(box.size.x, max(box.size.y, box.size.z), 0.001)
	model.scale = model.scale * shrink
	model.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * shrink
	var holder = Node3D.new()
	holder.add_child(model)
	return holder
