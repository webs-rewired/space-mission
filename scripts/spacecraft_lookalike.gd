extends RefCounted

# The real NASA spacecraft a player's design is most like, and its 3D model (the files are anywhere in the project).
# The launch puts it inside the fairing, and the journey flies it to its destination.
# "size" is the real spacecraft's biggest measurement in meters.

const Spacecraft = preload("res://scripts/spacecraft.gd")

# "mission" is where it flew and when; "why" says what your design has in common with it (shown in the probe builder).
const LOOKALIKES = {
	"perseverance": {"file": "perseverance.glb", "size": 3.0, "name": "Perseverance", "mission": "(Mars, 2021)", "why": "it lands with a heat shield, a parachute and a sky crane."},
	"opportunity": {"file": "opportunity.glb", "size": 2.3, "name": "Opportunity", "mission": "(Mars, 2004)", "why": "it bounced to a stop on Mars inside a ball of airbags."},
	"viking_lander": {"file": "viking_lander.glb", "size": 3.0, "name": "Viking 1 lander", "mission": "(Mars, 1976)", "why": "it landed on legs with braking rockets and ran on nuclear power (RTGs)."},
	"insight": {"file": "insight.glb", "size": 6.0, "name": "InSight", "mission": "(Mars, 2018)", "why": "it landed on legs with braking thrusters and ran on solar panels."},
	"apollo_lunar_module": {"file": "apollo_lunar_module.glb", "size": 9.4, "name": "Apollo Lunar Module", "mission": "(the Moon, 1969-1972)", "why": "it landed on the Moon on four legs with one big braking engine."},
	"dawn": {"file": "dawn.glb", "size": 19.7, "name": "Dawn", "mission": "(Vesta and Ceres, 2011-2018)", "why": "it used ion engines and huge solar wings to orbit two different worlds."},
	"cassini_huygens": {"file": "cassini_huygens.glb", "size": 11.0, "name": "Cassini-Huygens", "mission": "(Saturn, 2004-2017)", "why": "it ran on three RTGs and carried the Huygens probe, which landed on Titan behind a heat shield."},
	"cassini": {"file": "cassini.glb", "size": 11.0, "name": "Cassini", "mission": "(Saturn, 2004-2017)", "why": "it ran on three RTGs with a 4 m high-gain dish."},
	"new_horizons": {"file": "new_horizons.glb", "size": 2.7, "name": "New Horizons", "mission": "(Pluto, 2015)", "why": "it ran on a single RTG and used its spare heat to stay warm."},
	"juno": {"file": "juno.glb", "size": 20.1, "name": "Juno", "mission": "(Jupiter, since 2016)", "why": "it runs on three giant solar wings and keeps its electronics in a titanium vault."},
	"messenger": {"file": "messenger.glb", "size": 6.1, "name": "MESSENGER", "mission": "(Mercury, 2011-2015)", "why": "it hid behind a ceramic sunshade to survive near the Sun."},
	"magellan": {"file": "magellan.glb", "size": 9.0, "name": "Magellan", "mission": "(Venus, 1990-1994)", "why": "it mapped Venus with radar through the clouds."},
	"mars_reconnaissance_orbiter": {"file": "mars_reconnaissance_orbiter.glb", "size": 13.6, "name": "Mars Reconnaissance Orbiter", "mission": "(Mars, since 2006)", "why": "it's a solar-powered orbiter with a big 3 m dish for sending lots of pictures."},
	# More NASA spacecraft (NASA 3D Resources)
	"lunar_reconnaissance_orbiter": {"file": "lunar_reconnaissance_orbiter.glb", "size": 5.0, "name": "Lunar Reconnaissance Orbiter", "mission": "(the Moon, since 2009)", "why": "it orbits the Moon on solar power, mapping it from 50 km up. It even photographed the Apollo landing sites."},
	"mars_odyssey": {"file": "mars_odyssey.glb", "size": 7.5, "name": "2001 Mars Odyssey", "mission": "(Mars, since 2001)", "why": "it maps Mars with spectrometers (its gamma-ray spectrometer found water ice just under the ground), and it's the longest-working Mars spacecraft."},
	"galileo": {"file": "galileo.glb", "size": 11.0, "name": "Galileo", "mission": "(Jupiter, 1995-2003)", "why": "it orbited Jupiter on nuclear power (RTGs) for 8 years and dropped a probe into its clouds."},
	"pioneer_10": {"file": "pioneer_10.glb", "size": 8.2, "name": "Pioneer 10", "mission": "(Jupiter flyby, 1973)", "why": "it was a simple RTG-powered probe, the first to cross the asteroid belt and fly past Jupiter."},
	"voyager": {"file": "voyager.glb", "size": 13.0, "name": "Voyager 2", "mission": "(Uranus 1986, Neptune 1989)", "why": "it ran on RTGs and is the only spacecraft ever to visit Uranus and Neptune. It's still sending data from interstellar space."},
	"near_shoemaker": {"file": "near_shoemaker.glb", "size": 4.4, "name": "NEAR Shoemaker", "mission": "(asteroid Eros, 2000-2001)", "why": "it orbited a small rocky world on solar power, then landed on it, though it was never built to land."},
	"osiris_rex": {"file": "osiris_rex.glb", "size": 6.2, "name": "OSIRIS-REx", "mission": "(asteroid Bennu, 2018-2023)", "why": "it mapped a small world with spectrometers, grabbed a sample of its surface and brought it to Earth."},
	"rosetta": {"file": "rosetta.glb", "size": 32.0, "name": "Rosetta", "mission": "(comet 67P, 2014-2016)", "why": "its 32 m solar wings powered it far from the Sun, out to a comet, where it dropped the Philae lander."},
	"stardust": {"file": "stardust.glb", "size": 4.8, "name": "Stardust", "mission": "(comet Wild 2, 2004)", "why": "it flew through a comet's spray of dust and brought samples home, like a probe flying through Enceladus's plumes."},
	"ingenuity": {"file": "ingenuity.glb", "size": 1.2, "name": "Ingenuity", "mission": "(Mars, 2021-2024)", "why": "it was the first aircraft to fly on another world."},
}

const JUPITER_SYSTEM = ["Jupiter", "Io", "Europa", "Ganymede", "Callisto"]
const SATURN_SYSTEM = ["Saturn", "Titan", "Enceladus"]
const ICE_GIANT_SYSTEMS = ["Uranus", "Neptune", "Titania", "Triton"]
const KUIPER_BELT = ["Pluto", "Charon", "Haumea", "Makemake", "Eris"]

# The same choices the probe builder shows as "closest real spacecraft": landers by how they land, orbiters by their
# power, engine, instruments and where they're going (the real spacecraft that went there, or went somewhere like it)
static func closest():
	var choices = GameState.choices
	var destination = GameState.destination
	var instruments = GameState.instruments
	var power = choices["power"]
	if choices["landing"] == "landing_skycrane":
		return "perseverance"
	if choices["landing"] == "landing_airbags":
		return "opportunity"
	if choices["landing"] == "landing_legs":
		if destination == "Moon":
			return "apollo_lunar_module"
		return "viking_lander" if power in ["rtg", "rtg_triple"] else "insight"
	if choices["engine"] == "engine_ion":
		return "dawn"
	if power == "rtg_triple":
		return "cassini_huygens" if choices["shield"] == "shield_heat" else "cassini"
	if destination in JUPITER_SYSTEM:
		if power in ["solar_small", "solar_large"]:
			return "juno"
		if power == "rtg" and choices.get("battery", "") == "battery_small" and instruments.size() <= 1:
			return "pioneer_10"   # a simple probe, like Pioneer 10
		return "galileo"
	if destination in ICE_GIANT_SYSTEMS and power == "rtg":
		return "voyager"
	if destination in KUIPER_BELT and power == "rtg":
		return "new_horizons"
	if destination in SATURN_SYSTEM:
		return "cassini" if power == "rtg" else ("stardust" if destination == "Enceladus" else "cassini")
	match destination:
		"Mercury":
			return "messenger"
		"Venus":
			return "magellan"
		"Moon":
			return "lunar_reconnaissance_orbiter"
		"Mars":
			if "instrument_spectrometer" in instruments and not "instrument_camera" in instruments:
				return "mars_odyssey"
			return "mars_reconnaissance_orbiter"
		"Phobos", "Deimos":
			return "osiris_rex" if "instrument_spectrometer" in instruments else "near_shoemaker"
		"Ceres":
			return "rosetta" if power == "solar_large" else "near_shoemaker"
	if power == "rtg":
		return "new_horizons"
	if power == "solar_large":
		return "rosetta"
	if choices["thermal"] == "thermal_radiators":
		return "messenger"
	if "instrument_radar" in instruments:
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
	var middle = Spacecraft.body_center(model)   # the body, not the middle of the box (see Spacecraft.body_center)
	model.scale = model.scale * shrink
	model.position = -Vector3(middle.x, box.position.y, middle.z) * shrink
	var holder = Node3D.new()
	holder.add_child(model)
	return holder
