shader_type spatial;
render_mode cull_back;

uniform float macro_scale : hint_range(0.005, 0.08) = 0.028;
uniform float detail_scale : hint_range(0.05, 0.5) = 0.20;
uniform float macro_strength : hint_range(0.0, 0.5) = 0.20;
uniform float detail_strength : hint_range(0.0, 0.25) = 0.075;
uniform float dry_patch_strength : hint_range(0.0, 0.25) = 0.08;
uniform float ground_roughness : hint_range(0.0, 1.0) = 0.96;
uniform bool debug_mode = false;

varying vec3 surface_local_position;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise_3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

void vertex() {
	// Local terrain vertices are authored in Earth-fixed metre offsets from the
	// procedural surface anchor. This keeps the visual pattern stable while the
	// floating render origin moves with the player/spectator.
	surface_local_position = VERTEX;
}

void fragment() {
	if (debug_mode) {
		ALBEDO = vec3(0.0);
		EMISSION = COLOR.rgb;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	} else {
		float macro = value_noise_3d(surface_local_position * macro_scale);
		float detail = value_noise_3d(
			surface_local_position * detail_scale + vec3(17.3, 3.7, 29.1)
		);
		float dry_patch = value_noise_3d(
			surface_local_position * (macro_scale * 0.43) + vec3(41.7, 11.2, 7.4)
		);

		vec3 base = COLOR.rgb;
		float macro_modulation = mix(
			1.0 - macro_strength,
			1.0 + macro_strength * 0.55,
			macro
		);
		float detail_modulation = 1.0 + (detail - 0.5) * 2.0 * detail_strength;
		vec3 color = base * macro_modulation * detail_modulation;

		// Rare, very soft dry patches break up large grassland expanses without
		// introducing a new biome/material truth.
		float dry_amount = smoothstep(0.72, 0.91, dry_patch) * dry_patch_strength;
		vec3 dry_tint = color * vec3(1.03, 0.90, 0.72);
		color = mix(color, dry_tint, dry_amount);

		ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
		EMISSION = vec3(0.0);
		ROUGHNESS = clamp(ground_roughness + (detail - 0.5) * 0.035, 0.0, 1.0);
		SPECULAR = 0.12;
	}
}
