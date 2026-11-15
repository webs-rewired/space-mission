extends RefCounted

# The physics of the Engine Test Lab (scripts/engine_test_lab.gd), kept apart from its screen.
#
# Real numbers (from scripts/rocket_data.gd, the same engines as the rocket builder): thrust at sea level and in
# a vacuum, specific impulse (Isp) at sea level and in a vacuum, engine mass, and the propellants. Added here:
# each engine's chamber pressure, its usual oxidizer-to-fuel mixture ratio and how far it can throttle, from
# public NASA and manufacturer figures (rounded; marked "about" on screen).
#
# The relationships are the real ones:
#   mass flow (kg/s) = thrust / (Isp × g0)                  the rocket equation's exhaust speed is Isp × g0
#   thrust grows with chamber pressure (here, in step with the throttle)
#   Isp is best near the usual mixture ratio and falls off either side (too much oxygen also runs much hotter)
#   in a vacuum the exhaust expands fully, so thrust and Isp are higher than at sea level
# Simplified for the game (and said so on screen): the mixture curve is a smooth approximation, the wall
# temperature is a simple heating-and-cooling model, and ignition and shutdown are short ramps.

const G0 = 9.80665

# [chamber pressure in MPa, usual mixture ratio (oxidizer ÷ fuel by mass), lowest throttle, highest throttle]
const ENGINE_DETAILS = {
	"merlin": [9.7, 2.36, 0.40, 1.00],
	"rd180": [26.7, 2.72, 0.47, 1.00],
	"rs25": [20.6, 6.03, 0.67, 1.09],
	"raptor": [30.0, 3.6, 0.40, 1.00],
	"f1": [7.0, 2.27, 1.00, 1.00],
	"rs68a": [10.3, 5.97, 0.55, 1.02],
	"vulcain2": [11.7, 6.1, 1.00, 1.00],
	"merlin_vacuum": [9.7, 2.36, 0.39, 1.00],
	"rl10": [4.4, 5.88, 1.00, 1.00],
	"rl10c": [4.4, 5.5, 1.00, 1.00],
	"raptor_vacuum": [30.0, 3.6, 0.40, 1.00],
	"j2": [5.3, 5.5, 1.00, 1.00],
}
# Hottest the chamber wall may get before the test stand shuts the engine down (a game number)
const WALL_LIMIT = 1000.0
const START_SECONDS = 2.0      # ignition ramps up over this long
const STOP_SECONDS = 1.0

var engine_id = "merlin"
var engine = {}
var details = [10.0, 2.5, 0.5, 1.0]
var in_vacuum = false
var throttle = 1.0            # share of rated thrust asked for
var mixture = 2.36            # oxidizer ÷ fuel
var running = false
var spool = 0.0               # 0 (off) to 1 (fully running), the ignition and shutdown ramps
var wall_temperature = 300.0  # kelvin
var propellant_used = 0.0     # kg
var burn_seconds = 0.0
var failed = ""               # why the test stand cut the engine, if it did
var shake = 0.0               # roughness of the burn (combustion getting unstable)

func set_up(new_engine_id, engine_data):
	engine_id = new_engine_id
	engine = engine_data
	details = ENGINE_DETAILS.get(new_engine_id, [10.0, 2.5, 0.6, 1.0])
	mixture = details[1]
	throttle = 1.0
	in_vacuum = engine.get("stage", "bottom") == "top"   # top-stage engines are tested in a vacuum chamber
	reset()

func reset():
	running = false
	spool = 0.0
	wall_temperature = 300.0
	propellant_used = 0.0
	burn_seconds = 0.0
	failed = ""
	shake = 0.0

func can_throttle():
	return details[2] < details[3]

# How far the mixture is from the usual one, as a share (+0.1 = 10% more oxygen than usual)
func mixture_offset():
	return (mixture - details[1]) / details[1]

# Rated thrust where the engine is (kN). Top-stage engines can't fire at sea level: their huge nozzles would
# let the outside air push in, so the stand doesn't allow it.
func rated_thrust():
	if in_vacuum:
		return engine.get("thrust_vacuum", 0.0)
	return engine.get("thrust_sea_level", engine.get("thrust_vacuum", 0.0) * 0.6)

func rated_isp():
	if in_vacuum:
		return engine.get("isp_vacuum", 300.0)
	return engine.get("isp_sea_level", engine.get("isp_vacuum", 300.0) * 0.8)

# Isp right now: best at the usual mixture, a little lower when throttled down
func isp():
	var offset = mixture_offset()
	var mixture_factor = 1.0 - 1.8 * offset * offset
	var throttle_factor = 1.0 - 0.06 * (1.0 - clamp(throttle, 0.0, 1.0))
	return rated_isp() * mixture_factor * throttle_factor

func thrust():
	return rated_thrust() * effective_throttle() * spool * (1.0 - 0.6 * max(0.0, abs(mixture_offset()) - 0.25))

# The throttle the engine actually runs at: never below its lowest setting, and up to 10% past its highest
# rated setting ("overdrive", which heats the engine fast)
func effective_throttle():
	return clamp(throttle, details[2], details[3] + 0.1)

func chamber_pressure():
	return details[0] * effective_throttle() * spool

func mass_flow():
	if spool <= 0.0:
		return 0.0
	return thrust() * 1000.0 / (isp() * G0)

# Gas temperature in the chamber (K): hotter with more oxygen (closer to burning it all), cooler fuel-rich
func gas_temperature():
	if spool <= 0.0:
		return 300.0
	var base = 3500.0 if engine.get("fuel", "") != "kerosene" else 3650.0
	return base * (1.0 + 0.9 * mixture_offset()) * (0.85 + 0.15 * effective_throttle())

func step(delta):
	if running:
		spool = min(spool + delta / START_SECONDS, 1.0)
		burn_seconds += delta
	else:
		spool = max(spool - delta / STOP_SECONDS, 0.0)
	propellant_used += mass_flow() * delta
	# The wall heats toward a level set by how hot and how hard the engine is running, and cools when it stops
	# (about 860 K at full rated power and the usual mixture; 10% more oxygen reaches the 1,000 K limit, running
	# fuel-rich runs cooler, and pushing past the engine's highest rated throttle heats it fast)
	var hot_level = 300.0
	if spool > 0.0:
		var oxygen_heat = 1.0 + 2.5 * max(mixture_offset(), -0.5)
		var overdrive_heat = 1.0 + max(0.0, throttle - details[3]) * 6.0
		hot_level = 300.0 + 560.0 * effective_throttle() * oxygen_heat * overdrive_heat * spool
	wall_temperature += (hot_level - wall_temperature) * (0.25 if spool > 0.0 else 0.4) * delta
	# Far off the usual mixture, combustion turns rough (and very fuel-rich mixtures can blow the flame out)
	shake = clamp((abs(mixture_offset()) - 0.15) * 4.0, 0.0, 1.0) * spool
	if running and wall_temperature > WALL_LIMIT:
		failed = "The chamber wall passed %d K: the test stand cut the engine before it burned through." % int(WALL_LIMIT)
		running = false
	if running and mixture_offset() < -0.35:
		failed = "So fuel-rich that the flame blew out."
		running = false
