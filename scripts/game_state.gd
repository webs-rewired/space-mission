extends Node

# All 100 flight events live in this file. Change the path if you saved it elsewhere.
const EventsData = preload("res://scripts/events_data.gd")

# ---------------------------------------------------------------------------
# What the player has picked
# ---------------------------------------------------------------------------
var destination: String = "Mars"   # default so the builder can be tested with F6
var rocket: String = "medium"
var choices = {
	"power": "solar_small",
	"battery": "battery_small",
	"antenna": "antenna_small",
	"engine": "engine_chemical",
	"fuel": "fuel_small",
	"shield": "shield_none",
	"landing": "landing_none",
	"computer": "computer_basic",
	"thermal": "thermal_heaters",
}
var instruments = ["inst_camera"]

# ---------------------------------------------------------------------------
# Game data (placeholder numbers until the official NASA resources on Friday)
# ---------------------------------------------------------------------------
const SLOT_ORDER = ["power", "battery", "antenna", "engine", "fuel", "shield", "landing", "computer", "thermal"]

const SLOT_NAMES = {
	"power": "Power source",
	"battery": "Battery",
	"antenna": "Antenna",
	"engine": "Engine",
	"fuel": "Fuel tank",
	"shield": "Shield",
	"landing": "Landing system",
	"computer": "Flight computer",
	"thermal": "Thermal control",
}

# Probe body (always included)
const BASE = {"mass": 250, "power_need": 50, "cost": 150}

const DESTINATIONS = {
	"Moon": {"au": 1.0, "budget": 500, "small_antenna_share": 1.0},
	"Mars": {"au": 1.52, "budget": 800, "small_antenna_share": 0.7},
	"Venus": {"au": 0.72, "budget": 700, "small_antenna_share": 0.8},
	"Jupiter": {"au": 5.2, "budget": 1000, "small_antenna_share": 0.4},
	"Saturn": {"au": 9.54, "budget": 1300, "small_antenna_share": 0.3},
}

const PARTS = {
	# Power
	"solar_small": {"slot": "power", "name": "Small solar panels", "mass": 30, "cost": 15, "power_at_earth": 300},
	"solar_large": {"slot": "power", "name": "Large solar panels", "mass": 90, "cost": 40, "power_at_earth": 900},
	"rtg": {"slot": "power", "name": "RTG nuclear power (like Perseverance)", "mass": 45, "cost": 120, "power_fixed": 110},
	"rtg_triple": {"slot": "power", "name": "Three RTGs (like Cassini)", "mass": 135, "cost": 300, "power_fixed": 330},
	# Battery
	"battery_small": {"slot": "battery", "name": "Small battery", "mass": 15, "cost": 5},
	"battery_large": {"slot": "battery", "name": "Large battery", "mass": 40, "cost": 15},
	# Antenna
	"antenna_small": {"slot": "antenna", "name": "Low-gain antenna", "mass": 10, "cost": 5, "power_use": 10},
	"antenna_large": {"slot": "antenna", "name": "High-gain dish", "mass": 35, "cost": 20, "power_use": 25},
	# Engine
	"engine_chemical": {"slot": "engine", "name": "Chemical engine (like Juno)", "mass": 60, "cost": 20},
	"engine_ion": {"slot": "engine", "name": "Ion thrusters (like Dawn)", "mass": 30, "cost": 45, "power_use": 60},
	# Fuel
	"fuel_small": {"slot": "fuel", "name": "Small fuel tank", "mass": 40, "cost": 5},
	"fuel_large": {"slot": "fuel", "name": "Large fuel tank", "mass": 120, "cost": 12},
	# Shield
	"shield_none": {"slot": "shield", "name": "No shield", "mass": 0, "cost": 0},
	"shield_heat": {"slot": "shield", "name": "Heat shield", "mass": 120, "cost": 30},
	"shield_radiation": {"slot": "shield", "name": "Radiation vault (like Juno)", "mass": 150, "cost": 40},
	"shield_venus": {"slot": "shield", "name": "Pressure hull (like the Venera landers)", "mass": 200, "cost": 50},
	# Landing
	"landing_none": {"slot": "landing", "name": "No lander (orbiter only)", "mass": 0, "cost": 0},
	"landing_legs": {"slot": "landing", "name": "Landing legs and thrusters", "mass": 80, "cost": 30},
	"landing_airbags": {"slot": "landing", "name": "Airbags (like Spirit and Opportunity)", "mass": 60, "cost": 20},
	"landing_skycrane": {"slot": "landing", "name": "Sky crane (like Perseverance)", "mass": 200, "cost": 90},
	# Computer
	"computer_basic": {"slot": "computer", "name": "Standard computer", "mass": 5, "cost": 5},
	"computer_rad": {"slot": "computer", "name": "Radiation-hardened computer", "mass": 10, "cost": 25},
	# Thermal
	"thermal_heaters": {"slot": "thermal", "name": "Heaters", "mass": 15, "cost": 5, "power_use": 20},
	"thermal_radiators": {"slot": "thermal", "name": "Radiators", "mass": 20, "cost": 8},
	"thermal_both": {"slot": "thermal", "name": "Heaters and radiators", "mass": 35, "cost": 13, "power_use": 20},
	# Science instruments (pick any number)
	"inst_camera": {"slot": "instrument", "name": "Camera", "mass": 15, "cost": 10, "power_use": 10},
	"inst_spectrometer": {"slot": "instrument", "name": "Spectrometer", "mass": 20, "cost": 20, "power_use": 15},
	"inst_radar": {"slot": "instrument", "name": "Radar", "mass": 40, "cost": 30, "power_use": 25},
	"inst_magnetometer": {"slot": "instrument", "name": "Magnetometer", "mass": 5, "cost": 8, "power_use": 5},
	"inst_drill": {"slot": "instrument", "name": "Drill (landers only)", "mass": 30, "cost": 25, "power_use": 20},
	"inst_seismometer": {"slot": "instrument", "name": "Seismometer (landers only)", "mass": 10, "cost": 15, "power_use": 5},
}

const ROCKETS = {
	"light": {"name": "Light", "cost": 60, "capacity": {"Moon": 900, "Mars": 600, "Venus": 700, "Jupiter": 0, "Saturn": 0}},
	"medium": {"name": "Medium", "cost": 150, "capacity": {"Moon": 2000, "Mars": 1300, "Venus": 1500, "Jupiter": 800, "Saturn": 500}},
	"heavy": {"name": "Heavy", "cost": 350, "capacity": {"Moon": 5000, "Mars": 3500, "Venus": 4000, "Jupiter": 2000, "Saturn": 1400}},
}

const REAL_MISSIONS = {
	"Moon": "NASA's Lunar Reconnaissance Orbiter has mapped the Moon since 2009, powered by solar panels. It has even photographed the Apollo landing sites.",
	"Mars": "NASA's Perseverance rover landed in 2021 using a heat shield, a parachute and a sky crane, and runs on a nuclear power source (an RTG).",
	"Venus": "NASA's Magellan mapped Venus with radar through its clouds in the 1990s. The Soviet Venera landers survived only an hour or two on the surface.",
	"Jupiter": "NASA's Juno reached Jupiter in 2016. It uses three huge solar arrays and keeps its electronics inside a titanium radiation vault.",
	"Saturn": "NASA's Cassini orbited Saturn from 2004 to 2017 on three RTGs, and dropped ESA's Huygens probe onto Titan in 2005.",
}

# ---------------------------------------------------------------------------
# Math
# ---------------------------------------------------------------------------
func all_part_ids():
	var ids = choices.values().duplicate()
	ids.append_array(instruments)
	return ids

func total_mass():
	var m = BASE["mass"]
	for id in all_part_ids():
		m += PARTS[id]["mass"]
	return m

func total_cost():
	var c = BASE["cost"] + ROCKETS[rocket]["cost"]
	for id in all_part_ids():
		c += PARTS[id]["cost"]
	return c

func sunlight_factor():
	var au = DESTINATIONS[destination]["au"]
	return 1.0 / (au * au)

func power_made():
	var p = PARTS[choices["power"]]
	if p.has("power_fixed"):
		return p["power_fixed"]
	return p["power_at_earth"] * sunlight_factor()

func power_needed():
	var need = BASE["power_need"]
	for id in all_part_ids():
		need += PARTS[id].get("power_use", 0)
	return need

func rocket_capacity():
	return ROCKETS[rocket]["capacity"][destination]

func budget():
	return DESTINATIONS[destination]["budget"]

# ---------------------------------------------------------------------------
# Requirements, written like "has:inst_drill", "not:landing_none",
# or several options joined with "|" (any one is enough)
# ---------------------------------------------------------------------------
func is_chosen(id):
	return id in choices.values() or id in instruments

func single_met(req):
	var p = req.split(":")
	if p[0] == "has":
		return is_chosen(p[1])
	if p[0] == "not":
		return not is_chosen(p[1])
	return false

func req_met(req):
	for alt in req.split("|"):
		if single_met(alt):
			return true
	return false

func meets_all(reqs):
	for r in reqs:
		if not req_met(r):
			return false
	return true

func req_names(req):
	var names = []
	for alt in req.split("|"):
		var id = alt.split(":")[1]
		if PARTS.has(id):
			names.append(PARTS[id]["name"])
	return " or ".join(names)

# ---------------------------------------------------------------------------
# Mission
# ---------------------------------------------------------------------------
const PHASE_RANK = {"cruise": 0, "arrival": 1, "orbit": 2, "site": 3, "descent": 4, "surface": 5}

var events = []        # everything planned for this flight
var mission_log = []   # what actually happened, for the Results screen
var science = 100
var lost = false
var lost_reason = ""
var bold_choices = 0
var data_share = 1.0
var score = 0
var outcome = ""
var ending = ""

func build_mission():
	events = []
	mission_log = []
	science = 50 + 10 * instruments.size()
	lost = false
	lost_reason = ""
	bold_choices = 0

	var cruise = []
	var world = []
	for e in EventsData.EVENTS:
		if not meets_all(e.get("when", [])):
			continue
		if e["world"] == "any":
			cruise.append(e)
		elif e["world"] == destination:
			if e.has("check"):
				events.append(e)      # gear checks always happen
			else:
				world.append(e)
	cruise.shuffle()
	world.shuffle()
	events.append_array(cruise.slice(0, 2))
	events.append_array(world.slice(0, randi_range(4, 6)))
	events.append({"title": "Arrival power check", "phase": "arrival", "power": true})
	events.sort_custom(func(a, b): return PHASE_RANK[a["phase"]] < PHASE_RANK[b["phase"]])

# Events with no choice: the power check and gear checks. Returns {"text", "ok"}.
func apply_event(e):
	var text = ""
	var ok = true
	if e.has("power"):
		var made = power_made()
		var needed = power_needed()
		if made >= needed:
			text = "Power check passed: %d W made, %d W needed." % [made, needed]
		else:
			ok = false
			lost = true
			lost_reason = "Your probe ran out of power. %s gets %d%% of Earth's sunlight, and your probe made %d W but needed %d W." % [destination, int(round(sunlight_factor() * 100)), made, needed]
			text = lost_reason
	else:
		if req_met(e["pass_if"]):
			text = e["pass"]
		else:
			ok = false
			text = e["fail"]
			science += e.get("fail_science", 0)
			if e.get("fatal", false):
				lost = true
				lost_reason = e["fail"]
	mission_log.append({"title": e["title"], "text": text, "ok": ok})
	return {"text": text, "ok": ok}

# Called when the player picks a choice. Returns {"text", "ok"}.
func resolve_choice(e, index):
	var c = e["choices"][index]
	var outs = c["outcomes"]
	var o = outs[outs.size() - 1]
	var helped = false
	if outs.size() > 1:
		bold_choices += 1
	if c.has("safe_if") and req_met(c["safe_if"]):
		o = outs[0]
		helped = outs.size() > 1
	else:
		var roll = randf()
		var acc = 0.0
		for x in outs:
			acc += x[0]
			if roll < acc:
				o = x
				break
	science += o[1]
	var text = o[2]
	if helped:
		text += " Your gear made this a safe bet."
	var ok = o[1] >= 0 and o.size() < 4
	if o.size() > 3:
		lost = true
		lost_reason = o[3]
	mission_log.append({"title": e["title"], "text": text, "ok": ok})
	return {"text": text, "ok": ok}

func finish_mission():
	if choices["antenna"] == "antenna_large":
		data_share = 1.0
	else:
		data_share = DESTINATIONS[destination]["small_antenna_share"]

	if lost:
		score = 0
		outcome = "Mission lost"
		ending = lost_reason
		return

	var unspent = budget() - total_cost()
	score = min(100, int(round(0.8 * max(science, 0) * data_share + min(10.0, unspent / 30.0))))
	if science >= 140 and bold_choices > 0:
		outcome = "Legendary discovery!"
		ending = "You took big risks and they paid off. Scientists will study your data for years."
	elif score >= 70:
		outcome = "Mission success"
		ending = "Your probe did its job. Solid engineering!"
	else:
		outcome = "Partial success"
		ending = "Your probe reached its goal, but lost a lot along the way."
