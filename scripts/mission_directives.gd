extends RefCounted

# Mission directives: three bonus goals drawn at random for every mission, so flying to the same world again is
# a new challenge each time. They're shown while you design the probe and pick the rocket (so they change what
# you build), during the flight, and checked on the mission report. Each one completed earns a star and bonus XP.
#
# GameState.plan_directives() draws them; status() says how each one stands right now.
# Everything a directive looks at is already in GameState (the design, the budget, the science) or in
# GameState.mission_stats, which the flight fills in (rocks hit, science shards, photos, targets studied...).

const BONUS_XP = 40   # XP for each directive completed

# Every directive: its title, what to do, and what kind of mission it fits
#   "belt": only when the trip crosses the asteroid belt or the Kuiper belt
#   "any": every mission
const POOL = {
	"budget": {"title": "Shoestring budget", "text": "Spend no more than 75% of the budget.", "fits": "any"},
	"featherweight": {"title": "Featherweight", "text": "Launch a spacecraft lighter than 1,000 kg.", "fits": "any"},
	"every_bit": {"title": "Every last bit", "text": "Get all of your science data home (the antenna and the data recorder both matter).", "fits": "any"},
	"science_haul": {"title": "Science haul", "text": "Finish with at least 130 science.", "fits": "any"},
	"by_the_book": {"title": "Smooth flight", "text": "Nothing goes wrong: every event ends well.", "fits": "any"},
	"bold": {"title": "Fortune favors the bold", "text": "Take 2 risky choices and still succeed.", "fits": "any"},
	"thrifty_launch": {"title": "Thrifty launch", "text": "Fly on a Falcon 9 or an Atlas V.", "fits": "any"},
	"fieldwork": {"title": "Field work", "text": "Orbiters: photograph 4 places. Landers: study 2 targets on the ground.", "fits": "any"},
	"untouchable": {"title": "Untouchable", "text": "Cross the belt without a single rock strike.", "fits": "belt"},
	"prospector": {"title": "Belt prospector", "text": "Collect 6 science shards in the belt.", "fits": "belt"},
	"chain": {"title": "Chain reaction", "text": "Collect shards 4 in a row for a 4× combo.", "fits": "belt"},
	"close_calls": {"title": "Thread the needle", "text": "Make 3 close calls: pass right beside a rock.", "fits": "belt"},
}

# Draws three different directives for a mission to this destination (at most two of them about the belt)
static func draw(destination_distance_au):
	var crosses_belt = destination_distance_au > 2.0
	var general = []
	var belt = []
	for directive_id in POOL:
		if POOL[directive_id]["fits"] == "belt":
			belt.append(directive_id)
		else:
			general.append(directive_id)
	general.shuffle()
	belt.shuffle()
	var picked = []
	if crosses_belt:
		picked.append_array(belt.slice(0, randi_range(1, 2)))
	for directive_id in general:
		if picked.size() >= 3:
			break
		picked.append(directive_id)
	picked.shuffle()
	return picked

# How a directive stands: {"state": "done" / "failed" / "open", "progress": short text like "3 / 6"}
# finished: the mission is over, so anything still open counts as failed
static func status(directive_id, finished := false):
	var stats = GameState.mission_stats
	var state = "open"
	var progress = ""
	match directive_id:
		"budget":
			var share = GameState.total_cost() / max(GameState.budget(), 1.0)
			progress = "%d%%" % int(round(share * 100.0))
			state = "done" if share <= 0.75 else "open"
		"featherweight":
			var mass = GameState.total_mass()
			progress = "%s kg" % format_number(mass)
			state = "done" if mass < 1000 else "open"
		"every_bit":
			var antenna_ok = GameState.choices.get("antenna", "") == "antenna_large" or GameState.DESTINATIONS.get(GameState.destination, {}).get("small_antenna_data_share", 0.0) >= 1.0
			state = "done" if antenna_ok and GameState.recorder_share() >= 1.0 else "open"
			if finished and GameState.lost:
				state = "failed"
		"science_haul":
			progress = "%d / 130" % int(GameState.science)
			state = "done" if GameState.science >= 130 and stats.get("flying", false) else "open"
		"by_the_book":
			var went_wrong = GameState.mission_log.filter(func(entry): return not entry.get("ok", true)).size()
			if went_wrong > 0:
				state = "failed"
			elif finished:
				state = "done"
		"bold":
			progress = "%d / 2" % GameState.risky_choices
			if GameState.lost:
				state = "failed"
			elif GameState.risky_choices >= 2 and finished:
				state = "done"
		"thrifty_launch":
			# Falcon 9 flies on Merlin engines and Atlas V on an RD-180
			state = "done" if GameState.rocket.get("bottom_engine", "") in ["merlin", "rd180"] else "open"
		"fieldwork":
			if GameState.choices.get("landing", "landing_none") == "landing_none":
				progress = "%d / 4 photos" % stats.get("photos", 0)
				state = "done" if stats.get("photos", 0) >= 4 else "open"
			else:
				progress = "%d / 2 targets" % stats.get("targets", 0)
				state = "done" if stats.get("targets", 0) >= 2 else "open"
		"untouchable":
			if stats.get("rocks_hit", 0) > 0:
				state = "failed"
			elif stats.get("belts_cleared", 0) > 0:
				state = "done"
		"prospector":
			progress = "%d / 6" % stats.get("shards", 0)
			state = "done" if stats.get("shards", 0) >= 6 else "open"
		"chain":
			progress = "best %d×" % stats.get("best_combo", 0)
			state = "done" if stats.get("best_combo", 0) >= 4 else "open"
		"close_calls":
			progress = "%d / 3" % stats.get("close_calls", 0)
			state = "done" if stats.get("close_calls", 0) >= 3 else "open"
	if finished and state == "open":
		state = "failed"
	return {"state": state, "progress": progress}

static func title(directive_id):
	return POOL.get(directive_id, {}).get("title", directive_id)

static func description(directive_id):
	return POOL.get(directive_id, {}).get("text", "")

static func format_number(number):
	var digits = str(int(number))
	var result = ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return digits + result
