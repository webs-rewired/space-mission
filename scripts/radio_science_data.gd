extends RefCounted

# The worlds for the Radio Science minigame (scripts/radio_science.gd), and what real missions learned there with
# nothing but their radio signal.
#
# OCCULTATION (worlds with air): as the spacecraft slips behind the world, seen from Earth, its radio signal passes
# through the atmosphere on the way. The air bends the signal (more where it's denser), shifting its frequency a
# little; tracking that shift down through the air gives the pressure and temperature at every height. Mariner 4
# did it first, at Mars in 1965.
#   profile: "pressure" (surface pressure in bar, scale height in km, the lowest height the signal reaches) or
#            "temperature" (giant planets: the temperature at each pressure, with its minimum at 0.1 bar)
# GRAVITY (airless worlds): a world isn't the same all the way through. Flying over a heavier patch, the spacecraft
# speeds up a tiny bit, then slows again, and that shows as a frequency wiggle of a few millimeters per second.
# Missions like GRAIL, Dawn and Galileo mapped worlds' insides this way.
#   bumps: where along the track the heavier (+) or lighter (−) patches are (0 to 1), and how strong
#
# Each world has a question its real data answered, with the answer first in the options.

const WORLDS = {
	"Mars": {"mode": "occultation", "profile": "pressure", "surface_bar": 0.0061, "scale_km": 11.1, "lowest_km": 0.0, "top_km": 80.0,
		"mission": "Mariner 4, 1965",
		"question": "Read the lowest point of your profile. How does Mars's surface air pressure compare with Earth's?",
		"options": ["About 0.6% of Earth's", "About 6% of Earth's", "About 60% of Earth's", "About the same as Earth's"],
		"why": "About 6 millibars: 0.6% of Earth's. Mariner 4 measured 4 to 7 millibars in 1965, far thinner than anyone expected, which is why Mars landers need huge parachutes, heat shields AND rockets."},
	"Venus": {"mode": "occultation", "profile": "pressure", "surface_bar": 92.0, "scale_km": 15.9, "lowest_km": 35.0, "top_km": 110.0,
		"mission": "Mariner 5 (1967) and the Pioneer Venus Orbiter",
		"question": "Your signal never got below about 35 km. Why not?",
		"options": ["The air is so dense it bent the signal into a curve around the planet", "The clouds are made of metal", "The spacecraft's antenna froze", "Venus has no air below 35 km"],
		"why": "Venus's air is so thick (92 times Earth's pressure at the ground) that below about 35 km it bends radio waves more sharply than the planet curves, trapping them: 'critical refraction'. Radio occultations can't see the lowest air, so landers like Venera had to go there."},
	"Titan": {"mode": "occultation", "profile": "pressure", "surface_bar": 1.5, "scale_km": 20.0, "lowest_km": 0.0, "top_km": 140.0,
		"mission": "Voyager 1, 1980",
		"question": "Read the lowest point of your profile. How does Titan's surface air pressure compare with Earth's?",
		"options": ["About 1.5 times Earth's", "About half of Earth's", "About 15 times Earth's", "About 1% of Earth's"],
		"why": "1.5 bar: thicker than Earth's air, on a moon smaller than Mercury. Voyager 1 measured it with exactly this kind of radio occultation in 1980. With low gravity and thick air, a person could fly there with wings strapped to their arms."},
	"Pluto": {"mode": "occultation", "profile": "pressure", "surface_bar": 0.0000115, "scale_km": 50.0, "lowest_km": 0.0, "top_km": 250.0,
		"mission": "New Horizons, 2015",
		"question": "Read the lowest point of your profile. How does Pluto's surface air pressure compare with Earth's?",
		"options": ["About 1/100,000 of Earth's", "About 1/100 of Earth's", "About the same as Earth's", "About 10 times Earth's"],
		"why": "About 11 microbars, roughly one hundred-thousandth of Earth's. New Horizons beamed radio signals from Earth through Pluto's air as it flew behind Pluto in 2015 (its REX experiment)."},
	"Triton": {"mode": "occultation", "profile": "pressure", "surface_bar": 0.000014, "scale_km": 14.0, "lowest_km": 0.0, "top_km": 80.0,
		"mission": "Voyager 2, 1989",
		"question": "Read the lowest point of your profile. How does Triton's surface air pressure compare with Earth's?",
		"options": ["About 1/70,000 of Earth's", "About 1/70 of Earth's", "About the same as Earth's", "About 7 times Earth's"],
		"why": "About 14 microbars of nitrogen, measured by Voyager 2's radio occultation in 1989. Thin as it is, it carries geyser plumes 8 km up before the wind bends them."},
	"Jupiter": {"mode": "occultation", "profile": "temperature", "coldest_k": 110.0, "one_bar_k": 165.0, "top_k": 170.0,
		"mission": "Voyager, Galileo and Juno",
		"question": "Find the coldest point in your profile (the tropopause). At what pressure is it?",
		"options": ["About 0.1 bar", "About 10 bar", "About 1,000 bar", "About 0.000001 bar"],
		"why": "About 0.1 bar, a tenth of Earth's surface pressure. Strangely, the tropopause sits near 0.1 bar on Earth, Titan, Jupiter, Saturn, Uranus and Neptune: above it, sunlight warms the haze; below it, rising and sinking air carries heat."},
	"Saturn": {"mode": "occultation", "profile": "temperature", "coldest_k": 82.0, "one_bar_k": 134.0, "top_k": 140.0,
		"mission": "Voyager and Cassini",
		"question": "Find the coldest point in your profile (the tropopause). At what pressure is it?",
		"options": ["About 0.1 bar", "About 10 bar", "About 1,000 bar", "About 0.000001 bar"],
		"why": "About 0.1 bar. Cassini made dozens of radio occultations of Saturn, its rings and Titan. The tropopause sits near 0.1 bar on Earth, Titan and all four giant planets: above it sunlight warms the haze, below it moving air carries heat."},
	"Uranus": {"mode": "occultation", "profile": "temperature", "coldest_k": 53.0, "one_bar_k": 76.0, "top_k": 120.0,
		"mission": "Voyager 2, 1986",
		"question": "Find the coldest point in your profile (the tropopause). At what pressure is it?",
		"options": ["About 0.1 bar", "About 10 bar", "About 1,000 bar", "About 0.000001 bar"],
		"why": "About 0.1 bar, measured by Voyager 2 in 1986: at about 53 K (−220 °C) it's one of the coldest places in any planet's air. The same 0.1 bar tropopause shows up on Earth, Titan and the other giants."},
	"Neptune": {"mode": "occultation", "profile": "temperature", "coldest_k": 52.0, "one_bar_k": 72.0, "top_k": 150.0,
		"mission": "Voyager 2, 1989",
		"question": "Find the coldest point in your profile (the tropopause). At what pressure is it?",
		"options": ["About 0.1 bar", "About 10 bar", "About 1,000 bar", "About 0.000001 bar"],
		"why": "About 0.1 bar, measured by Voyager 2 in 1989. Neptune is so far from the Sun that its own inner heat drives the fastest winds in the solar system."},
	"Moon": {"mode": "gravity", "bumps": [[0.22, 1.0], [0.48, 0.7], [0.75, 1.0]],
		"mission": "GRAIL, 2012",
		"question": "Your track sped up over the big dark lava plains (the maria). What are these 'mascons' (mass concentrations)?",
		"options": ["Dense mantle rock and lava pushed up under old impact basins", "Buried iron asteroids", "Hollow caves", "Thick ice sheets"],
		"why": "NASA's twin GRAIL spacecraft (2012) measured changes in the distance between them as small as a micron and mapped the Moon's gravity in detail. The mascons are dense mantle rock that rose under giant impact basins, topped with lava."},
	"Mercury": {"mode": "gravity", "bumps": [[0.3, 0.8], [0.65, 0.6]],
		"mission": "MESSENGER, 2011 to 2015",
		"question": "MESSENGER's gravity data showed Mercury is unusually heavy for its size. Why?",
		"options": ["Its iron core fills about 85% of its radius", "It's made of solid gold", "It has an ocean of mercury", "It's mostly water ice"],
		"why": "Its metal core reaches about 85% of the way out (Earth's reaches about 55%). One idea: a giant impact long ago blasted much of Mercury's rocky outer layer away."},
	"Ceres": {"mode": "gravity", "bumps": [[0.35, -0.6], [0.6, 0.7]],
		"mission": "Dawn, 2015 to 2018",
		"question": "Dawn's gravity data showed how Ceres is built inside. What did it find?",
		"options": ["A denser rocky inside under a lighter crust of ice, salt and rock", "Solid iron all the way through", "It's hollow", "Exactly the same all the way through"],
		"why": "Ceres separated into layers: a dense, rocky inside and a lighter crust mixing ice, salts and rock, with signs of brine deep down. The low spot under Occator Crater fits brine rising toward the surface."},
	"Europa": {"mode": "gravity", "bumps": [[0.4, 0.6], [0.7, -0.4]],
		"mission": "Galileo, 1996 to 2000",
		"question": "Galileo's gravity measurements, with its magnetometer, showed Europa's layers. What's on top?",
		"options": ["About 100 km of water: an ice shell over a salty ocean", "A thick layer of iron", "Solid rock right to the surface", "A gas layer"],
		"why": "Europa has an iron core, a rocky mantle and about 100 km of water on top: an ice shell over a global ocean with more water than all of Earth's oceans."},
	"Ganymede": {"mode": "gravity", "bumps": [[0.3, 0.5], [0.62, 0.8]],
		"mission": "Galileo, 1996 to 2000",
		"question": "Galileo's gravity data showed Ganymede is the most layered moon known. What's at its center?",
		"options": ["An iron core (with a magnetic field)", "An ocean", "Ice", "Nothing: it's hollow"],
		"why": "Ganymede has an iron core that makes its own magnetic field (the only moon with one), a rocky mantle, and ice layered with a salty ocean."},
	"Callisto": {"mode": "gravity", "bumps": [[0.5, 0.3]],
		"mission": "Galileo, 1996 to 2000",
		"question": "Galileo's gravity data showed Callisto's inside is surprisingly mixed. What does that mean?",
		"options": ["Rock and ice never fully separated into layers", "It has a huge iron core", "It's made of pure rock", "It's hollow"],
		"why": "Callisto is only partly separated: rock and ice are still mostly mixed, so it never got hot enough inside to sort itself into layers like Ganymede."},
	"Enceladus": {"mode": "gravity", "bumps": [[0.45, 0.4], [0.8, -0.7]],
		"mission": "Cassini, 2014",
		"question": "Cassini's gravity data from close flybys found something under Enceladus's south pole. What?",
		"options": ["An ocean of liquid water under the ice", "A volcano of lava", "A buried spaceship", "A huge iron meteorite"],
		"why": "A dense layer of liquid water under the south pole's ice, feeding its geysers. Later measurements showed the ocean goes all the way around the moon."},
	"Io": {"mode": "gravity", "bumps": [[0.3, 0.6], [0.7, 0.6]],
		"mission": "Juno, 2023 and 2024",
		"question": "Juno's gravity measurements in 2023 and 2024 tested whether Io has a shallow ocean of magma. What did they show?",
		"options": ["No shallow magma ocean: its volcanoes are fed from deeper, mostly solid rock", "A global ocean of magma just under the crust", "An ocean of water", "A hollow inside"],
		"why": "Io flexes as it orbits Jupiter, and a shallow magma ocean would make it flex a lot more. Juno found it doesn't, so its hundreds of volcanoes draw on magma from mostly solid, hot rock (published in 2024)."},
	"Phobos": {"mode": "gravity", "bumps": [[0.5, -0.5]],
		"mission": "Mars Express, 2008 and 2010 flybys",
		"question": "Mars Express's gravity data showed Phobos is very light for a rock. What does that suggest?",
		"options": ["It's a porous pile of rubble, maybe with ice", "It's made of iron", "It's made of gold", "It's a hollow alien base"],
		"why": "Phobos's density is only about 1.9 grams per cubic centimeter, so it's probably a porous pile of rubble, perhaps with some ice inside, not a solid rock."},
	"Charon": {"mode": "gravity", "bumps": [[0.5, 0.5]],
		"mission": "New Horizons, 2015",
		"question": "New Horizons measured Charon's mass from how it pulled on things. Its density (about 1.7 g/cm³) tells you what it's made of. What?",
		"options": ["Roughly half rock, half ice", "Pure iron", "Pure ice", "Gas"],
		"why": "Water ice is about 0.9 g/cm³ and rock about 3, so 1.7 means roughly half rock and half ice. Mass and size alone tell you a world's recipe."},
}

static func has_world(world_name):
	return WORLDS.has(world_name)
