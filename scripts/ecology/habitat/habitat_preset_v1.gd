extends RefCounted
## Versioned input recipe, not a biological model. All founders and transitions
## come from the accepted A1-A10.5 stack; no archetype is required.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")

const PRESET_ID := "eco/a11/wet-dry-dark/v1"
const DEFAULT_SEED := 20260912
const DEFAULT_HORIZON := 256

static func create(seed: int = DEFAULT_SEED, horizon: int = DEFAULT_HORIZON) -> Dictionary:
	if not C.integer(seed, 0, C.MAX_INT) or not C.integer(horizon, 1, 4096):
		return {}
	var manifest := {
		"schema": Manifest.SCHEMA,
		"experiment_id": PRESET_ID,
		"seed": seed,
		"horizon_ticks": horizon,
		"founders": [
			{"founder_id": "founder/a", "biological_hash": null, "genome": Protocol.ancestor()},
			{"founder_id": "founder/b", "biological_hash": null, "genome": Fixtures.make(1)},
		],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 3, "depth": 1},
			"zones": [
				{"id": "wet", "water_mg": 800000, "light": 800, "temperature": 500, "nutrient_mg": 2000, "organic_mg": 0},
				{"id": "dry", "water_mg": 200000, "light": 900, "temperature": 600, "nutrient_mg": 300, "organic_mg": 0},
				{"id": "dark", "water_mg": 100000, "light": 100, "temperature": 450, "nutrient_mg": 100, "organic_mg": 0},
			],
		},
		# Same genome across two environments + another canonical founder.
		"placement": {"entries": [
			{"founder_ref": "founder/a", "zone_id": "wet", "position_mm": [500, 0, 500]},
			{"founder_ref": "founder/a", "zone_id": "dry", "position_mm": [1500, 0, 500]},
			{"founder_ref": "founder/b", "zone_id": "dark", "position_mm": [2500, 0, 500]},
		]},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population", "resources", "lineage"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "LAB",
	}
	return manifest if Manifest.validate(manifest).is_empty() else {}
