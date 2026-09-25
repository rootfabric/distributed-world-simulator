extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P1 ExperimentManifest v1 tests.
# Runner: Godot headless --script; prints checks/failed counts and PASS/FAIL.

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P1_FAIL " + message)

func _program() -> Dictionary:
	return {
		"schema": P.SCHEMA, "entry": "r1", "max_age": 32, "max_depth": 4,
		"rules": [P.rule("r1", [P.action("extend", "support", [0, 100, 0], 10)])],
	}

func _valid_manifest() -> Dictionary:
	var founder := Genome.create(_program(), "founder-a")
	return {
		"schema": Manifest.SCHEMA,
		"experiment_id": "eco-polygon/exp-001",
		"seed": 12345,
		"horizon_ticks": 2000,
		"founders": [
			{"founder_id": "founder/a", "biological_hash": Genome.biological_hash(founder), "genome": null},
			{"founder_id": "founder/b", "biological_hash": null, "genome": founder},
		],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 4, "depth": 4},
			"zones": [
				{"id": "zone/wet", "water_mg": 500000, "light": 700, "temperature": 500, "nutrient_mg": 1000, "organic_mg": 0},
				{"id": "zone/dry", "water_mg": 50000, "light": 900, "temperature": 600, "nutrient_mg": 100, "organic_mg": 0},
			],
		},
		"placement": {
			"entries": [
				{"founder_ref": "founder/a", "zone_id": "zone/wet", "position_mm": [500, 0, 500]},
				{"founder_ref": "founder/b", "zone_id": "zone/dry", "position_mm": [1500, 0, 1500]},
			],
		},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population", "diversity"]},
		"checkpoint": {"interval_ticks": 100},
		"mode": "LAB",
	}

func _run() -> void:
	# 1. Valid manifest validates and hashes deterministically.
	var manifest := _valid_manifest()
	_check(Manifest.validate(manifest) == "", "valid manifest passes validation")
	var hash_a := Manifest.canonical_hash(manifest)
	_check(not hash_a.is_empty(), "valid manifest has canonical hash")
	_check(Manifest.canonical_hash(_valid_manifest()) == hash_a, "same manifest produces same hash")
	_check(not hash_a.is_empty() and hash_a.length() == 64, "canonical hash is sha256")

	# 2. Field insertion order does not alter the canonical hash.
	var reordered := {}
	for key in ["mode", "checkpoint", "metrics", "feedback", "organization_profile", "mutation", "placement", "environment", "founders", "horizon_ticks", "seed", "experiment_id", "schema"]:
		reordered[key] = manifest[key]
	var reordered_nested := reordered.duplicate(true)
	reordered_nested["environment"] = {
		"zones": reordered["environment"]["zones"],
		"spatial": reordered["environment"]["spatial"],
	}
	_check(Manifest.validate(reordered_nested) == "", "reordered manifest still valid")
	_check(Manifest.canonical_hash(reordered_nested) == hash_a, "field order does not alter canonical hash")

	# 3. Unknown fields fail closed.
	var unknown_top := manifest.duplicate(true)
	unknown_top["surprise"] = 1
	_check(not Manifest.validate(unknown_top).is_empty(), "unknown top-level field fails closed")
	var unknown_nested := manifest.duplicate(true)
	unknown_nested["environment"]["spatial"]["extra"] = 5
	_check(not Manifest.validate(unknown_nested).is_empty(), "unknown nested field fails closed")

	# 4. Invalid seed fails.
	for bad_seed in [-1, C.MAX_INT + 1, 1.5, "7"]:
		var bad := manifest.duplicate(true)
		bad["seed"] = bad_seed
		_check(not Manifest.validate(bad).is_empty(), "invalid seed rejected: %s" % [str(bad_seed)])

	# 5. Invalid founder / genome references fail.
	var inline_genome: Dictionary = Genome.create(_program(), "founder-b")
	var broken_genome := inline_genome.duplicate(true)
	broken_genome["genes"]["length_permille"] = 10  # below canonical bound
	var bad_genome := manifest.duplicate(true)
	bad_genome["founders"][1]["genome"] = broken_genome
	_check(not Manifest.validate(bad_genome).is_empty(), "invalid inline genome rejected")
	var bad_hash := manifest.duplicate(true)
	bad_hash["founders"][0]["biological_hash"] = "deadbeef"
	_check(not Manifest.validate(bad_hash).is_empty(), "malformed biological_hash reference rejected")
	var both_forms := manifest.duplicate(true)
	both_forms["founders"][0]["genome"] = inline_genome
	_check(not Manifest.validate(both_forms).is_empty(), "founder with both reference forms rejected")
	var unresolved := manifest.duplicate(true)
	unresolved["placement"]["entries"][0]["founder_ref"] = "founder/ghost"
	_check(not Manifest.validate(unresolved).is_empty(), "unresolved founder reference rejected")
	var bad_zone_ref := manifest.duplicate(true)
	bad_zone_ref["placement"]["entries"][0]["zone_id"] = "zone/ghost"
	_check(not Manifest.validate(bad_zone_ref).is_empty(), "placement references unknown zone rejected")
	var bad_position := manifest.duplicate(true)
	bad_position["placement"]["entries"][0]["position_mm"] = [500, 0]
	_check(not Manifest.validate(bad_position).is_empty(), "malformed placement position rejected")

	# 6. Invalid environment configuration fails.
	var negative_stock := manifest.duplicate(true)
	negative_stock["environment"]["zones"][0]["water_mg"] = -1
	_check(not Manifest.validate(negative_stock).is_empty(), "negative zone stock rejected")
	var zone_without_id := manifest.duplicate(true)
	zone_without_id["environment"]["zones"][0].erase("id")
	_check(not Manifest.validate(zone_without_id).is_empty(), "zone without id rejected")
	var over_capacity := manifest.duplicate(true)
	over_capacity["environment"]["zones"][0]["water_mg"] = Manifest.CELL_CAPACITY_MG + 1
	_check(not Manifest.validate(over_capacity).is_empty(), "zone stock above explicit ecology capacity rejected")
	var duplicate_zones := manifest.duplicate(true)
	duplicate_zones["environment"]["zones"][1]["id"] = "zone/wet"
	_check(not Manifest.validate(duplicate_zones).is_empty(), "duplicate zone id rejected")
	var zero_width := manifest.duplicate(true)
	zero_width["environment"]["spatial"]["width"] = 0
	_check(not Manifest.validate(zero_width).is_empty(), "zero spatial width rejected")
	var zero_depth := manifest.duplicate(true)
	zero_depth["environment"]["spatial"]["depth"] = -1
	_check(not Manifest.validate(zero_depth).is_empty(), "negative spatial depth rejected")
	var bad_cell_size := manifest.duplicate(true)
	bad_cell_size["environment"]["spatial"]["cell_size_mm"] = 0
	_check(not Manifest.validate(bad_cell_size).is_empty(), "nonpositive cell_size_mm rejected")

	# 7. Enum fields fail closed.
	var bad_mode := manifest.duplicate(true)
	bad_mode["mode"] = "production"
	_check(not Manifest.validate(bad_mode).is_empty(), "unknown mode rejected")
	var bad_operator := manifest.duplicate(true)
	bad_operator["mutation"]["operator"] = "gigantic"
	_check(not Manifest.validate(bad_operator).is_empty(), "unknown mutation operator rejected")
	var bad_profile := manifest.duplicate(true)
	bad_profile["organization_profile"] = "HIVE"
	_check(not Manifest.validate(bad_profile).is_empty(), "unknown organization profile rejected")

	# 7b. Optional explicit genesis founder endowment is canonical experiment
	# input (needed for starvation/death experiments), not runtime save state.
	var low_endowment := manifest.duplicate(true)
	low_endowment["genesis"] = {"founder_endowment": {"material_mg": 1000, "water_mg": 0, "energy_mj": 0}}
	_check(Manifest.validate(low_endowment).is_empty(), "explicit founder endowment validates")
	_check(Manifest.canonical_hash(low_endowment) != hash_a, "founder endowment changes manifest identity")
	var bad_endowment := low_endowment.duplicate(true)
	bad_endowment.genesis.founder_endowment.water_mg = -1
	_check(not Manifest.validate(bad_endowment).is_empty(), "negative founder endowment fails closed")
	var bad_genesis_field := low_endowment.duplicate(true)
	bad_genesis_field.genesis["runtime_state"] = {}
	_check(not Manifest.validate(bad_genesis_field).is_empty(), "genesis cannot smuggle runtime state")

	# 8. Manifest carries no runtime biological state keys.
	var text := Manifest.to_text(manifest)
	_check(text.find("population_state") == -1 and text.find("field_state") == -1, "manifest text carries no runtime state keys")

	# 9. Round-trip serialize/deserialize preserves identity and hash.
	_check(not text.is_empty(), "to_text produces canonical text")
	var restored := Manifest.from_text(text)
	_check(bool(restored.get("success", false)), "from_text parses canonical text")
	if bool(restored.get("success", false)):
		_check(restored["manifest"] == manifest, "round-trip manifest equals original")
		_check(String(restored["manifest_hash"]) == hash_a, "round-trip preserves canonical hash")
	_check(not bool(Manifest.from_text(text.replace("12345", "12346")).get("success", false)), "tampered text fails closed")
	_check(not bool(Manifest.from_text("{not json").get("success", false)), "invalid JSON fails closed")

	# 10. Treatment projection stays deterministic and state-free.
	var treatment := Manifest.to_treatment(manifest)
	_check(not treatment.is_empty() and treatment["seed"] == 12345 and treatment["mode"] == "LAB", "treatment projection deterministic")
	_check(not Manifest.canonical_hash(_valid_manifest()).is_empty(), "hashing does not mutate manifest")

	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_5_MANIFEST_P1 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_MANIFEST_P1 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P1_FAILURE " + failure)
		quit(1)
