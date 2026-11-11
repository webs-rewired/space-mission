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
	# Top-stage engines have huge nozzles that only work in space
	"merlin_vacuum": {"name": "Merlin Vacuum (Falcon 9 top stage)", "stage": "top", "fuel": "kerosene",
		"thrust_vacuum": 981, "isp_vacuum": 348, "mass": 490, "cost": 2},
	"rl10": {"name": "RL10 (Centaur top stage)", "stage": "top", "fuel": "hydrogen",
		"thrust_vacuum": 110, "isp_vacuum": 465, "mass": 300, "cost": 17},
	"raptor_vacuum": {"name": "Raptor Vacuum (Starship)", "stage": "top", "fuel": "methane",
		"thrust_vacuum": 2500, "isp_vacuum": 378, "mass": 2000, "cost": 4},
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
}

const STARTING_ROCKETS = {
	"falcon9": {"bottom_engine": "merlin", "bottom_engine_count": 9, "bottom_tank": "kerosene_400", "boosters": "none",
		"top_engine": "merlin_vacuum", "top_engine_count": 1, "top_tank": "kerosene_100", "kick_stage": "none"},
	"atlas5": {"bottom_engine": "rd180", "bottom_engine_count": 1, "bottom_tank": "kerosene_250", "boosters": "small_boosters_4",
		"top_engine": "rl10", "top_engine_count": 1, "top_tank": "hydrogen_21", "kick_stage": "none"},
	"sls": {"bottom_engine": "rs25", "bottom_engine_count": 4, "bottom_tank": "hydrogen_900", "boosters": "giant_boosters_2",
		"top_engine": "rl10", "top_engine_count": 1, "top_tank": "hydrogen_21", "kick_stage": "none"},
}
