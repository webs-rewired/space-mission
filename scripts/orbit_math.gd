extends RefCounted

# Real orbit math, used by the bodies, the orbit paths and the belts.
#
# Positions are worked out in the "ecliptic" frame astronomers use (x toward the spring equinox,
# z toward the north side of Earth's orbit), in AU, then turned into Godot game units.

const J2000 = 2451545.0                 # Julian date of January 1, 2000 at noon (the standard starting point)
const UNIX_EPOCH_JULIAN_DATE = 2440587.5
const MOON_DISTANCE_AU = 384400.0 / 149597870.7
const TRUE_SCALE_UNITS_PER_AU = 100.0   # at true scale, 1 AU = 100 units
const VIEWABLE_EARTH_DISTANCE = 10.0    # in the viewable layout Earth sits 10 units from the Sun
const VIEWABLE_DISTANCE_POWER = 0.6     # squeezes far distances so everything fits on screen
const VIEWABLE_MOON_DISTANCE = 1.2      # the Moon's average distance from Earth in the viewable layout

static func julian_date_now():
	return Time.get_unix_time_from_system() / 86400.0 + UNIX_EPOCH_JULIAN_DATE

static func unix_time_from_julian_date(julian_date):
	return (julian_date - UNIX_EPOCH_JULIAN_DATE) * 86400.0

const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

static func date_text(julian_date):
	var date = Time.get_datetime_dict_from_unix_time(int(floor(unix_time_from_julian_date(julian_date))))
	return "%s %d, %d" % [MONTH_NAMES[date["month"] - 1], date["day"], date["year"]]

# "14:05 UTC"
static func time_text(julian_date):
	var date = Time.get_datetime_dict_from_unix_time(int(floor(unix_time_from_julian_date(julian_date))))
	return "%02d:%02d UTC" % [date["hour"], date["minute"]]

# Solves Kepler's equation M = E - e sin(E) for E (all in radians)
static func solve_kepler(mean_anomaly, eccentricity):
	var mean = fposmod(mean_anomaly + PI, TAU) - PI
	var eccentric = mean
	if eccentricity > 0.8:
		eccentric = PI if mean >= 0.0 else -PI
	for step in 50:
		var change = (eccentric - eccentricity * sin(eccentric) - mean) / (1.0 - eccentricity * cos(eccentric))
		eccentric -= change
		if abs(change) < 1e-12:
			break
	return eccentric

# The six orbital elements at a given date: a (AU), e, then inclination, node, argument of perihelion
# and mean anomaly in radians
static func elements_at(orbit, julian_date):
	var a = 0.0
	var e = 0.0
	var inclination = 0.0
	var node = 0.0
	var argument_of_perihelion = 0.0
	var mean_anomaly = 0.0
	if orbit.has("jpl"):
		var centuries = (julian_date - J2000) / 36525.0
		var values = orbit["jpl"]
		var rates = orbit["rates"]
		a = values[0] + rates[0] * centuries
		e = values[1] + rates[1] * centuries
		inclination = values[2] + rates[2] * centuries
		var mean_longitude = values[3] + rates[3] * centuries
		var perihelion_longitude = values[4] + rates[4] * centuries
		node = values[5] + rates[5] * centuries
		argument_of_perihelion = perihelion_longitude - node
		mean_anomaly = mean_longitude - perihelion_longitude
	elif orbit.has("moon"):
		# A standard simple model of the Moon's orbit around Earth
		var days = julian_date - J2000
		a = MOON_DISTANCE_AU
		e = 0.0549
		inclination = 5.145
		var mean_longitude = 218.316 + 13.176396 * days
		var perigee_longitude = 83.353 + 0.111404 * days    # the orbit's long axis slowly turns
		node = 125.044 - 0.052954 * days                     # the orbit's tilt slowly turns backwards
		argument_of_perihelion = perigee_longitude - node
		mean_anomaly = mean_longitude - perigee_longitude
	else:
		a = orbit["a"]
		e = orbit["e"]
		inclination = orbit["i"]
		node = orbit["node"]
		argument_of_perihelion = orbit["arg_peri"]
		var period_days = orbit.get("period_days", 365.25 * pow(a, 1.5))
		mean_anomaly = orbit["mean_anomaly"] + 360.0 * (julian_date - orbit["epoch_jd"]) / period_days
	return {"a": a, "e": e, "inclination": deg_to_rad(inclination), "node": deg_to_rad(node),
		"argument_of_perihelion": deg_to_rad(argument_of_perihelion), "mean_anomaly": deg_to_rad(mean_anomaly)}

# Position on the orbit for a given eccentric anomaly, in ecliptic AU, as [x, y, z].
# Plain numbers keep full (double) precision, which matters far from the Sun at true scale.
static func position_xyz(elements, eccentric):
	var a = elements["a"]
	var e = elements["e"]
	var x_in_plane = a * (cos(eccentric) - e)
	var y_in_plane = a * sqrt(1.0 - e * e) * sin(eccentric)
	var cos_node = cos(elements["node"])
	var sin_node = sin(elements["node"])
	var cos_argument = cos(elements["argument_of_perihelion"])
	var sin_argument = sin(elements["argument_of_perihelion"])
	var cos_inclination = cos(elements["inclination"])
	var sin_inclination = sin(elements["inclination"])
	var x = (cos_argument * cos_node - sin_argument * sin_node * cos_inclination) * x_in_plane \
		+ (-sin_argument * cos_node - cos_argument * sin_node * cos_inclination) * y_in_plane
	var y = (cos_argument * sin_node + sin_argument * cos_node * cos_inclination) * x_in_plane \
		+ (-sin_argument * sin_node + cos_argument * cos_node * cos_inclination) * y_in_plane
	var z = (sin_argument * sin_inclination) * x_in_plane + (cos_argument * sin_inclination) * y_in_plane
	return [x, y, z]

static func position_from_eccentric_anomaly(elements, eccentric):
	var xyz = position_xyz(elements, eccentric)
	return Vector3(xyz[0], xyz[1], xyz[2])

# Where a body is on a given date, in ecliptic AU, measured from what it orbits (the Sun, or Earth for the Moon)
static func ecliptic_xyz(orbit, julian_date):
	var elements = elements_at(orbit, julian_date)
	var eccentric = solve_kepler(elements["mean_anomaly"], elements["e"])
	return position_xyz(elements, eccentric)

static func ecliptic_position(orbit, julian_date):
	var xyz = ecliptic_xyz(orbit, julian_date)
	return Vector3(xyz[0], xyz[1], xyz[2])

# Ecliptic AU [x, y, z] to game units [x, y, z] (Godot directions), at full precision
static func game_xyz(ecliptic, true_scale):
	var godot_x = ecliptic[0]
	var godot_y = ecliptic[2]
	var godot_z = -ecliptic[1]
	var factor = TRUE_SCALE_UNITS_PER_AU
	if not true_scale:
		var distance = sqrt(godot_x * godot_x + godot_y * godot_y + godot_z * godot_z)
		if distance == 0.0:
			return [0.0, 0.0, 0.0]
		factor = VIEWABLE_EARTH_DISTANCE * pow(distance, VIEWABLE_DISTANCE_POWER) / distance
	return [godot_x * factor, godot_y * factor, godot_z * factor]

# The Moon's position from Earth: exact at true scale, about 1.2 units away in the viewable layout
static func moon_offset_game_xyz(ecliptic, true_scale):
	var factor = TRUE_SCALE_UNITS_PER_AU if true_scale else VIEWABLE_MOON_DISTANCE / MOON_DISTANCE_AU
	return [ecliptic[0] * factor, ecliptic[2] * factor, -ecliptic[1] * factor]

# Ecliptic (x, y, z north) to Godot (x, y up, z toward the viewer)
static func to_godot(ecliptic):
	return Vector3(ecliptic.x, ecliptic.z, -ecliptic.y)

# Turns an ecliptic position in AU into game units.
# True scale is exact. The viewable layout keeps every direction exact but squeezes distances.
static func to_game_units(ecliptic_au, true_scale):
	var godot = to_godot(ecliptic_au)
	if true_scale:
		return godot * TRUE_SCALE_UNITS_PER_AU
	var distance = godot.length()
	if distance == 0.0:
		return godot
	return godot / distance * VIEWABLE_EARTH_DISTANCE * pow(distance, VIEWABLE_DISTANCE_POWER)

static func moon_offset_to_game_units(ecliptic_au, true_scale):
	var godot = to_godot(ecliptic_au)
	if true_scale:
		return godot * TRUE_SCALE_UNITS_PER_AU
	return godot / MOON_DISTANCE_AU * VIEWABLE_MOON_DISTANCE

# How a body sits in space before it spins: its north pole (local +y) and where its prime meridian
# (longitude 0, local -z) points when its spin angle is 0. Uses the official IAU pole directions.
# With the IAU spin angle W added (see spin_angle_at), longitude 0 faces the right way on the right date,
# so it's daytime in Texas when it really is.
static func pole_basis(body):
	var pole = Vector3.ZERO
	var node_direction = Vector3.ZERO
	if body.has("pole_ra"):
		# Sky coordinates (right ascension, declination), turned into the ecliptic frame with Earth's 23.44° tilt
		var right_ascension = deg_to_rad(body["pole_ra"])
		var declination = deg_to_rad(body["pole_dec"])
		pole = equatorial_to_ecliptic(Vector3(cos(declination) * cos(right_ascension), cos(declination) * sin(right_ascension), sin(declination)))
		node_direction = equatorial_to_ecliptic(Vector3(-sin(right_ascension), cos(right_ascension), 0.0))
	else:
		var tilt = deg_to_rad(body.get("tilt", 0.0))
		var toward = deg_to_rad(body.get("tilt_toward", 0.0))
		pole = Vector3(sin(tilt) * cos(toward), sin(tilt) * sin(toward), cos(tilt))
		node_direction = Vector3(-sin(toward), cos(toward), 0.0)
	pole = to_godot(pole).normalized()
	node_direction = to_godot(node_direction).normalized()
	return Basis(-pole.cross(node_direction), pole, -node_direction)

static func equatorial_to_ecliptic(equatorial):
	var obliquity = deg_to_rad(23.43928)
	return Vector3(equatorial.x,
		equatorial.y * cos(obliquity) + equatorial.z * sin(obliquity),
		-equatorial.y * sin(obliquity) + equatorial.z * cos(obliquity))

# Direction a body's north pole points, in Godot coordinates
static func pole_direction(body):
	return pole_basis(body).y

# The real spin angle (radians) on a date: W = W0 + rate × days since 2000 (IAU rotation models)
static func spin_angle_at(prime_meridian, julian_date):
	return fposmod(deg_to_rad(prime_meridian[0] + prime_meridian[1] * (julian_date - J2000)), TAU)

# Points along a whole orbit, for drawing its path
static func orbit_path_points(orbit, julian_date, point_count, true_scale, is_moon):
	var elements = elements_at(orbit, julian_date)
	var points = PackedVector3Array()
	for index in point_count + 1:
		var eccentric = TAU * index / point_count
		var ecliptic = position_from_eccentric_anomaly(elements, eccentric)
		if is_moon:
			points.append(moon_offset_to_game_units(ecliptic, true_scale))
		else:
			points.append(to_game_units(ecliptic, true_scale))
	return points
