extends "res://scripts/world_packs/packs/pack_profile_base.gd"

## WP0.8 — Alien Wetland R1 presentation profile.
##
## Wet ground, shallow-water presentation, unusual ground cover, dense fog,
## non-Earth color composition. Presentation only: no liquid simulation and
## no canonical ecology is authorized by this pack.


func spec() -> Dictionary:
	return {
		"pack_id": "WP-ALIEN-WETLAND",
		"manifest_path": "res://config/world_packs/packs/wp_alien_wetland.v1.json",
		"seed": 808,
		"sky": {
			"mode": "procedural",
			"top": Color(0.12, 0.1, 0.22),
			"horizon": Color(0.35, 0.5, 0.45),
			"ground_bottom": Color(0.1, 0.14, 0.12),
			"ground_horizon": Color(0.3, 0.45, 0.4),
		},
		"ambient": {
			"color": Color(0.35, 0.5, 0.42),
			"energy": 0.5,
		},
		"sun": {
			"color": Color(0.7, 1.0, 0.8),
			"energy": 1.0,
			"rotation_degrees": Vector3(-30.0, 60.0, 0.0),
			"shadow": true,
		},
		"fog": {
			"enabled": true,
			"color": Color(0.2, 0.35, 0.3),
			"density": 0.035,
			"sky_affect": 1.0,
		},
		"ground": {
			"size": Vector2(14.0, 14.0),
			"albedo_a": Color(0.12, 0.16, 0.13),
			"noise_frequency": 0.012,
			"roughness": 0.35,
			"metallic": 0.0,
		},
		"scatter": {
			"count": 80,
			"area": Vector2(12.0, 12.0),
			"scale_min": 0.3,
			"scale_max": 1.2,
			"color_a": Color(0.2, 0.45, 0.35),
			"color_b": Color(0.35, 0.55, 0.4),
			"roughness": 0.6,
			"metallic": 0.0,
		},
		"props": [
			{"type": "water", "count": 1, "color": Color(0.15, 0.4, 0.35), "scale_min": 1.0, "scale_max": 1.0, "size": Vector2(11.0, 11.0), "y": 0.06, "opacity": 0.7, "roughness": 0.05},
			{"type": "reed", "count": 8, "color": Color(0.25, 0.5, 0.4), "scale_min": 0.8, "scale_max": 1.6},
			{"type": "shard", "count": 3, "color": Color(0.3, 0.7, 0.6), "scale_min": 0.7, "scale_max": 1.5, "metallic": 0.4, "roughness": 0.3},
			{"type": "boulder", "count": 2, "color": Color(0.16, 0.2, 0.18), "scale_min": 0.7, "scale_max": 1.3},
		],
		"decals": {
			"count": 6,
			"color": Color(0.25, 0.5, 0.4, 0.35),
			"size_min": 1.4,
			"size_max": 3.6,
			"roughness": 0.3,
		},
		"skin": {
			"primary": Color(0.3, 0.4, 0.36),
			"secondary": Color(0.18, 0.26, 0.23),
			"accent": Color(0.6, 1.0, 0.8),
			"emissive": Color(0.5, 1.0, 0.75),
			"metallic": 0.5,
			"roughness": 0.4,
		},
	}
