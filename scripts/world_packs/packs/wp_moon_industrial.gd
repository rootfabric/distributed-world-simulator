extends "res://scripts/world_packs/packs/pack_profile_base.gd"

## WP0.3 — Moon Industrial R1 presentation profile.
##
## Flagship pack for the digging/outpost experience. Presentation only:
## grey basalt regolith, hard sunlight, deep dark star dome, industrial
## props, sparse rock scatter, dust scars. Asset-free by design.


func spec() -> Dictionary:
	return {
		"pack_id": "WP-MOON-INDUSTRIAL",
		"manifest_path": "res://config/world_packs/packs/wp_moon_industrial.v1.json",
		"seed": 2701,
		"sky": {
			"mode": "star_dome",
			"top": Color(0.004, 0.005, 0.008),
			"horizon": Color(0.02, 0.022, 0.03),
			"ground_bottom": Color(0.01, 0.01, 0.012),
			"ground_horizon": Color(0.02, 0.02, 0.028),
		},
		"ambient": {
			"color": Color(0.18, 0.2, 0.26),
			"energy": 0.42,
		},
		"sun": {
			"color": Color(1.0, 0.96, 0.9),
			"energy": 1.7,
			"rotation_degrees": Vector3(-52.0, -28.0, 0.0),
			"shadow": true,
		},
		"fog": {
			"enabled": false,
		},
		"ground": {
			"size": Vector2(14.0, 14.0),
			"albedo_a": Color(0.16, 0.17, 0.18),
			"noise_frequency": 0.01,
			"roughness": 0.97,
			"metallic": 0.0,
		},
		"scatter": {
			"count": 90,
			"area": Vector2(12.0, 12.0),
			"scale_min": 0.15,
			"scale_max": 0.9,
			"color_a": Color(0.2, 0.21, 0.22),
			"color_b": Color(0.33, 0.34, 0.36),
			"roughness": 0.95,
			"metallic": 0.0,
		},
		"props": [
			{"type": "crate", "count": 5, "color": Color(0.38, 0.39, 0.41), "scale_min": 0.8, "scale_max": 1.3},
			{"type": "scrap", "count": 4, "color": Color(0.3, 0.31, 0.32), "scale_min": 0.7, "scale_max": 1.2},
			{"type": "antenna", "count": 2, "color": Color(0.45, 0.46, 0.48), "scale_min": 0.9, "scale_max": 1.4},
			{"type": "pipe", "count": 2, "color": Color(0.36, 0.37, 0.39), "scale_min": 0.9, "scale_max": 1.5},
			{"type": "boulder", "count": 3, "color": Color(0.26, 0.27, 0.29), "scale_min": 0.8, "scale_max": 1.6},
		],
		"decals": {
			"count": 6,
			"color": Color(0.08, 0.08, 0.09, 0.55),
			"size_min": 1.5,
			"size_max": 3.5,
			"roughness": 1.0,
		},
		"skin": {
			"primary": Color(0.42, 0.43, 0.45),
			"secondary": Color(0.28, 0.29, 0.31),
			"accent": Color(0.9, 0.3, 0.08),
			"emissive": Color(1.0, 0.55, 0.15),
			"metallic": 0.6,
			"roughness": 0.6,
		},
	}
