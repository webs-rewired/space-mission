extends RefCounted

# Your career across every mission, saved on this computer (user://career.cfg):
#   XP and rank      every mission earns XP (more for a better score, the directives and harder difficulty)
#   Research points  the science your missions send home becomes research points, which buy technology
#                    upgrades that change how your next spacecraft performs (better solar cells, lighter
#                    structures...). This is what science is for.
#   Achievements     milestones like your first landing or a clean run through the asteroid belt
#   Best results     your best score and the most directive stars on each destination
#
# GameState loads this when the game starts (GameState.career) and the mission report records each mission.

const SAVE_FILE = "user://career.cfg"

const RANKS = [
	[0, "Intern"], [150, "Flight Controller"], [400, "Mission Specialist"], [800, "Principal Investigator"],
	[1400, "Flight Director"], [2200, "Center Director"], [3200, "NASA Administrator"],
]

# Technology upgrades bought with research points. Each one changes a real number in the game (GameState uses them).
const UPGRADES = {
	"solar_cells": {"title": "Triple-junction solar cells", "text": "Solar arrays make 20% more power. (Juno's cells turn about 30% of sunlight into electricity.)", "cost": 120},
	"light_structures": {"title": "Carbon-composite structure", "text": "Your spacecraft is 8% lighter, so every rocket and engine goes further.", "cost": 100},
	"ka_band": {"title": "Ka-band radio", "text": "Sends data home 50% faster, and a small antenna gets 15% more of your science back.", "cost": 140},
	"thruster_fuel": {"title": "Extra thruster fuel", "text": "40% more thruster time for dodging rocks in the belts.", "cost": 80},
	"funding": {"title": "Congressional funding", "text": "Every mission budget is 10% bigger.", "cost": 200},
	"better_propellant": {"title": "High-performance propellant", "text": "Your spacecraft's engine can change its speed 10% more.", "cost": 150},
	"instruments": {"title": "Next-generation instruments", "text": "Every instrument starts the mission with 5 more science.", "cost": 160},
	"shard_scanner": {"title": "Shard scanner", "text": "Science shards in the belts are easier to catch and worth 1 more science each.", "cost": 90},
	# Power
	"tandem_cells": {"title": "Perovskite tandem solar cells", "text": "Solar arrays make another 15% more power.", "cost": 180, "requires": "solar_cells"},
	"next_gen_rtg": {"title": "Next-generation RTG", "text": "Nuclear power sources make 25% more power and fade half as fast on long trips.", "cost": 220},
	"better_batteries": {"title": "Lithium-sulfur batteries", "text": "Rovers drain their batteries 30% more slowly.", "cost": 110},
	# Structure and propulsion
	"printed_parts": {"title": "3D-printed titanium parts", "text": "Your spacecraft is another 5% lighter.", "cost": 160, "requires": "light_structures"},
	"densified_propellant": {"title": "Densified propellant", "text": "Your spacecraft's engine changes its speed another 5% more.", "cost": 200, "requires": "better_propellant"},
	"engine_uprate": {"title": "Rocket engine uprate", "text": "Every rocket engine's Isp goes up 2%, so every rocket goes a little faster.", "cost": 240},
	"lithium_tanks": {"title": "Aluminum-lithium tanks", "text": "Rocket tanks weigh 10% less when empty (the Space Shuttle's Super Lightweight Tank did this).", "cost": 190},
	"reusable_boosters": {"title": "Reusable boosters", "text": "Rockets cost 15% less to launch.", "cost": 260},
	"bulk_contracts": {"title": "Bulk part contracts", "text": "Spacecraft parts cost 10% less.", "cost": 170},
	"precision_navigation": {"title": "Optical navigation", "text": "Arrivals are aimed more precisely: braking into orbit needs 5% less speed change.", "cost": 150},
	# Communications
	"laser_comms": {"title": "Laser communications", "text": "Sends data home 30% faster again (like the DSOC laser that flew on Psyche).", "cost": 230, "requires": "ka_band"},
	"dsn_priority": {"title": "Deep Space Network priority", "text": "A small antenna gets another 10% of your science home.", "cost": 140},
	"data_compression": {"title": "Onboard data compression", "text": "Instruments make 40% less data, so the data recorder fills up more slowly.", "cost": 100},
	# Science
	"cryo_detectors": {"title": "Cryocooled detectors", "text": "Every instrument starts the mission with another 4 science.", "cost": 250, "requires": "instruments"},
	"auto_targeting": {"title": "Autonomous science targeting", "text": "Rovers get 2 more science from every target they study.", "cost": 130},
	"lab_power": {"title": "Sample lab power budget", "text": "One more instrument run when identifying rock samples.", "cost": 120},
	"force_sensors": {"title": "Arm force sensors", "text": "The robotic arm's strain builds 40% more slowly when it bumps something.", "cost": 90},
	# Piloting and rovers
	"collision_radar": {"title": "Collision-avoidance radar", "text": "Rocks in the belts have to come 15% closer to count as a hit.", "cost": 140},
	"rcs_upgrade": {"title": "Upgraded thrusters", "text": "20% more push for steering through belts, and 30% more propellant in the docking trainer and sample return.", "cost": 160},
	"titanium_wheels": {"title": "Titanium wheels", "text": "Rover wheels take 40% less damage (Curiosity's aluminum wheels got holes from sharp rocks).", "cost": 120},
	# Program
	"partners": {"title": "International partners", "text": "Every mission budget is another 10% bigger, like ESA and JAXA joining a NASA mission.", "cost": 280, "requires": "funding"},
	"outreach": {"title": "Public outreach", "text": "Every mission earns 15% more XP.", "cost": 110},
	"university_labs": {"title": "University partnerships", "text": "The science your missions send home earns 20% more research points.", "cost": 300},
}

const ACHIEVEMENTS = {
	"first_light": {"title": "First light", "text": "Finish your first mission."},
	"touchdown": {"title": "Touchdown", "text": "Land safely on another world."},
	"ringside": {"title": "Ringside seat", "text": "Fly a mission to Saturn, Titan or Enceladus."},
	"ocean_hunter": {"title": "Ocean hunter", "text": "Reach Europa or Enceladus, moons with oceans under their ice."},
	"grand_tour": {"title": "Grand tour", "text": "Fly missions to 5 different worlds."},
	"far_frontier": {"title": "Far frontier", "text": "Reach Pluto, Charon, Eris, Haumea or Makemake."},
	"top_marks": {"title": "Top marks", "text": "Earn an A+."},
	"perfect": {"title": "Perfect mission", "text": "Score 100."},
	"untouchable": {"title": "Untouchable", "text": "Cross a belt without a single rock strike."},
	"prospector": {"title": "Prospector", "text": "Collect 10 science shards in one trip."},
	"chain_reaction": {"title": "Chain reaction", "text": "Reach a 5× shard combo."},
	"penny_pincher": {"title": "Penny pincher", "text": "Finish a mission with half the budget left."},
	"high_roller": {"title": "High roller", "text": "Survive 3 risky choices in one mission."},
	"by_the_book": {"title": "By the book", "text": "Complete all 3 directives in one mission."},
	"lessons_learned": {"title": "Lessons learned", "text": "Lose a mission. Every space program has."},
	"veteran": {"title": "Veteran", "text": "Fly 10 missions."},
	"hard_as_nails": {"title": "Hard as nails", "text": "Earn a B or better on Veteran difficulty."},
	"researcher": {"title": "Research lab", "text": "Buy your first technology upgrade."},
	"return_to_sender": {"title": "Return to sender", "text": "Bring rock samples home with a sample return."},
	"textbook": {"title": "Textbook insertion", "text": "Fly an excellent orbital insertion."},
	"field_geologist": {"title": "Field geologist", "text": "Identify 3 rock samples correctly in one mission."},
	"road_trip": {"title": "Road trip", "text": "Drive a rover 300 m in one mission."},
	"slingshot": {"title": "Slingshot", "text": "Fly a mission with a gravity assist."},
	"close_shave": {"title": "Close shave", "text": "Get 5 close calls in one trip through the belts."},
	"ace_pilot": {"title": "Ace pilot", "text": "Earn gold in the docking trainer."},
	"test_stand": {"title": "Test stand veteran", "text": "Earn gold on 5 different engine tests."},
	"gold_plan": {"title": "Gravity master", "text": "Earn a gold plan in the flyby planner."},
	"smooth_operator": {"title": "Smooth operator", "text": "Earn a gold traverse rating with a rover."},
	"overachiever": {"title": "Overachiever", "text": "Earn 3 gold medals in minigames during one mission."},
	"astrobiologist": {"title": "Astrobiologist", "text": "Report a potential biosignature honestly, with contamination ruled out and the place shown habitable."},
	"seismologist": {"title": "Seismologist", "text": "Locate a quake within 10% of its real distance."},
	"rock_hound": {"title": "Rock hound", "text": "Earn gold in the sample lab."},
}

static func load_data():
	var data = {"xp": 0, "research": 0, "missions": 0, "upgrades": [], "achievements": [], "best": {}, "worlds": [], "engine_tests": {}, "assist_plans": {}, "docking_best": 0, "docking_targets": {}, "rover_best": {}}
	var file = ConfigFile.new()
	if file.load(SAVE_FILE) == OK:
		for key in data:
			data[key] = file.get_value("career", key, data[key])
	return data

static func save_data(data):
	var file = ConfigFile.new()
	for key in data:
		file.set_value("career", key, data[key])
	file.save(SAVE_FILE)

# The rank for an amount of XP: {"index", "title", "floor" (XP where it starts), "next" (XP for the next one, or -1)}
static func rank_for(xp):
	var index = 0
	for rank_index in RANKS.size():
		if xp >= RANKS[rank_index][0]:
			index = rank_index
	var next = RANKS[index + 1][0] if index + 1 < RANKS.size() else -1
	return {"index": index, "title": RANKS[index][1], "floor": RANKS[index][0], "next": next}

# Records a finished mission. report: destination, score, grade, lost, science, data_share, directives_done,
# risky, money_left_share, difficulty, stats (GameState.mission_stats). Changes data and returns what changed:
# {"xp_before", "xp_gained", "research_gained", "rank_before", "rank_after", "new_achievements", "new_best", "stars"}
static func record_mission(data, report):
	var summary = {"xp_before": data["xp"], "rank_before": rank_for(data["xp"])}
	var xp_multiplier = [0.8, 1.0, 1.5][clamp(report["difficulty"], 0, 2)]
	var xp = 20 if report["lost"] else report["score"] + 40 * report["directives_done"]
	summary["xp_gained"] = int(round(xp * xp_multiplier * (1.15 if "outreach" in data["upgrades"] else 1.0)))
	# The science that made it home becomes research points (a lost mission still teaches a little)
	var research = int(max(report["science"], 0) * (0.25 if report["lost"] else report["data_share"]) * (1.2 if "university_labs" in data["upgrades"] else 1.0))
	summary["research_gained"] = research
	data["xp"] += summary["xp_gained"]
	data["research"] += research
	data["missions"] += 1
	if not report["destination"] in data["worlds"]:
		data["worlds"].append(report["destination"])
	summary["rank_after"] = rank_for(data["xp"])
	# Best result on this destination
	var best = data["best"].get(report["destination"], {"score": -1, "grade": "", "stars": 0})
	summary["new_best"] = not report["lost"] and report["score"] > best["score"] and best["score"] >= 0
	summary["first_time"] = best["score"] < 0
	summary["stars"] = report["directives_done"]
	if not report["lost"] and report["score"] > best["score"]:
		best["score"] = report["score"]
		best["grade"] = report["grade"]
	best["stars"] = max(best.get("stars", 0), report["directives_done"])
	data["best"][report["destination"]] = best
	# Achievements
	var stats = report["stats"]
	var earned = []
	var checks = {
		"first_light": data["missions"] >= 1,
		"touchdown": stats.get("landed", false) and not report["lost"],
		"ringside": report["destination"] in ["Saturn", "Titan", "Enceladus"] and not report["lost"],
		"ocean_hunter": report["destination"] in ["Europa", "Enceladus"] and not report["lost"],
		"grand_tour": data["worlds"].size() >= 5,
		"far_frontier": report["destination"] in ["Pluto", "Charon", "Eris", "Haumea", "Makemake"] and not report["lost"],
		"top_marks": report["grade"] == "A+",
		"perfect": report["score"] >= 100,
		"untouchable": stats.get("belts_cleared", 0) > 0 and stats.get("rocks_hit", 0) == 0,
		"prospector": stats.get("shards", 0) >= 10,
		"chain_reaction": stats.get("best_combo", 0) >= 5,
		"penny_pincher": report["money_left_share"] >= 0.5 and not report["lost"],
		"high_roller": report["risky"] >= 3 and not report["lost"],
		"by_the_book": report["directives_done"] >= 3,
		"lessons_learned": report["lost"],
		"veteran": data["missions"] >= 10,
		"hard_as_nails": report["difficulty"] == 2 and report["grade"] in ["A+", "A", "B"],
		"return_to_sender": stats.get("samples_returned", 0) > 0 and not report["lost"],
		"textbook": stats.get("insertion_excellent", 0) > 0,
		"field_geologist": stats.get("samples_identified", 0) >= 3,
		"road_trip": stats.get("rover_meters", 0) >= 300,
		"slingshot": stats.get("gravity_assist", 0) > 0 and not report["lost"],
		"close_shave": stats.get("close_calls", 0) >= 5,
		"overachiever": stats.get("gold_medals", 0) >= 3,
	}
	for achievement_id in checks:
		if checks[achievement_id] and not achievement_id in data["achievements"]:
			data["achievements"].append(achievement_id)
			earned.append(achievement_id)
	summary["new_achievements"] = earned
	return summary

# Awards one achievement right away (for the minigames you play outside a mission report). Returns true if it's new.
static func award(data, achievement_id):
	if not ACHIEVEMENTS.has(achievement_id) or achievement_id in data["achievements"]:
		return false
	data["achievements"].append(achievement_id)
	return true

# Buys an upgrade if there are enough research points. Returns true if it was bought.
static func buy_upgrade(data, upgrade_id):
	if not UPGRADES.has(upgrade_id) or upgrade_id in data["upgrades"]:
		return false
	if UPGRADES[upgrade_id].has("requires") and not UPGRADES[upgrade_id]["requires"] in data["upgrades"]:
		return false
	if data["research"] < UPGRADES[upgrade_id]["cost"]:
		return false
	data["research"] -= UPGRADES[upgrade_id]["cost"]
	data["upgrades"].append(upgrade_id)
	if not "researcher" in data["achievements"]:
		data["achievements"].append("researcher")
	return true
