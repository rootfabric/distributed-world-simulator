extends "res://scripts/world_packs/packs/pack_profile_base.gd"

## WP0.4 — Mars Dust R1 presentation profile.
##
## Red/orange dust, layered rock, pervasive haze, worn industrial props,
## low-contrast horizon. Presentation only; reuses the industrial prop
## vocabulary of the Moon pack under a different palette.


func spec() -> Dictionary:
	return {
		"pack_id": "WP-MARS-DUST",
		"manifest_path": "res://config/world_packs/packs/wp_mars_dust.v1.json",
		"seed": 2404,
		"sky": {
			"mode": "procedural",
			"top": Color(0.25, 0.09, 0.04),
			"horizon": Color(0.62, 0.3, 0.12),
			"ground_bottom": Color(0.3, 0.12, 0.05),
			"ground_horizon": Color(0.55, 0.28, 0.12),
		},
		"ambient": {
			"color": Color(0.5, 0.3, 0.2),
			"energy": 0.5,
		},
		"sun": {
			"color": Color(1.0, 0.75, 0.5),
			"energy": 1.25,
			"rotation_degrees": Vector3(-38.0, -15.0, 0.0),
			"shadow": true,
		},
		"fog": {
			"enabled": true,
			"color": Color(0.66, 0.36, 0.16),
			"density": 0.012,
			"sky_affect": 0.85,
		},
		"ground": {
			"size": Vector2(14.0, 14.0),
			"albedo_a": Color(0.5, 0.2, 0.09),
			"noise_frequency": 0.008,
			"roughness": 1.0,
			"metallic": 0.0,
		},
		"scatter": {
			"count": 120,
			"area": Vector2(12.0, 12.0),
			"scale_min": 0.15,
			"scale_max": 1.0,
			"color_a": Color(0.42, 0.18, 0.08),
			"color_b": Color(0.6, 0.3, 0.14),
			"roughness": 1.0,
			"metallic": 0.0,
		},
		"props": [
			{"type": "boulder", "count": 4, "color": Color(0.45, 0.2, 0.1), "scale_min": 0.9, "scale_max": 1.7},
			{"type": "crate", "count": 3, "color": Color(0.5, 0.26, 0.13), "scale_min": 0.8, "scale_max": 1.2},
			{"type": "scrap", "count": 3, "color": Color(0.4, 0.2, 0.1), "scale_min": 0.7, "scale_max": 1.2},
			{"type": "pipe", "count": 2, "color": Color(0.46, 0.24, 0.12), "scale_min": 0.9, "scale_max": 1.4},
		],
		"decals": {
			"count": 8,
			"color": Color(0.32, 0.13, 0.06, 0.5),
			"size_min": 1.8,
			"size_max": 4.0,
			"roughness": 1.0,
		},
		"skin": {
			"primary": Color(0.52, 0.28, 0.15),
			"secondary": Color(0.34, 0.18, 0.1),
			"accent": Color(1.0, 0.62, 0.18),
			"emissive": Color(1.0, 0.66, 0.25),
			"metallic": 0.45,
			"roughness": 0.7,
		},
	}
