extends Node

# What the player has picked
var destination: String = "Mars"
var rocket: String = "medium"
var choices = {
	"power": "solar_small",
	"battery": "battery_small",
	"antenna": "antenna_small",
	"shield": "shield_none",
}

# ---- Game data (placeholder numbers until NASA resources on Friday) ----
const BASE = {"mass": 250, "power_need": 80, "cost": 150}

const DESTINATIONS = {
	"Moon": {"au": 1.0, "budget": 400, "small_antenna_share": 1.0},
	"Mars": {"au": 1.52, "budget": 600, "small_antenna_share": 0.7},
	"Jupiter": {"au": 5.2, "budget": 900, "small_antenna_share": 0.4},
}

const PARTS = {
	"solar_small": {"slot": "power", "name": "Small solar panels", "mass": 30, "cost": 15, "power_at_earth": 300},
	"solar_large": {"slot": "power", "name": "Large solar panels", "mass": 90, "cost": 40, "power_at_earth": 900},
	"rtg": {"slot": "power", "name": "RTG (nuclear battery)", "mass": 45, "cost": 120, "power_fixed": 110},
	"battery_small": {"slot": "battery", "name": "Small battery", "mass": 15, "cost": 5},
	"battery_large": {"slot": "battery", "name": "Large battery", "mass": 40, "cost": 15},
	"antenna_small": {"slot": "antenna", "name": "Small antenna", "mass": 10, "cost": 5, "power_use": 10},
	"antenna_large": {"slot": "antenna", "name": "Large antenna", "mass": 35, "cost": 20, "power_use": 25},
	"shield_none": {"slot": "shield", "name": "No shield", "mass": 0, "cost": 0},
	"shield_heat": {"slot": "shield", "name": "Heat shield", "mass": 120, "cost": 30},
	"shield_radiation": {"slot": "shield", "name": "Radiation vault", "mass": 150, "cost": 40},
}

const ROCKETS = {
	"light": {"name": "Light", "cost": 60, "capacity": {"Moon": 600, "Mars": 350, "Jupiter": 0}},
	"medium": {"name": "Medium", "cost": 150, "capacity": {"Moon": 1500, "Mars": 900, "Jupiter": 400}},
	"heavy": {"name": "Heavy", "cost": 350, "capacity": {"Moon": 4000, "Mars": 2500, "Jupiter": 1200}},
}

# ---- Math ----
func total_mass():
	var m = BASE["mass"]
	for slot in choices:
		m += PARTS[choices[slot]]["mass"]
	return m

func total_cost():
	var c = BASE["cost"] + ROCKETS[rocket]["cost"]
	for slot in choices:
		c += PARTS[choices[slot]]["cost"]
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
	return BASE["power_need"] + PARTS[choices["antenna"]]["power_use"]

func rocket_capacity():
	return ROCKETS[rocket]["capacity"][destination]

func budget():
	return DESTINATIONS[destination]["budget"]

# ---- Mission ----
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

const REAL_MISSIONS = {
	"Moon": "NASA's Lunar Reconnaissance Orbiter has mapped the Moon since 2009, powered by solar panels.",
	"Mars": "NASA's Perseverance rover landed in 2021 using a heat shield and parachute, and runs on a nuclear power source (an RTG).",
	"Jupiter": "NASA's Juno reached Jupiter in 2016. It uses three huge solar arrays and keeps its electronics inside a titanium radiation vault.",
}

func ev(title, text, ok, science_change = 0, fatal = false, reason = ""):
	return {"title": title, "text": text, "ok": ok, "science": science_change, "fatal": fatal, "reason": reason, "choices": [], "kind": ""}

func choice_ev(kind, title, text, choices):
	var e = ev(title, text, true)
	e["kind"] = kind
	e["choices"] = choices
	return e

func build_mission():
	events = []
	mission_log = []
	science = 100
	lost = false
	lost_reason = ""
	bold_choices = 0
	var has_rtg = choices["power"] == "rtg"
	var big_battery = choices["battery"] == "battery_large"
	var shield = choices["shield"]

	# 1. Solar flare (50% chance)
	if randf() < 0.5:
		if shield != "shield_none":
			events.append(ev("Solar flare!", "Your shield protected the electronics.", true))
		else:
			events.append(choice_ev("flare", "Solar flare!", "A burst of radiation is coming and you have no shield. What do you do?",
				["Power down and wait it out (safe, lose 10 science)", "Keep the instruments running (risky)"]))

	# 2. Course correction (every mission)
	events.append(choice_ev("course", "Course correction", "You're slightly off course. Fire the engine now, or save fuel and correct later?",
		["Fire the engine now (safe)", "Wait and save fuel for extra science (risky)"]))

	# 3. Arrival power check
	var made = power_made()
	var needed = power_needed()
	if made >= needed:
		events.append(ev("Arrival", "Power check passed: %d W made, %d W needed." % [made, needed], true))
	else:
		events.append(ev("Arrival", "Not enough power! %s gets %d%% of Earth's sunlight. Your probe made %d W but needed %d W." % [destination, int(round(sunlight_factor() * 100)), made, needed], false, 0, true, "Your probe ran out of power."))

	# 4. Destination events
	match destination:
		"Moon":
			if has_rtg or big_battery:
				events.append(ev("Lunar night", "The Moon's night lasts about 14 Earth days. Your probe made it through.", true))
			else:
				events.append(ev("Lunar night", "The Moon's night lasts about 14 Earth days. Your small battery ran out. Lost 30 science.", false, -30))
			events.append(choice_ev("moon_target", "Choose a target", "Where should your probe focus its search?",
				["Map the sunny equator (safe)", "Search the dark south pole for water ice (risky, big discovery)"]))
		"Mars":
			events.append(choice_ev("mars_site", "Pick a landing site", "Where should your probe land?",
				["A flat, safe plain (safe)", "An ancient river delta (risky, big discovery)"]))
			if shield == "shield_heat":
				events.append(ev("Entry and landing", "Your heat shield survived the fiery trip through Mars's atmosphere.", true))
			else:
				events.append(ev("Entry and landing", "Without a heat shield, the probe burned up in Mars's atmosphere.", false, 0, true, "Your probe burned up entering Mars's atmosphere."))
			if has_rtg or big_battery:
				events.append(ev("Dust storm", "A dust storm blocked the sunlight, but your probe kept running.", true))
			else:
				events.append(ev("Dust storm", "A dust storm cut solar power in half and your small battery couldn't cover it. Lost 30 science.", false, -30))
		"Jupiter":
			if shield == "shield_radiation":
				events.append(ev("Radiation belts", "Jupiter's radiation is intense, but your radiation vault protected the electronics.", true))
			else:
				events.append(ev("Radiation belts", "Jupiter's radiation destroyed the unprotected electronics.", false, 0, true, "Jupiter's radiation destroyed your probe."))
			events.append(choice_ev("europa", "Europa flyby?", "Jupiter's moon Europa may hide an ocean under its ice. Fly close?",
				["Stay in a safe orbit (safe)", "Fly close to Europa (risky, big discovery)"]))

# Called for events with no choice
func apply_event(e):
	science += e["science"]
	if e["fatal"]:
		lost = true
		lost_reason = e["reason"]
	mission_log.append({"title": e["title"], "text": e["text"], "ok": e["ok"]})

# Called when the player picks a choice. Returns {"text", "ok"}.
func resolve_choice(e, index):
	var text = ""
	var ok = true
	match e["kind"]:
		"flare":
			if index == 0:
				science -= 10
				text = "You powered down and waited. Lost 10 science, but everything survived."
			else:
				bold_choices += 1
				if randf() < 0.5:
					science -= 30
					ok = false
					text = "The flare fried two instruments. Lost 30 science."
				else:
					text = "Lucky! The instruments survived the flare."
		"course":
			if index == 0:
				text = "Clean burn. You're right on target."
			else:
				bold_choices += 1
				if randf() < 0.25:
					ok = false
					lost = true
					lost_reason = "You waited too long to correct course and missed the planet."
					text = lost_reason
				else:
					science += 10
					text = "The gamble paid off! The saved fuel gives you extra time for science. +10 science."
		"moon_target":
			if index == 0:
				text = "You mapped the equator in detail. Solid, safe science."
			else:
				bold_choices += 1
				if randf() < 0.3:
					science -= 20
					ok = false
					text = "The crater was too cold and dark. Your probe lost power for weeks. Lost 20 science."
				else:
					science += 20
					text = "You found signs of water ice in the dark craters! +20 science."
		"mars_site":
			if index == 0:
				text = "You chose the safe plain. A smooth landing spot."
			else:
				bold_choices += 1
				if randf() < 0.25:
					ok = false
					lost = true
					lost_reason = "Your probe crashed into the rocky river delta."
					text = lost_reason
				else:
					science += 20
					text = "The delta is full of layered rocks from ancient water! +20 science."
		"europa":
			if index == 0:
				text = "You stayed in a safe orbit around Jupiter."
			else:
				bold_choices += 1
				if randf() < 0.3:
					science -= 30
					ok = false
					text = "Radiation near Europa damaged your instruments. Lost 30 science."
				else:
					science += 25
					text = "You spotted water plumes shooting out of Europa's ice! +25 science."
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
	score = min(100, int(round(0.9 * max(science, 0) * data_share + min(10.0, unspent / 20.0))))
	if score >= 95 and bold_choices > 0:
		outcome = "Legendary discovery!"
		ending = "You took big risks and they paid off. Scientists will study your data for years."
	elif score >= 70:
		outcome = "Mission success"
		ending = "Your probe did its job. Solid engineering!"
	else:
		outcome = "Partial success"
		ending = "Your probe reached its goal, but lost a lot along the way."
