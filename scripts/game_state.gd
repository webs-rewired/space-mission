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

# ---- Mission results ----
var events = []
var science_lost = 0
var lost = false
var data_share = 1.0
var score = 0
var outcome = ""

const REAL_MISSIONS = {
	"Moon": "NASA's Lunar Reconnaissance Orbiter has mapped the Moon since 2009, powered by solar panels.",
	"Mars": "NASA's Perseverance rover landed in 2021 using a heat shield and parachute, and runs on a nuclear power source (an RTG).",
	"Jupiter": "NASA's Juno reached Jupiter in 2016. It uses three huge solar arrays and keeps its electronics inside a titanium radiation vault.",
}

func add_event(title, text, ok, fatal = false):
	events.append({"title": title, "text": text, "ok": ok})
	if fatal:
		lost = true

func run_mission():
	events = []
	science_lost = 0
	lost = false
	var has_rtg = choices["power"] == "rtg"
	var big_battery = choices["battery"] == "battery_large"
	var shield = choices["shield"]

	# 1. Solar flare during the trip (50% chance)
	if randf() < 0.5:
		if shield != "shield_none":
			add_event("Solar flare!", "Your shield protected the electronics.", true)
		else:
			science_lost += 20
			add_event("Solar flare!", "With no shield, some instruments were damaged. Lost 20 science.", false)

	# 2. Arrival power check
	var made = power_made()
	var needed = power_needed()
	if made >= needed:
		add_event("Arrival", "Power check passed: %d W made, %d W needed." % [made, needed], true)
	else:
		add_event("Arrival", "Not enough power! %s gets %d%% of Earth's sunlight. Your probe made %d W but needed %d W." % [destination, int(round(sunlight_factor() * 100)), made, needed], false, true)

	# 3. Destination events
	if not lost:
		match destination:
			"Moon":
				if has_rtg or big_battery:
					add_event("Lunar night", "The Moon's night lasts about 14 Earth days. Your probe made it through.", true)
				else:
					science_lost += 30
					add_event("Lunar night", "The Moon's night lasts about 14 Earth days. Your small battery ran out. Lost 30 science.", false)
			"Mars":
				if shield == "shield_heat":
					add_event("Entry and landing", "Your heat shield survived the fiery trip through Mars's atmosphere.", true)
				else:
					add_event("Entry and landing", "Without a heat shield, the probe burned up in Mars's atmosphere.", false, true)
				if not lost:
					if has_rtg or big_battery:
						add_event("Dust storm", "A dust storm blocked the sunlight, but your probe kept running.", true)
					else:
						science_lost += 30
						add_event("Dust storm", "A dust storm cut solar power in half and your small battery couldn't cover it. Lost 30 science.", false)
			"Jupiter":
				if shield == "shield_radiation":
					add_event("Radiation belts", "Jupiter's radiation is intense, but your radiation vault protected the electronics.", true)
				else:
					add_event("Radiation belts", "Jupiter's radiation destroyed the unprotected electronics.", false, true)

	# 4. Score
	if choices["antenna"] == "antenna_large":
		data_share = 1.0
	else:
		data_share = DESTINATIONS[destination]["small_antenna_share"]

	if lost:
		score = 0
		outcome = "Mission lost"
	else:
		var unspent = budget() - total_cost()
		score = int(round(0.9 * (100 - science_lost) * data_share + min(10.0, unspent / 20.0)))
		outcome = "Mission success" if score >= 70 else "Partial success"
