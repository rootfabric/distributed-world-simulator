extends "res://scripts/world_packs/packs/pack_profile_base.gd"

## WP0.6 — Volcanic World R1 presentation profile.
##
## Dark igneous rock, emissive cracks with a lava-like presentation, ash
## haze, basalt formations. Presentation only: no canonical heat, damage
## or hazard belongs to WORLD PACKS.


func spec() -> Dictionary:
	return {
		"pack_id": "WP-VOLCANIC",
		"manifest_path": "res://config/world_packs/packs/wp_volcanic.v1.json",
		"seed": 6666,
		"sky": {
			"mode": "color",
			"top": Color(0.05, 0.03, 0.035),
			"horizon": Color(0.12, 0.06, 0.05),
			"ground_bottom": Color(0.05, 0.03, 0.03),
			"ground_horizon": Color(0.1, 0.05, 0.045),
		},
		"ambient": {
			"color": Color(0.35, 0.18, 0.12),
			"energy": 0.55,
		},
		"sun": {
			"color": Color(1.0, 0.5, 0.3),
			"energy": 0.85,
			"rotation_degrees": Vector3(-35.0, 10.0, 0.0),
			"shadow": true,
		},
		"fog": {
			"enabled": true,
			"color": Color(0.12, 0.06, 0.05),
			"density": 0.01,
			"sky_affect": 0.9,
		},
		"ground": {
			"size": Vector2(14.0, 14.0),
			"albedo_a": Color(0.09, 0.07, 0.07),
			"noise_frequency": 0.016,
			"roughness": 0.9,
			"metallic": 0.0,
		},
		"scatter": {
			"count": 110,
			"area": Vector2(12.0, 12.0),
			"scale_min": 0.15,
			"scale_max": 1.1,
			"color_a": Color(0.08, 0.065, 0.06),
			"color_b": Color(0.16, 0.13, 0.12),
			"roughness": 0.95,
			"metallic": 0.0,
		},
		"props": [
			{"type": "crack", "count": 6, "color": Color(1.0, 0.32, 0.05), "scale_min": 0.8, "scale_max": 1.6},
			{"type": "boulder", "count": 4, "color": Color(0.11, 0.09, 0.09), "scale_min": 0.9, "scale_max": 1.7},
			{"type": "shard", "count": 3, "color": Color(0.14, 0.1, 0.09), "scale_min": 0.7, "scale_max": 1.4, "metallic": 0.05, "roughness": 0.7},
			{"type": "pipe", "count": 1, "color": Color(0.2, 0.16, 0.15), "scale_min": 0.9, "scale_max": 1.3},
		],
		"decals": {
			"count": 5,
			"color": Color(0.02, 0.02, 0.02, 0.6),
			"size_min": 2.0,
			"size_max": 4.2,
			"roughness": 1.0,
		},
		"skin": {
			"primary": Color(0.22, 0.19, 0.18),
			"secondary": Color(0.13, 0.11, 0.11),
			"accent": Color(1.0, 0.32, 0.05),
			"emissive": Color(1.0, 0.38, 0.06),
			"metallic": 0.55,
			"roughness": 0.65,
		},
	}
