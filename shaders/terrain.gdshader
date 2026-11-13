// The ground at a landing site, from right under the lander out past the horizon.
// Its shape: gentle hills (flat where the lander comes down), craters, mountains and a landmark far off, all on a world
// whose ground curves away: on a small moon like Phobos the horizon is only a few hundred meters away.
// Its look: a real photo of lunar soil (around Buzz Aldrin's bootprint, Apollo 11) for the grain, a real rock photo on
// steep slopes, all tinted in the world's own colors, plus each world's own patterns: Europa's reddish cracks,
// Pluto's nitrogen ice cells, Ganymede's grooves, wind ripples in sand.
// surface_view.gd works out the same height on the computer's side (so the rover can drive on it): the hills,
// craters and curve in height_at() must stay the same as ground_height() there.
shader_type spatial;

uniform sampler2D height_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D regolith_detail : repeat_enable, filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D regolith_normal : repeat_enable, filter_linear_mipmap_anisotropic, hint_normal;
uniform sampler2D rock_detail : repeat_enable, filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D rock_normal : repeat_enable, filter_linear_mipmap_anisotropic, hint_normal;

group_uniforms colors;
uniform vec3 light_ground : source_color = vec3(0.55, 0.32, 0.18);
uniform vec3 dark_ground : source_color = vec3(0.32, 0.18, 0.1);
uniform vec3 rock_color : source_color = vec3(0.3, 0.2, 0.14);       // steep slopes, crater walls and cliffs
uniform vec3 patch_color : source_color = vec3(0.2, 0.15, 0.12);     // dark sand, sulfur, salt... depending on the world
uniform float patch_amount = 0.0;                                     // how much of the ground the patches cover (0 to 1)
uniform float patch_scale = 0.012;
uniform vec3 second_patch_color : source_color = vec3(1.0);
uniform float second_patch_amount = 0.0;
uniform float grain_strength = 1.0;                                   // how strongly the soil photo shows
uniform float ground_roughness = 0.95;
uniform float ice_sheen = 0.0;                                        // icy worlds shine a little

group_uniforms shape;
uniform float hill_height = 14.0;
uniform float flat_radius = 30.0;
uniform float world_radius = 3389500.0;                               // meters: how fast the ground curves away
uniform float near_half_size = 240.0;                                 // the detailed ground's half width
uniform float mountain_height = 0.0;
uniform float mountain_start = 900.0;                                 // keep at least 600, past where the rover drives
uniform float mountain_sharpness = 0.0;                               // 0 rolling hills, 1 jagged ridges
uniform float terrace = 0.0;                                          // flat-topped layered mesas, like Mars's
uniform vec2 landmark_direction = vec2(0.0, -1.0);
uniform float landmark_distance = 5000.0;
uniform float landmark_height = 0.0;
uniform float landmark_width = 1500.0;
uniform int landmark_kind = 0;    // 0 none, 1 layered mound (Mount Sharp), 2 volcano, 3 cliff (scarp), 4 jagged peaks, 5 basin, 6 crust block
uniform vec4 craters[48];         // x, z, radius, depth (surface_view.gd fills these in)
uniform int crater_count = 0;
uniform float crater_freshness = 0.5;                                 // fresh craters have bright rims and ejecta

group_uniforms patterns;
uniform float groove_strength = 0.0;                                  // Ganymede's and Phobos's long parallel grooves
uniform float groove_spacing = 40.0;
uniform vec2 groove_direction = vec2(1.0, 0.3);
uniform float crack_strength = 0.0;                                   // Europa's reddish cracks (lineae)
uniform vec3 crack_color : source_color = vec3(0.45, 0.25, 0.15);
uniform float crack_scale = 90.0;
uniform float cell_strength = 0.0;                                    // Pluto's nitrogen ice cells (Sputnik Planitia)
uniform float cell_size = 60.0;
uniform float ripple_strength = 0.0;                                  // wind ripples in sand
uniform vec2 ripple_direction = vec2(0.8, 0.6);

instance uniform float sink_inside = 0.0;   // set on the far ground: the part under the detailed ground drops out of sight

varying vec3 ground_position;
varying float crater_tone;

float hills(vec2 place) {
	float keep_flat = smoothstep(flat_radius, flat_radius * 4.0, length(place));
	return (texture(height_noise, place * 0.0035).r - 0.5) * hill_height * keep_flat
		+ (texture(height_noise, place * 0.03).r - 0.5) * 0.5;
}

// A bowl with a raised rim, and the blanket of thrown-out rock fading away around it
float craters_at(vec2 place, out float tone) {
	float total = 0.0;
	tone = 0.0;
	for (int index = 0; index < crater_count; index++) {
		vec4 crater = craters[index];
		float r = distance(place, crater.xy) / crater.z;
		if (r > 4.0) {
			continue;
		}
		float rim = crater.w * 0.22;
		if (r < 1.0) {
			total += rim + crater.w * (r * r - 1.0);
			tone += smoothstep(0.7, 1.0, r) * crater_freshness;
		} else {
			total += rim / (r * r * r);
			tone += crater_freshness * 0.8 / (r * r) * (1.0 - smoothstep(2.5, 4.0, r));
		}
	}
	return total;
}

float ridged(float value) {
	float ridge = 1.0 - abs(value * 2.0 - 1.0);
	return ridge * ridge;
}

// Mountains far off, and the world's landmark (none of it reaches where the rover drives)
float far_relief(vec2 place) {
	float distance_out = length(place);
	float total = 0.0;
	float rise = smoothstep(mountain_start * 0.6, mountain_start * 2.5, distance_out);
	if (rise > 0.0 && mountain_height != 0.0) {
		vec2 uv = place * 0.00013;   // mountains a few kilometers across
		float large = texture(height_noise, uv).r;
		float small = texture(height_noise, uv * 3.1 + 0.31).r;
		float shape = mix(large * 0.8 + small * 0.2, ridged(large) * 0.8 + ridged(small) * 0.3, mountain_sharpness);
		if (terrace > 0.0) {
			float steps = shape * 7.0;
			shape = mix(shape, (floor(steps) + smoothstep(0.75, 1.0, fract(steps))) / 7.0, terrace);
		}
		total += shape * mountain_height * rise;
	}
	if (landmark_kind > 0) {
		vec2 direction = normalize(landmark_direction);
		vec2 center = direction * landmark_distance;
		float across = distance(place, center) / landmark_width;
		if (landmark_kind == 1) {
			// A broad mound of rock layers with a terraced top, like Mount Sharp in Gale crater
			float mound = pow(max(1.0 - across * across, 0.0), 1.3);
			float layers = mound * 9.0;
			mound = mix(mound, (floor(layers) + smoothstep(0.6, 1.0, fract(layers))) / 9.0, 0.6);
			total += landmark_height * mound;
		} else if (landmark_kind == 2) {
			// A shield volcano with a crater (caldera) on top, like Maat Mons on Venus
			float cone = pow(max(1.0 - across, 0.0), 1.7);
			total += landmark_height * (cone - 0.06 * smoothstep(0.06, 0.0, across));
		} else if (landmark_kind == 3) {
			// A long cliff where the crust shrank and buckled (a scarp), like Mercury's
			float beyond = dot(place, direction) - landmark_distance + (texture(height_noise, place * 0.00015).r - 0.5) * landmark_width * 0.5;
			total += landmark_height * smoothstep(-landmark_width * 0.15, landmark_width * 0.15, beyond);
		} else if (landmark_kind == 4) {
			// Jagged peaks, like Pluto's water-ice mountains
			float peaks = ridged(texture(height_noise, place * 0.00028 + 0.17).r) * 0.85 + texture(height_noise, place * 0.0009).r * 0.15;
			total += landmark_height * peaks * smoothstep(1.0, 0.3, across);
		} else if (landmark_kind == 6) {
			// A tilted block of crust with steep cliffs all round, like Io's mountains
			float tilt = 0.75 + 0.25 * dot((place - center) / landmark_width, direction);
			total += landmark_height * smoothstep(1.0, 0.82, across) * tilt;
		} else if (landmark_kind == 5) {
			// A low basin (a lake bed, or a big crater floor)
			total -= abs(landmark_height) * smoothstep(1.0, 0.35, across);
		}
	}
	return total;
}

float height_at(vec2 place, out float tone) {
	float curve = dot(place, place) / (2.0 * world_radius);   // how far the ground has dropped below flat
	return hills(place) + craters_at(place, tone) + far_relief(place) - curve;
}

void vertex() {
	vec2 place = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float tone;
	float unused_tone;
	float height = height_at(place, tone);
	float step_size = sink_inside > 0.0 ? 20.0 : 1.0;
	float east = height_at(place + vec2(step_size, 0.0), unused_tone);
	float north = height_at(place + vec2(0.0, step_size), unused_tone);
	VERTEX.y += height;
	if (sink_inside > 0.0 && max(abs(place.x), abs(place.y)) < near_half_size - 0.5) {
		VERTEX.y -= 60.0;
	}
	vec3 tangent = normalize(vec3(step_size, east - height, 0.0));
	vec3 binormal = normalize(vec3(0.0, north - height, step_size));
	NORMAL = normalize(cross(binormal, tangent));
	TANGENT = tangent;
	BINORMAL = -binormal;
	ground_position = vec3(place.x, VERTEX.y, place.y);
	crater_tone = tone;
}

vec2 hash2(vec2 point) {
	point = vec2(dot(point, vec2(127.1, 311.7)), dot(point, vec2(269.5, 183.3)));
	return fract(sin(point) * 43758.5453);
}

// Distance to the nearest edge between cells (a crack network or a pattern of ice cells)
float cell_edge_distance(vec2 point) {
	vec2 cell = floor(point);
	vec2 inside = fract(point);
	vec2 nearest_offset = vec2(0.0);
	vec2 nearest_cell = vec2(0.0);
	float nearest = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 offset = neighbor + hash2(cell + neighbor) - inside;
			float distance_squared = dot(offset, offset);
			if (distance_squared < nearest) {
				nearest = distance_squared;
				nearest_offset = offset;
				nearest_cell = neighbor;
			}
		}
	}
	float edge = 8.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 neighbor = nearest_cell + vec2(float(x), float(y));
			vec2 offset = neighbor + hash2(cell + neighbor) - inside;
			if (dot(nearest_offset - offset, nearest_offset - offset) > 0.00001) {
				edge = min(edge, dot(0.5 * (nearest_offset + offset), normalize(offset - nearest_offset)));
			}
		}
	}
	return edge;
}

void fragment() {
	vec2 place = ground_position.xz;
	float distance_out = length(place);
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Big blotches of lighter and darker ground
	float patches = texture(detail_noise, place * 0.004).r;
	float blotches = texture(detail_noise, place * 0.02 + 0.37).r;
	vec3 color = mix(dark_ground, light_ground, clamp(patches * 0.8 + blotches * 0.5 - 0.15, 0.0, 1.0));
	// The world's own patches: dark sand on Mars, sulfur on Io, salt on Ceres...
	if (patch_amount > 0.0) {
		float patch_noise = texture(detail_noise, place * patch_scale + 0.71).r * 0.8 + blotches * 0.2;
		color = mix(color, patch_color, smoothstep(1.0 - patch_amount - 0.04, 1.0 - patch_amount + 0.04, patch_noise));
	}
	if (second_patch_amount > 0.0) {
		float second_noise = texture(detail_noise, place * patch_scale * 0.6 + 0.23).r;
		color = mix(color, second_patch_color, smoothstep(1.0 - second_patch_amount - 0.03, 1.0 - second_patch_amount + 0.03, second_noise));
	}

	// The soil photo at two sizes, so its repeat doesn't show
	float grain_near = texture(regolith_detail, place * 0.42).r;
	float grain_far = texture(regolith_detail, place * 0.093 + 0.5).r;
	float grain_fade = 1.0 - smoothstep(25.0, 300.0, distance(place, CAMERA_POSITION_WORLD.xz)) * 0.8;
	color *= 1.0 + ((grain_near - 0.5) * 1.1 + (grain_far - 0.5) * 0.6) * grain_strength * grain_fade;
	color *= 1.0 + clamp(crater_tone, -1.0, 1.5) * 0.3;

	if (groove_strength > 0.0) {
		float wobble = (texture(detail_noise, place * 0.002).r - 0.5) * 10.0;
		float groove = sin(dot(place, normalize(groove_direction)) / groove_spacing * 6.2831 + wobble);
		color *= 1.0 - groove_strength * 0.3 * smoothstep(0.55, 1.0, groove);
	}
	if (crack_strength > 0.0) {
		vec2 warp = vec2(texture(detail_noise, place * 0.003).r, texture(detail_noise, place * 0.003 + 0.5).r) - 0.5;
		float edge = cell_edge_distance(place / crack_scale + warp * 0.8);
		float line = 1.0 - smoothstep(0.0, 0.035, edge);
		float band = 1.0 - smoothstep(0.035, 0.11, edge);   // the reddish stain on either side of a crack
		color = mix(color, crack_color, (line * 0.9 + band * 0.35) * crack_strength);
	}
	if (cell_strength > 0.0) {
		float edge = cell_edge_distance(place / cell_size);
		color *= 1.0 - cell_strength * (1.0 - smoothstep(0.0, 0.1, edge)) * 0.5;
		color *= 1.0 + cell_strength * 0.08 * smoothstep(0.1, 0.4, edge);
	}
	if (ripple_strength > 0.0) {
		float ripple = sin(dot(place, normalize(ripple_direction)) * 3.6 + texture(detail_noise, place * 0.05).r * 9.0);
		color *= 1.0 + ripple * ripple_strength * 0.08 * grain_fade;
	}

	// Steep ground (crater walls, cliffs, mountainsides) is bare rock
	float steep = smoothstep(0.8, 0.6, world_normal.y);
	vec3 blend = pow(abs(world_normal), vec3(4.0));
	blend /= blend.x + blend.y + blend.z;
	float rock_grain = texture(rock_detail, ground_position.zy * 0.06).r * blend.x
		+ texture(rock_detail, ground_position.xz * 0.06).r * blend.y
		+ texture(rock_detail, ground_position.xy * 0.06).r * blend.z;
	color = mix(color, rock_color * (0.45 + rock_grain), steep);

	ALBEDO = clamp(color, 0.0, 1.0);
	ROUGHNESS = mix(ground_roughness, 0.4, ice_sheen * (1.0 - steep));
	SPECULAR = 0.35 + ice_sheen * 0.3;
	vec3 normal_near = texture(regolith_normal, place * 0.42).rgb;
	vec3 normal_far = texture(regolith_normal, place * 0.093 + 0.5).rgb;
	vec3 normal_rock = texture(rock_normal, place * 0.06).rgb;
	NORMAL_MAP = mix(mix(normal_near, normal_far, 0.35), normal_rock, steep);
	NORMAL_MAP_DEPTH = 1.0 * grain_fade * grain_fade;
}
