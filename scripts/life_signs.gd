extends RefCounted

# The search for signs of life, for the Signs of Life minigame (scripts/life_search.gd). One scenario per world where
# scientists really think life could exist, or once could have, built from what missions actually found there.
#
# No mission has ever found life beyond Earth. The best anyone has is "potential biosignatures": things life
# can make, that might also have been made without life. NASA scientists judge claims on the Confidence of Life
# Detection (CoLD) scale (Green et al., Nature, 2021), seven steps from "we see a possible signal" to "independent
# teams confirm it". A rover can climb the first three rungs; the rest need labs on Earth and years of checking.
#
# Each scenario: the target, the rock's colors, a short brief, and features hidden on the close-up. Each feature:
#   place, size     where it is on the close-up (0 to 1 across and down) and how big (share of the width)
#   draw            how it looks: spots, vein, layers, grains, smear, patch, haze
#   signals         what each instrument sees there: camera (close-up camera), organics (UV laser: organic
#                   molecules glow), chemistry (X-ray / mass spectrometer: the elements and minerals). Missing = nothing.
#   answer          "life" (points to life), "either" (life or chemistry could make it), "not" (not a sign of life)
#   role            "signal" (a possible biosignature), "habitat" (shows life could have lived here: water, energy,
#                   the right elements), "contamination" (it came from the spacecraft itself), "ordinary"
#   why             the explanation shown after you judge it
# The scenario's features are real findings; where a lander finds something no mission has seen yet (no mission has
# landed on Europa, Enceladus, Titan or Ceres), the text says so.

const INSTRUMENTS = {
	"camera": {"name": "Close-up camera", "short": "CAMERA", "color": Color(0.85, 0.9, 1.0), "cost": 3.0,
		"what": "Shapes and textures, like Perseverance's WATSON camera."},
	"organics": {"name": "UV laser (organics)", "short": "UV LASER", "color": Color(0.35, 1.0, 0.55), "cost": 7.0,
		"what": "Organic molecules glow under ultraviolet light, like Perseverance's SHERLOC."},
	"chemistry": {"name": "X-ray chemistry", "short": "X-RAY", "color": Color(1.0, 0.62, 0.3), "cost": 7.0,
		"what": "The elements and minerals, like Perseverance's PIXL."},
}

const SCENARIOS = {
	"Mars": {
		"target": "Leopard-spotted mudstone",
		"base": Color(0.55, 0.32, 0.24), "speck": Color(0.7, 0.45, 0.33),
		"brief": "A reddish mudstone in an old river channel, like 'Cheyava Falls', which Perseverance found in Jezero Crater in July 2024. Map it with your instruments, find what's interesting, and check it isn't something you brought with you.",
		"features": [
			{"place": Vector2(0.38, 0.46), "size": 0.1, "draw": "spots",
				"signals": {"camera": "Millimeter-sized pale spots with dark rims, like a leopard's coat.", "chemistry": "The dark rims are rich in iron and phosphate: the minerals vivianite (iron phosphate) and greigite (iron sulfide).", "organics": "Organic molecules in the rock around the spots."},
				"answer": "either", "role": "signal",
				"why": "On Earth, reactions like these happen where microbes feed on organic matter, leaving rims of iron phosphate and iron sulfide. They can also happen without life. In 2025 NASA called Cheyava Falls a potential biosignature: the most promising yet, but not proof."},
			{"place": Vector2(0.7, 0.3), "size": 0.12, "draw": "vein",
				"signals": {"camera": "A bright white vein cutting across the rock.", "chemistry": "Calcium sulfate: minerals left by water flowing through cracks."},
				"answer": "not", "role": "habitat",
				"why": "Not a sign of life by itself, but water once flowed through this rock, and life as we know it needs liquid water. That makes the place habitable."},
			{"place": Vector2(0.22, 0.75), "size": 0.13, "draw": "layers",
				"signals": {"camera": "Very fine, flat layers: mud that settled in still water.", "chemistry": "Clay minerals, which form in water."},
				"answer": "not", "role": "habitat",
				"why": "A river or lake laid this mud down. Not life, but on Earth fine mud like this is where traces of microbes are preserved best."},
			{"place": Vector2(0.78, 0.74), "size": 0.08, "draw": "smear",
				"signals": {"organics": "A strong organic signal, only in a stripe exactly where the rover's brush touched the rock."},
				"answer": "not", "role": "contamination",
				"why": "Contamination! Organics only where your own tool touched means they probably came from the rover. Ruling this out is the second rung of the CoLD scale. Perseverance carries 'witness tubes' to check for exactly this."},
			{"place": Vector2(0.55, 0.15), "size": 0.09, "draw": "patch",
				"signals": {"camera": "Fine reddish dust in a little drift.", "chemistry": "Iron oxides, sulfur and chlorine: the same dust found all over Mars."},
				"answer": "not", "role": "ordinary",
				"why": "Wind-blown dust. Global dust storms spread it around the whole planet, so it tells you about Mars in general, not this rock."},
		],
	},
	"Enceladus": {
		"target": "Fresh plume snow by a tiger stripe",
		"base": Color(0.78, 0.84, 0.9), "speck": Color(0.9, 0.94, 1.0),
		"brief": "Snow that fell from the geysers a few hours ago, straight from the ocean under the ice. No mission has landed here yet: Cassini tasted the plumes from space, flying through them. Map the snow and decide what it says about the ocean.",
		"features": [
			{"place": Vector2(0.35, 0.4), "size": 0.12, "draw": "grains",
				"signals": {"organics": "Large, complex organic molecules in the ice grains (Cassini found these in 2018).", "camera": "Slightly darker, sticky-looking ice grains."},
				"answer": "either", "role": "signal",
				"why": "Big organic molecules can be made by life, or by hot water reacting with rock on the seafloor. They're ingredients, not proof."},
			{"place": Vector2(0.7, 0.55), "size": 0.1, "draw": "haze",
				"signals": {"chemistry": "Hydrogen gas and methane coming out of the snow as it warms (Cassini measured both in the plumes)."},
				"answer": "either", "role": "signal",
				"why": "On Earth, microbes at seafloor vents eat hydrogen and breathe out methane. But rock reacting with hot water makes both too. It means there's chemical food for life down there."},
			{"place": Vector2(0.2, 0.72), "size": 0.1, "draw": "grains",
				"signals": {"chemistry": "Tiny grains of silica, a few nanometers across.", "camera": "Nothing you can see: the grains are far too small."},
				"answer": "not", "role": "habitat",
				"why": "Silica grains like these form where water hotter than about 90 °C meets rock: hydrothermal vents. Not life, but a place with water, energy and rock, like the vents where life may have started on Earth."},
			{"place": Vector2(0.58, 0.2), "size": 0.09, "draw": "patch",
				"signals": {"chemistry": "Sodium phosphates in the ice (found in Cassini data in 2023)."},
				"answer": "not", "role": "habitat",
				"why": "Phosphorus is one of the six elements all Earth life needs (with carbon, hydrogen, nitrogen, oxygen and sulfur). The ocean has plenty: habitable, not inhabited."},
			{"place": Vector2(0.82, 0.8), "size": 0.08, "draw": "smear",
				"signals": {"organics": "Nitrogen-rich organic molecules, only in a ring right under where the lander's thrusters fired.", "chemistry": "Nitrogen and hydrogen: the leftovers of hydrazine rocket fuel."},
				"answer": "not", "role": "contamination",
				"why": "Contamination from your own landing engines. Spotting it is exactly what the second rung of the CoLD scale asks: prove the signal didn't come from the spacecraft."},
		],
	},
	"Europa": {
		"target": "Reddish band of salty ice",
		"base": Color(0.68, 0.62, 0.58), "speck": Color(0.82, 0.74, 0.66),
		"brief": "A reddish-brown band where ocean water may have reached the surface. No mission has landed on Europa yet (NASA's Europa Clipper arrives in 2030 to study it from flybys), so what your lander finds here is new.",
		"features": [
			{"place": Vector2(0.4, 0.5), "size": 0.13, "draw": "patch",
				"signals": {"chemistry": "Sodium chloride (table salt) and magnesium sulfate.", "camera": "A yellowish-brown stain in the ice."},
				"answer": "not", "role": "habitat",
				"why": "Salt from the ocean below (Hubble saw it in 2019). The ocean has the chemistry of a salty sea: a place life could live, if it has energy."},
			{"place": Vector2(0.72, 0.32), "size": 0.1, "draw": "grains",
				"signals": {"chemistry": "Carbon dioxide frozen into the ice.", "camera": "Small white specks."},
				"answer": "not", "role": "habitat",
				"why": "The James Webb Space Telescope found carbon dioxide here in 2023, probably from the ocean. Carbon is a building block of life; this is an ingredient, not a sign of life."},
			{"place": Vector2(0.25, 0.25), "size": 0.1, "draw": "spots",
				"signals": {"organics": "Faint organic molecules inside the reddish ice (your lander's find: no mission has seen this yet).", "camera": "Darker reddish flecks."},
				"answer": "either", "role": "signal",
				"why": "Organics in ocean ice would be exciting, but Jupiter's radiation can make some organic molecules without any life, and it also breaks them down. Only a sample from deeper ice could tell."},
			{"place": Vector2(0.6, 0.78), "size": 0.12, "draw": "haze",
				"signals": {"camera": "The top millimeter of ice is darkened and cracked.", "chemistry": "Sulfur compounds in the top layer only."},
				"answer": "not", "role": "ordinary",
				"why": "Jupiter's radiation and sulfur from Io's volcanoes darken Europa's surface ice. That's space weather, not biology, and it's why landers would dig below the top layer."},
			{"place": Vector2(0.85, 0.6), "size": 0.07, "draw": "smear",
				"signals": {"organics": "Organic molecules in a neat circle exactly the size of your sampling scoop."},
				"answer": "not", "role": "contamination",
				"why": "A perfect circle the shape of your own scoop: contamination from the spacecraft. Planetary protection rules make Europa landers extremely clean for this reason."},
		],
	},
	"Titan": {
		"target": "Organic sand at the edge of a dry riverbed",
		"base": Color(0.3, 0.22, 0.14), "speck": Color(0.42, 0.3, 0.18),
		"brief": "Titan rains methane, and its sand is made of organic molecules. If there's life here it would be life 'as we don't know it', living in liquid methane instead of water. NASA's Dragonfly will land here in 2034.",
		"features": [
			{"place": Vector2(0.4, 0.42), "size": 0.13, "draw": "grains",
				"signals": {"organics": "Organic molecules everywhere: the sand itself is made of them.", "camera": "Dark, rounded sand grains."},
				"answer": "not", "role": "ordinary",
				"why": "Sunlight breaking up methane in Titan's air makes organic molecules without any life, and they snow down onto the ground. On Titan, finding organics is normal."},
			{"place": Vector2(0.72, 0.6), "size": 0.1, "draw": "haze",
				"signals": {"chemistry": "Less hydrogen right at the ground than there should be, as if something is using it up."},
				"answer": "either", "role": "signal",
				"why": "In 2010 scientists noticed hydrogen seems to vanish near Titan's surface. Methane-based life could eat it, but unknown chemistry, or errors in the measurements and models, could explain it too."},
			{"place": Vector2(0.22, 0.72), "size": 0.12, "draw": "layers",
				"signals": {"camera": "Rounded pebbles and layers left by a flowing liquid.", "chemistry": "Water-ice pebbles, coated in organics."},
				"answer": "not", "role": "habitat",
				"why": "Liquid methane flowed here. Liquid is the one thing every possible kind of life needs, so this is where to look."},
			{"place": Vector2(0.6, 0.18), "size": 0.08, "draw": "spots",
				"signals": {"organics": "Organic molecules with nitrogen, the kind that might form cell-like membranes in liquid methane (a 2015 computer-model idea)."},
				"answer": "either", "role": "signal",
				"why": "A real idea from chemists, but later studies doubted those membranes could form. Interesting chemistry, far from proof."},
			{"place": Vector2(0.85, 0.82), "size": 0.08, "draw": "smear",
				"signals": {"chemistry": "Methane frost vanishing in a patch right next to the lander's warm body."},
				"answer": "not", "role": "contamination",
				"why": "The lander's own warmth (its nuclear power source) is changing the ground next to it. Always measure away from your spacecraft."},
		],
	},
	"Ceres": {
		"target": "Bright salt crust in Occator Crater",
		"base": Color(0.32, 0.31, 0.3), "speck": Color(0.85, 0.85, 0.82),
		"brief": "Salt left by brine that rose from deep inside Ceres, maybe within the last few million years. Dawn studied it from orbit; no mission has landed. Ceres probably once had an ocean and may still have pockets of brine.",
		"features": [
			{"place": Vector2(0.42, 0.42), "size": 0.12, "draw": "patch",
				"signals": {"chemistry": "Hydrated sodium chloride: salt that still has water in it.", "camera": "A brilliant white crust."},
				"answer": "not", "role": "habitat",
				"why": "This salt loses its water within centuries in space, so liquid brine reached the surface recently (Dawn, 2020). Liquid salty water, still inside Ceres: possibly habitable."},
			{"place": Vector2(0.7, 0.62), "size": 0.1, "draw": "spots",
				"signals": {"organics": "Organic molecules with long carbon chains, like the ones Dawn found near Ernutet Crater in 2017.", "camera": "Faint reddish patches."},
				"answer": "either", "role": "signal",
				"why": "Organics this rich could come from chemistry inside an icy world, or arrive on meteorites. Life isn't needed to make them."},
			{"place": Vector2(0.22, 0.72), "size": 0.12, "draw": "layers",
				"signals": {"chemistry": "Clays with ammonia locked inside, and carbonate salts.", "camera": "Dark layered soil."},
				"answer": "not", "role": "habitat",
				"why": "These clays formed in water long ago. Ceres was once a wet world with the right ingredients, which is why it's on the list of places that could have hosted life."},
			{"place": Vector2(0.62, 0.18), "size": 0.08, "draw": "grains",
				"signals": {"camera": "Dark grains scattered on the white salt.", "chemistry": "Iron and nickel metal, and the minerals of stony meteorites."},
				"answer": "not", "role": "ordinary",
				"why": "Bits of meteorites that hit Ceres. They can carry organics from elsewhere, one more reason organics alone don't mean life."},
			{"place": Vector2(0.86, 0.82), "size": 0.07, "draw": "smear",
				"signals": {"organics": "Organic molecules only on the sampling arm's own tip and the grains it just touched."},
				"answer": "not", "role": "contamination",
				"why": "From the arm itself. Real missions bring blank samples and clean tools to prove a signal is really from the place, not the spacecraft."},
		],
	},
}

# The CoLD scale's seven rungs (Green et al., 2021)
const COLD_LEVELS = [
	"1  Detect a possible signal of life",
	"2  Rule out contamination from the spacecraft",
	"3  Show life could make it in this place",
	"4  Rule out non-living ways to make it",
	"5  Find another, independent sign",
	"6  Rule out every other explanation",
	"7  Independent teams confirm it",
]

static func has_scenario(world):
	return SCENARIOS.has(world)
