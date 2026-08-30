extends RefCounted

## ECO.EVO7 PERF2.0 — measurement contract.
##
## Performance evidence is a noncanonical side channel. This class freezes
## workload identity, sample validation, comparison identity and summary
## statistics so PERF2.1..PERF2.4 cannot silently change benchmark semantics.

const CONTRACT_PATH := "res://config/ecology/eco-evo7-perf2-measurement-contract.v1.json"
const CONTRACT_SCHEMA := "distributed_world_simulator.ecology.evo7_perf2.measurement_contract.v1"
const SAMPLE_SCHEMA := "distributed_world_simulator.ecology.evo7_perf2.measurement_sample.v1"
const REPORT_SCHEMA := "distributed_world_simulator.ecology.evo7_perf2.measurement_report.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-PERF2.0-R1"
const EXPECTED_GODOT := "4.7.1.stable.double.custom_build.a13da4feb"

const WORKLOAD_FIELDS := [
	"workload_id",
	"execution_mode",
	"environment_recipe",
	"warmup_generations",
	"measured_generations",
	"repetitions",
	"initial_records",
	"parents_per_chunk",
	"audit_interval_generations",
	"audit_generation_1",
	"founder_seed",
	"placement_seed",
	"evolution_seed",
	"environment_seed",
]

const HASH_FIELDS := [
	"final_workbench_hash",
	"final_ecology_state_hash",
	"final_population_hash",
	"final_classification_hash",
]

const SAMPLE_FIELDS := [
	"schema",
	"version",
	"revision",
	"run_id",
	"target",
	"host_fingerprint",
	"measurement_method_revision",
	"workload",
	"workload_hash",
	"passed",
	"canonical_result",
	"metrics",
	"flags",
]


static func load_contract() -> Dictionary:
	if not FileAccess.file_exists(CONTRACT_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	return Dictionary(parsed).duplicate(true) if parsed is Dictionary else {}


static func validate_contract(contract: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if String(contract.get("schema", "")) != CONTRACT_SCHEMA:
		errors.append("CONTRACT_SCHEMA")
	if String(contract.get("version", "")) != VERSION:
		errors.append("CONTRACT_VERSION")
	if String(contract.get("revision", "")) != REVISION:
		errors.append("CONTRACT_REVISION")

	var accepted: Dictionary = Dictionary(contract.get("accepted_stream1_subject", {}))
	if not _is_git_sha(String(accepted.get("head", ""))):
		errors.append("STREAM1_HEAD")
	if not _is_git_sha(String(accepted.get("tree", ""))):
		errors.append("STREAM1_TREE")
	if String(accepted.get("godot", "")) != EXPECTED_GODOT:
		errors.append("GODOT_PIN")

	var rules: Dictionary = Dictionary(contract.get("rules", {}))
	if bool(rules.get("canonical", true)):
		errors.append("MEASUREMENT_MUST_BE_NONCANONICAL")
	if not bool(rules.get("side_channel_only", false)):
		errors.append("SIDE_CHANNEL_REQUIRED")
	if not bool(rules.get("ecology_truth_mutation_forbidden", false)):
		errors.append("ECOLOGY_MUTATION_MUST_BE_FORBIDDEN")
	if not bool(rules.get("timing_values_in_canonical_hash_forbidden", false)):
		errors.append("TIMING_HASH_BOUNDARY")
	if not bool(rules.get("memory_values_in_canonical_hash_forbidden", false)):
		errors.append("MEMORY_HASH_BOUNDARY")

	var workload: Dictionary = Dictionary(contract.get("workload_contract", {}))
	if Array(workload.get("required_fields", [])) != WORKLOAD_FIELDS:
		errors.append("WORKLOAD_FIELD_SET")
	if int(workload.get("minimum_warmup_generations", 0)) < 1:
		errors.append("MIN_WARMUP")
	if int(workload.get("minimum_measured_generations", 0)) < 1:
		errors.append("MIN_MEASURED")
	if int(workload.get("minimum_repetitions", 0)) < 3:
		errors.append("MIN_REPETITIONS")
	var modes := _string_array(workload.get("execution_modes", []))
	if modes != ["SERIAL_REFERENCE", "STREAM1"]:
		errors.append("EXECUTION_MODES")

	var comparison: Dictionary = Dictionary(contract.get("comparison_contract", {}))
	if "target_head" not in Array(comparison.get("comparison_key_excludes", [])):
		errors.append("TARGET_HEAD_MUST_NOT_ENTER_COMPARISON_KEY")
	if "timings" not in Array(comparison.get("comparison_key_excludes", [])):
		errors.append("TIMINGS_MUST_NOT_ENTER_COMPARISON_KEY")
	for required in ["count", "p50", "p95", "mean", "min", "max"]:
		if required not in Array(comparison.get("required_summary_statistics", [])):
			errors.append("SUMMARY_%s" % String(required).to_upper())

	return _result(errors)


static func validate_workload(workload: Dictionary, contract: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var policy := contract if not contract.is_empty() else load_contract()
	var workload_contract: Dictionary = Dictionary(policy.get("workload_contract", {}))

	if workload.size() != WORKLOAD_FIELDS.size():
		errors.append("WORKLOAD_EXACT_FIELD_COUNT")
	for key in WORKLOAD_FIELDS:
		if not workload.has(key):
			errors.append("WORKLOAD_MISSING_%s" % String(key).to_upper())
	if not errors.is_empty():
		return _result(errors)

	if String(workload["workload_id"]).strip_edges().is_empty():
		errors.append("WORKLOAD_ID")
	var modes := _string_array(workload_contract.get("execution_modes", []))
	if String(workload["execution_mode"]) not in modes:
		errors.append("EXECUTION_MODE")
	var recipes := _string_array(workload_contract.get("allowed_environment_recipes", []))
	if String(workload["environment_recipe"]) not in recipes:
		errors.append("ENVIRONMENT_RECIPE")

	if int(workload["warmup_generations"]) < int(workload_contract.get("minimum_warmup_generations", 1)):
		errors.append("WARMUP_GENERATIONS")
	if int(workload["measured_generations"]) < int(workload_contract.get("minimum_measured_generations", 1)):
		errors.append("MEASURED_GENERATIONS")
	if int(workload["repetitions"]) < int(workload_contract.get("minimum_repetitions", 3)):
		errors.append("REPETITIONS")
	for key in ["initial_records", "parents_per_chunk", "audit_interval_generations"]:
		if typeof(workload[key]) != TYPE_INT or int(workload[key]) < 1:
			errors.append("WORKLOAD_%s" % String(key).to_upper())
	if typeof(workload["audit_generation_1"]) != TYPE_BOOL:
		errors.append("AUDIT_GENERATION_1")
	for key in ["founder_seed", "placement_seed", "evolution_seed", "environment_seed"]:
		if typeof(workload[key]) != TYPE_INT:
			errors.append("WORKLOAD_%s" % String(key).to_upper())

	return _result(errors)


static func workload_hash(workload: Dictionary) -> String:
	var validation := validate_workload(workload)
	if not bool(validation.get("success", false)):
		return ""
	var parts := PackedStringArray()
	parts.append("PERF2_WORKLOAD_V1")
	for key in WORKLOAD_FIELDS:
		var value = workload[key]
		if value is bool:
			parts.append("%s=%s" % [key, "true" if bool(value) else "false"])
		else:
			parts.append("%s=%s" % [key, str(value)])
	return "|".join(parts).sha256_text()


static func validate_sample(sample: Dictionary, contract: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var policy := contract if not contract.is_empty() else load_contract()
	if sample.size() != SAMPLE_FIELDS.size():
		errors.append("SAMPLE_EXACT_FIELD_COUNT")
	for key in SAMPLE_FIELDS:
		if not sample.has(key):
			errors.append("SAMPLE_MISSING_%s" % String(key).to_upper())
	if not errors.is_empty():
		return _result(errors)

	if String(sample["schema"]) != SAMPLE_SCHEMA:
		errors.append("SAMPLE_SCHEMA")
	if String(sample["version"]) != VERSION or String(sample["revision"]) != REVISION:
		errors.append("SAMPLE_VERSION")
	if String(sample["run_id"]).strip_edges().is_empty():
		errors.append("RUN_ID")

	var target: Dictionary = Dictionary(sample["target"])
	if not _is_git_sha(String(target.get("head", ""))):
		errors.append("TARGET_HEAD")
	if not _is_git_sha(String(target.get("tree", ""))):
		errors.append("TARGET_TREE")
	if String(target.get("godot_version", "")) != EXPECTED_GODOT:
		errors.append("TARGET_GODOT")

	if String(sample["host_fingerprint"]).strip_edges().is_empty():
		errors.append("HOST_FINGERPRINT")
	if String(sample["measurement_method_revision"]) != REVISION:
		errors.append("MEASUREMENT_METHOD_REVISION")

	var workload: Dictionary = Dictionary(sample["workload"])
	var workload_validation := validate_workload(workload, policy)
	if not bool(workload_validation.get("success", false)):
		for error in workload_validation.get("errors", []):
			errors.append("SAMPLE_%s" % String(error))
	var expected_workload_hash := workload_hash(workload)
	if expected_workload_hash.is_empty() or String(sample["workload_hash"]) != expected_workload_hash:
		errors.append("WORKLOAD_HASH")

	if typeof(sample["passed"]) != TYPE_BOOL:
		errors.append("PASSED_TYPE")
	var canonical: Dictionary = Dictionary(sample["canonical_result"])
	for key in HASH_FIELDS:
		if not _is_hash(String(canonical.get(key, ""))):
			errors.append("CANONICAL_%s" % String(key).to_upper())

	var flags: Dictionary = Dictionary(sample["flags"])
	if bool(flags.get("canonical", true)):
		errors.append("FLAG_CANONICAL")
	if not bool(flags.get("side_channel_only", false)):
		errors.append("FLAG_SIDE_CHANNEL")
	if not bool(flags.get("measurement_only", false)):
		errors.append("FLAG_MEASUREMENT_ONLY")

	var metric_validation := _validate_metrics(Dictionary(sample["metrics"]), policy)
	if not bool(metric_validation.get("success", false)):
		for error in metric_validation.get("errors", []):
			errors.append(String(error))

	return _result(errors)


static func comparison_key(sample: Dictionary) -> String:
	if not bool(validate_sample(sample).get("success", false)):
		return ""
	return "|".join(PackedStringArray([
		"PERF2_COMPARISON_V1",
		String(sample["workload_hash"]),
		String(Dictionary(sample["target"]).get("godot_version", "")),
		String(sample["host_fingerprint"]),
		String(sample["measurement_method_revision"]),
	])).sha256_text()


static func canonical_result_fingerprint(sample: Dictionary) -> String:
	if not bool(validate_sample(sample).get("success", false)):
		return ""
	var canonical: Dictionary = Dictionary(sample["canonical_result"])
	var parts := PackedStringArray(["PERF2_RESULT_V1"])
	for key in HASH_FIELDS:
		parts.append("%s=%s" % [key, String(canonical[key])])
	return "|".join(parts).sha256_text()


static func can_compare(a: Dictionary, b: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if not bool(validate_sample(a).get("success", false)):
		errors.append("BASELINE_INVALID")
	if not bool(validate_sample(b).get("success", false)):
		errors.append("CANDIDATE_INVALID")
	if not errors.is_empty():
		return _result(errors)
	if not bool(a.get("passed", false)) or not bool(b.get("passed", false)):
		errors.append("FAILED_SAMPLE")
	if comparison_key(a) != comparison_key(b):
		errors.append("COMPARISON_KEY_MISMATCH")
	if canonical_result_fingerprint(a) != canonical_result_fingerprint(b):
		errors.append("CANONICAL_RESULT_MISMATCH")
	return _result(errors)


static func summarize(samples: Array[Dictionary], metric_path: String) -> Dictionary:
	if samples.size() < 1:
		return {}
	var key := comparison_key(samples[0])
	var result_fingerprint := canonical_result_fingerprint(samples[0])
	if key.is_empty() or result_fingerprint.is_empty():
		return {}
	var values: Array[float] = []
	for sample in samples:
		if not bool(validate_sample(sample).get("success", false)):
			return {}
		if not bool(sample.get("passed", false)):
			return {}
		if comparison_key(sample) != key:
			return {}
		if canonical_result_fingerprint(sample) != result_fingerprint:
			return {}
		var read := _read_metric_path(Dictionary(sample.get("metrics", {})), metric_path)
		if not bool(read.get("success", false)):
			return {}
		values.append(float(read["value"]))
	values.sort()
	var sum := 0.0
	for value in values:
		sum += value
	return {
		"schema": "distributed_world_simulator.ecology.evo7_perf2.summary.v1",
		"metric_path": metric_path,
		"comparison_key": key,
		"canonical_result_fingerprint": result_fingerprint,
		"count": values.size(),
		"p50": _percentile(values, 0.50),
		"p95": _percentile(values, 0.95),
		"mean": sum / float(values.size()),
		"min": values[0],
		"max": values[-1],
	}


static func minimum_repetitions_satisfied(samples: Array[Dictionary], contract: Dictionary = {}) -> bool:
	var policy := contract if not contract.is_empty() else load_contract()
	var minimum := int(Dictionary(policy.get("workload_contract", {})).get("minimum_repetitions", 3))
	return samples.size() >= minimum


static func _validate_metrics(metrics: Dictionary, contract: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var metric_contract: Dictionary = Dictionary(contract.get("metric_contract", {}))
	var timings: Dictionary = Dictionary(metrics.get("timings_ms", {}))
	for key in metric_contract.get("required_timing_fields", []):
		if not timings.has(key) or not _finite_nonnegative(timings[key]):
			errors.append("METRIC_TIMING_%s" % String(key).to_upper())
	var counts: Dictionary = Dictionary(metrics.get("counts", {}))
	for key in metric_contract.get("required_count_fields", []):
		if not counts.has(key) or typeof(counts[key]) != TYPE_INT or int(counts[key]) < 0:
			errors.append("METRIC_COUNT_%s" % String(key).to_upper())

	var memory: Dictionary = Dictionary(metrics.get("memory_bytes", {}))
	for key in ["engine_static_bytes", "engine_static_peak_bytes"]:
		if not memory.has(key) or typeof(memory[key]) != TYPE_INT or int(memory[key]) < 0:
			errors.append("METRIC_MEMORY_%s" % String(key).to_upper())
	for key in metric_contract.get("optional_external_memory_fields", []):
		if memory.has(key) and memory[key] != null:
			if typeof(memory[key]) != TYPE_INT or int(memory[key]) < 0:
				errors.append("METRIC_MEMORY_%s" % String(key).to_upper())

	var stream: Dictionary = Dictionary(metrics.get("stream", {}))
	for key in ["stream_calls", "chunks_processed", "serial_audit_calls", "oracle_elided_generations"]:
		if not stream.has(key) or typeof(stream[key]) != TYPE_INT or int(stream[key]) < 0:
			errors.append("METRIC_STREAM_%s" % String(key).to_upper())
	return _result(errors)


static func _read_metric_path(root: Dictionary, path: String) -> Dictionary:
	var current = root
	for part in path.split("."):
		if not current is Dictionary or not Dictionary(current).has(part):
			return {"success": false}
		current = Dictionary(current)[part]
	if not _finite_nonnegative(current):
		return {"success": false}
	return {"success": true, "value": float(current)}


static func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	if sorted_values.size() == 1:
		return sorted_values[0]
	var position := clampf(fraction, 0.0, 1.0) * float(sorted_values.size() - 1)
	var low := int(floor(position))
	var high := int(ceil(position))
	if low == high:
		return sorted_values[low]
	var weight := position - float(low)
	return lerpf(sorted_values[low], sorted_values[high], weight)


static func _finite_nonnegative(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0


static func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item in value:
		result.append(String(item))
	return result


static func _is_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


static func _is_git_sha(value: String) -> bool:
	if value.length() != 40:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


static func _result(errors: Array[String]) -> Dictionary:
	return {
		"success": errors.is_empty(),
		"errors": errors.duplicate(),
	}
