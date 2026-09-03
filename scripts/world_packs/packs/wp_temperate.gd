extends "res://scripts/world_packs/packs/pack_profile_base.gd"

## WP0.7 — Temperate R1 presentation profile.
##
## Soil/rock/grass surfaces, wet/dry patches, simple vegetation dressing,
## softer sky. Presentation only: ECO remains the owner of ecological truth
## and this pack simulates none of it.


func spec() -> Dictionary:
	return {
		"pack_id": "WP-TEMPERATE",
		"manifest_path": "res://config/world_packs/packs/wp_temperate.v1.json",
		"seed": 707,
		"sky": {
			"mode": "procedural",
			"top": Color(0.3, 0.5, 0.75),
			"horizon": Color(0.7, 0.8, 0.85),
			"ground_bottom": Color(0.45, 0.42, 0.3),
			"ground_horizon": Color(0.62, 0.66, 0.62),
		},
		"ambient": {
			"color": Color(0.55, 0.6, 0.6),
			"energy": 0.55,
		},
		"sun": {
			"color": Color(1.0, 0.97, 0.88),
			"energy": 1.3,
			"rotation_degrees": Vector3(-45.0, -20.0, 0.0),
			"shadow": true,
		},
		"fog": {
			"enabled": true,
			"color": Color(0.75, 0.8, 0.82),
			"density": 0.004,
			"sky_affect": 0.35,
		},
		"ground": {
			"size": Vector2(14.0, 14.0),
			"albedo_a": Color(0.35, 0.26, 0.16),
			"noise_frequency": 0.01,
			"roughness": 0.95,
			"metallic": 0.0,
		},
		"scatter": {
			"count": 60,
			"area": Vector2(12.0, 12.0),
			"scale_min": 0.12,
			"scale_max": 0.7,
			"color_a": Color(0.3, 0.28, 0.25),
			"color_b": Color(0.35, 0.38, 0.28),
			"roughness": 0.9,
			"metallic": 0.0,
		},
		"props": [
			{"type": "tree", "count": 4, "color": Color(0.3, 0.2, 0.12), "secondary_color": Color(0.25, 0.42, 0.18), "scale_min": 0.8, "scale_max": 1.5},
			{"type": "grass_tuft", "count": 10, "color": Color(0.32, 0.45, 0.2), "scale_min": 0.7, "scale_max": 1.4},
			{"type": "boulder", "count": 3, "color": Color(0.4, 0.39, 0.37), "scale_min": 0.7, "scale_max": 1.4},
			{"type": "crate", "count": 2, "color": Color(0.45, 0.4, 0.32), "scale_min": 0.8, "scale_max": 1.1},
		],
		"decals": {
			"count": 5,
			"color": Color(0.2, 0.16, 0.1, 0.45),
			"size_min": 1.5,
			"size_max": 3.2,
			"roughness": 0.35,
		},
		"skin": {
			"primary": Color(0.48, 0.42, 0.34),
			"secondary": Color(0.32, 0.28, 0.22),
			"accent": Color(0.9, 0.65, 0.2),
			"emissive": Color(1.0, 0.75, 0.3),
			"metallic": 0.35,
			"roughness": 0.7,
		},
	}
