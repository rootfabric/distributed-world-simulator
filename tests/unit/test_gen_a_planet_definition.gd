extends SceneTree

# GEN-A predicate evidence:
#   PLANET_DEFINITION_PER_WORLD_PASS      - catalog is the single seed source
#   CONTROL_POINT_ELEVATION_MATCH_PASS    - identical seeds => identical
#     centimetre-rounded control-point elevations; a substituted seed changes
#     the control-point digest (detection power)

const WorldDefinitionScript = preload(
	"res://scripts/world/earth/world_definition.gd"
)
const ControlPointProbeScript = preload(
	"res://scripts/world/earth/control_point_probe.gd"
)
const PipelineScript = preload(
	"res://scripts/world/planetary/earth_rule_pipeline.gd"
)

const EARTH_SEED := 20260726
const RULES_CONFIG_PATH := "res://config/generation/earth_rules.json"
const VEGETATION_CONFIG_PATH := "res://config/generation/earth_vegetation.json"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	_test_planet_definition_per_world()
	_test_single_seed_source()
	_test_seed_parameter_forwarding()
	_test_world_definition_hash_contract()
	_test_announcement_evaluation_fail_closed()
	_test_control_point_elevation_match()
	if failures.is_empty():
		print("GEN-A planet definition tests: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("GEN-A planet definition tests: FAIL (%d)" % failures.size())
	quit(1)


func _test_planet_definition_per_world() -> void:
	var definition := WorldDefinitionScript.load_definition("earth")
	_assert(not definition.is_empty(), "Earth planet definition resolves from catalog.")
	if definition.is_empty():
		return
	_assert(int(definition["seed"]) == EARTH_SEED, "Earth catalog seed is 20260726.")
	_assert(
		String(definition["generator_version"]) == "earth-rule-pipeline-v1",
		"Earth generator_version is earth-rule-pipeline-v1."
	)
	_assert(
		String(definition["rules_config"]) == RULES_CONFIG_PATH,
		"Earth rules_config points at the rule pipeline config."
	)
	_assert(
		FileAccess.file_exists(String(definition["rules_config"])),
		"Earth rules_config file exists."
	)
	var hash_value := WorldDefinitionScript.get_world_definition_hash("earth")
	_assert(hash_value.length() == 64, "World definition hash is a sha256 hex digest.")


func _test_single_seed_source() -> void:
	var rules := _read_json(RULES_CONFIG_PATH)
	_assert(
		not rules.is_empty() and not rules.has("seed"),
		"earth_rules.json no longer carries a duplicated seed."
	)
	var vegetation := _read_json(VEGETATION_CONFIG_PATH)
	_assert(
		not vegetation.is_empty() and not vegetation.has("seed"),
		"earth_vegetation.json no longer carries a duplicated seed."
	)


func _test_seed_parameter_forwarding() -> void:
	var pipeline = PipelineScript.new()
	_assert(pipeline.setup(), "Pipeline setup succeeds without a seed in the rules file.")
	_assert(int(pipeline.seed) == EARTH_SEED, "Default pipeline seed comes from the catalog.")
	var overridden = PipelineScript.new()
	_assert(
		overridden.setup(PipelineScript.CONFIG_PATH, 7777),
		"Pipeline setup honours an explicit seed override."
	)
	_assert(int(overridden.seed) == 7777, "Seed override replaces the catalog seed.")
	# missing rules file still fails closed through the normal path
	var missing = PipelineScript.new()
	_assert(not missing.setup("user://definitely-missing-rules.json"), "Missing rules config fails closed.")


func _test_world_definition_hash_contract() -> void:
	var baseline_hash := WorldDefinitionScript.get_world_definition_hash()
	_assert(
		baseline_hash == WorldDefinitionScript.get_world_definition_hash(),
		"World definition hash is stable across calls."
	)
	var definition := WorldDefinitionScript.load_definition()
	_assert(
		baseline_hash == WorldDefinitionScript.compute_definition_hash(definition),
		"Hash matches the canonical payload of the resolved definition."
	)
	# Canonical JSON: key order must not influence the encoding.
	var reordered_a := {"a": 1, "b": [1, 2, {"y": 2, "x": 1}]}
	var reordered_b := {"b": [{"y": 2, "x": 1}, 2, 1], "a": 1}
	var reordered_b_fixed := {"b": [1, 2, {"y": 2, "x": 1}], "a": 1}
	_assert(
		WorldDefinitionScript.canonical_json(reordered_a)
			== WorldDefinitionScript.canonical_json(reordered_b_fixed),
		"Canonical JSON sorts object keys recursively."
	)
	_assert(
		WorldDefinitionScript.canonical_json(reordered_a)
			!= WorldDefinitionScript.canonical_json(reordered_b),
		"Canonical JSON keeps array element order significant."
	)
	# Rules content sensitivity: modifying one rule parameter must change the hash.
	var tampered_path := _write_tampered_rules_copy(float(definition["seed"]))
	_assert(not tampered_path.is_empty(), "Tampered rules copy written for hash sensitivity.")
	if not tampered_path.is_empty():
		var tampered_definition := definition.duplicate(true)
		tampered_definition["rules_config"] = tampered_path
		var tampered_hash := WorldDefinitionScript.compute_definition_hash(tampered_definition)
		_assert(tampered_hash != baseline_hash, "Rules content change alters the world hash.")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tampered_path))
	# Seed substitution via the documented test hook.
	OS.set_environment(WorldDefinitionScript.TEST_SEED_OVERRIDE_ENV, "")
	var neutral_hash := WorldDefinitionScript.get_world_definition_hash()
	_assert(neutral_hash == baseline_hash, "Empty test override keeps the catalog hash.")
	OS.set_environment(WorldDefinitionScript.TEST_SEED_OVERRIDE_ENV, "20260727")
	var substituted := WorldDefinitionScript.load_definition()
	_assert(int(substituted.get("seed", 0)) == 20260727, "Test override substitutes the seed.")
	_assert(
		WorldDefinitionScript.get_world_definition_hash() != baseline_hash,
		"Substituted seed produces a different world hash."
	)
	OS.set_environment(WorldDefinitionScript.TEST_SEED_OVERRIDE_ENV, "")
	_assert(
		WorldDefinitionScript.get_world_definition_hash() == baseline_hash,
		"Hash returns to the catalog value after the override clears."
	)


func _test_announcement_evaluation_fail_closed() -> void:
	var local := WorldDefinitionScript.create_announcement("earth")
	_assert(not local.is_empty(), "Local world announcement resolves.")
	_assert(
		bool(WorldDefinitionScript.evaluate_announcement(local, local.duplicate(true)).get("success", false)),
		"Identical announcements evaluate compatible."
	)
	var tampered := local.duplicate(true)
	tampered["generator_hash"] = String(tampered["generator_hash"]).substr(0, 63) + "0"
	var evaluation: Dictionary = WorldDefinitionScript.evaluate_announcement(local, tampered)
	_assert(
		not bool(evaluation.get("success", false))
		and String(evaluation.get("error_code", "")) == "WORLD_DEFINITION_MISMATCH",
		"Tampered generator hash fails with WORLD_DEFINITION_MISMATCH."
	)
	var wrong_world := local.duplicate(true)
	wrong_world["world_id"] = "moon"
	_assert(
		String(WorldDefinitionScript.evaluate_announcement(local, wrong_world).get("error_code", ""))
			== "WORLD_DEFINITION_MISMATCH",
		"Divergent world_id fails closed."
	)
	var incomplete := {"world_id": "earth"}
	_assert(
		String(WorldDefinitionScript.evaluate_announcement(local, incomplete).get("error_code", ""))
			== "INVALID_WORLD_DEFINITION_ANNOUNCEMENT",
		"Incomplete announcement fails closed."
	)
	_assert(
		String(WorldDefinitionScript.evaluate_announcement({}, local).get("error_code", ""))
			== "WORLD_DEFINITION_UNRESOLVABLE",
		"Unresolvable local definition fails closed."
	)


func _test_control_point_elevation_match() -> void:
	var probe_a := ControlPointProbeScript.compute(EARTH_SEED)
	var probe_b := ControlPointProbeScript.compute(EARTH_SEED)
	_assert(not probe_a.is_empty(), "Control point probe resolves for the catalog seed.")
	if probe_a.is_empty():
		return
	_assert(int(probe_a["point_count"]) == 5, "Control point probe samples five directions.")
	_assert(
		probe_a["elevation_cm"] == probe_b["elevation_cm"],
		"Two independent pipelines agree on centimetre-rounded elevations."
	)
	_assert(probe_a["digest"] == probe_b["digest"], "Control point digests match for equal seeds.")
	var elevations: Array = probe_a["elevation_cm"]
	var all_integers := true
	for value in elevations:
		if typeof(value) != TYPE_INT:
			all_integers = false
	_assert(all_integers, "Control point elevations are integer centimetres.")
	var probe_substituted := ControlPointProbeScript.compute(20260727)
	_assert(
		String(probe_substituted.get("digest", "")) != String(probe_a["digest"]),
		"A substituted seed yields a different control point digest."
	)
	# Server-side and client-side stand-ins resolve the probe independently.
	var server_probe := ControlPointProbeScript.compute_for_world("earth")
	var client_probe := ControlPointProbeScript.compute_for_world("earth")
	_assert(
		String(server_probe.get("digest", "")) == String(client_probe.get("digest", ""))
		and String(server_probe.get("digest", "")) == String(probe_a["digest"]),
		"World-resolved probes match the explicit-seed probe."
	)


func _write_tampered_rules_copy(seed_value: int) -> String:
	var source_text := FileAccess.get_file_as_string(RULES_CONFIG_PATH)
	var parsed = JSON.parse_string(source_text)
	if not parsed is Dictionary:
		return ""
	var config: Dictionary = parsed
	var rules: Array = config.get("rules", [])
	if rules.is_empty() or not rules[0] is Dictionary:
		return ""
	var parameters: Dictionary = rules[0].get("parameters", {})
	parameters["mountain_height_m"] = float(parameters.get("mountain_height_m", 7600.0)) + 1.0
	config["rules"][0]["parameters"] = parameters
	config["seed"] = int(seed_value)  # tolerated by the parser, never used as a source
	var path := "user://gen_a_tampered_rules_%d.json" % OS.get_process_id()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(config, "  "))
	file.close()
	return path


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
