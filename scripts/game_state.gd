extends Node

# GameState remembers everything the player picks and does all the math.
# It's an Autoload, so every scene can use it (Project > Project Settings > Globals).

# All the flight events live in this file.
const EventsData = preload("res://scripts/events_data.gd")
# Rocket engines, tanks and boosters live in this file.
const RocketData = preload("res://scripts/rocket_data.gd")

# ---------------------------------------------------------------------------
# What the player has picked
# ---------------------------------------------------------------------------
var destination: String = "Mars"   # default so the builders can be tested on their own with F6

# How fast time runs in the solar system view: how many DAYS pass every real second.
# 0 = paused, negative = backwards. The solar system's Controls node sets it (real time to start).
var time_speed: float = 1.0 / 86400.0
var rocket = RocketData.STARTING_ROCKETS["falcon9"].duplicate()
var choices = {
	"power": "solar_small",
	"battery": "battery_small",
	"antenna": "antenna_small",
	"engine": "engine_chemical",
	"fuel": "fuel_small",
	"shield": "shield_none",
	"landing": "landing_none",
	"computer": "computer_standard",
	"thermal": "thermal_heaters",
}
var instruments = ["instrument_camera"]

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

# The probe's body, which is always included
const PROBE_BODY = {"mass": 250, "power_needed": 50, "cost": 150}

const DESTINATIONS = {
	"Moon": {"distance_from_sun_au": 1.0, "budget": 500, "small_antenna_data_share": 1.0},
	"Mars": {"distance_from_sun_au": 1.52, "budget": 800, "small_antenna_data_share": 0.7},
	"Venus": {"distance_from_sun_au": 0.72, "budget": 700, "small_antenna_data_share": 0.8},
	"Jupiter": {"distance_from_sun_au": 5.2, "budget": 1000, "small_antenna_data_share": 0.4},
	"Saturn": {"distance_from_sun_au": 9.54, "budget": 1600, "small_antenna_data_share": 0.3},
	# Moons: sunlight and radio distance are the same as for their planet
	"Phobos": {"distance_from_sun_au": 1.52, "budget": 800, "small_antenna_data_share": 0.7},
	"Deimos": {"distance_from_sun_au": 1.52, "budget": 750, "small_antenna_data_share": 0.7},
	"Io": {"distance_from_sun_au": 5.2, "budget": 1100, "small_antenna_data_share": 0.4},
	"Europa": {"distance_from_sun_au": 5.2, "budget": 1100, "small_antenna_data_share": 0.4},
	"Ganymede": {"distance_from_sun_au": 5.2, "budget": 1050, "small_antenna_data_share": 0.4},
	"Callisto": {"distance_from_sun_au": 5.2, "budget": 1000, "small_antenna_data_share": 0.4},
	"Enceladus": {"distance_from_sun_au": 9.54, "budget": 1600, "small_antenna_data_share": 0.3},
	"Titan": {"distance_from_sun_au": 9.54, "budget": 1700, "small_antenna_data_share": 0.3},
	"Titania": {"distance_from_sun_au": 19.2, "budget": 1900, "small_antenna_data_share": 0.2},
	"Triton": {"distance_from_sun_au": 30.1, "budget": 2000, "small_antenna_data_share": 0.15},
	"Charon": {"distance_from_sun_au": 39.5, "budget": 2000, "small_antenna_data_share": 0.12},
}

# Moons with no air: parachutes, airbags and sky cranes can't work there, so landers need legs and thrusters
const AIRLESS_MOONS = ["Moon", "Phobos", "Deimos", "Io", "Europa", "Ganymede", "Callisto", "Enceladus", "Titania", "Triton", "Charon"]

const PARTS = {
	# Power
	"solar_small": {"slot": "power", "name": "Small solar panels", "mass": 30, "cost": 15, "power_at_earth": 300},
	"solar_large": {"slot": "power", "name": "Large solar panels", "mass": 90, "cost": 40, "power_at_earth": 900},
	"rtg": {"slot": "power", "name": "RTG nuclear power (like Perseverance)", "mass": 45, "cost": 120, "power_anywhere": 110},
	"rtg_triple": {"slot": "power", "name": "Three RTGs (like Cassini)", "mass": 135, "cost": 300, "power_anywhere": 330},
	# Battery
	"battery_small": {"slot": "battery", "name": "Small battery", "mass": 15, "cost": 5},
	"battery_large": {"slot": "battery", "name": "Large battery", "mass": 40, "cost": 15},
	# Antenna
	"antenna_small": {"slot": "antenna", "name": "Low-gain antenna", "mass": 10, "cost": 5, "power_used": 10},
	"antenna_large": {"slot": "antenna", "name": "High-gain dish", "mass": 35, "cost": 20, "power_used": 25},
	# Engine
	"engine_chemical": {"slot": "engine", "name": "Chemical engine (like Juno)", "mass": 60, "cost": 20},
	"engine_ion": {"slot": "engine", "name": "Ion thrusters (like Dawn)", "mass": 30, "cost": 45, "power_used": 60},
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
	"computer_standard": {"slot": "computer", "name": "Standard computer", "mass": 5, "cost": 5},
	"computer_radiation_hardened": {"slot": "computer", "name": "Radiation-hardened computer", "mass": 10, "cost": 25},
	# Thermal
	"thermal_heaters": {"slot": "thermal", "name": "Heaters", "mass": 15, "cost": 5, "power_used": 20},
	"thermal_radiators": {"slot": "thermal", "name": "Radiators", "mass": 20, "cost": 8},
	"thermal_both": {"slot": "thermal", "name": "Heaters and radiators", "mass": 35, "cost": 13, "power_used": 20},
	# Science instruments (pick any number)
	"instrument_camera": {"slot": "instrument", "name": "Camera", "mass": 15, "cost": 10, "power_used": 10},
	"instrument_spectrometer": {"slot": "instrument", "name": "Spectrometer", "mass": 20, "cost": 20, "power_used": 15},
	"instrument_radar": {"slot": "instrument", "name": "Radar", "mass": 40, "cost": 30, "power_used": 25},
	"instrument_magnetometer": {"slot": "instrument", "name": "Magnetometer", "mass": 5, "cost": 8, "power_used": 5},
	"instrument_drill": {"slot": "instrument", "name": "Drill (landers only)", "mass": 30, "cost": 25, "power_used": 20},
	"instrument_seismometer": {"slot": "instrument", "name": "Seismometer (landers only)", "mass": 10, "cost": 15, "power_used": 5},
}

const REAL_MISSIONS = {
	"Moon": "NASA's Lunar Reconnaissance Orbiter has mapped the Moon since 2009, powered by solar panels. It has even photographed the Apollo landing sites.",
	"Mars": "NASA's Perseverance rover landed in 2021 using a heat shield, a parachute and a sky crane, and runs on a nuclear power source (an RTG).",
	"Venus": "NASA's Magellan mapped Venus with radar through its clouds in the 1990s. The Soviet Venera landers survived only an hour or two on the surface.",
	"Jupiter": "NASA's Juno reached Jupiter in 2016. It uses three huge solar arrays and keeps its electronics inside a titanium radiation vault.",
	"Saturn": "NASA's Cassini orbited Saturn from 2004 to 2017 on three RTGs, and dropped ESA's Huygens probe onto Titan in 2005.",
	"Phobos": "Japan's MMX mission is designed to land on Phobos, scoop up a sample and bring it back to Earth. ESA's Mars Express has flown past Phobos many times since 2003.",
	"Deimos": "NASA's Viking 2 orbiter flew within 30 km of Deimos in 1977. The UAE's Hope orbiter took close-up pictures of it in 2023.",
	"Io": "NASA's Galileo studied Io from 1995 to 2003, and Juno flew just 1,500 km above it in 2023 and 2024, photographing lava lakes. Both had to survive Jupiter's intense radiation.",
	"Europa": "NASA's Europa Clipper launched in 2024 and arrives in 2030. It keeps its electronics in a radiation vault and flies past Europa about 50 times instead of orbiting, to limit its radiation dose.",
	"Ganymede": "ESA's JUICE launched in 2023 and is set to orbit Ganymede in 2034, the first spacecraft to orbit another planet's moon. It runs on huge solar panels.",
	"Callisto": "NASA's Galileo flew past Callisto many times in the 1990s and found hints of a hidden ocean. It's far from Jupiter's worst radiation, so NASA has studied it as a future human base.",
	"Enceladus": "NASA's Cassini flew through Enceladus's plumes several times between 2005 and 2015, as low as 49 km above the surface, and found salty water, hydrogen and organic molecules.",
	"Titan": "ESA's Huygens probe parachuted onto Titan in 2005 behind a heat shield. NASA's Dragonfly, a nuclear-powered drone, is planned to launch in 2028 and fly between sites on Titan.",
	"Titania": "Only NASA's Voyager 2 has visited, flying past in January 1986, and it photographed less than half of Titania. A Uranus orbiter is NASA's top choice for its next big planetary mission.",
	"Triton": "NASA's Voyager 2 flew past Triton in August 1989 and saw nitrogen geysers on its frozen surface. It ran on RTGs, because sunlight there is about 1/900 of Earth's.",
	"Charon": "NASA's New Horizons flew past Pluto and Charon in July 2015 at 14 km/s. It ran on an RTG and launched on an Atlas V with a Star 48B kick stage, too fast to stop and orbit.",
}

# ---------------------------------------------------------------------------
# Probe math
# ---------------------------------------------------------------------------
func all_chosen_part_ids():
	var part_ids = choices.values().duplicate()
	part_ids.append_array(instruments)
	return part_ids

func total_mass():
	var mass = PROBE_BODY["mass"]
	for part_id in all_chosen_part_ids():
		mass += PARTS[part_id]["mass"]
	return mass

func probe_cost():
	var cost = PROBE_BODY["cost"]
	for part_id in all_chosen_part_ids():
		cost += PARTS[part_id]["cost"]
	return cost

func total_cost():
	return probe_cost() + rocket_cost()

# Sunlight gets weaker with the square of the distance from the Sun
func sunlight_factor():
	var distance = DESTINATIONS[destination]["distance_from_sun_au"]
	return 1.0 / (distance * distance)

func power_made():
	var power_part = PARTS[choices["power"]]
	if power_part.has("power_anywhere"):
		return power_part["power_anywhere"]
	return power_part["power_at_earth"] * sunlight_factor()

func power_needed():
	var power = PROBE_BODY["power_needed"]
	for part_id in all_chosen_part_ids():
		power += PARTS[part_id].get("power_used", 0)
	return power

func budget():
	return DESTINATIONS[destination]["budget"]

# ---------------------------------------------------------------------------
# Rocket math (the real rocket equation)
#   speed gained = Isp x gravity x ln(mass with fuel / mass without fuel)
# ---------------------------------------------------------------------------
func rocket_cost():
	var cost = RocketData.LAUNCH_OPERATIONS_COST
	cost += RocketData.ENGINES[rocket["bottom_engine"]]["cost"] * rocket["bottom_engine_count"]
	cost += RocketData.TANKS[rocket["bottom_tank"]]["cost"]
	var booster = RocketData.BOOSTERS[rocket["boosters"]]
	cost += booster.get("cost_each", 0) * booster["count"]
	cost += RocketData.ENGINES[rocket["top_engine"]]["cost"] * rocket["top_engine_count"]
	cost += RocketData.TANKS[rocket["top_tank"]]["cost"]
	cost += RocketData.KICK_STAGES[rocket["kick_stage"]].get("cost", 0)
	return cost

func speed_from_burn(isp, mass_before, mass_after):
	return isp * RocketData.GRAVITY * log(mass_before / mass_after)

# Works out everything about the current rocket. Returns a dictionary.
func rocket_report():
	var gravity = RocketData.GRAVITY
	var probe_mass = float(total_mass())
	var problems = []

	# Kick stage (on top, just under the probe)
	var kick = RocketData.KICK_STAGES[rocket["kick_stage"]]
	var kick_propellant = kick.get("propellant", 0)
	var kick_empty_mass = kick.get("empty_mass", 0)
	var kick_speed = 0.0
	if kick_propellant > 0:
		kick_speed = speed_from_burn(kick["isp"], probe_mass + kick_empty_mass + kick_propellant, probe_mass + kick_empty_mass)

	# Top stage
	var top_engine = RocketData.ENGINES[rocket["top_engine"]]
	var top_tank = RocketData.TANKS[rocket["top_tank"]]
	var top_engine_count = rocket["top_engine_count"]
	var mass_above_top_stage = probe_mass + kick_empty_mass + kick_propellant
	var top_stage_empty_mass = top_tank["empty_mass"] + top_engine["mass"] * top_engine_count
	var top_stage_full_mass = mass_above_top_stage + top_stage_empty_mass + top_tank["propellant"]
	var top_stage_speed = speed_from_burn(top_engine["isp_vacuum"], top_stage_full_mass, mass_above_top_stage + top_stage_empty_mass)
	var top_thrust_to_weight = top_engine["thrust_vacuum"] * 1000.0 * top_engine_count / (top_stage_full_mass * gravity)

	# Bottom stage and boosters
	var bottom_engine = RocketData.ENGINES[rocket["bottom_engine"]]
	var bottom_tank = RocketData.TANKS[rocket["bottom_tank"]]
	var bottom_engine_count = rocket["bottom_engine_count"]
	var booster = RocketData.BOOSTERS[rocket["boosters"]]
	var booster_count = booster["count"]
	var core_empty_mass = bottom_tank["empty_mass"] + bottom_engine["mass"] * bottom_engine_count
	var core_propellant = bottom_tank["propellant"]
	# Average Isp while climbing from the ground into space
	var core_isp = (bottom_engine["isp_sea_level"] + bottom_engine["isp_vacuum"]) / 2.0
	var core_thrust = bottom_engine["thrust_sea_level"] * bottom_engine_count
	var booster_propellant = booster.get("propellant_each", 0) * booster_count
	var booster_empty_mass = booster.get("empty_mass_each", 0) * booster_count
	var booster_thrust = booster.get("thrust_each", 0) * booster_count
	var liftoff_mass = top_stage_full_mass + core_empty_mass + core_propellant + booster_propellant + booster_empty_mass
	var liftoff_thrust_to_weight = (core_thrust + booster_thrust) * 1000.0 / (liftoff_mass * gravity)

	var bottom_stage_speed = 0.0
	if booster_count > 0:
		# Part 1: boosters and core burn together until the boosters are empty
		var booster_burn_time = booster["propellant_each"] / (booster["thrust_each"] * 1000.0 / (booster["isp"] * gravity))
		var core_fuel_per_second = core_thrust * 1000.0 / (core_isp * gravity)
		var core_fuel_used = min(core_propellant, core_fuel_per_second * booster_burn_time)
		var combined_isp = (core_isp * core_thrust + booster["isp"] * booster_thrust) / (core_thrust + booster_thrust)
		var mass_when_boosters_empty = liftoff_mass - booster_propellant - core_fuel_used
		bottom_stage_speed += speed_from_burn(combined_isp, liftoff_mass, mass_when_boosters_empty)
		# Part 2: the empty boosters drop off and the core keeps burning
		var mass_after_drop = mass_when_boosters_empty - booster_empty_mass
		bottom_stage_speed += speed_from_burn(core_isp, mass_after_drop, mass_after_drop - (core_propellant - core_fuel_used))
	else:
		bottom_stage_speed = speed_from_burn(core_isp, liftoff_mass, liftoff_mass - core_propellant)

	var total_speed = bottom_stage_speed + top_stage_speed + kick_speed
	var speed_needed = RocketData.SPEED_NEEDED[destination]

	if bottom_engine["fuel"] != bottom_tank["fuel"]:
		problems.append("Bottom stage fuel mismatch: this engine burns %s, the tank holds %s." % [bottom_engine["fuel"], bottom_tank["fuel"]])
	if top_engine["fuel"] != top_tank["fuel"]:
		problems.append("Top stage fuel mismatch: this engine burns %s, the tank holds %s." % [top_engine["fuel"], top_tank["fuel"]])
	if liftoff_thrust_to_weight < 1.2:
		problems.append("Too heavy to lift off. Add engines or boosters, or use a smaller tank.")
	if top_thrust_to_weight < 0.4:
		problems.append("The top stage is too weak to reach orbit. Add an engine or use a smaller tank.")

	return {
		"total_speed": total_speed,
		"speed_needed": speed_needed,
		"bottom_stage_speed": bottom_stage_speed,
		"top_stage_speed": top_stage_speed,
		"kick_speed": kick_speed,
		"liftoff_thrust_to_weight": liftoff_thrust_to_weight,
		"top_thrust_to_weight": top_thrust_to_weight,
		"liftoff_mass": liftoff_mass,
		"problems": problems,
		"fast_enough": total_speed >= speed_needed,
	}

func rocket_ready():
	var report = rocket_report()
	return report["problems"].is_empty() and report["fast_enough"] and total_cost() <= budget()

# ---------------------------------------------------------------------------
# Requirements, written like "has:instrument_drill" or "not:landing_none",
# or several options joined with "|" (any one of them is enough)
# ---------------------------------------------------------------------------
func is_chosen(part_id):
	return part_id in choices.values() or part_id in instruments

func single_requirement_met(requirement):
	var pieces = requirement.split(":")
	var rule = pieces[0]
	var part_id = pieces[1]
	if rule == "has":
		return is_chosen(part_id)
	if rule == "not":
		return not is_chosen(part_id)
	return false

func requirement_met(requirement):
	for option in requirement.split("|"):
		if single_requirement_met(option):
			return true
	return false

func all_requirements_met(requirements):
	for requirement in requirements:
		if not requirement_met(requirement):
			return false
	return true

func requirement_part_names(requirement):
	var names = []
	for option in requirement.split("|"):
		var part_id = option.split(":")[1]
		if PARTS.has(part_id):
			names.append(PARTS[part_id]["name"])
	return " or ".join(names)

# ---------------------------------------------------------------------------
# Mission
# ---------------------------------------------------------------------------
const PHASE_ORDER = {"cruise": 0, "arrival": 1, "orbit": 2, "site": 3, "descent": 4, "surface": 5}

var events = []        # everything planned for this flight
var mission_log = []   # what actually happened, for the Results screen
var science = 100
var lost = false
var lost_reason = ""
var risky_choices = 0
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
	risky_choices = 0

	var cruise_events = []
	var world_events = []
	for event in EventsData.EVENTS:
		if not all_requirements_met(event.get("when", [])):
			continue
		if event["world"] == "any":
			cruise_events.append(event)
		elif event["world"] == destination:
			if event.has("check"):
				events.append(event)      # gear checks always happen
			else:
				world_events.append(event)
	cruise_events.shuffle()
	world_events.shuffle()
	events.append_array(cruise_events.slice(0, 2))
	events.append_array(world_events.slice(0, randi_range(4, 6)))
	events.append({"title": "Arrival power check", "phase": "arrival", "power_check": true})
	events.sort_custom(func(first, second): return PHASE_ORDER[first["phase"]] < PHASE_ORDER[second["phase"]])

# Events with no choice: the power check and gear checks. Returns {"text", "ok"}.
func apply_event(event):
	var text = ""
	var ok = true
	if event.has("power_check"):
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
		if requirement_met(event["pass_if"]):
			text = event["pass"]
		else:
			ok = false
			text = event["fail"]
			science += event.get("fail_science", 0)
			if event.get("fatal", false):
				lost = true
				lost_reason = event["fail"]
	mission_log.append({"title": event["title"], "text": text, "ok": ok})
	return {"text": text, "ok": ok}

# Called when the player picks a choice. Returns {"text", "ok"}.
# Each outcome is [chance, science change, text] or [chance, science change, text, reason the mission was lost].
func resolve_choice(event, choice_index):
	var choice = event["choices"][choice_index]
	var outcomes = choice["outcomes"]
	var picked_outcome = outcomes[outcomes.size() - 1]
	var gear_helped = false
	if outcomes.size() > 1:
		risky_choices += 1
	if choice.has("safe_if") and requirement_met(choice["safe_if"]):
		picked_outcome = outcomes[0]
		gear_helped = outcomes.size() > 1
	else:
		var roll = randf()
		var chance_so_far = 0.0
		for possible_outcome in outcomes:
			chance_so_far += possible_outcome[0]
			if roll < chance_so_far:
				picked_outcome = possible_outcome
				break
	var science_change = picked_outcome[1]
	var text = picked_outcome[2]
	var mission_ends = picked_outcome.size() > 3
	science += science_change
	if gear_helped:
		text += " Your gear made this a safe bet."
	var ok = science_change >= 0 and not mission_ends
	if mission_ends:
		lost = true
		lost_reason = picked_outcome[3]
	mission_log.append({"title": event["title"], "text": text, "ok": ok})
	return {"text": text, "ok": ok}

func finish_mission():
	if choices["antenna"] == "antenna_large":
		data_share = 1.0
	else:
		data_share = DESTINATIONS[destination]["small_antenna_data_share"]

	if lost:
		score = 0
		outcome = "Mission lost"
		ending = lost_reason
		return

	var money_left = budget() - total_cost()
	score = min(100, int(round(0.8 * max(science, 0) * data_share + min(10.0, money_left / 30.0))))
	if science >= 140 and risky_choices > 0:
		outcome = "Legendary discovery!"
		ending = "You took big risks and they paid off. Scientists will study your data for years."
	elif score >= 70:
		outcome = "Mission success"
		ending = "Your probe did its job. Solid engineering!"
	else:
		outcome = "Partial success"
		ending = "Your probe reached its goal, but lost a lot along the way."
