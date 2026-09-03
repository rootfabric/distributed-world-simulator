extends "res://scripts/world_packs/packs/pack_profile_base.gd"

## WP0.5 — Frozen World R1 presentation profile.
##
## Ice/snow surfaces, cold blue ambient response, exposed dark rock,
## frost props, low drifting haze. Presentation only; no canonical
## temperature or damage belongs to this pack.


func spec() -> Dictionary:
	return {
		"pack_id": "WP-FROZEN",
		"manifest_path": "res://config/world_packs/packs/wp_frozen.v1.json",
		"seed": 505,
		"sky": {
			"mode": "procedural",
			"top": Color(0.55, 0.68, 0.8),
			"horizon": Color(0.82, 0.88, 0.94),
			"ground_bottom": Color(0.88, 0.92, 0.96),
			"ground_horizon": Color(0.8, 0.86, 0.92),
		},
		"ambient": {
			"color": Color(0.6, 0.7, 0.85),
			"energy": 0.6,
		},
		"sun": {
			"color": Color(0.85, 0.9, 1.0),
			"energy": 0.9,
			"rotation_degrees": Vector3(-28.0, 40.0, 0.0),
			"shadow": true,
		},
		"fog": {
			"enabled": true,
			"color": Color(0.8, 0.86, 0.92),
			"density": 0.02,
			"sky_affect": 1.0,
		},
		"ground": {
			"size": Vector2(14.0, 14.0),
			"albedo_a": Color(0.85, 0.9, 0.95),
			"noise_frequency": 0.014,
			"roughness": 0.55,
			"metallic": 0.0,
		},
		"scatter": {
			"count": 70,
			"area": Vector2(12.0, 12.0),
			"scale_min": 0.2,
			"scale_max": 1.0,
			"color_a": Color(0.75, 0.85, 0.95),
			"color_b": Color(0.9, 0.96, 1.0),
			"roughness": 0.25,
			"metallic": 0.05,
		},
		"props": [
			{"type": "shard", "count": 5, "color": Color(0.8, 0.9, 1.0), "scale_min": 0.7, "scale_max": 1.6, "metallic": 0.05, "roughness": 0.2},
			{"type": "boulder", "count": 3, "color": Color(0.25, 0.28, 0.32), "scale_min": 0.8, "scale_max": 1.5},
			{"type": "antenna", "count": 1, "color": Color(0.5, 0.56, 0.62), "scale_min": 0.9, "scale_max": 1.2},
			{"type": "crate", "count": 2, "color": Color(0.55, 0.6, 0.66), "scale_min": 0.8, "scale_max": 1.1},
		],
		"decals": {
			"count": 7,
			"color": Color(0.95, 0.97, 1.0, 0.4),
			"size_min": 1.6,
			"size_max": 3.8,
			"roughness": 0.35,
		},
		"skin": {
			"primary": Color(0.6, 0.66, 0.72),
			"secondary": Color(0.4, 0.45, 0.52),
			"accent": Color(0.2, 0.7, 1.0),
			"emissive": Color(0.45, 0.85, 1.0),
			"metallic": 0.5,
			"roughness": 0.45,
		},
	}
