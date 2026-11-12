extends RefCounted

# Everything we know about each body in the solar system view: its real orbit, size, spin, tilt,
# how it looks, and the facts shown in the stats panel.
#
# ORBITS
#   Planets use NASA JPL's "Approximate Positions of the Planets" table (valid 1800 to 2050):
#     "jpl": [a (AU), e, inclination (deg), mean longitude L (deg), longitude of perihelion (deg), longitude of ascending node (deg)]
#     "rates": how much each of those changes per century
#   Pluto uses the same kind of numbers from JPL's earlier version of that table.
#   Dwarf planets and comets use standard orbital elements at an epoch (a Julian date):
#     "a", "e", "i", "node", "arg_peri" (all degrees), "mean_anomaly" at "epoch_jd".
#     Comets give the date they were closest to the Sun ("epoch_jd" with mean anomaly 0).
#   The Moon uses a standard simple model of its orbit around Earth ("moon": true).
#   Other moons use JPL's mean orbital elements ("satellite"), measured in the moon's own reference plane
#   (its planet's equator, or its "Laplace plane"), whose pole is "pole_ra" / "pole_dec". The angles are
#   measured from where that plane crosses Earth's equator, at Jan 1, 2000. "degrees_per_day" is how fast the
#   moon goes around; the orbit's long axis and its tilt slowly turn ("apsis_" and "node_degrees_per_day").
#   Checked against NASA's high-accuracy theory for Jupiter's moons: within half a degree from 2000 to 2035.
#
# SPACECRAFT (kind "spacecraft", worked out in spacecraft.gd)
#   "route": the real trip as [date, "Planet"] stops (closest approach at each flyby), ending with
#     [date, [right ascension (hours), declination (degrees), distance from Earth (AU)]] from NASA's tracking.
#   Parker Solar Probe uses an orbit around the Sun; Juno and the ISS use "satellite" orbits around their planet.
#   "shown_from": the date it appears (launch, or when its current orbit began).
#   "faces": which side of the model ("+y", "-z") points at "earth" or the "sun"; the ISS flies "level" with Earth.
#
# SPIN AND TILT
#   "pole_ra" / "pole_dec": where the north pole points (IAU, in sky coordinates). This sets the real tilt.
#   Bodies without a measured pole use "tilt" (degrees from straight up) toward "tilt_toward" (ecliptic longitude).
#   "rotation_hours": one turn, in hours. Negative means it turns clockwise around the pole given
#   (Venus and Uranus, whose IAU "north" pole is the one on the north side of the solar system).
#   Pluto's pole is given by the right-hand rule instead, so it points south and its number is positive:
#   either way, it spins backwards compared with its orbit.
#   PRIME_MERIDIANS (below) gives the exact spin angle on any date for bodies with official IAU models,
#   so Earth's day and night fall on the right places for today's date.

# Every moon comes right after its planet, so the planet's position is worked out first
const BODY_ORDER = ["Sun", "Mercury", "Venus", "Earth", "Moon", "Mars", "Phobos", "Deimos", "Ceres",
	"Jupiter", "Io", "Europa", "Ganymede", "Callisto", "Saturn", "Enceladus", "Titan", "Uranus", "Titania",
	"Neptune", "Triton", "Pluto", "Charon", "Haumea", "Makemake", "Eris", "Halley", "Encke", "67P", "Hale-Bopp",
	"Voyager 1", "Voyager 2", "New Horizons", "Parker Solar Probe", "Juno", "ISS"]

# IAU rotation models: [W0 (degrees at Jan 1, 2000, noon), degrees per day]. Bodies not listed spin from rotation_hours.
const PRIME_MERIDIANS = {
	"Sun": [84.176, 14.1844000],
	"Mercury": [329.5988, 6.1385108],
	"Venus": [160.20, -1.4813688],
	"Earth": [190.147, 360.9856235],
	"Moon": [38.3213, 13.17635815],
	"Mars": [176.630, 350.89198226],
	"Ceres": [170.650, 952.1532],
	"Jupiter": [284.95, 870.5360000],
	"Saturn": [38.90, 810.7939024],
	"Uranus": [203.81, -501.1600928],
	"Neptune": [249.978, 541.1397757],
	"Pluto": [302.695, 56.3625225],
}

const KILOMETERS_PER_AU = 149597870.7
const EARTH_RADIUS_KM = 6371.0

const BODIES = {
	"Sun": {
		"kind": "star", "label": "Sun", "radius_km": 696340.0, "mass_earths": 333000.0,
		"pole_ra": 286.13, "pole_dec": 63.87, "rotation_hours": 609.12,
		"images": ["sun"], "color": Color(1.0, 0.8, 0.35), "label_color": Color(1.0, 0.85, 0.4),
		"facts": {
			"type": "Star", "distance": "At the center of the solar system", "diameter_km": 1392700,
			"mass": "1.99 × 10^30 kg (333,000 Earths)", "gravity": 274.0, "escape_speed": "617.7 km/s",
			"orbital_speed": "Circles the Milky Way at about 230 km/s", "day": "About 25 Earth days at its equator",
			"year": "About 230 million years to circle the Milky Way", "temperature": "About 5,500 °C at the surface",
			"moons": "8 planets and 5 dwarf planets orbit it", "sunlight": "",
			"explored": "Parker Solar Probe has flown closer to the Sun than anything else built by people.",
		},
	},
	"Mercury": {
		"kind": "planet", "label": "Mercury", "radius_km": 2439.7, "mass_earths": 0.0553,
		"orbit": {"jpl": [0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593],
			"rates": [0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081]},
		"pole_ra": 281.01, "pole_dec": 61.42, "rotation_hours": 1407.6,
		"images": ["mercury"], "color": Color(0.55, 0.53, 0.5), "label_color": Color(0.8, 0.78, 0.75),
		"facts": {
			"type": "Rocky planet, closest to the Sun", "distance": "0.39 AU (58 million km) from the Sun",
			"diameter_km": 4879, "mass": "3.30 × 10^23 kg (0.055 Earths)", "gravity": 3.7, "escape_speed": "4.3 km/s",
			"orbital_speed": "47.4 km/s, the fastest planet", "day": "58.6 Earth days to spin once (sunrise to sunrise takes 176 days)",
			"year": "88 Earth days", "temperature": "From -173 °C at night to 427 °C in the day", "moons": "0",
			"sunlight": "About 667% of Earth's", "explored": "MESSENGER orbited it from 2011 to 2015. BepiColombo is on its way.",
		},
	},
	"Venus": {
		"kind": "planet", "label": "Venus", "radius_km": 6051.8, "mass_earths": 0.815,
		"orbit": {"jpl": [0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255],
			"rates": [0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418]},
		"pole_ra": 272.76, "pole_dec": 67.16, "rotation_hours": -5832.5,
		"images": ["venus_atmosphere"], "color": Color(0.95, 0.85, 0.55), "label_color": Color(1.0, 0.9, 0.6),
		"atmosphere": [Color(1.0, 0.85, 0.55), 1.4],
		"facts": {
			"type": "Rocky planet", "distance": "0.72 AU (108 million km) from the Sun", "diameter_km": 12104,
			"mass": "4.87 × 10^24 kg (0.82 Earths)", "gravity": 8.87, "escape_speed": "10.4 km/s", "orbital_speed": "35.0 km/s",
			"day": "243 Earth days, spinning backwards", "year": "225 Earth days", "temperature": "About 464 °C, hot enough to melt lead",
			"moons": "0", "sunlight": "191% of Earth's", "explored": "Magellan mapped it with radar. The Soviet Venera landers reached the surface.",
		},
	},
	"Earth": {
		"kind": "planet", "label": "Earth", "radius_km": 6371.0, "mass_earths": 1.0,
		"orbit": {"jpl": [1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0],
			"rates": [0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0]},
		"pole_ra": 0.0, "pole_dec": 90.0, "rotation_hours": 23.934,
		"images": ["earth_daymap"], "color": Color(0.2, 0.4, 0.9), "label_color": Color(0.5, 0.75, 1.0),
		"atmosphere": [Color(0.35, 0.6, 1.0), 1.2], "clouds": ["earth_clouds"], "night_lights": ["earth_nightmap"],
		"facts": {
			"type": "Rocky planet, our home", "distance": "1.00 AU (150 million km) from the Sun", "diameter_km": 12756,
			"mass": "5.97 × 10^24 kg", "gravity": 9.81, "escape_speed": "11.2 km/s", "orbital_speed": "29.8 km/s",
			"day": "23.9 hours", "year": "365.25 days", "temperature": "About 15 °C", "moons": "1", "sunlight": "100%",
			"explored": "Every mission launches from here.",
		},
	},
	"Moon": {
		"kind": "moon", "parent": "Earth", "label": "Moon", "radius_km": 1737.4, "mass_earths": 0.0123,
		"orbit": {"moon": true}, "pole_ra": 269.99, "pole_dec": 66.54, "rotation_hours": 655.72,
		"locked": true,   # tidally locked: the same side always faces Earth
		"images": ["moon"], "color": Color(0.8, 0.8, 0.8), "label_color": Color(0.85, 0.85, 0.85),
		# Used only if 2k_moon.jpg is missing: bright highlands, dark lava "seas" and lots of craters
		"surface": {"base_color": Color(0.66, 0.64, 0.62), "second_color": Color(0.3, 0.29, 0.28), "patch_scale": 1.5, "patch_amount": 0.35,
			"crater_amount": 0.8, "crater_scale": 6.0, "bump_strength": 0.8},
		"facts": {
			"type": "Moon of Earth", "distance": "384,400 km from Earth on average", "diameter_km": 3475,
			"mass": "7.35 × 10^22 kg (0.012 Earths)", "gravity": 1.62, "escape_speed": "2.4 km/s", "orbital_speed": "1.0 km/s around Earth",
			"day": "27.3 Earth days (the same side always faces Earth)", "year": "Orbits Earth every 27.3 days",
			"temperature": "From -173 °C at night to 127 °C in the day", "moons": "0", "sunlight": "100% of Earth's",
			"explored": "Twelve Apollo astronauts walked on it between 1969 and 1972.",
		},
	},
	"Mars": {
		"kind": "planet", "label": "Mars", "radius_km": 3389.5, "mass_earths": 0.107,
		"orbit": {"jpl": [1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891],
			"rates": [0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343]},
		"pole_ra": 317.68, "pole_dec": 52.89, "rotation_hours": 24.623,
		"images": ["mars"], "color": Color(0.85, 0.35, 0.15), "label_color": Color(1.0, 0.55, 0.4),
		"atmosphere": [Color(0.95, 0.6, 0.45), 0.5],
		"facts": {
			"type": "Rocky planet", "distance": "1.52 AU (228 million km) from the Sun", "diameter_km": 6792,
			"mass": "6.42 × 10^23 kg (0.11 Earths)", "gravity": 3.71, "escape_speed": "5.0 km/s", "orbital_speed": "24.1 km/s",
			"day": "24.6 hours", "year": "687 Earth days", "temperature": "About -65 °C", "moons": "2 (Phobos and Deimos)",
			"sunlight": "43% of Earth's", "explored": "Rovers like Curiosity and Perseverance are exploring it right now.",
		},
	},
	"Ceres": {
		"kind": "dwarf", "label": "Ceres", "radius_km": 469.7, "mass_earths": 0.000157,
		"orbit": {"a": 2.77, "e": 0.0785, "i": 10.6, "node": 80.3, "arg_peri": 73.6, "mean_anomaly": 291.4, "epoch_jd": 2459600.5, "period_days": 1680.0},
		"pole_ra": 291.42, "pole_dec": 66.76, "rotation_hours": 9.074,
		"images": ["ceres", "ceres_fictional"], "color": Color(0.45, 0.43, 0.42), "label_color": Color(0.75, 0.75, 0.72),
		"facts": {
			"type": "Dwarf planet, the largest object in the asteroid belt", "distance": "2.77 AU (414 million km) from the Sun",
			"diameter_km": 939, "mass": "9.38 × 10^20 kg (0.00016 Earths)", "gravity": 0.28, "escape_speed": "0.52 km/s",
			"orbital_speed": "17.9 km/s", "day": "9.1 hours", "year": "4.6 Earth years", "temperature": "About -100 °C",
			"moons": "0", "sunlight": "13% of Earth's", "explored": "NASA's Dawn orbited it from 2015 to 2018 and found bright salt deposits.",
		},
	},
	"Jupiter": {
		"kind": "planet", "label": "Jupiter", "radius_km": 69911.0, "mass_earths": 317.8,
		"orbit": {"jpl": [5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909],
			"rates": [-0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106]},
		"pole_ra": 268.06, "pole_dec": 64.50, "rotation_hours": 9.925,
		"images": ["jupiter"], "color": Color(0.85, 0.65, 0.45), "label_color": Color(0.95, 0.8, 0.6),
		"atmosphere": [Color(0.95, 0.85, 0.7), 0.45], "rings": "jupiter",
		"facts": {
			"type": "Gas giant, the biggest planet", "distance": "5.20 AU (778 million km) from the Sun", "diameter_km": 142984,
			"mass": "1.90 × 10^27 kg (318 Earths)", "gravity": 24.8, "escape_speed": "59.5 km/s", "orbital_speed": "13.1 km/s",
			"day": "9.9 hours, the shortest of any planet", "year": "11.9 Earth years", "temperature": "About -110 °C at the cloud tops",
			"moons": "More than 90 known", "sunlight": "4% of Earth's", "explored": "Juno has orbited it since 2016. Europa Clipper is on its way.",
		},
	},
	"Saturn": {
		"kind": "planet", "label": "Saturn", "radius_km": 58232.0, "mass_earths": 95.2,
		"orbit": {"jpl": [9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448],
			"rates": [-0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794]},
		"pole_ra": 40.59, "pole_dec": 83.54, "rotation_hours": 10.656,
		"images": ["saturn"], "color": Color(0.9, 0.8, 0.55), "label_color": Color(0.95, 0.88, 0.65),
		"atmosphere": [Color(0.95, 0.88, 0.7), 0.45], "rings": "saturn",
		"facts": {
			"type": "Gas giant with the brightest rings", "distance": "9.54 AU (1.43 billion km) from the Sun", "diameter_km": 120536,
			"mass": "5.68 × 10^26 kg (95 Earths)", "gravity": 10.4, "escape_speed": "35.5 km/s", "orbital_speed": "9.7 km/s",
			"day": "10.7 hours", "year": "29.4 Earth years", "temperature": "About -140 °C at the cloud tops",
			"moons": "More than 270 known, including Titan", "sunlight": "1% of Earth's", "explored": "Cassini orbited it from 2004 to 2017.",
		},
	},
	"Uranus": {
		"kind": "planet", "label": "Uranus", "radius_km": 25362.0, "mass_earths": 14.5,
		"orbit": {"jpl": [19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503],
			"rates": [-0.00196176, -0.00004397, -0.00242939, 428.48202785, 0.40805281, 0.04240589]},
		"pole_ra": 257.31, "pole_dec": -15.18, "rotation_hours": -17.24,
		"images": ["uranus"], "color": Color(0.62, 0.85, 0.9), "label_color": Color(0.65, 0.9, 0.95),
		"atmosphere": [Color(0.6, 0.9, 1.0), 0.6], "rings": "uranus",
		"facts": {
			"type": "Ice giant that rolls around the Sun on its side", "distance": "19.2 AU (2.87 billion km) from the Sun",
			"diameter_km": 51118, "mass": "8.68 × 10^25 kg (14.5 Earths)", "gravity": 8.87, "escape_speed": "21.3 km/s",
			"orbital_speed": "6.8 km/s", "day": "17.2 hours, spinning backwards, tipped over 98°", "year": "84 Earth years",
			"temperature": "About -195 °C", "moons": "28 or more known", "sunlight": "0.27% of Earth's",
			"explored": "Only Voyager 2 has visited, in 1986.",
		},
	},
	"Neptune": {
		"kind": "planet", "label": "Neptune", "radius_km": 24622.0, "mass_earths": 17.1,
		"orbit": {"jpl": [30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574],
			"rates": [0.00026291, 0.00005105, 0.00035372, 218.45945325, -0.32241464, -0.00508664]},
		"pole_ra": 299.36, "pole_dec": 43.46, "rotation_hours": 16.11,
		"images": ["neptune"], "color": Color(0.3, 0.45, 0.9), "label_color": Color(0.5, 0.65, 1.0),
		"atmosphere": [Color(0.4, 0.6, 1.0), 0.6], "rings": "neptune",
		"facts": {
			"type": "Ice giant, the farthest planet", "distance": "30.1 AU (4.5 billion km) from the Sun", "diameter_km": 49528,
			"mass": "1.02 × 10^26 kg (17.1 Earths)", "gravity": 11.15, "escape_speed": "23.5 km/s", "orbital_speed": "5.4 km/s",
			"day": "16.1 hours", "year": "165 Earth years", "temperature": "About -200 °C, with the fastest winds of any planet",
			"moons": "16 known, including Triton", "sunlight": "0.11% of Earth's", "explored": "Only Voyager 2 has visited, in 1989.",
		},
	},
	"Pluto": {
		"kind": "dwarf", "label": "Pluto", "radius_km": 1188.3, "mass_earths": 0.00218,
		"orbit": {"jpl": [39.48211675, 0.24882730, 17.14001206, 238.92903833, 224.06891629, 110.30393684],
			"rates": [-0.00031596, 0.00005170, 0.00004818, 145.20780515, -0.04062942, -0.01183482]},
		"pole_ra": 132.99, "pole_dec": -6.16, "rotation_hours": 153.29,
		"images": ["pluto"], "color": Color(0.82, 0.72, 0.6), "label_color": Color(0.9, 0.8, 0.7),
		"atmosphere": [Color(0.5, 0.7, 1.0), 0.25],
		"facts": {
			"type": "Dwarf planet in the Kuiper belt", "distance": "39.5 AU on average (from 30 to 49 AU)", "diameter_km": 2377,
			"mass": "1.30 × 10^22 kg (0.0022 Earths)", "gravity": 0.62, "escape_speed": "1.2 km/s", "orbital_speed": "4.7 km/s",
			"day": "6.4 Earth days, spinning backwards", "year": "248 Earth years", "temperature": "About -230 °C",
			"moons": "5 (Charon, Nix, Hydra, Kerberos and Styx)", "sunlight": "About 0.06% of Earth's",
			"explored": "New Horizons flew past in 2015 and found a giant heart-shaped plain of nitrogen ice.",
		},
	},
	"Haumea": {
		"kind": "dwarf", "label": "Haumea", "radius_km": 772.0, "mass_earths": 0.00066,
		"orbit": {"a": 43.116, "e": 0.19642, "i": 28.2137, "node": 122.167, "arg_peri": 239.041, "mean_anomaly": 218.205, "epoch_jd": 2459200.5, "period_days": 103410.0},
		"tilt": 81.2, "tilt_toward": 150.0, "rotation_hours": 3.915,
		# Haumea is shaped like a squashed egg, about 2,122 x 1,036 (pole to pole) x 1,688 km
		"shape": Vector3(1.366, 0.669, 1.093), "rings": "haumea",
		"images": ["haumea", "haumea_fictional"], "color": Color(0.88, 0.88, 0.9), "label_color": Color(0.85, 0.88, 0.95),
		"facts": {
			"type": "Egg-shaped dwarf planet in the Kuiper belt", "distance": "43 AU on average (from 35 to 52 AU)",
			"diameter_km": 1544, "mass": "3.95 × 10^21 kg (0.00066 Earths)", "gravity": 0.44,
			"gravity_note": "from 0.24 m/s² at its long ends to 0.93 m/s² at its poles", "escape_speed": "0.7 to 1.0 km/s",
			"orbital_speed": "4.5 km/s", "day": "3.9 hours, the fastest spin of any large body in the solar system",
			"year": "283 Earth years", "temperature": "Below -223 °C", "moons": "2 (Hiʻiaka and Namaka), plus a thin ring",
			"sunlight": "About 0.05% of Earth's", "explored": "Never visited. Its shape comes from how its brightness changes as it spins.",
		},
	},
	"Makemake": {
		"kind": "dwarf", "label": "Makemake", "radius_km": 715.0, "mass_earths": 0.00045,
		"orbit": {"a": 45.499, "e": 0.1604, "i": 29.002, "node": 79.441, "arg_peri": 296.065, "mean_anomaly": 170.497, "epoch_jd": 2461000.5, "period_days": 112022.0},
		"tilt": 75.0, "tilt_toward": 40.0, "rotation_hours": 22.83,
		"images": ["makemake", "makemake_fictional"], "color": Color(0.78, 0.55, 0.45), "label_color": Color(0.95, 0.7, 0.6),
		"facts": {
			"type": "Dwarf planet in the Kuiper belt", "distance": "45.5 AU on average (from 38 to 53 AU)", "diameter_km": 1430,
			"mass": "About 2.7 × 10^21 kg (0.00045 Earths)", "gravity": 0.35, "escape_speed": "0.71 km/s", "orbital_speed": "4.4 km/s",
			"day": "22.8 hours", "year": "307 Earth years", "temperature": "About -238 °C", "moons": "1", "sunlight": "About 0.05% of Earth's",
			"explored": "Never visited. Its reddish color comes from frozen methane.",
		},
	},
	"Eris": {
		"kind": "dwarf", "label": "Eris", "radius_km": 1163.0, "mass_earths": 0.00276,
		"orbit": {"a": 68.15, "e": 0.4323, "i": 43.74, "node": 36.08, "arg_peri": 150.87, "mean_anomaly": 209.4, "epoch_jd": 2460200.5, "period_days": 206000.0},
		"tilt": 78.0, "tilt_toward": 300.0, "rotation_hours": 378.9,
		"images": ["eris", "eris_fictional"], "color": Color(0.93, 0.93, 0.93), "label_color": Color(0.92, 0.92, 0.95),
		"facts": {
			"type": "Dwarf planet in the scattered disk, heavier than Pluto", "distance": "68 AU on average (from 38.7 to 97.6 AU). It's near its farthest point now.",
			"diameter_km": 2326, "mass": "1.66 × 10^22 kg (0.0028 Earths)", "gravity": 0.82, "escape_speed": "1.4 km/s",
			"orbital_speed": "3.4 km/s", "day": "About 15.8 Earth days, locked facing its moon", "year": "About 560 Earth years",
			"temperature": "About -243 °C", "moons": "1 (Dysnomia)", "sunlight": "About 0.02% of Earth's",
			"explored": "Never visited. Its discovery in 2005 led to Pluto being renamed a dwarf planet.",
		},
	},

	# ===================================================================== MOONS
	"Phobos": {
		"kind": "moon", "parent": "Mars", "label": "Phobos", "radius_km": 11.08, "mass_earths": 1.79e-9,
		"orbit": {"satellite": {"a_km": 9375.0, "e": 0.015, "i": 1.1, "node": 169.2, "arg_peri": 216.3, "mean_anomaly": 189.7,
			"degrees_per_day": 360.0 / 0.31891023, "apsis_degrees_per_day": 360.0 / (1.1 * 365.25), "node_degrees_per_day": -360.0 / (2.3 * 365.25),
			"pole_ra": 317.7, "pole_dec": 52.9, "parent_gm": 42828.37}},
		"locked": true, "rotation_hours": 7.654, "irregular": true,
		# About 27 x 22 x 18 km: the long end always points at Mars (local -z), the short axis is the pole
		"shape": Vector3(1.03, 0.82, 1.17),
		"images": ["phobos"], "color": Color(0.33, 0.3, 0.28), "label_color": Color(0.85, 0.7, 0.62),
		"surface": {"base_color": Color(0.2, 0.18, 0.17), "second_color": Color(0.15, 0.14, 0.13), "patch_scale": 2.0, "patch_amount": 0.5,
			"crater_amount": 1.0, "crater_scale": 3.5, "crack_amount": 0.5, "crack_color": Color(0.11, 0.1, 0.1), "crack_scale": 2.2, "bump_strength": 1.2},
		"facts": {
			"type": "Moon of Mars, a dark, potato-shaped rock", "distance": "9,376 km from Mars' center, only about 6,000 km above its surface",
			"diameter_km": 22, "mass": "1.07 × 10^16 kg", "gravity": 0.0057, "escape_speed": "11 m/s (you could throw a ball into space)",
			"orbital_speed": "2.1 km/s", "day": "7.7 hours, always showing Mars the same face",
			"year": "Orbits Mars every 7 hours 39 minutes, so it rises in the west 2 or 3 times a day", "temperature": "From about -112 °C to -4 °C",
			"sunlight": "43% of Earth's",
			"explored": "Viking, Phobos 2 and Mars Express have photographed it up close. Japan's MMX mission is designed to land and bring a sample home.",
		},
	},
	"Deimos": {
		"kind": "moon", "parent": "Mars", "label": "Deimos", "radius_km": 6.2, "mass_earths": 2.47e-10,
		"orbit": {"satellite": {"a_km": 23457.0, "e": 0.0002, "i": 1.8, "node": 54.3, "arg_peri": 0.0, "mean_anomaly": 205.0,
			"degrees_per_day": 360.0 / 1.2624407, "node_degrees_per_day": -360.0 / (56.2 * 365.25),
			"pole_ra": 316.6, "pole_dec": 53.5, "parent_gm": 42828.37}},
		"locked": true, "rotation_hours": 30.3, "irregular": true,
		"shape": Vector3(0.97, 0.82, 1.26),
		"images": ["deimos"], "color": Color(0.4, 0.37, 0.34), "label_color": Color(0.85, 0.75, 0.68),
		"surface": {"base_color": Color(0.26, 0.24, 0.22), "second_color": Color(0.22, 0.2, 0.19), "patch_scale": 1.6, "patch_amount": 0.4,
			"crater_amount": 0.35, "crater_scale": 4.5, "bump_strength": 0.6},
		"facts": {
			"type": "Moon of Mars, small and smooth under deep dust", "distance": "23,460 km from Mars' center",
			"diameter_km": 12, "mass": "1.48 × 10^15 kg", "gravity": 0.003, "escape_speed": "5.6 m/s (a fast run would launch you into space)",
			"orbital_speed": "1.35 km/s", "day": "30.3 hours, always showing Mars the same face", "year": "Orbits Mars every 30.3 hours",
			"temperature": "About -40 °C", "sunlight": "43% of Earth's",
			"explored": "Viking 2 flew within 30 km of it in 1977. The UAE's Hope orbiter took close-up pictures in 2023.",
		},
	},
	"Io": {
		"kind": "moon", "parent": "Jupiter", "label": "Io", "radius_km": 1821.6, "mass_earths": 0.01496,
		"orbit": {"satellite": {"a_km": 421800.0, "e": 0.004, "i": 0.0, "node": 0.0, "arg_peri": 49.1, "mean_anomaly": 330.9,
			"degrees_per_day": 203.488955790, "apsis_degrees_per_day": -0.7395,
			"pole_ra": 268.1, "pole_dec": 64.5, "parent_gm": 126686534.0}},
		"locked": true, "rotation_hours": 42.459,
		"images": ["io"], "color": Color(0.92, 0.82, 0.45), "label_color": Color(1.0, 0.9, 0.5),
		"surface": {"base_color": Color(0.88, 0.76, 0.36), "second_color": Color(0.8, 0.52, 0.24), "patch_scale": 2.5, "patch_amount": 0.75,
			"spot_amount": 0.9, "spot_color": Color(0.12, 0.07, 0.05), "spot_scale": 9.0,
			"cap_amount": 0.55, "cap_color": Color(0.55, 0.36, 0.24), "cap_side": 0.0, "cap_size": 0.72, "bump_strength": 0.4},
		"facts": {
			"type": "Moon of Jupiter, the most volcanic world in the solar system", "distance": "421,700 km from Jupiter",
			"diameter_km": 3643, "mass": "8.93 × 10^22 kg (0.015 Earths)", "gravity": 1.8, "escape_speed": "2.6 km/s",
			"orbital_speed": "17.3 km/s", "day": "42.5 hours, always showing Jupiter the same face", "year": "Orbits Jupiter every 1.77 days",
			"temperature": "About -130 °C, but lava reaches 1,600 °C", "sunlight": "3.7% of Earth's",
			"explored": "Galileo studied it from 1995 to 2003. Juno flew just 1,500 km above it in 2023 and 2024.",
		},
	},
	"Europa": {
		"kind": "moon", "parent": "Jupiter", "label": "Europa", "radius_km": 1560.8, "mass_earths": 0.008035,
		"orbit": {"satellite": {"a_km": 671100.0, "e": 0.009, "i": 0.5, "node": 184.0, "arg_peri": 45.0, "mean_anomaly": 345.4,
			"degrees_per_day": 101.374724735, "apsis_degrees_per_day": -0.7395, "node_degrees_per_day": -360.0 / (30.202 * 365.25),
			"pole_ra": 268.1, "pole_dec": 64.5, "parent_gm": 126686534.0}},
		"locked": true, "rotation_hours": 85.228,
		"images": ["europa"], "color": Color(0.85, 0.8, 0.72), "label_color": Color(0.9, 0.85, 0.75),
		"surface": {"base_color": Color(0.87, 0.83, 0.76), "second_color": Color(0.72, 0.6, 0.47), "patch_scale": 3.0, "patch_amount": 0.5,
			"crack_amount": 1.0, "crack_color": Color(0.55, 0.32, 0.2), "crack_scale": 2.2,
			"spot_amount": 0.45, "spot_color": Color(0.62, 0.45, 0.32), "spot_scale": 4.0, "crater_amount": 0.05, "bump_strength": 0.4},
		"facts": {
			"type": "Moon of Jupiter with an ocean under its ice", "distance": "671,100 km from Jupiter",
			"diameter_km": 3122, "mass": "4.80 × 10^22 kg (0.008 Earths)", "gravity": 1.31, "escape_speed": "2.0 km/s",
			"orbital_speed": "13.7 km/s", "day": "3.55 Earth days, always showing Jupiter the same face", "year": "Orbits Jupiter every 3.55 days",
			"temperature": "From about -160 °C at the equator to -220 °C at the poles", "sunlight": "3.7% of Earth's",
			"explored": "Galileo found signs of its ocean. NASA's Europa Clipper launched in 2024 and arrives in 2030.",
		},
	},
	"Ganymede": {
		"kind": "moon", "parent": "Jupiter", "label": "Ganymede", "radius_km": 2634.1, "mass_earths": 0.0248,
		"orbit": {"satellite": {"a_km": 1070400.0, "e": 0.001, "i": 0.2, "node": 58.5, "arg_peri": 198.3, "mean_anomaly": 324.8,
			"degrees_per_day": 50.317609207, "apsis_degrees_per_day": 360.0 / (68.301 * 365.25), "node_degrees_per_day": -360.0 / (137.812 * 365.25),
			"pole_ra": 268.2, "pole_dec": 64.6, "parent_gm": 126686534.0}},
		"locked": true, "rotation_hours": 171.71,
		"images": ["ganymede"], "color": Color(0.5, 0.46, 0.42), "label_color": Color(0.8, 0.76, 0.7),
		"surface": {"base_color": Color(0.56, 0.51, 0.46), "second_color": Color(0.3, 0.27, 0.24), "patch_scale": 1.6, "patch_amount": 0.9,
			"crater_amount": 0.5, "crater_scale": 5.0, "crack_amount": 0.35, "crack_color": Color(0.66, 0.63, 0.58), "crack_scale": 4.0,
			"cap_amount": 0.6, "cap_color": Color(0.8, 0.8, 0.83), "cap_side": 0.0, "cap_size": 0.8, "bump_strength": 0.7},
		"facts": {
			"type": "Moon of Jupiter, the biggest moon in the solar system", "distance": "1,070,400 km from Jupiter",
			"diameter_km": 5268, "mass": "1.48 × 10^23 kg (0.025 Earths)", "gravity": 1.43, "escape_speed": "2.7 km/s",
			"orbital_speed": "10.9 km/s", "day": "7.15 Earth days, always showing Jupiter the same face", "year": "Orbits Jupiter every 7.15 days",
			"temperature": "About -160 °C", "sunlight": "3.7% of Earth's",
			"explored": "Galileo found its magnetic field in 1996. ESA's JUICE is set to orbit it from 2034, the first spacecraft to orbit another planet's moon.",
		},
	},
	"Callisto": {
		"kind": "moon", "parent": "Jupiter", "label": "Callisto", "radius_km": 2410.3, "mass_earths": 0.01803,
		"orbit": {"satellite": {"a_km": 1882700.0, "e": 0.007, "i": 0.3, "node": 309.1, "arg_peri": 43.8, "mean_anomaly": 87.4,
			"degrees_per_day": 21.571071177, "apsis_degrees_per_day": 360.0 / (277.921 * 365.25), "node_degrees_per_day": -360.0 / (577.264 * 365.25),
			"pole_ra": 268.7, "pole_dec": 64.8, "parent_gm": 126686534.0}},
		"locked": true, "rotation_hours": 400.54,
		"images": ["callisto"], "color": Color(0.32, 0.29, 0.26), "label_color": Color(0.75, 0.7, 0.65),
		"surface": {"base_color": Color(0.3, 0.27, 0.24), "second_color": Color(0.38, 0.34, 0.3), "patch_scale": 2.0, "patch_amount": 0.6,
			"crater_amount": 1.3, "crater_scale": 7.0, "spot_amount": 0.3, "spot_color": Color(0.72, 0.69, 0.65), "spot_scale": 22.0, "bump_strength": 1.0},
		"facts": {
			"type": "Moon of Jupiter, the most heavily cratered world known", "distance": "1,882,700 km from Jupiter",
			"diameter_km": 4821, "mass": "1.08 × 10^23 kg (0.018 Earths)", "gravity": 1.24, "escape_speed": "2.4 km/s",
			"orbital_speed": "8.2 km/s", "day": "16.7 Earth days, always showing Jupiter the same face", "year": "Orbits Jupiter every 16.7 days",
			"temperature": "About -140 °C", "sunlight": "3.7% of Earth's",
			"explored": "Galileo flew past it many times and found hints of a hidden ocean. It's far enough from Jupiter's radiation that NASA has studied it as a future human base.",
		},
	},
	"Enceladus": {
		"kind": "moon", "parent": "Saturn", "label": "Enceladus", "radius_km": 252.1, "mass_earths": 1.81e-5,
		"orbit": {"satellite": {"a_km": 238400.0, "e": 0.005, "i": 0.0, "node": 0.0, "arg_peri": 119.5, "mean_anomaly": 57.0,
			"degrees_per_day": 360.0 / 1.370218, "apsis_degrees_per_day": 360.0 / (2.916 * 365.25),
			"pole_ra": 40.6, "pole_dec": 83.5, "parent_gm": 37931207.0}},
		"locked": true, "rotation_hours": 32.885, "plumes": true,
		"images": ["enceladus"], "color": Color(0.95, 0.96, 0.98), "label_color": Color(0.85, 0.92, 1.0),
		"surface": {"base_color": Color(0.95, 0.96, 0.98), "second_color": Color(0.86, 0.89, 0.93), "patch_scale": 2.0, "patch_amount": 0.4,
			"crater_amount": 0.45, "crater_scale": 6.0, "crack_amount": 0.4, "crack_color": Color(0.78, 0.85, 0.93), "crack_scale": 3.0,
			"stripe_amount": 1.0, "stripe_color": Color(0.5, 0.65, 0.85), "bump_strength": 0.6},
		"facts": {
			"type": "Moon of Saturn, shooting water out of its south pole", "distance": "238,000 km from Saturn",
			"diameter_km": 504, "mass": "1.08 × 10^20 kg", "gravity": 0.113, "escape_speed": "0.24 km/s",
			"orbital_speed": "12.6 km/s", "day": "1.37 Earth days, always showing Saturn the same face", "year": "Orbits Saturn every 1.37 days",
			"temperature": "About -200 °C, but the tiger stripes are much warmer", "sunlight": "1.1% of Earth's",
			"explored": "Cassini flew through its plumes several times, as low as 49 km above the surface, and found salty water, hydrogen and organic molecules.",
		},
	},
	"Titan": {
		"kind": "moon", "parent": "Saturn", "label": "Titan", "radius_km": 2574.7, "mass_earths": 0.02252,
		"orbit": {"satellite": {"a_km": 1221900.0, "e": 0.029, "i": 0.3, "node": 78.6, "arg_peri": 78.3, "mean_anomaly": 11.7,
			"degrees_per_day": 360.0 / 15.945421, "apsis_degrees_per_day": 360.0 / (346.68 * 365.25), "node_degrees_per_day": -360.0 / (687.37 * 365.25),
			"pole_ra": 36.4, "pole_dec": 84.0, "parent_gm": 37931207.0}},
		"locked": true, "rotation_hours": 382.69,
		"images": ["titan"], "color": Color(0.85, 0.58, 0.25), "label_color": Color(1.0, 0.75, 0.4),
		"atmosphere": [Color(1.0, 0.62, 0.22), 1.8],
		"surface": {"base_color": Color(0.86, 0.57, 0.24), "second_color": Color(0.7, 0.45, 0.19), "patch_scale": 2.0, "patch_amount": 0.5,
			"haze_amount": 0.85, "bump_strength": 0.0},
		"facts": {
			"type": "Moon of Saturn, the only moon with a thick atmosphere", "distance": "1,221,900 km from Saturn",
			"diameter_km": 5150, "mass": "1.35 × 10^23 kg (0.023 Earths)", "gravity": 1.35, "escape_speed": "2.6 km/s",
			"orbital_speed": "5.6 km/s", "day": "16 Earth days, always showing Saturn the same face", "year": "Orbits Saturn every 15.9 days",
			"temperature": "About -179 °C, with methane rain and lakes", "sunlight": "1.1% of Earth's",
			"explored": "ESA's Huygens parachuted onto it in 2005. NASA's Dragonfly drone is planned to launch in 2028.",
		},
	},
	"Titania": {
		"kind": "moon", "parent": "Uranus", "label": "Titania", "radius_km": 788.4, "mass_earths": 0.00057,
		"orbit": {"satellite": {"a_km": 436298.0, "e": 0.002, "i": 0.1, "node": 29.5, "arg_peri": 184.0, "mean_anomaly": 68.1,
			"degrees_per_day": 360.0 / 8.7058717, "apsis_degrees_per_day": 360.0 / (579.928 * 365.25), "node_degrees_per_day": -360.0 / (1644.649 * 365.25),
			"pole_ra": 257.311, "pole_dec": -15.175, "parent_gm": 5793951.0}},
		"locked": true, "rotation_hours": 208.94,
		"images": ["titania"], "color": Color(0.5, 0.48, 0.47), "label_color": Color(0.75, 0.85, 0.88),
		"surface": {"base_color": Color(0.53, 0.51, 0.5), "second_color": Color(0.4, 0.38, 0.37), "patch_scale": 2.0, "patch_amount": 0.6,
			"crater_amount": 0.8, "crater_scale": 6.0, "crack_amount": 0.6, "crack_color": Color(0.28, 0.27, 0.27), "crack_scale": 1.8, "bump_strength": 0.8},
		"facts": {
			"type": "Moon of Uranus, its biggest", "distance": "436,300 km from Uranus",
			"diameter_km": 1577, "mass": "3.4 × 10^21 kg (0.0006 Earths)", "gravity": 0.38, "escape_speed": "0.77 km/s",
			"orbital_speed": "3.6 km/s", "day": "8.7 Earth days, always showing Uranus the same face", "year": "Orbits Uranus every 8.7 days",
			"temperature": "About -200 °C", "sunlight": "0.27% of Earth's",
			"explored": "Only Voyager 2 has visited, in 1986, and it photographed less than half of Titania.",
		},
	},
	"Triton": {
		"kind": "moon", "parent": "Neptune", "label": "Triton", "radius_km": 1353.4, "mass_earths": 0.00358,
		"orbit": {"satellite": {"a_km": 354800.0, "e": 0.0, "i": 157.3, "node": 177.7, "arg_peri": 0.0, "mean_anomaly": 63.0,
			"degrees_per_day": 360.0 / 5.876854, "node_degrees_per_day": 360.0 / (299.4 * 365.25),
			"pole_ra": 299.36, "pole_dec": 43.46, "parent_gm": 6835100.0}},
		"locked": true, "rotation_hours": 141.04,
		"images": ["triton"], "color": Color(0.78, 0.74, 0.72), "label_color": Color(0.85, 0.85, 1.0),
		"atmosphere": [Color(0.6, 0.75, 1.0), 0.2],
		"surface": {"base_color": Color(0.74, 0.72, 0.7), "second_color": Color(0.86, 0.77, 0.73), "patch_scale": 2.0, "patch_amount": 0.6,
			"cell_amount": 0.8, "cap_amount": 0.9, "cap_color": Color(0.93, 0.8, 0.76), "cap_side": -1.0, "cap_size": 0.2,
			"spot_amount": 0.3, "spot_color": Color(0.36, 0.31, 0.29), "spot_scale": 9.0, "crater_amount": 0.1, "bump_strength": 0.6},
		"facts": {
			"type": "Moon of Neptune that orbits backwards, probably a captured Kuiper belt world", "distance": "354,800 km from Neptune",
			"diameter_km": 2707, "mass": "2.14 × 10^22 kg (0.0036 Earths)", "gravity": 0.78, "escape_speed": "1.5 km/s",
			"orbital_speed": "4.4 km/s, backwards", "day": "5.9 Earth days, always showing Neptune the same face",
			"year": "Orbits Neptune every 5.9 days, the opposite way to Neptune's spin", "temperature": "About -235 °C, one of the coldest surfaces ever measured",
			"sunlight": "0.11% of Earth's",
			"explored": "Only Voyager 2 has visited, in 1989. It saw geysers of nitrogen shooting 8 km high.",
		},
	},
	"Charon": {
		"kind": "moon", "parent": "Pluto", "label": "Charon", "radius_km": 606.0, "mass_earths": 0.000266,
		# Pluto and Charon always face each other: Pluto's longitude 0 is defined as the side facing Charon
		"orbit": {"satellite": {"a_km": 19596.0, "e": 0.0, "i": 0.0, "node": 0.0, "arg_peri": 0.0, "mean_anomaly": 302.695,
			"degrees_per_day": 56.3625225, "pole_ra": 132.993, "pole_dec": -6.163, "parent_gm": 975.5}},
		"locked": true, "rotation_hours": 153.29,
		"images": ["charon"], "color": Color(0.55, 0.53, 0.52), "label_color": Color(0.82, 0.78, 0.75),
		"surface": {"base_color": Color(0.56, 0.54, 0.53), "second_color": Color(0.46, 0.45, 0.45), "patch_scale": 2.0, "patch_amount": 0.5,
			"crater_amount": 0.5, "crater_scale": 6.0, "crack_amount": 0.5, "crack_color": Color(0.35, 0.34, 0.34), "crack_scale": 1.5,
			"cap_amount": 0.85, "cap_color": Color(0.46, 0.26, 0.18), "cap_side": 1.0, "cap_size": 0.82, "bump_strength": 0.7},
		"facts": {
			"type": "Moon of Pluto, so big the two are almost a double planet", "distance": "19,600 km from Pluto",
			"diameter_km": 1212, "mass": "1.59 × 10^21 kg (0.0003 Earths)", "gravity": 0.29, "escape_speed": "0.59 km/s",
			"orbital_speed": "0.2 km/s", "day": "6.4 Earth days. Charon and Pluto always show each other the same face",
			"year": "Orbits Pluto every 6.4 days", "temperature": "About -220 °C", "sunlight": "About 0.06% of Earth's",
			"explored": "Only New Horizons has visited, flying past in July 2015.",
		},
	},
	"Halley": {
		"kind": "comet", "label": "Halley's Comet", "radius_km": 5.5, "mass_earths": 0.0,
		"orbit": {"a": 17.86, "e": 0.96714, "i": 162.26, "node": 58.42, "arg_peri": 111.33, "mean_anomaly": 0.0, "epoch_jd": 2446470.96, "period_days": 27510.0},
		"tilt": 30.0, "tilt_toward": 0.0, "rotation_hours": 52.8,
		"images": [], "color": Color(0.25, 0.24, 0.23), "label_color": Color(0.7, 0.9, 1.0),
		"facts": {
			"type": "Comet. It orbits backwards compared with the planets.", "distance": "From 0.59 AU to 35 AU from the Sun",
			"diameter_km": 11, "mass": "About 2.2 × 10^14 kg", "gravity": 0.0003, "escape_speed": "About 2 m/s",
			"orbital_speed": "From about 1 km/s far away to 55 km/s near the Sun", "day": "About 2.2 Earth days",
			"year": "About 76 Earth years. Next closest to the Sun in July 2061.", "temperature": "Changes hugely with distance from the Sun",
			"moons": "0", "sunlight": "", "explored": "The Giotto spacecraft flew past its icy core in 1986.",
		},
	},
	"Encke": {
		"kind": "comet", "label": "Comet Encke", "radius_km": 2.4, "mass_earths": 0.0,
		"orbit": {"a": 2.215, "e": 0.8483, "i": 11.78, "node": 334.57, "arg_peri": 186.54, "mean_anomaly": 0.0, "epoch_jd": 2460239.5, "period_days": 1204.0},
		"tilt": 20.0, "tilt_toward": 90.0, "rotation_hours": 11.0,
		"images": [], "color": Color(0.22, 0.22, 0.22), "label_color": Color(0.7, 0.9, 1.0),
		"facts": {
			"type": "Comet with the shortest known orbit", "distance": "From 0.34 AU to 4.1 AU from the Sun", "diameter_km": 4.8,
			"mass": "Unknown, likely a few trillion tonnes", "gravity": 0.0002, "escape_speed": "About 1 m/s",
			"orbital_speed": "Fastest near the Sun", "day": "About 11 hours", "year": "3.3 Earth years", "temperature": "Changes hugely with distance from the Sun",
			"moons": "0", "sunlight": "", "explored": "Its dust causes the Taurid meteor shower every autumn.",
		},
	},
	"67P": {
		"kind": "comet", "label": "Comet 67P", "radius_km": 2.0, "mass_earths": 0.0,
		"orbit": {"a": 3.46, "e": 0.6405, "i": 7.04, "node": 50.14, "arg_peri": 12.78, "mean_anomaly": 0.0, "epoch_jd": 2459520.5, "period_days": 2352.0},
		"tilt": 52.0, "tilt_toward": 200.0, "rotation_hours": 12.4,
		"images": [], "color": Color(0.2, 0.2, 0.2), "label_color": Color(0.7, 0.9, 1.0),
		"facts": {
			"type": "Comet shaped like a rubber duck", "distance": "From 1.2 AU to 5.7 AU from the Sun", "diameter_km": 4.1,
			"mass": "1.0 × 10^13 kg", "gravity": 0.0002, "escape_speed": "About 1 m/s", "orbital_speed": "Fastest near the Sun",
			"day": "12.4 hours", "year": "6.4 Earth years", "temperature": "Changes hugely with distance from the Sun", "moons": "0", "sunlight": "",
			"explored": "ESA's Rosetta orbited it from 2014 to 2016, and its Philae lander touched down on it.",
		},
	},
	"Hale-Bopp": {
		"kind": "comet", "label": "Comet Hale-Bopp", "radius_km": 30.0, "mass_earths": 0.0,
		"orbit": {"a": 186.0, "e": 0.9951, "i": 89.43, "node": 282.47, "arg_peri": 130.59, "mean_anomaly": 0.0, "epoch_jd": 2450539.6, "period_days": 927000.0},
		"tilt": 40.0, "tilt_toward": 270.0, "rotation_hours": 11.4,
		"images": [], "color": Color(0.24, 0.23, 0.22), "label_color": Color(0.7, 0.9, 1.0),
		"facts": {
			"type": "Comet, the Great Comet of 1997", "distance": "From 0.91 AU to about 370 AU from the Sun", "diameter_km": 60,
			"mass": "Unknown, one of the biggest comet cores known", "gravity": 0.003, "escape_speed": "A few m/s",
			"orbital_speed": "Fastest near the Sun", "day": "About 11.4 hours", "year": "About 2,500 Earth years",
			"temperature": "Changes hugely with distance from the Sun", "moons": "0", "sunlight": "",
			"explored": "Seen with the naked eye for a record 18 months in 1996 and 1997.",
		},
	},

	# -----------------------------------------------------------------------
	# Spacecraft
	# -----------------------------------------------------------------------
	"Voyager 1": {
		"kind": "spacecraft", "label": "Voyager 1", "radius_km": 0.0066, "mass_earths": 0.0, "rotation_hours": 24.0,
		"images": [], "color": Color(0.85, 0.7, 0.4), "label_color": Color(1.0, 0.78, 0.35),
		"model_file": "voyager.glb", "faces": "+y", "faces_toward": "earth", "shown_from": 2443392.03889,
		"route": [
			[2443392.03889, "Earth"],      # launch, Sep 5, 1977 12:56 UTC
			[2443938.00377, "Jupiter"],    # Mar 5, 1979 12:05 UTC
			[2444556.49063, "Saturn"],     # Nov 12, 1980 23:46 UTC
			[2461356.49794, [17.26667, 12.08333, 173.102]],   # Nov 11, 2026: RA 17h 16m, Dec +12° 05', 173.102 AU from Earth
		],
		"facts": {
			"type": "Spacecraft. The farthest object people have ever built.",
			"launched": "September 5, 1977, on a Titan IIIE rocket from Cape Canaveral",
			"mission": "Flew past Jupiter in March 1979 and Saturn in November 1980, with a close look at Titan. It crossed the heliopause into interstellar space on August 25, 2012.",
			"size": "3.7 m dish antenna and a 13 m long magnetometer boom",
			"mass": "About 826 kg at launch",
			"power": "Three nuclear batteries (RTGs). Their power drops about 4 watts a year, so instruments are being switched off one by one.",
			"status": "Still sending data home with a few instruments left on.",
			"did_you_know": "It reaches one light-day from Earth on November 18, 2026: a radio message takes a full 24 hours to get there. It carries the Golden Record, with sounds and pictures of Earth.",
		},
	},
	"Voyager 2": {
		"kind": "spacecraft", "label": "Voyager 2", "radius_km": 0.0066, "mass_earths": 0.0, "rotation_hours": 24.0,
		"images": [], "color": Color(0.85, 0.7, 0.4), "label_color": Color(1.0, 0.78, 0.35),
		"model_file": "voyager.glb", "faces": "+y", "faces_toward": "earth", "shown_from": 2443376.10347,
		"route": [
			[2443376.10347, "Earth"],      # launch, Aug 20, 1977 14:29 UTC
			[2444064.43740, "Jupiter"],    # Jul 9, 1979 22:29 UTC
			[2444842.64233, "Saturn"],     # Aug 26, 1981 03:24 UTC
			[2446455.24985, "Uranus"],     # Jan 24, 1986 17:59 UTC
			[2447763.66431, "Neptune"],    # Aug 25, 1989 03:56 UTC
			[2461356.49794, [20.08333, -59.73333, 144.787]],  # Nov 11, 2026: RA 20h 05m, Dec -59° 44', 144.787 AU from Earth
		],
		"facts": {
			"type": "Spacecraft. The only one to visit all four giant planets.",
			"launched": "August 20, 1977 (16 days before Voyager 1), on a Titan IIIE rocket",
			"mission": "Flew past Jupiter (1979), Saturn (1981), Uranus (1986) and Neptune (1989). It is still the only spacecraft to visit Uranus and Neptune. It crossed into interstellar space on November 5, 2018.",
			"size": "3.7 m dish antenna and a 13 m long magnetometer boom",
			"mass": "About 826 kg at launch",
			"power": "Three nuclear batteries (RTGs), losing about 4 watts a year",
			"status": "Still sending data. It's heading so far south that only NASA's big dish in Australia can talk to it.",
			"did_you_know": "Its pictures of Neptune in 1989 took about 4 hours to reach Earth at the speed of light.",
		},
	},
	"New Horizons": {
		"kind": "spacecraft", "label": "New Horizons", "radius_km": 0.0015, "mass_earths": 0.0, "rotation_hours": 24.0,
		"images": [], "color": Color(0.85, 0.7, 0.4), "label_color": Color(1.0, 0.78, 0.35),
		"model_file": "new_horizons.glb", "faces": "+y", "faces_toward": "earth", "shown_from": 2453755.29167,
		"route": [
			[2453755.29167, "Earth"],      # launch, Jan 19, 2006 19:00 UTC
			[2454159.73866, "Jupiter"],    # Feb 28, 2007 05:43 UTC
			[2457217.99302, "Pluto"],      # Jul 14, 2015 11:49 UTC
			[2461356.49794, [19.26667, -20.3, 66.537]],       # Nov 11, 2026: RA 19h 16m, Dec -20° 18', 66.537 AU from Earth
		],
		"facts": {
			"type": "Spacecraft. The first to visit Pluto.",
			"launched": "January 19, 2006, on an Atlas V. It left Earth faster than anything before it (16.3 km/s).",
			"mission": "Got a speed boost from Jupiter in February 2007, flew past Pluto and Charon on July 14, 2015, then past Arrokoth on January 1, 2019, the most distant world ever explored up close.",
			"size": "About the size of a grand piano, with a 2.1 m dish antenna",
			"mass": "478 kg at launch",
			"power": "One nuclear battery (RTG), about 245 watts at launch",
			"status": "Still exploring the Kuiper belt. It woke up in June 2026 from a record 321-day hibernation.",
			"did_you_know": "It took nine and a half years to reach Pluto, and its pictures took 4.5 hours to get home.",
		},
	},
	"Parker Solar Probe": {
		"kind": "spacecraft", "label": "Parker Solar Probe", "radius_km": 0.0015, "mass_earths": 0.0, "rotation_hours": 24.0,
		"images": [], "color": Color(0.9, 0.9, 0.9), "label_color": Color(1.0, 0.78, 0.35),
		"model_file": "parker_solar_probe.glb", "faces": "-z", "faces_toward": "sun", "shown_from": 2460621.40833,
		# Its final orbit since its last Venus flyby (Nov 6, 2024): closest to the Sun on Dec 24, 2024 11:53 UTC,
		# 9.86 Sun radii from its center, then every 88.3 days. Its tilt matches Venus's orbit, which shaped it.
		"orbit": {"a": 0.38811, "e": 0.88185, "i": 3.394, "node": 76.611, "arg_peri": 68.666, "mean_anomaly": 0.0,
			"epoch_jd": 2460668.99514, "period_days": 88.314},
		"facts": {
			"type": "Spacecraft. The fastest object ever built, and the closest to the Sun.",
			"launched": "August 12, 2018, on a Delta IV Heavy",
			"mission": "Used seven Venus flybys to shrink its orbit. Since late 2024 it dives to 6.1 million km from the Sun's surface every 88 days, flying through the Sun's outer atmosphere (the corona).",
			"size": "About 3 m tall, hiding behind a 2.3 m wide heat shield that always faces the Sun",
			"mass": "685 kg at launch",
			"power": "Solar panels that fold back behind the heat shield near the Sun, cooled by water",
			"status": "Its path here is its final orbit, which began in November 2024.",
			"did_you_know": "At its closest it moves at about 191 km/s, fast enough to fly from New York to Tokyo in under a minute. Its heat shield is built to take about 1,400 °C while the instruments behind it stay near room temperature.",
		},
	},
	"Juno": {
		"kind": "spacecraft", "label": "Juno", "radius_km": 0.01, "mass_earths": 0.0, "rotation_hours": 24.0,
		"images": [], "color": Color(0.8, 0.8, 0.85), "label_color": Color(1.0, 0.78, 0.35),
		"model_file": "juno.glb", "faces": "+y", "faces_toward": "earth", "shown_from": 2457574.66181, "parent": "Jupiter",
		# A long, thin orbit over Jupiter's poles: 33 days, swooping about 3,500 km over the cloud tops.
		# The shape and period are real; where it is along the orbit is estimated from its close pass of Thebe on May 1, 2026.
		"orbit": {"satellite": {"a_km": 2965801.0, "e": 0.97471, "i": 90.0, "node": 88.83, "arg_peri": 140.0, "mean_anomaly": 0.0,
			"degrees_per_day": 10.909091, "epoch_jd": 2461162.0,
			"pole_ra": 268.057, "pole_dec": 64.495, "parent_gm": 126686534.0}},
		"facts": {
			"type": "Spacecraft orbiting Jupiter",
			"launched": "August 5, 2011, on an Atlas V. It flew past Earth in 2013 for a speed boost.",
			"mission": "Arrived at Jupiter on July 4, 2016. Every 33 days it swoops over Jupiter's poles just a few thousand km above the clouds, studying what's inside the planet, its storms and its auroras.",
			"size": "About 20 m across its three solar wings",
			"mass": "3,625 kg at launch",
			"power": "Solar panels: about 14,000 watts near Earth but only about 500 watts at Jupiter, where sunlight is 25 times weaker",
			"status": "Still orbiting Jupiter. It flew close past the little moon Thebe on May 1, 2026. Its funding beyond its extended mission has been uncertain.",
			"did_you_know": "It was the first solar-powered spacecraft to work as far out as Jupiter. It carries three LEGO figures: Galileo, Jupiter and Juno.",
		},
	},
	"ISS": {
		"kind": "spacecraft", "label": "ISS", "radius_km": 0.055, "mass_earths": 0.0, "rotation_hours": 24.0,
		"images": [], "color": Color(0.85, 0.85, 0.85), "label_color": Color(1.0, 0.78, 0.35),
		"model_file": "iss.glb", "faces": "level", "faces_toward": "earth", "shown_from": 2451137.77778, "parent": "Earth",
		# From the official tracking data (TLE) of Nov 10, 2026 04:12 UTC. Earth's bulge turns the orbit
		# (node -4.95° a day, perigee +3.69° a day) and air drag slowly speeds it up as it sinks.
		"orbit": {"satellite": {"a_km": 6796.94, "e": 0.0007292, "i": 51.6322, "node": 297.3244, "arg_peri": 8.9462, "mean_anomaly": 351.1656,
			"degrees_per_day": 5576.186689, "degrees_per_day_per_day": 0.0336456, "apsis_degrees_per_day": -1.25628, "node_degrees_per_day": -4.95055,
			"epoch_jd": 2461354.67503, "pole_ra": 270.0, "pole_dec": 90.0, "parent_gm": 398600.4418}},
		"facts": {
			"type": "Space station orbiting Earth",
			"launched": "Its first part (Zarya) launched November 20, 1998. People have lived on board without a break since November 2, 2000.",
			"mission": "A science lab where astronauts from many countries live and work. It circles Earth about 15.5 times a day, about 420 km up.",
			"size": "109 m end to end, longer than the wingspan of the biggest airliner (Airbus A380, 80 m)",
			"mass": "About 420,000 kg",
			"power": "Eight huge pairs of solar wings, plus newer roll-out solar panels",
			"status": "NASA plans to retire it around 2030 and steer it into a remote part of the Pacific Ocean.",
			"did_you_know": "Its orbit here comes from official tracking data from November 10, 2026. Air drag and engine boosts change it, so it gets less exact the further you move the date from then.",
		},
	},
}
