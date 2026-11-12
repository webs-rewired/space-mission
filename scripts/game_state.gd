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
# The date the mission launches (a Julian date), taken from the solar system's clock when you press
# "Send a mission". 0 means "today". The planets' real positions on that date decide what you fly past.
var launch_date: float = 0.0

# ---------------------------------------------------------------------------
# Game data: real spacecraft parts and numbers (see each part's "like" for the real mission it comes from)
# ---------------------------------------------------------------------------
const SLOT_ORDER = ["power", "battery", "antenna", "engine", "fuel", "shield", "landing", "computer", "thermal"]

const SLOT_NAMES = {
	"power": "Power source",
	"battery": "Battery",
	"antenna": "Antenna",
	"engine": "Engine",
	"fuel": "Propellant tank",
	"shield": "Protection",
	"landing": "Landing system",
	"computer": "Flight computer",
	"thermal": "Temperature control",
}

# The probe's body (the "bus"): frame, wiring, guidance and small steering thrusters. Always included.
const PROBE_BODY = {"mass": 250, "power_needed": 100, "cost": 150}

# Data from far away: a 3 m high-gain dish talking to NASA's Deep Space Network sends about 2,940 kilobits per
# second at 1 AU (Mars Reconnaissance Orbiter: up to 6 megabits per second at 0.7 AU), and the rate falls with
# the square of the distance (New Horizons managed about 1 to 2 kilobits per second from Pluto).
const HIGH_GAIN_KILOBITS_AT_1_AU = 2940.0
const PHOTO_MEGABITS = 16.0            # one compressed high-resolution photo, about 2 megabytes
const CONTACT_HOURS_PER_DAY = 8.0      # one Deep Space Network pass a day
const LIGHT_MINUTES_PER_AU = 8.3167
const ION_ENGINE_MINIMUM_WATTS = 500.0 # Dawn's ion engines could throttle down to about 500 W, but no lower
const CHEMICAL_THRUST_NEWTONS = 645.0  # Juno's Leros-1b
const ION_THRUST_NEWTONS = 0.092       # one of Dawn's NSTAR engines at full power

# For each destination: average distance from the Sun, budget ($ millions), the share of data a low-gain
# antenna gets home, how long the trip takes (from real missions: Juno took 5 years, Cassini 6.7,
# New Horizons 9.5) and how much the probe's own engine must slow it down to stay there
# ("arrival_burn_km_s", from real missions: Juno 0.54 at Jupiter, Cassini 0.63 at Saturn, Mars Reconnaissance
# Orbiter 1.0 at Mars; for worlds no one has orbited yet, from NASA mission studies).
const DESTINATIONS = {
	"Moon": {"distance_from_sun_au": 1.0, "budget": 500, "small_antenna_data_share": 1.0, "trip_years": 0.012, "arrival_burn_km_s": 0.85},
	"Mars": {"distance_from_sun_au": 1.52, "budget": 800, "small_antenna_data_share": 0.7, "trip_years": 0.6, "arrival_burn_km_s": 1.0},
	"Venus": {"distance_from_sun_au": 0.72, "budget": 700, "small_antenna_data_share": 0.8, "trip_years": 0.4, "arrival_burn_km_s": 1.25},
	"Jupiter": {"distance_from_sun_au": 5.2, "budget": 1000, "small_antenna_data_share": 0.4, "trip_years": 5.0, "arrival_burn_km_s": 0.55},
	"Saturn": {"distance_from_sun_au": 9.54, "budget": 1600, "small_antenna_data_share": 0.3, "trip_years": 6.7, "arrival_burn_km_s": 0.63},
	# Moons: sunlight and radio distance are the same as for their planet
	"Phobos": {"distance_from_sun_au": 1.52, "budget": 800, "small_antenna_data_share": 0.7, "trip_years": 1.0, "arrival_burn_km_s": 1.4},
	"Deimos": {"distance_from_sun_au": 1.52, "budget": 750, "small_antenna_data_share": 0.7, "trip_years": 1.0, "arrival_burn_km_s": 1.3},
	"Io": {"distance_from_sun_au": 5.2, "budget": 1100, "small_antenna_data_share": 0.4, "trip_years": 6.0, "arrival_burn_km_s": 1.6},
	"Europa": {"distance_from_sun_au": 5.2, "budget": 1100, "small_antenna_data_share": 0.4, "trip_years": 6.0, "arrival_burn_km_s": 1.8},
	"Ganymede": {"distance_from_sun_au": 5.2, "budget": 1050, "small_antenna_data_share": 0.4, "trip_years": 7.5, "arrival_burn_km_s": 2.0},
	"Callisto": {"distance_from_sun_au": 5.2, "budget": 1000, "small_antenna_data_share": 0.4, "trip_years": 6.0, "arrival_burn_km_s": 1.6},
	"Enceladus": {"distance_from_sun_au": 9.54, "budget": 1600, "small_antenna_data_share": 0.3, "trip_years": 7.0, "arrival_burn_km_s": 3.0},
	"Titan": {"distance_from_sun_au": 9.54, "budget": 1700, "small_antenna_data_share": 0.3, "trip_years": 7.0, "arrival_burn_km_s": 0.65},
	"Titania": {"distance_from_sun_au": 19.2, "budget": 1900, "small_antenna_data_share": 0.2, "trip_years": 12.0, "arrival_burn_km_s": 2.6},
	"Triton": {"distance_from_sun_au": 30.1, "budget": 2000, "small_antenna_data_share": 0.15, "trip_years": 14.0, "arrival_burn_km_s": 3.2},
	"Charon": {"distance_from_sun_au": 39.5, "budget": 2000, "small_antenna_data_share": 0.12, "trip_years": 10.0, "arrival_burn_km_s": 4.6},
	# More planets and the dwarf planets (distances are their average distance from the Sun)
	"Mercury": {"distance_from_sun_au": 0.39, "budget": 900, "small_antenna_data_share": 0.8, "trip_years": 6.6, "arrival_burn_km_s": 2.3},
	"Uranus": {"distance_from_sun_au": 19.2, "budget": 1900, "small_antenna_data_share": 0.2, "trip_years": 12.0, "arrival_burn_km_s": 2.0},
	"Neptune": {"distance_from_sun_au": 30.1, "budget": 2000, "small_antenna_data_share": 0.15, "trip_years": 14.0, "arrival_burn_km_s": 2.5},
	"Ceres": {"distance_from_sun_au": 2.77, "budget": 900, "small_antenna_data_share": 0.5, "trip_years": 4.0, "arrival_burn_km_s": 4.5},
	"Pluto": {"distance_from_sun_au": 39.5, "budget": 2000, "small_antenna_data_share": 0.12, "trip_years": 10.0, "arrival_burn_km_s": 4.5},
	"Haumea": {"distance_from_sun_au": 43.1, "budget": 2100, "small_antenna_data_share": 0.1, "trip_years": 12.0, "arrival_burn_km_s": 4.5},
	"Makemake": {"distance_from_sun_au": 45.5, "budget": 2100, "small_antenna_data_share": 0.1, "trip_years": 13.0, "arrival_burn_km_s": 4.5},
	"Eris": {"distance_from_sun_au": 68.0, "budget": 2300, "small_antenna_data_share": 0.08, "trip_years": 18.0, "arrival_burn_km_s": 5.0},
}

# Worlds with no air (or far too little): parachutes, airbags and sky cranes can't work there,
# so landers need legs and thrusters
const AIRLESS_WORLDS = ["Moon", "Mercury", "Phobos", "Deimos", "Io", "Europa", "Ganymede", "Callisto", "Enceladus", "Titania",
	"Triton", "Charon", "Ceres", "Pluto", "Haumea", "Makemake", "Eris"]
# Giant planets with no solid surface to land on
const NO_SURFACE = ["Jupiter", "Uranus", "Neptune"]

# Every part: what slot it goes in, its name, the real spacecraft it's based on ("like"), a plain description
# ("about"), its mass (kg), cost ($ millions) and the power it uses while doing science ("power_used", watts).
const PARTS = {
	# Power
	"solar_small": {"slot": "power", "name": "Solar arrays (small)", "mass": 60, "cost": 20, "power_at_earth": 1850,
		"like": "Like NASA's Lunar Reconnaissance Orbiter",
		"about": "Light and cheap, with plenty of power near the Sun. But sunlight fades fast with distance: at Jupiter you get only 4% of it."},
	"solar_large": {"slot": "power", "name": "Solar arrays (giant)", "mass": 340, "cost": 60, "power_at_earth": 14000,
		"like": "Like Juno's three 9-meter wings",
		"about": "About 14,000 W at Earth, but only about 500 W at Jupiter. Heavy, and they have to keep facing the Sun."},
	"rtg": {"slot": "power", "name": "Nuclear power (1 RTG)", "mass": 57, "cost": 120, "power_anywhere": 245, "fades_per_year": 0.02,
		"like": "Like New Horizons' RTG",
		"about": "Turns heat from decaying plutonium into electricity, so it works anywhere, even in the dark. About 245 W at launch, fading about 2% a year. Its spare heat also keeps the probe warm."},
	"rtg_triple": {"slot": "power", "name": "Nuclear power (3 RTGs)", "mass": 170, "cost": 300, "power_anywhere": 885, "fades_per_year": 0.017,
		"like": "Like Cassini",
		"about": "Three of the same RTGs: about 885 W at launch, enough for a big orbiter at Saturn or beyond. Heavy, and very expensive."},
	# Battery
	"battery_small": {"slot": "battery", "name": "Battery (1 kWh)", "mass": 10, "cost": 5, "capacity_wh": 1000,
		"like": "Lithium-ion, like most modern probes",
		"about": "Covers power peaks, and keeps a solar probe running for an hour or two in a planet's shadow."},
	"battery_large": {"slot": "battery", "name": "Battery (3 kWh)", "mass": 40, "cost": 15, "capacity_wh": 3000,
		"like": "Like Juno's two big lithium-ion batteries",
		"about": "Enough to ride out long shadows, or a night on the surface of Mars."},
	# Antenna
	"antenna_small": {"slot": "antenna", "name": "Low-gain antenna", "mass": 5, "cost": 5, "power_used": 15, "data_gain": 0.0005,
		"like": "Every NASA probe carries these as backups",
		"about": "Talks to Earth from almost any direction, but very slowly. Fine near Earth, painfully slow far away."},
	"antenna_large": {"slot": "antenna", "name": "High-gain dish (3 m)", "mass": 35, "cost": 20, "power_used": 40, "data_gain": 1.0,
		"like": "Like Mars Reconnaissance Orbiter's (Cassini's was 4 m)",
		"about": "Has to point right at Earth, but sends data about 2,000 times faster. The only way to send lots of pictures from far away."},
	# Engine
	"engine_chemical": {"slot": "engine", "name": "Main engine (chemical)", "mass": 60, "cost": 20, "isp": 318,
		"like": "Like Juno's Leros-1b engine (645 newtons)",
		"about": "Strong, quick burns, so it can brake into orbit in under an hour. Uses propellant fast."},
	"engine_ion": {"slot": "engine", "name": "Ion engines", "mass": 90, "cost": 70, "isp": 3100,
		"like": "Like Dawn's three NSTAR ion engines",
		"about": "About 10 times more fuel-efficient, but they push with the force of a sheet of paper resting on your hand, so they run for months. They need at least 500 W of spare electricity."},
	# Propellant
	"fuel_small": {"slot": "fuel", "name": "Propellant tank (300 kg)", "mass": 330, "cost": 5, "propellant": 300,
		"like": "About a quarter of what Mars Reconnaissance Orbiter carried",
		"about": "Enough for a small braking burn. Lighter, so it's easier on the rocket."},
	"fuel_large": {"slot": "fuel", "name": "Propellant tank (1,200 kg)", "mass": 1300, "cost": 12, "propellant": 1200,
		"like": "Like Mars Reconnaissance Orbiter's 1,187 kg",
		"about": "Room for big braking burns, but over half the probe's weight is now fuel, so it needs a bigger rocket."},
	# Protection
	"shield_none": {"slot": "shield", "name": "No extra protection", "mass": 0, "cost": 0,
		"like": "Most orbiters fly like this",
		"about": "Lightest and cheapest. Fine unless you're landing through air or flying through radiation belts."},
	"shield_heat": {"slot": "shield", "name": "Heat shield and parachute", "mass": 300, "cost": 30,
		"like": "Like Perseverance's 4.5 m heat shield",
		"about": "Needed to land through air (Mars, Venus or Titan). The air does most of the braking, but heats the shield to about 1,300 °C."},
	"shield_radiation": {"slot": "shield", "name": "Radiation vault", "mass": 200, "cost": 40,
		"like": "Like Juno's titanium vault (walls about 1 cm thick)",
		"about": "A titanium box around the electronics. Jupiter's radiation belts are the harshest in the solar system."},
	"shield_venus": {"slot": "shield", "name": "Pressure and heat hull", "mass": 400, "cost": 50,
		"like": "Like the Soviet Venera landers",
		"about": "Venus's surface is 465 °C, with 92 times Earth's air pressure. The record is 127 minutes (Venera 13, 1982)."},
	# Landing
	"landing_none": {"slot": "landing", "name": "No lander (orbiter only)", "mass": 0, "cost": 0,
		"like": "Like Juno, Cassini and Mars Reconnaissance Orbiter",
		"about": "Studies the world from above. The safest choice."},
	"landing_legs": {"slot": "landing", "name": "Landing legs and thrusters", "mass": 150, "cost": 30,
		"like": "Like Phoenix and InSight on Mars, and Apollo's lunar module",
		"about": "Rocket thrusters slow you all the way down. The only way to land on worlds with no air."},
	"landing_airbags": {"slot": "landing", "name": "Airbags", "mass": 100, "cost": 20,
		"like": "Like Mars Pathfinder, Spirit and Opportunity",
		"about": "A ball of airbags bounces across the ground until it stops. Needs air and a parachute first, and only works for small landers."},
	"landing_skycrane": {"slot": "landing", "name": "Sky crane", "mass": 500, "cost": 90,
		"like": "Like Curiosity and Perseverance",
		"about": "A rocket-powered crane lowers the lander on cables, then flies away. Gentle and precise, but heavy and expensive."},
	# Computer
	"computer_standard": {"slot": "computer", "name": "Flight computer", "mass": 5, "cost": 5,
		"like": "A standard space-grade computer",
		"about": "Fine for most places, but radiation can scramble it."},
	"computer_radiation_hardened": {"slot": "computer", "name": "Radiation-hardened computer", "mass": 10, "cost": 25,
		"like": "Like the RAD750 on Curiosity, Juno and the James Webb Space Telescope",
		"about": "Slower than a phone (200 MHz), but built to keep working when radiation hits it. Each one costs about $200,000."},
	# Temperature control
	"thermal_heaters": {"slot": "thermal", "name": "Heaters and blankets", "mass": 15, "cost": 5, "power_used": 40,
		"like": "Gold and silver insulation blankets, like on almost every probe",
		"about": "Keeps the electronics and fuel from freezing far from the Sun. Uses about 40 W."},
	"thermal_radiators": {"slot": "thermal", "name": "Radiators and sunshade", "mass": 20, "cost": 8,
		"like": "Like MESSENGER's ceramic sunshade at Mercury",
		"about": "Sheds extra heat into space so the probe doesn't cook near the Sun."},
	"thermal_both": {"slot": "thermal", "name": "Heaters and radiators", "mass": 35, "cost": 13, "power_used": 40,
		"like": "Like Parker Solar Probe, which handles both extremes",
		"about": "Copes with very hot and very cold. Heavier."},
	# Science instruments (pick any number)
	"instrument_camera": {"slot": "instrument", "name": "Camera", "mass": 20, "cost": 10, "power_used": 15,
		"like": "Like New Horizons' LORRI and Mars Reconnaissance Orbiter's HiRISE",
		"about": "Takes pictures. HiRISE can spot things about 1 m wide from orbit."},
	"instrument_spectrometer": {"slot": "instrument", "name": "Spectrometer", "mass": 25, "cost": 20, "power_used": 20,
		"like": "Like Cassini's VIMS",
		"about": "Splits light into its colors to tell what things are made of: ice, minerals, gases."},
	"instrument_radar": {"slot": "instrument", "name": "Radar", "mass": 40, "cost": 30, "power_used": 60,
		"like": "Like Magellan's, which mapped 98% of Venus through its clouds",
		"about": "Sees through clouds, dust and even ice. Power-hungry."},
	"instrument_magnetometer": {"slot": "instrument", "name": "Magnetometer", "mass": 5, "cost": 8, "power_used": 4,
		"like": "Like Juno's, on a long boom",
		"about": "Measures magnetic fields. That's how Galileo found the hidden ocean under Europa's ice."},
	"instrument_drill": {"slot": "instrument", "name": "Drill (landers only)", "mass": 30, "cost": 25, "power_used": 40,
		"like": "Like Perseverance's coring drill",
		"about": "Collects rock and ice from below the surface."},
	"instrument_seismometer": {"slot": "instrument", "name": "Seismometer (landers only)", "mass": 15, "cost": 15, "power_used": 9,
		"like": "Like InSight's, which recorded over 1,300 marsquakes",
		"about": "Feels quakes to work out what's deep inside a world."},
}

# What the air is like, for landing
const AIR = {
	"Mars": "Thin: 1% of Earth's. Enough for a heat shield and parachute to do most of the braking, but you still need rockets, airbags or a sky crane at the end.",
	"Venus": "Crushing: 92 times Earth's pressure, and 465 °C at the surface. A heat shield gets you down; surviving there is the hard part.",
	"Titan": "Thicker than Earth's (1.5 times the pressure) with weak gravity: parachutes work wonderfully. Huygens floated down for over 2 hours.",
	"Jupiter": "No solid surface: the air just gets thicker and hotter all the way down.",
	"Saturn": "No solid surface. Landers go to its moon Titan instead.",
	"Uranus": "No solid surface: the air just gets thicker and hotter all the way down.",
	"Neptune": "No solid surface: the air just gets thicker and hotter all the way down.",
	"Pluto": "Far too thin to slow a lander (about 1/100,000 of Earth's): landers need rocket thrusters.",
	"Triton": "Far too thin to slow a lander: landers need rocket thrusters.",
}

# How harsh the radiation is (Jupiter's belts are the worst in the solar system)
const RADIATION = {
	"Io": "Extreme: inside Jupiter's most intense radiation belts. Unprotected electronics would fail within hours.",
	"Europa": "Very high: Europa Clipper flies past instead of orbiting, to limit the dose.",
	"Jupiter": "Very high, especially close in. Juno keeps its electronics in a titanium vault.",
	"Ganymede": "High, though Ganymede's own magnetic field shields part of it.",
	"Callisto": "Moderate: outside Jupiter's worst belts.",
	"Saturn": "Moderate.", "Enceladus": "Moderate.", "Titan": "Low: Titan's thick air shields its surface.",
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
	"Mercury": "NASA's MESSENGER orbited Mercury from 2011 to 2015 behind a ceramic sunshade and found ice in shadowed polar craters. ESA and Japan's BepiColombo used nine planet flybys to slow down enough to reach it.",
	"Uranus": "Only NASA's Voyager 2 has visited, flying past in January 1986 on RTG power. A Uranus orbiter with an atmosphere probe is NASA's top choice for its next big planetary mission.",
	"Neptune": "Only NASA's Voyager 2 has visited, flying past in August 1989, 12 years after launch, on RTG power. It found the Great Dark Spot and the fastest winds in the solar system.",
	"Ceres": "NASA's Dawn orbited Ceres from 2015 to 2018. Its ion engines let it orbit two worlds, Vesta and then Ceres, and it found bright salt deposits left by salty water from below.",
	"Pluto": "NASA's New Horizons flew past Pluto in July 2015 after nine and a half years in space. It ran on an RTG and was going too fast to stop and orbit.",
	"Haumea": "No spacecraft has visited Haumea. Astronomers worked out its egg shape from how its brightness changes as it spins, and found its ring in 2017 when it passed in front of a star.",
	"Makemake": "No spacecraft has visited Makemake. The Hubble Space Telescope found its small dark moon in 2016, and the James Webb Space Telescope has studied its methane ice.",
	"Eris": "No spacecraft has visited Eris. It was discovered in 2005 with a telescope at Palomar Observatory, and its moon Dysnomia let astronomers weigh it: it's slightly heavier than Pluto.",
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

# Power when the probe gets there: sunlight fades with the square of the distance, and an RTG's power fades a
# little every year of the trip (New Horizons' RTG made 245.7 W at launch and 202 W at Pluto, 9.5 years later)
func power_made():
	var power_part = PARTS[choices["power"]]
	if power_part.has("power_anywhere"):
		return power_part["power_anywhere"] * pow(1.0 - power_part["fades_per_year"], trip_years())
	return power_part["power_at_earth"] * sunlight_factor()

func power_at_launch():
	var power_part = PARTS[choices["power"]]
	return power_part.get("power_anywhere", power_part.get("power_at_earth", 0))

func trip_years():
	return DESTINATIONS[destination]["trip_years"]

# Average distance from Earth: sometimes the destination is on our side of the Sun, sometimes the far side
func earth_distance_au():
	if destination == "Moon":
		return 384400.0 / 149597870.7
	var distance = DESTINATIONS[destination]["distance_from_sun_au"]
	return sqrt(distance * distance + 1.0)

# How long a radio signal takes to get from Earth to the probe, one way
func radio_delay_minutes():
	return earth_distance_au() * LIGHT_MINUTES_PER_AU

# How fast the probe can send data home (kilobits per second), falling with the square of the distance
func data_rate_kilobits():
	var gain = PARTS[choices["antenna"]]["data_gain"]
	return min(HIGH_GAIN_KILOBITS_AT_1_AU * gain / pow(earth_distance_au(), 2.0), 100000.0)

# How many high-resolution photos fit through one 8-hour Deep Space Network contact a day
func photos_per_day():
	return data_rate_kilobits() * 1000.0 * CONTACT_HOURS_PER_DAY * 3600.0 / (PHOTO_MEGABITS * 1000000.0)

func propellant_mass():
	return PARTS[choices["fuel"]].get("propellant", 0)

# Ion engines run while the instruments rest, on whatever the probe's body doesn't need
func ion_engines_have_power():
	return power_made() - PROBE_BODY["power_needed"] >= ION_ENGINE_MINIMUM_WATTS

# A lander with a heat shield can dive straight into the air (like Perseverance), so it only needs small corrections
func direct_entry():
	return choices["landing"] != "landing_none" and choices["shield"] in ["shield_heat", "shield_venus"] and destination in ["Mars", "Venus", "Titan"]

func arrival_burn_needed_km_s():
	if direct_entry():
		return 0.05
	return DESTINATIONS[destination]["arrival_burn_km_s"]

# How much the probe can change its own speed, from the rocket equation:
#   speed change = Isp × g × ln(mass with propellant / mass without it)
func probe_speed_change_km_s():
	if choices["engine"] == "engine_ion" and not ion_engines_have_power():
		return 0.0
	var full_mass = float(total_mass())
	var empty_mass = full_mass - propellant_mass()
	return PARTS[choices["engine"]]["isp"] * RocketData.GRAVITY * log(full_mass / empty_mass) / 1000.0

# How long the braking burn takes: under an hour for a chemical engine, months for ion engines
func arrival_burn_seconds():
	var exhaust_speed = PARTS[choices["engine"]]["isp"] * RocketData.GRAVITY
	var propellant_used = total_mass() * (1.0 - exp(-arrival_burn_needed_km_s() * 1000.0 / exhaust_speed))
	var thrust = CHEMICAL_THRUST_NEWTONS
	if choices["engine"] == "engine_ion":
		# Dawn ran one engine at a time; its push grows with the power it gets (full push at 2,300 W)
		thrust = ION_THRUST_NEWTONS * clamp((power_made() - PROBE_BODY["power_needed"]) / 2300.0, 0.25, 1.0)
	return propellant_used / (thrust / exhaust_speed)

func arrival_burn_time_text():
	var seconds = arrival_burn_seconds()
	if seconds < 3600.0 * 2.0:
		return "a %d-minute burn" % int(round(seconds / 60.0))
	if seconds < 86400.0 * 2.0:
		return "a %d-hour burn" % int(round(seconds / 3600.0))
	if seconds < 86400.0 * 60.0:
		return "%d days of thrusting" % int(round(seconds / 86400.0))
	return "%d months of thrusting" % int(round(seconds / (86400.0 * 30.4)))

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
	events.append({"title": "Braking into orbit", "phase": "arrival", "insertion_check": true})
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
	elif event.has("insertion_check"):
		var needed = arrival_burn_needed_km_s()
		var can_do = probe_speed_change_km_s()
		if direct_entry():
			text = "Your lander dove straight into %s's air behind its heat shield, like Perseverance did at Mars." % destination
		elif can_do >= needed:
			text = "Your engine slowed the probe by %.2f km/s (%s), and %s's gravity captured it." % [needed, arrival_burn_time_text(), destination]
		else:
			ok = false
			science -= 25
			if choices["engine"] == "engine_ion" and not ion_engines_have_power():
				text = "Your ion engines didn't have enough electricity to run, so the probe couldn't slow down. It flew past %s, grabbing what science it could. Lost 25 science." % destination
			else:
				text = "Your engine could only slow the probe by %.2f km/s, but it needed %.2f km/s. It flew past %s like New Horizons at Pluto, grabbing what science it could. Lost 25 science." % [can_do, needed, destination]
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
