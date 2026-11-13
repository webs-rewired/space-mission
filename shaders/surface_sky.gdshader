// The sky over a landing site.
// Worlds with air: a color from the horizon up (Mars's butterscotch with a bluish glow around the Sun, Titan's orange
// haze, Venus's thick yellow murk), and Pluto's thin layers of blue haze just above the horizon.
// Airless worlds: black. The Sun's disk is its real size from that distance (the light's angular size): bigger
// than from Earth on Mercury, a dazzling point at Pluto. Stars only show where the ground isn't sunlit and dazzling:
// in daylight, cameras (and eyes) can't see them, which is why the Apollo photos have black, starless skies.
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.0);
uniform vec3 horizon_color : source_color = vec3(0.0);
uniform vec3 ground_color : source_color = vec3(0.05);
uniform float horizon_softness = 0.35;
uniform float sky_energy = 1.0;
uniform vec3 sun_halo_color : source_color = vec3(0.0);   // Mars: dust scatters blue light forward, around the Sun
uniform float sun_halo_size = 0.12;                        // radians
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.97, 0.9);
uniform float sun_glow_strength = 0.0;                     // glare around the Sun
uniform float sun_disk_strength = 1.0;                     // 0 where thick clouds hide the Sun's disk
uniform vec3 band_color : source_color = vec3(0.3, 0.5, 1.0);
uniform float band_strength = 0.0;                         // Pluto's blue haze layers
uniform sampler2D star_map : source_color, filter_linear, hint_default_black;
uniform float star_brightness = 0.0;

void sky() {
	vec3 direction = EYEDIR;
	float up = direction.y;
	vec3 color;
	if (up >= 0.0) {
		color = mix(horizon_color, zenith_color, pow(up, horizon_softness));
	} else {
		color = mix(horizon_color, ground_color, smoothstep(0.0, 0.08, -up));
	}
	color *= sky_energy;
	if (band_strength > 0.0) {
		color += band_color * band_strength * (exp(-abs(up - 0.015) * 70.0) + 0.6 * exp(-abs(up - 0.05) * 90.0) + 0.3 * exp(-abs(up - 0.09) * 110.0));
	}
	if (star_brightness > 0.0 && up > -0.05) {
		color += texture(star_map, SKY_COORDS).rgb * star_brightness;
	}
	if (LIGHT0_ENABLED) {
		float angle = acos(clamp(dot(direction, LIGHT0_DIRECTION), -1.0, 1.0));
		float radius = max(LIGHT0_SIZE * 0.5, 0.0012);
		float disk = 1.0 - smoothstep(radius * 0.85, radius, angle);
		color += LIGHT0_COLOR * LIGHT0_ENERGY * disk * sun_disk_strength * 30.0;
		color += sun_halo_color * exp(-angle / max(sun_halo_size, 0.001)) * LIGHT0_ENERGY;
		color += sun_glow_color * sun_glow_strength * exp(-angle / (radius * 5.0 + 0.01)) * LIGHT0_ENERGY;
	}
	COLOR = color;
}
