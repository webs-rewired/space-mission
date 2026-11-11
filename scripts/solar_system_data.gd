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

const BODY_ORDER = ["Sun", "Mercury", "Venus", "Earth", "Moon", "Mars", "Ceres", "Jupiter", "Saturn",
	"Uranus", "Neptune", "Pluto", "Haumea", "Makemake", "Eris", "Halley", "Encke", "67P", "Hale-Bopp"]

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
}
