extends RefCounted

# Rocket parts for Orbit Lab, based on real engines and stages.
# Numbers are rounded public figures. Costs are rough estimates in millions of dollars.
#
# Units: thrust in kilonewtons (kN), mass in kilograms (kg), Isp in seconds.
# Isp (specific impulse) is how efficiently an engine uses fuel. Higher is better.

const GRAVITY = 9.81                # Earth's gravity in m/s², used in the rocket equation
const LAUNCH_OPERATIONS_COST = 20   # launch pad, crew and range safety, in $M

# How much speed (delta-v) the rocket must give the probe, in meters per second.
# About 9,400 m/s gets you into low Earth orbit (including losses to gravity and air).
# The rest is the burn that sends the probe toward its target. The probe brakes on its own when it arrives.
const SPEED_NEEDED = {
	"Moon": 12500,
	"Mars": 13000,
	"Venus": 12900,
	"Jupiter": 15700,
	"Saturn": 16700,
	# Moons: the rocket's job is getting to the planet; the probe does the last steps to its moon
	"Phobos": 13000,
	"Deimos": 13000,
	"Io": 15700,
	"Europa": 15700,
	"Ganymede": 15700,
	"Callisto": 15700,
	"Enceladus": 16700,
	"Titan": 16700,
	"Titania": 17500,
	"Triton": 17800,
	"Charon": 17900,
	"Mercury": 15000,
	"Uranus": 17500,
	"Neptune": 17800,
	"Ceres": 14000,
	"Pluto": 17900,
	"Haumea": 18000,
	"Makemake": 18000,
	"Eris": 18200,
}

const SPEED_NOTE = {
	"Moon": "About 9,400 m/s to reach Earth orbit, plus about 3,100 m/s to head for the Moon.",
	"Mars": "About 9,400 m/s to reach Earth orbit, plus about 3,600 m/s to head for Mars.",
	"Venus": "About 9,400 m/s to reach Earth orbit, plus about 3,500 m/s to head for Venus.",
	"Jupiter": "About 9,400 m/s to reach Earth orbit, plus about 6,300 m/s to head for Jupiter.",
	"Saturn": "About 9,400 m/s to reach Earth orbit, plus about 7,300 m/s to head for Saturn.",
	"Phobos": "About 9,400 m/s to reach Earth orbit, plus about 3,600 m/s to head for Mars. Your probe does the last steps to Phobos.",
	"Deimos": "About 9,400 m/s to reach Earth orbit, plus about 3,600 m/s to head for Mars. Your probe does the last steps to Deimos.",
	"Io": "About 9,400 m/s to reach Earth orbit, plus about 6,300 m/s to head for Jupiter. Your probe does the last steps to Io.",
	"Europa": "About 9,400 m/s to reach Earth orbit, plus about 6,300 m/s to head for Jupiter. Your probe does the last steps to Europa.",
	"Ganymede": "About 9,400 m/s to reach Earth orbit, plus about 6,300 m/s to head for Jupiter. Your probe does the last steps to Ganymede.",
	"Callisto": "About 9,400 m/s to reach Earth orbit, plus about 6,300 m/s to head for Jupiter. Your probe does the last steps to Callisto.",
	"Enceladus": "About 9,400 m/s to reach Earth orbit, plus about 7,300 m/s to head for Saturn. Your probe does the last steps to Enceladus.",
	"Titan": "About 9,400 m/s to reach Earth orbit, plus about 7,300 m/s to head for Saturn. Your probe does the last steps to Titan.",
	"Titania": "About 9,400 m/s to reach Earth orbit, plus about 8,100 m/s to head for Uranus. Your probe does the last steps to Titania.",
	"Triton": "About 9,400 m/s to reach Earth orbit, plus about 8,400 m/s to head for Neptune. Your probe does the last steps to Triton.",
	"Charon": "About 9,400 m/s to reach Earth orbit, plus about 8,500 m/s to head for Pluto. Your probe does the last steps to Charon.",
	"Mercury": "About 9,400 m/s to reach Earth orbit, plus about 5,600 m/s to head for Mercury. Falling toward the Sun is hard: you have to cancel much of Earth's speed around it.",
	"Uranus": "About 9,400 m/s to reach Earth orbit, plus about 8,100 m/s to head for Uranus.",
	"Neptune": "About 9,400 m/s to reach Earth orbit, plus about 8,400 m/s to head for Neptune.",
	"Ceres": "About 9,400 m/s to reach Earth orbit, plus about 4,600 m/s to head for Ceres in the asteroid belt.",
	"Pluto": "About 9,400 m/s to reach Earth orbit, plus about 8,500 m/s to head for Pluto.",
	"Haumea": "About 9,400 m/s to reach Earth orbit, plus about 8,600 m/s to head for Haumea in the Kuiper belt.",
	"Makemake": "About 9,400 m/s to reach Earth orbit, plus about 8,600 m/s to head for Makemake in the Kuiper belt.",
	"Eris": "About 9,400 m/s to reach Earth orbit, plus about 8,800 m/s to head for Eris, the most distant of all these worlds.",
}

const FUEL_NAMES = {
	"kerosene": "kerosene and liquid oxygen",
	"hydrogen": "liquid hydrogen and liquid oxygen",
	"methane": "methane and liquid oxygen",
}

# How heavy each propellant mix is, in kg per cubic meter (used to draw tank sizes)
const FUEL_DENSITY = {"kerosene": 1030, "hydrogen": 360, "methane": 830}

const TANK_COLORS = {
	"kerosene": Color(0.92, 0.92, 0.92),
	"hydrogen": Color(0.85, 0.45, 0.15),
	"methane": Color(0.72, 0.74, 0.78),
}

const ENGINES = {
	# Bottom-stage engines work at sea level
	"merlin": {"name": "Merlin 1D (Falcon 9)", "stage": "bottom", "fuel": "kerosene",
		"thrust_sea_level": 845, "thrust_vacuum": 914, "isp_sea_level": 282, "isp_vacuum": 311, "mass": 470, "cost": 1},
	"rd180": {"name": "RD-180 (Atlas V)", "stage": "bottom", "fuel": "kerosene",
		"thrust_sea_level": 3830, "thrust_vacuum": 4150, "isp_sea_level": 311, "isp_vacuum": 338, "mass": 5480, "cost": 25},
	"rs25": {"name": "RS-25 (Space Shuttle, SLS)", "stage": "bottom", "fuel": "hydrogen",
		"thrust_sea_level": 1860, "thrust_vacuum": 2280, "isp_sea_level": 366, "isp_vacuum": 452, "mass": 3527, "cost": 100},
	"raptor": {"name": "Raptor (Starship)", "stage": "bottom", "fuel": "methane",
		"thrust_sea_level": 2260, "thrust_vacuum": 2450, "isp_sea_level": 327, "isp_vacuum": 350, "mass": 1600, "cost": 2},
	"f1": {"name": "F-1 (Saturn V)", "stage": "bottom", "fuel": "kerosene",
		"thrust_sea_level": 6770, "thrust_vacuum": 7770, "isp_sea_level": 263, "isp_vacuum": 304, "mass": 8400, "cost": 60},
	# Top-stage engines have huge nozzles that only work in space
	"merlin_vacuum": {"name": "Merlin Vacuum (Falcon 9 top stage)", "stage": "top", "fuel": "kerosene",
		"thrust_vacuum": 981, "isp_vacuum": 348, "mass": 490, "cost": 2},
	"rl10": {"name": "RL10 (Centaur top stage)", "stage": "top", "fuel": "hydrogen",
		"thrust_vacuum": 110, "isp_vacuum": 465, "mass": 300, "cost": 17},
	"raptor_vacuum": {"name": "Raptor Vacuum (Starship)", "stage": "top", "fuel": "methane",
		"thrust_vacuum": 2500, "isp_vacuum": 378, "mass": 2000, "cost": 4},
	"j2": {"name": "J-2 (Saturn V second and third stages)", "stage": "top", "fuel": "hydrogen",
		"thrust_vacuum": 1033, "isp_vacuum": 421, "mass": 1788, "cost": 25},
}

# "propellant" is the fuel and oxygen inside. "empty_mass" is the tank and structure.
const TANKS = {
	"kerosene_30": {"name": "Kerosene tank, 30 t", "fuel": "kerosene", "propellant": 30000, "empty_mass": 2000, "cost": 5, "radius": 1.5},
	"kerosene_100": {"name": "Kerosene tank, 100 t (like Falcon 9's top stage)", "fuel": "kerosene", "propellant": 100000, "empty_mass": 5500, "cost": 10, "radius": 1.85},
	"kerosene_250": {"name": "Kerosene tank, 250 t (like Atlas V's core)", "fuel": "kerosene", "propellant": 250000, "empty_mass": 14000, "cost": 20, "radius": 1.95},
	"kerosene_400": {"name": "Kerosene tank, 400 t (like Falcon 9's bottom stage)", "fuel": "kerosene", "propellant": 400000, "empty_mass": 22000, "cost": 25, "radius": 1.85},
	"hydrogen_21": {"name": "Hydrogen tank, 21 t (like Centaur)", "fuel": "hydrogen", "propellant": 21000, "empty_mass": 2300, "cost": 15, "radius": 1.5},
	"hydrogen_60": {"name": "Hydrogen tank, 60 t", "fuel": "hydrogen", "propellant": 60000, "empty_mass": 5500, "cost": 30, "radius": 2.5},
	"hydrogen_900": {"name": "Hydrogen tank, 900 t (like SLS's core)", "fuel": "hydrogen", "propellant": 900000, "empty_mass": 85000, "cost": 200, "radius": 4.2},
	"methane_150": {"name": "Methane tank, 150 t", "fuel": "methane", "propellant": 150000, "empty_mass": 9000, "cost": 10, "radius": 4.5},
	"methane_1200": {"name": "Methane tank, 1,200 t (like Starship)", "fuel": "methane", "propellant": 1200000, "empty_mass": 80000, "cost": 40, "radius": 4.5},
	"kerosene_2150": {"name": "Kerosene tank, 2,150 t (like Saturn V's S-IC)", "fuel": "kerosene", "propellant": 2150000, "empty_mass": 89000, "cost": 250, "radius": 5.05},
	"hydrogen_450": {"name": "Hydrogen tank, 450 t (like Saturn V's S-II)", "fuel": "hydrogen", "propellant": 450000, "empty_mass": 27000, "cost": 180, "radius": 5.05},
	"methane_3400": {"name": "Methane tank, 3,400 t (like Super Heavy)", "fuel": "methane", "propellant": 3400000, "empty_mass": 200000, "cost": 60, "radius": 4.5},
}

# Solid boosters burn alongside the bottom stage and drop off when empty
const BOOSTERS = {
	"none": {"name": "No boosters", "count": 0},
	"small_boosters_2": {"name": "2 small solid boosters (like GEM 63)", "count": 2, "propellant_each": 44000, "empty_mass_each": 5500,
		"thrust_each": 1660, "isp": 260, "cost_each": 12, "radius": 0.8, "height": 20},
	"small_boosters_4": {"name": "4 small solid boosters (like GEM 63)", "count": 4, "propellant_each": 44000, "empty_mass_each": 5500,
		"thrust_each": 1660, "isp": 260, "cost_each": 12, "radius": 0.8, "height": 20},
	"giant_boosters_2": {"name": "2 giant solid boosters (like SLS)", "count": 2, "propellant_each": 630000, "empty_mass_each": 100000,
		"thrust_each": 16000, "isp": 255, "cost_each": 90, "radius": 1.85, "height": 54},
}

# A small solid motor that gives the probe a final push after the top stage
const KICK_STAGES = {
	"none": {"name": "No kick stage"},
	"star48": {"name": "Star 48B solid kick stage (like New Horizons)", "propellant": 2010, "empty_mass": 124, "isp": 286, "cost": 15,
		"radius": 0.62, "height": 2.0},
	# Saturn V's third stage: one J-2 that fired twice, once to reach orbit and again to head for the Moon
	"s_ivb": {"name": "S-IVB third stage (Saturn V, one J-2)", "propellant": 109500, "empty_mass": 13500, "isp": 421, "cost": 200,
		"radius": 3.3, "height": 17.8, "burn_seconds": 350, "caption": "The S-IVB third stage relights for the push out of Earth orbit"},
}

const STARTING_ROCKETS = {
	"falcon9": {"bottom_engine": "merlin", "bottom_engine_count": 9, "bottom_tank": "kerosene_400", "boosters": "none",
		"top_engine": "merlin_vacuum", "top_engine_count": 1, "top_tank": "kerosene_100", "kick_stage": "none"},
	"atlas5": {"bottom_engine": "rd180", "bottom_engine_count": 1, "bottom_tank": "kerosene_250", "boosters": "small_boosters_4",
		"top_engine": "rl10", "top_engine_count": 1, "top_tank": "hydrogen_21", "kick_stage": "none"},
	"atlas5_star48": {"bottom_engine": "rd180", "bottom_engine_count": 1, "bottom_tank": "kerosene_250", "boosters": "small_boosters_4",
		"top_engine": "rl10", "top_engine_count": 1, "top_tank": "hydrogen_21", "kick_stage": "star48"},
	"sls": {"bottom_engine": "rs25", "bottom_engine_count": 4, "bottom_tank": "hydrogen_900", "boosters": "giant_boosters_2",
		"top_engine": "rl10", "top_engine_count": 1, "top_tank": "hydrogen_21", "kick_stage": "none"},
	"starship": {"bottom_engine": "raptor", "bottom_engine_count": 33, "bottom_tank": "methane_3400", "boosters": "none",
		"top_engine": "raptor_vacuum", "top_engine_count": 3, "top_tank": "methane_1200", "kick_stage": "none"},
	"saturn5": {"bottom_engine": "f1", "bottom_engine_count": 5, "bottom_tank": "kerosene_2150", "boosters": "none",
		"top_engine": "j2", "top_engine_count": 5, "top_tank": "hydrogen_450", "kick_stage": "s_ivb"},
}

# The real rockets behind the starting points, for the briefing and the 3D view.
# "model" is a 3D model file anywhere in the project (shown when your design matches); "height" is the real height in meters.
const REAL_ROCKETS = {
	"falcon9": {"name": "Falcon 9", "menu": "Falcon 9 (SpaceX)", "height": 70.0, "model": "falcon9.glb",
		"facts": "SpaceX's workhorse, flying since 2010 and now launching every few days. Its first stage flies back and lands on a ship or at Cape Canaveral, and some boosters have flown more than 25 times. It launched NASA's DART asteroid mission and carries astronauts to the Space Station."},
	"atlas5": {"name": "Atlas V 541", "menu": "Atlas V 541 (Curiosity, Perseverance)", "height": 58.3, "model": "atlas_v.glb",
		"facts": "United Launch Alliance's Atlas V, flying since 2002 and one of the most reliable rockets ever built. This version, with 4 solid boosters, sent the Curiosity and Perseverance rovers to Mars. Other Atlas Vs launched Juno, OSIRIS-REx and Lucy."},
	"atlas5_star48": {"name": "Atlas V 551 + Star 48B", "menu": "Atlas V + Star 48B kick stage (New Horizons)", "height": 62.2, "model": "atlas_v.glb",
		"facts": "In January 2006 an Atlas V with 5 solid boosters (you get 4 here) and a Star 48B kick stage threw New Horizons off Earth at 16.26 km/s, the fastest launch ever at the time. It crossed the Moon's orbit in 9 hours and reached Pluto in 2015."},
	"sls": {"name": "SLS Block 1", "menu": "SLS Block 1 (Artemis: NASA's Moon rocket)", "height": 98.0, "model": "sls.glb", "turn_degrees": 90.0,
		"facts": "NASA's Space Launch System, the rocket of the Artemis Moon missions. Its orange core stage carries 4 RS-25 engines that flew on the Space Shuttle, and its two 5-segment boosters are stretched Shuttle boosters. Artemis I in November 2022 sent an uncrewed Orion around the Moon. Each SLS is thrown away after one flight."},
	"saturn5": {"name": "Saturn V", "menu": "Saturn V (Apollo Moon rocket)", "height": 110.6, "model": "saturn_v_stages.glb",
		"facts": "The rocket that took 24 astronauts to the Moon between 1968 and 1972, still one of the most powerful ever flown. Its first stage burned 20 tonnes of kerosene and oxygen every second through 5 F-1 engines. The second stage had 5 J-2 hydrogen engines, and the third stage's single J-2 fired twice: once to reach orbit and again to head for the Moon. 13 launched and none was lost. Each cost about $185 million in 1969 money (about $1.4 billion today); the costs here are game estimates."},
	"starship": {"name": "Starship", "menu": "Starship (SpaceX)", "height": 121.0, "model": "starship.glb",
		"facts": "The biggest and most powerful rocket ever flown, first launched in 2023. The Super Heavy booster has 33 Raptor engines and is caught by the launch tower's giant arms when it comes back. The ship on top has 6 Raptors (3 made for space, which you get here). Both halves are built to fly again and again."},
}

# Real-world facts shown under each choice: "like" is where it flies for real, "about" is the detail in plain words
const PART_FACTS = {
	"merlin": {"like": "Falcon 9's first stage uses 9", "about": "SpaceX's kerosene engine. Cheap, and it relights in flight so the booster can fly itself back and land. 845 kN each, about the push of 3 jumbo jet engines."},
	"rd180": {"like": "Atlas V's first stage uses 1", "about": "Built in Russia, with two combustion chambers fed by one huge pump. 3,830 kN from a single engine, but no backup if it fails."},
	"rs25": {"like": "SLS uses 4, the Space Shuttle used 3", "about": "Burns liquid hydrogen, the most efficient fuel for a big engine (452 s in space). Most of the engines flying on SLS today flew on the Space Shuttle first. Very expensive."},
	"raptor": {"like": "Starship's Super Heavy booster uses 33", "about": "Burns methane, which could one day be made on Mars from water and carbon dioxide. Strong, cheap and reusable."},
	"f1": {"like": "Saturn V's first stage used 5", "about": "The most powerful single-chamber liquid rocket engine ever flown: 6,770 kN, as much push as 30 jumbo jets. Each one gulped about 2.6 tonnes of propellant every second."},
	"j2": {"like": "Saturn V's second stage used 5, its third stage 1", "about": "A hydrogen engine that could restart in space, which is how the third stage left Earth orbit for the Moon. 1,033 kN and 421 s."},
	"kerosene_2150": {"like": "Saturn V's S-IC first stage held about 2,150 t", "about": "42 m tall and 10 m wide. It emptied in about 2 minutes 40 seconds, by which time the rocket was 68 km up and going 2.4 km/s."},
	"hydrogen_450": {"like": "Saturn V's S-II second stage held about 450 t", "about": "Its hydrogen and oxygen tanks shared one wall (a common bulkhead) to save weight. It burned for about 6 minutes."},
	"s_ivb": {"like": "Saturn V's third stage (and the Saturn IB's second)", "about": "109 t of hydrogen and oxygen and one restartable J-2. It burned about 2.5 minutes to reach orbit, then 6 minutes more to send Apollo to the Moon."},
	"merlin_vacuum": {"like": "Falcon 9's top stage uses 1", "about": "A Merlin with a giant 3.3 m nozzle that only works in the vacuum of space. 981 kN. Thrown away after every flight."},
	"rl10": {"like": "Centaur (Atlas V, Vulcan) and SLS's top stage", "about": "First flew in the early 1960s and still flying. Burns hydrogen, so it gets the most speed out of its fuel (465 s), but it's gentle: 110 kN, about the weight of 11 tonnes."},
	"raptor_vacuum": {"like": "Starship's ship uses 3", "about": "A Raptor with a big nozzle made for space. 2,500 kN and 378 s: powerful and efficient, but it needs huge methane tanks."},
	"kerosene_30": {"like": "A small first or top stage", "about": "30 t of kerosene and liquid oxygen. Kerosene is dense, so the tank stays short and light."},
	"kerosene_100": {"like": "Falcon 9's top stage holds about 110 t", "about": "Kerosene is basically very pure jet fuel. It stays liquid at room temperature, so it's easy to handle."},
	"kerosene_250": {"like": "Atlas V's core holds about 284 t", "about": "A big kerosene core, 32.5 m tall on Atlas V. Bigger tanks mean more speed, but more weight to lift off the pad."},
	"kerosene_400": {"like": "Falcon 9's first stage holds about 410 t", "about": "Falcon 9 chills its propellant extra cold so more fits in the tank."},
	"hydrogen_21": {"like": "Centaur holds about 21 t", "about": "Centaur's tank walls are so thin that it has to stay pressurized or it would collapse, like a balloon."},
	"hydrogen_60": {"like": "A large hydrogen top stage", "about": "Liquid hydrogen is −253 °C and so light that a tonne of it fills 14 cubic meters, so hydrogen tanks are huge."},
	"hydrogen_900": {"like": "SLS's core stage holds about 990 t", "about": "65 m tall. The orange color is bare spray-on foam that keeps the −253 °C hydrogen from boiling away. Hydrogen leaks delayed Artemis I for months."},
	"methane_150": {"like": "A mid-size methane stage", "about": "Methane is −162 °C as a liquid: much easier to keep cold than hydrogen, and it burns cleaner than kerosene."},
	"methane_1200": {"like": "Starship's ship holds about 1,200 t", "about": "Built from shiny stainless steel instead of carbon fiber or aluminum: cheap, and it gets stronger when it's super cold."},
	"methane_3400": {"like": "Super Heavy holds about 3,400 t", "about": "71 m tall and 9 m wide, the biggest rocket stage ever flown."},
	"none": {"like": "Falcon 9 and Starship fly without them", "about": "Simpler and cheaper, but all the liftoff push has to come from the bottom stage's engines."},
	"small_boosters_2": {"like": "GEM 63 boosters on Atlas V", "about": "Northrop Grumman solid rockets, 1,660 kN each. They burn for about 94 seconds, then drop into the ocean. A solid rocket can't be turned off once lit."},
	"small_boosters_4": {"like": "Atlas V 541 used 4 (Curiosity, Perseverance)", "about": "Four solid boosters for a much stronger liftoff. Each burns about 94 seconds, then falls away."},
	"giant_boosters_2": {"like": "SLS's two 5-segment boosters", "about": "Space Shuttle boosters with one extra segment, the most powerful boosters ever flown. 16,000 kN each, as much push as 16 jumbo jets. They burn for about 2 minutes and fall into the Atlantic."},
	"no_kick": {"like": "Most missions to the Moon, Mars and Venus", "about": "The top stage alone gives the final push."},
	"star48": {"like": "New Horizons, and Parker Solar Probe used a Star 48BV", "about": "A 2 m long solid motor on top of the top stage. It fires for about 85 seconds and gives a light probe a big extra kick toward faraway worlds."},
}

# The order the dropdowns list the starting rockets in
const STARTING_ROCKET_ORDER = ["falcon9", "atlas5", "atlas5_star48", "saturn5", "sls", "starship"]

# When each part of the climb happens, in seconds after liftoff (same math as the launch scene)
static func flight_plan(rocket, report):
	var bottom_engine = ENGINES[rocket["bottom_engine"]]
	var bottom_tank = TANKS[rocket["bottom_tank"]]
	var top_engine = ENGINES[rocket["top_engine"]]
	var top_tank = TANKS[rocket["top_tank"]]
	var booster = BOOSTERS[rocket["boosters"]]
	# Fuel used per second = thrust / (Isp × g)
	var core_isp = (bottom_engine["isp_sea_level"] + bottom_engine["isp_vacuum"]) / 2.0
	var core_fuel_per_second = bottom_engine["thrust_sea_level"] * 1000.0 * rocket["bottom_engine_count"] / (core_isp * GRAVITY)
	var plan = {"booster_burnout": 0.0}
	plan["main_engine_cutoff"] = clamp(bottom_tank["propellant"] / core_fuel_per_second, 60.0, 600.0)
	if booster["count"] > 0:
		var booster_fuel_per_second = booster["thrust_each"] * 1000.0 / (booster["isp"] * GRAVITY)
		plan["booster_burnout"] = min(booster["propellant_each"] / booster_fuel_per_second, plan["main_engine_cutoff"] - 8.0)
	var top_fuel_per_second = top_engine["thrust_vacuum"] * 1000.0 * rocket["top_engine_count"] / (top_engine["isp_vacuum"] * GRAVITY)
	var top_burn_seconds = top_tank["propellant"] / top_fuel_per_second
	var still_needed = max(9400.0 - report["bottom_stage_speed"], 300.0)
	var share_to_orbit = clamp(still_needed / max(report["top_stage_speed"], 1.0), 0.1, 0.9)
	plan["top_ignition"] = plan["main_engine_cutoff"] + 7.0
	plan["orbit"] = plan["main_engine_cutoff"] + 8.0 + max(30.0, top_burn_seconds * share_to_orbit)
	plan["fairing"] = min(clamp(plan["main_engine_cutoff"] + 40.0, 150.0, 230.0), plan["orbit"] - 10.0)
	plan["escape_start"] = plan["orbit"] + 60.0
	plan["escape_end"] = plan["escape_start"] + clamp(top_burn_seconds * (1.0 - share_to_orbit), 40.0, 400.0)
	var kick = KICK_STAGES[rocket["kick_stage"]]
	plan["kick_end"] = plan["escape_end"]
	if kick.has("propellant"):
		plan["kick_end"] = plan["escape_end"] + 30.0 + kick.get("burn_seconds", 85.0)   # (a Star 48B burns about 85 seconds)
	return plan
