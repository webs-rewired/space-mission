extends RefCounted

# The physics of the Gravity-Assist Planner (scripts/gravity_assist.gd), kept apart from its screen.
#
# A gravity assist, the way NASA plans them (the "patched conic" method used for Voyager, Galileo and Cassini):
#   1. Far from the planet, the spacecraft moves relative to the planet at a speed v∞ ("v-infinity").
#   2. Swinging past, the planet's gravity bends that relative velocity by an angle δ, but doesn't change its size:
#        δ = 2 × asin(1 / (1 + rp × v∞² / μ))       rp = closest distance from the planet's center, μ = its GM
#      Closer passes and heavier planets bend it more; faster arrivals bend less.
#   3. Seen from the Sun, the spacecraft's velocity is the planet's velocity plus the bent v∞. Bending v∞ toward
#      the planet's direction of travel adds speed (the planet gives up a tiny bit of its own); bending it the
#      other way takes speed away (how MESSENGER slowed down to reach Mercury).
# Then the new velocity gives a new orbit around the Sun (vis-viva and angular momentum), and its farthest point
# says whether it reaches the destination.
# Simplified for the game (and said so on screen): planets on circular orbits in one flat plane.

const SUN_MU = 132712440018.0   # km³/s² (NASA JPL)
const AU_KM = 149597870.7

# Planets you can fly past: [orbit radius (AU), GM (km³/s²), radius (km), lowest safe pass above the cloud tops or
# ground (km), a real mission that used it]
const FLYBY_PLANETS = {
	"Venus": [0.723, 324859.0, 6051.8, 300.0, "Cassini flew past Venus twice (1998 and 1999) on its way to Saturn."],
	"Earth": [1.0, 398600.4, 6371.0, 300.0, "Juno came back past Earth in 2013, two years after launch: NASA said the flyby boosted its speed by more than 16,330 mph (about 7.3 km/s)."],
	"Mars": [1.524, 42828.4, 3389.5, 200.0, "Rosetta used a Mars flyby in 2007 on its way to comet 67P."],
	"Jupiter": [5.203, 126686534.0, 69911.0, 300000.0, "Voyager 2, New Horizons and Cassini all borrowed speed from Jupiter. Passes closer than a few hundred thousand km get dangerous radiation doses."],
}

static func circular_speed(radius_km):
	return sqrt(SUN_MU / radius_km)

static func bend_angle(v_infinity, closest_km, planet_mu):
	return 2.0 * asin(1.0 / (1.0 + closest_km * v_infinity * v_infinity / planet_mu))

# The speed at the closest point of the flyby (km/s): v∞ plus what falling into the planet's gravity adds
static func speed_at_closest(v_infinity, closest_km, planet_mu):
	return sqrt(v_infinity * v_infinity + 2.0 * planet_mu / closest_km)

# A burn at the closest point (a "powered flyby") changes v∞ on the way out, and the Oberth effect makes it count
# for more than the same burn far away: v∞ out = √((v at closest + burn)² − 2μ/rp)
static func v_infinity_after_burn(v_infinity, closest_km, planet_mu, burn):
	var fast = speed_at_closest(v_infinity, closest_km, planet_mu) + burn
	return sqrt(max(fast * fast - 2.0 * planet_mu / closest_km, 0.0))

# The orbit around the Sun from a position and velocity (km, km/s, flat plane):
# {"apoapsis", "periapsis" (km), "eccentricity", "escapes" (true if it leaves the solar system),
#  "semi_major", "angular_momentum", "periapsis_angle"}
static func sun_orbit(position, velocity):
	var radius = position.length()
	var speed = velocity.length()
	var energy = speed * speed / 2.0 - SUN_MU / radius
	var angular_momentum = position.x * velocity.y - position.y * velocity.x
	var eccentricity_vector = (position * (speed * speed - SUN_MU / radius) - velocity * position.dot(velocity)) / SUN_MU
	var eccentricity = eccentricity_vector.length()
	var semi_latus = angular_momentum * angular_momentum / SUN_MU
	var periapsis = semi_latus / (1.0 + eccentricity)
	var escapes = energy >= 0.0
	var apoapsis = INF if escapes else semi_latus / (1.0 - eccentricity)
	return {"apoapsis": apoapsis, "periapsis": periapsis, "eccentricity": eccentricity, "escapes": escapes,
		"semi_major": -SUN_MU / (2.0 * energy) if not escapes else INF, "angular_momentum": angular_momentum,
		"periapsis_angle": atan2(eccentricity_vector.y, eccentricity_vector.x), "semi_latus": semi_latus}

# Points along an orbit around the Sun (for drawing), starting at the given angle and going the way it moves
static func orbit_points(orbit, start_angle, sweep, steps, farthest_km):
	var points = PackedVector2Array()
	var direction = sign(orbit["angular_momentum"])
	for step in steps + 1:
		var angle = start_angle + direction * sweep * step / steps
		var true_anomaly = angle - orbit["periapsis_angle"]
		var denominator = 1.0 + orbit["eccentricity"] * cos(true_anomaly)
		if denominator <= 0.02:
			break
		var radius = orbit["semi_latus"] / denominator
		if radius > farthest_km:
			points.append(Vector2(cos(angle), sin(angle)) * farthest_km)
			break
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
