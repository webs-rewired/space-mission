extends RefCounted

# Two-body orbital mechanics for the Orbital Insertion minigame (scripts/orbital_insertion.gd), in the plane
# of the orbit. Units: kilometers, seconds, km/s, and the world's gravitational parameter mu (GM) in km³/s².
#
#   orbit_of(position, velocity, mu)   periapsis, apoapsis, eccentricity, energy... of the path it's on
#   step(state, mu, seconds)           moves the spacecraft along (velocity Verlet integration)
#   conic_points(...)                  points along the predicted path, for drawing it
#   approach(...)                      a real arrival: a hyperbola that dips to the target periapsis
#
# These are the standard textbook equations (vis-viva, the eccentricity vector, the conic equation
# r = p / (1 + e cos θ)). Nothing here is made up for the game; what IS simplified is listed in orbital_insertion.gd.

const EARTH_MU = 398600.4418   # km³/s², Earth's GM (other worlds use their mass in Earths times this)

# Everything about the path a spacecraft at this position and velocity is on
static func orbit_of(position: Vector2, velocity: Vector2, mu: float) -> Dictionary:
	var distance = position.length()
	var speed = velocity.length()
	var energy = speed * speed / 2.0 - mu / distance                     # per kilogram: kinetic + potential
	var angular_momentum = position.x * velocity.y - position.y * velocity.x
	var eccentricity_vector = ((speed * speed - mu / distance) * position - position.dot(velocity) * velocity) / mu
	var eccentricity = eccentricity_vector.length()
	var semi_latus = angular_momentum * angular_momentum / mu
	var periapsis = semi_latus / (1.0 + eccentricity)
	var apoapsis = INF
	if eccentricity < 1.0:
		apoapsis = semi_latus / (1.0 - eccentricity)
	return {
		"energy": energy, "eccentricity": eccentricity, "periapsis": periapsis, "apoapsis": apoapsis,
		"captured": energy < 0.0, "semi_latus": semi_latus, "angular_momentum": angular_momentum,
		"periapsis_angle": atan2(eccentricity_vector.y, eccentricity_vector.x),
		"period": TAU * sqrt(pow(-mu / (2.0 * energy), 3.0) / mu) if energy < 0.0 else INF,
	}

# Moves the spacecraft along for some seconds (small sub-steps, so close passes stay accurate)
static func step(state: Dictionary, mu: float, seconds: float, thrust_acceleration := Vector2.ZERO) -> void:
	var steps = int(clamp(ceil(seconds / 2.0), 1, 400))
	var small = seconds / steps
	for index in steps:
		var acceleration = -mu * state["position"] / pow(state["position"].length(), 3.0) + thrust_acceleration
		state["velocity"] += acceleration * small * 0.5
		state["position"] += state["velocity"] * small
		acceleration = -mu * state["position"] / pow(state["position"].length(), 3.0) + thrust_acceleration
		state["velocity"] += acceleration * small * 0.5

# Points along a path (ellipse or hyperbola) for drawing, out to at most farthest km from the world's center
static func conic_points(orbit: Dictionary, farthest: float, count := 160) -> PackedVector2Array:
	var points = PackedVector2Array()
	var eccentricity = orbit["eccentricity"]
	var semi_latus = orbit["semi_latus"]
	var turn = orbit["periapsis_angle"]
	var limit = PI
	if eccentricity >= 1.0:
		limit = acos(-1.0 / eccentricity) - 0.02   # a hyperbola only has angles up to its asymptotes
	var direction = sign(orbit["angular_momentum"]) if orbit["angular_momentum"] != 0.0 else 1.0
	for index in count + 1:
		var angle = -limit + 2.0 * limit * index / count
		var radius = semi_latus / (1.0 + eccentricity * cos(angle))
		if radius <= 0.0 or radius > farthest:
			continue
		points.append(Vector2(cos(turn + angle * direction), sin(turn + angle * direction)) * radius)
	return points

# A real arrival: the spacecraft falls in on a hyperbola (it's too fast to be caught by gravity on its own)
# whose closest point is target_periapsis, sized from the braking burn this world needs
# (GameState.arrival_burn_needed_km_s, from real missions). Starts it start_distance from the world.
# Returns {"position", "velocity", "speed_at_infinity", "target_apoapsis" (the orbit the full burn gives)}.
static func approach(mu: float, target_periapsis: float, burn_needed: float, start_distance: float) -> Dictionary:
	# Arriving on a hyperbola just fast enough that half the planned burn is needed only to be caught at all, and
	# the full planned burn gives the target orbit. With the real burn sizes this gives real arrival speeds: about
	# 2.7 km/s "at infinity" at Mars and 5.7 km/s at Jupiter (Juno arrived at about 5.8), and at Jupiter a first
	# orbit reaching about 8.7 million km out (Juno's first orbit after its 2016 burn reached about 8.1 million km).
	var escape_speed = sqrt(2.0 * mu / target_periapsis)
	var periapsis_speed = escape_speed + max(burn_needed, 0.05) * 0.5
	var speed_after_burn = periapsis_speed - max(burn_needed, 0.05)
	var semi_major = 1.0 / (2.0 / target_periapsis - speed_after_burn * speed_after_burn / mu)
	var target_apoapsis = 2.0 * semi_major - target_periapsis
	var speed_at_infinity = sqrt(periapsis_speed * periapsis_speed - escape_speed * escape_speed)
	var eccentricity = 1.0 + target_periapsis * speed_at_infinity * speed_at_infinity / mu
	var semi_latus = target_periapsis * (1.0 + eccentricity)
	# Where on the incoming leg the spacecraft is start_distance away (θ negative = before the closest point)
	var cos_angle = clamp((semi_latus / start_distance - 1.0) / eccentricity, -1.0, 1.0)
	var angle = -acos(cos_angle)
	var radius = semi_latus / (1.0 + eccentricity * cos(angle))
	var speed_scale = sqrt(mu / semi_latus)
	var radial_speed = speed_scale * eccentricity * sin(angle)
	var sideways_speed = speed_scale * (1.0 + eccentricity * cos(angle))
	var outward = Vector2(cos(angle), sin(angle))
	var forward = Vector2(-sin(angle), cos(angle))
	return {"position": outward * radius, "velocity": outward * radial_speed + forward * sideways_speed, "speed_at_infinity": speed_at_infinity, "target_apoapsis": target_apoapsis}
