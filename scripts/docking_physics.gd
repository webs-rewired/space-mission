extends RefCounted

# The physics of the Docking Trainer (scripts/docking.gd), kept apart from its screen.
#
# Close to the Space Station, the spacecraft and the station are both in orbit around Earth, so they don't move
# in straight lines relative to each other. NASA's rendezvous planners use the Clohessy-Wiltshire (Hill's)
# equations for this, in the station's own frame:
#   radial (up, away from Earth)          ẍ = 3n²x + 2nẏ + thrust
#   along-track (the way the station flies) ÿ = −2nẋ + thrust
#   cross-track (sideways out of the orbit) z̈ = −n²z + thrust
# n is how fast the station goes around Earth (once every 92.9 minutes, so n ≈ 0.00113 radians per second).
# The surprise: if you drift toward the station from in front of it (ẏ < 0), you're moving a little slower than
# the station, so you sink toward Earth (2nẏ is negative). Real crews correct for this all the way in.
# The station flies "forward port first", so the spacecraft comes in from in front, along the velocity vector
# (the "V-bar approach" that Crew Dragon and Starliner use to reach the forward docking port).
#
# Simplified for the game (and said so on screen): no plume forces on the station, the station holds still in
# its orbit frame, and the thrusters push with a fixed acceleration.

const ORBIT_SECONDS = 92.9 * 60.0     # the Space Station's orbit (about 92.9 minutes at roughly 420 km up)
const MEAN_MOTION = TAU / ORBIT_SECONDS

# Position and velocity in the station's frame (meters, meters per second): x up, y forward, z sideways
var position = Vector3.ZERO
var velocity = Vector3.ZERO
var mean_motion = MEAN_MOTION     # radians per second around the world being orbited (the Space Station's by default)

func set_state(new_position, new_velocity):
	position = new_position
	velocity = new_velocity

# Moves the spacecraft along for delta seconds with a thrust acceleration (m/s², in the station's frame).
# Small steps keep the integration accurate.
func step(delta, thrust_acceleration := Vector3.ZERO, longest_step := 0.02):
	var steps = max(1, int(ceil(delta / longest_step)))
	var small = delta / steps
	for index in steps:
		var n = mean_motion
		var acceleration = Vector3(
			3.0 * n * n * position.x + 2.0 * n * velocity.y,
			-2.0 * n * velocity.x,
			-n * n * position.z) + thrust_acceleration
		velocity += acceleration * small
		position += velocity * small

# The drift orbital mechanics alone adds per second right now (for the screen's "drift" readout)
func natural_acceleration():
	var n = mean_motion
	return Vector3(3.0 * n * n * position.x + 2.0 * n * velocity.y, -2.0 * n * velocity.x, -n * n * position.z)
