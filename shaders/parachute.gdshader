// A disk-gap-band parachute like Perseverance's: alternating orange and white gores, with an open ring (the "gap").
shader_type spatial;
render_mode cull_disabled;

uniform vec3 band_color : source_color = vec3(0.93, 0.45, 0.12);
uniform vec3 cloth_color : source_color = vec3(0.95, 0.94, 0.9);
varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float angle = atan(local_position.x, local_position.z) / 6.2832 + 0.5;
	float gore = mod(floor(angle * 20.0), 2.0);
	float height = local_position.y;   // 0 at the rim, 1 at the top of the dome
	if (height > 0.42 && height < 0.5) {
		discard;   // the gap between the disk and the band
	}
	ALBEDO = mix(cloth_color, band_color, gore * step(0.5, height) + (1.0 - gore) * step(height, 0.42) * 0.85);
	ROUGHNESS = 0.85;
}
