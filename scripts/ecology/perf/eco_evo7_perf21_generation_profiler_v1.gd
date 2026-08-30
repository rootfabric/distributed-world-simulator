extends RefCounted

## ECO.EVO7 PERF2.1 R1 — STREAM1 generation profiling campaign.
##
## Measurement-only orchestration over the accepted public Workbench facade.
## It consumes the frozen PERF2.0 measurement contract unchanged and never
## reaches into ecology private state. Reports are machine-local side-channel
## artifacts and are not canonical world/ecology truth.

const Contract = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
const Probe = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_probe_v1.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const StreamExecutor = preload("res://scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_perf2_1.generation_profile.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-PERF2.1-R1"
const MODE := "RESEARCH_SHADOW_PERFORMANCE_ONLY"
const FROZEN_PERF2_CONTRACT_REVISION := "ECO.EVO7-PERF2.0-R1"
const FROZEN_PERF2_CONTRACT_BLOB_SHA := "b076784f6b4016a0191e937c4e6ada1fe90c783b"

const DEFAULT_RECIPE := "MIXED_PHYSICAL_HETEROGENEITY"
const REQUIRED_METRICS: Array[String] = [
	"timings_ms.generation_total_ms",
	"timings_ms.ls33_total_ms",
	"timings_ms.candidate_build_ms",
	"timings_ms.route_build_ms",
	"timings_ms.recruitment_eval_ms",
	"timings_ms.audit_ms",
]
const EXECUTION_MODES: Array[String] = ["SERIAL_REFERENCE", "STREAM1"]

const AUTHORITIES := {
	"canonical": false,
	"world_write": false,
	"ecology_truth_write": false,
	"generation_commit": false,
	"biology_write": false,
	"persistence_truth_write": false,
	"network_write": false,
	"measurement_only": true,
	"side_channel_only": true,
}

func default_campaign_config() -> Dictionary:
	var contract := Contract.load_contract()
	var defaults: Dictionary = Dictionary(Dictionary(contract.get("workload_contract", {})).get("default_stream1", {}))
	return {
		"recipes": [DEFAULT_RECIPE],
		"warmup_generations": int(defaults.get("warmup_generations", 2)),
		"measured_generations": int(defaults.get("measured_generations", 12)),
		"repetitions": int(defaults.get("repetitions", 3)),
		"initial_records": int(defaults.get("initial_records", 64)),
		"parents_per_chunk": int(defaults.get("parents_per_chunk", 64)),
		"audit_interval_generations": int(defaults.get("audit_interval_generations", 10)),
		"audit_generation_1": bool(defaults.get("audit_generation_1", true)),
		"founder_seed": Workbench.FOUNDER_SEED,
		"placement_seed": Workbench.PLACEMENT_SEED,
		"evolution_seed": Workbench.EVOLUTION_SEED,
		"environment_seed": Workbench.DEFAULT_ENVIRONMENT_SEED,
	}

func validate_campaign_config(config: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var contract := Contract.load_contract()
	if not bool(Contract.validate_contract(contract).get("success", false)):
		errors.append("PERF2_CONTRACT_INVALID")
	if Contract.REVISION != FROZEN_PERF2_CONTRACT_REVISION:
		errors.append("PERF2_CONTRACT_REVISION_DRIFT")

	var recipes_value = config.get("recipes")
	if not recipes_value is Array or Array(recipes_value).is_empty():
		errors.append("RECIPES")
	else:
		var allowed: Array = Array(Dictionary(contract.get("workload_contract", {})).get("allowed_environment_recipes", []))
		for value in Array(recipes_value):
			if String(value) not in allowed:
				errors.append("RECIPE_%s" % String(value))

	for key in ["warmup_generations", "measured_generations", "repetitions", "initial_records", "parents_per_chunk", "audit_interval_generations"]:
		if typeof(config.get(key)) != TYPE_INT or int(config.get(key, 0)) < 1:
			errors.append("CONFIG_%s" % key.to_upper())
	if typeof(config.get("audit_generation_1")) != TYPE_BOOL:
		errors.append("CONFIG_AUDIT_GENERATION_1")
	for key in ["founder_seed", "placement_seed", "evolution_seed", "environment_seed"]:
		if typeof(config.get(key)) != TYPE_INT:
			errors.append("CONFIG_%s" % key.to_upper())

	var workload_policy: Dictionary = Dictionary(contract.get("workload_contract", {}))
	if int(config.get("warmup_generations", 0)) < int(workload_policy.get("minimum_warmup_generations", 1)):
		errors.append("MIN_WARMUP")
	if int(config.get("measured_generations", 0)) < int(workload_policy.get("minimum_measured_generations", 12)):
		errors.append("MIN_MEASURED")
	if int(config.get("repetitions", 0)) < int(workload_policy.get("minimum_repetitions", 3)):
		errors.append("MIN_REPETITIONS")

	## PERF2.1 R1 deliberately refuses to mutate the Workbench public contract
	## merely to benchmark alternate seeds/population sizes.
	if int(config.get("initial_records", -1)) != Workbench.INITIAL_RECORDS:
		errors.append("R1_WORKBENCH_INITIAL_RECORDS_UNSUPPORTED")
	if int(config.get("founder_seed", -1)) != Workbench.FOUNDER_SEED:
		errors.append("R1_WORKBENCH_FOUNDER_SEED_UNSUPPORTED")
	if int(config.get("placement_seed", -1)) != Workbench.PLACEMENT_SEED:
		errors.append("R1_WORKBENCH_PLACEMENT_SEED_UNSUPPORTED")
	if int(config.get("evolution_seed", -1)) != Workbench.EVOLUTION_SEED:
		errors.append("R1_WORKBENCH_EVOLUTION_SEED_UNSUPPORTED")

	return {"success": errors.is_empty(), "errors": errors}

func run_campaign(planet_source, config: Dictionary, target: Dictionary, host_fingerprint: String) -> Dictionary:
	var validation := validate_campaign_config(config)
	if not bool(validation.get("success", false)):
		return _failure("CONFIG_INVALID", validation.get("errors", []))
	if planet_source == null:
		return _failure("PLANET_SOURCE", [])
	if not _valid_target(target):
		return _failure("TARGET_INVALID", [])
	if host_fingerprint.strip_edges().is_empty():
		return _failure("HOST_FINGERPRINT", [])

	var samples: Array[Dictionary] = []
	for recipe_value in Array(config["recipes"]):
		var recipe := String(recipe_value)
		for repetition in int(config["repetitions"]):
			var serial := _run_repetition(
				planet_source, config, target, host_fingerprint,
				recipe, "SERIAL_REFERENCE", repetition)
			if serial.is_empty():
				return _failure("SERIAL_REPETITION_FAILED", [recipe, repetition])
			var streamed := _run_repetition(
				planet_source, config, target, host_fingerprint,
				recipe, "STREAM1", repetition)
			if streamed.is_empty():
				return _failure("STREAM1_REPETITION_FAILED", [recipe, repetition])
			var parity := Contract.can_compare_execution_modes(serial, streamed)
			if not bool(parity.get("success", false)):
				return _failure("CROSS_MODE_PARITY_FAILED", parity.get("errors", []))
			samples.append(serial)
			samples.append(streamed)

	var summaries := _build_summaries(samples, config)
	if summaries.is_empty():
		return _failure("SUMMARY_BUILD_FAILED", [])

	var report := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"mode": MODE,
		"accepted_measurement_contract_revision": Contract.REVISION,
		"accepted_measurement_contract_blob_sha": FROZEN_PERF2_CONTRACT_BLOB_SHA,
		"target": target.duplicate(true),
		"host_fingerprint": host_fingerprint,
		"config": config.duplicate(true),
		"samples": samples.duplicate(true),
		"summaries": summaries.duplicate(true),
		"authorities": AUTHORITIES.duplicate(true),
	}
	report["report_hash"] = report_hash(report)
	if not validate_report(report):
		return _failure("REPORT_VALIDATION_FAILED", [])
	return report

func validate_report(report: Dictionary) -> bool:
	var required := [
		"schema", "version", "revision", "mode",
		"accepted_measurement_contract_revision",
		"accepted_measurement_contract_blob_sha",
		"target", "host_fingerprint", "config", "samples",
		"summaries", "authorities", "report_hash",
	]
	if report.keys().size() != required.size():
		return false
	for key in required:
		if not report.has(key):
			return false
	if String(report["schema"]) != SCHEMA or String(report["version"]) != VERSION or String(report["revision"]) != REVISION:
		return false
	if String(report["mode"]) != MODE:
		return false
	if String(report["accepted_measurement_contract_revision"]) != Contract.REVISION:
		return false
	if String(report["accepted_measurement_contract_blob_sha"]) != FROZEN_PERF2_CONTRACT_BLOB_SHA:
		return false
	if not _valid_target(Dictionary(report["target"])):
		return false
	if String(report["host_fingerprint"]).strip_edges().is_empty():
		return false
	if not bool(validate_campaign_config(Dictionary(report["config"])).get("success", false)):
		return false
	var auth: Dictionary = Dictionary(report["authorities"])
	if auth != AUTHORITIES:
		return false

	var samples_value = report["samples"]
	if not samples_value is Array or Array(samples_value).is_empty():
		return false
	var samples: Array = samples_value
	for sample_value in samples:
		if not sample_value is Dictionary:
			return false
		var sample: Dictionary = sample_value
		if not bool(Contract.validate_sample(sample).get("success", false)):
			return false
		if not bool(sample.get("passed", false)):
			return false

	var expected_count := Array(Dictionary(report["config"])["recipes"]).size() * int(Dictionary(report["config"])["repetitions"]) * EXECUTION_MODES.size()
	if samples.size() != expected_count:
		return false

	for recipe_value in Array(Dictionary(report["config"])["recipes"]):
		var recipe := String(recipe_value)
		for repetition in int(Dictionary(report["config"])["repetitions"]):
			var serial := _find_sample(samples, recipe, "SERIAL_REFERENCE", repetition)
			var streamed := _find_sample(samples, recipe, "STREAM1", repetition)
			if serial.is_empty() or streamed.is_empty():
				return false
			if Contract.simulation_workload_hash(Dictionary(serial["workload"])) != Contract.simulation_workload_hash(Dictionary(streamed["workload"])):
				return false
			if not bool(Contract.can_compare_execution_modes(serial, streamed).get("success", false)):
				return false

	var summaries_value = report["summaries"]
	if not summaries_value is Array or Array(summaries_value).is_empty():
		return false
	for summary_value in Array(summaries_value):
		if not summary_value is Dictionary:
			return false
		var summary: Dictionary = summary_value
		if int(summary.get("count", 0)) < int(Dictionary(report["config"])["repetitions"]):
			return false
		for key in ["p50", "p95", "mean", "min", "max"]:
			if not _finite_nonnegative(summary.get(key)):
				return false

	return String(report["report_hash"]) == report_hash(report)

func write_report(report: Dictionary, path: String) -> bool:
	if not validate_report(report) or path.strip_edges().is_empty():
		return false
	var parent := path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "  ", false) + "\n")
	file.close()
	return true

func report_hash(report: Dictionary) -> String:
	var target: Dictionary = Dictionary(report.get("target", {}))
	var config: Dictionary = Dictionary(report.get("config", {}))
	var sample_hashes := PackedStringArray()
	for value in Array(report.get("samples", [])):
		var sample: Dictionary = value
		sample_hashes.append(_sample_evidence_hash(sample))
	var summary_hashes := PackedStringArray()
	for value in Array(report.get("summaries", [])):
		var summary: Dictionary = value
		summary_hashes.append(_summary_evidence_hash(summary))
	return "|".join(PackedStringArray([
		"PERF2_1_REPORT_V1",
		String(target.get("head", "")),
		String(target.get("tree", "")),
		String(target.get("godot_version", "")),
		String(report.get("host_fingerprint", "")),
		Contract.REVISION,
		_config_hash(config),
		";".join(sample_hashes),
		";".join(summary_hashes),
	])).sha256_text()

func _run_repetition(
	planet_source,
	config: Dictionary,
	target: Dictionary,
	host_fingerprint: String,
	recipe: String,
	execution_mode: String,
	repetition: int
) -> Dictionary:
	var workload := _workload(config, recipe, execution_mode)
	if not bool(Contract.validate_workload(workload).get("success", false)):
		return {}

	var wb = Workbench.new()
	var requested_spec := Workbench.default_spec()
	requested_spec["environment_seed"] = int(config["environment_seed"])
	requested_spec["environment_recipe"] = recipe
	if not wb.setup(planet_source, requested_spec):
		return {}

	var executor = null
	if execution_mode == "STREAM1":
		executor = StreamExecutor.new()
		if not executor.setup({
			"parents_per_chunk": int(config["parents_per_chunk"]),
			"audit_interval": int(config["audit_interval_generations"]),
			"audit_generation_1": bool(config["audit_generation_1"]),
		}):
			return {}
		if not wb.set_generation_stream_executor(executor):
			return {}

	for _warmup in int(config["warmup_generations"]):
		if wb.advance_generations(1).is_empty():
			return {}

	var telemetry_before := {
		"stream_calls": 0,
		"chunks_processed": 0,
		"serial_audit_calls": 0,
		"oracle_elided_generations": 0,
	}
	if execution_mode == "STREAM1":
		var raw_before: Dictionary = executor.get_telemetry()
		for key in telemetry_before.keys():
			telemetry_before[key] = int(raw_before.get(key, 0))

	var probe := Probe.new()
	var started := probe.begin()
	if not bool(started.get("success", false)):
		return {}

	var timing_sums := {
		"generation_total_ms": 0.0,
		"ls33_total_ms": 0.0,
		"stream_total_ms": 0.0,
		"candidate_build_ms": 0.0,
		"route_build_ms": 0.0,
		"recruitment_eval_ms": 0.0,
		"audit_ms": 0.0,
	}
	var final_ls33: Dictionary = {}
	for _measured in int(config["measured_generations"]):
		if wb.advance_generations(1).is_empty():
			return {}
		var profile: Dictionary = wb.get_last_generation_profile()
		var ecology: Dictionary = Dictionary(profile.get("ecology", {}))
		var ls33: Dictionary = Dictionary(ecology.get("ls33", {}))
		if profile.is_empty() or ls33.is_empty():
			return {}
		timing_sums["generation_total_ms"] += float(profile.get("total_ms", -1.0))
		timing_sums["ls33_total_ms"] += float(ecology.get("ls33_total_ms", -1.0))
		timing_sums["candidate_build_ms"] += float(ls33.get("candidate_build_ms", -1.0))
		timing_sums["route_build_ms"] += float(ls33.get("route_build_ms", -1.0))
		timing_sums["recruitment_eval_ms"] += float(ls33.get("recruitment_eval_ms", -1.0))
		if execution_mode == "STREAM1":
			var stream_timings: Dictionary = Dictionary(ls33.get("timings_ms", {}))
			timing_sums["stream_total_ms"] += float(stream_timings.get("total_ms", -1.0))
			timing_sums["audit_ms"] += float(stream_timings.get("audit_ms", -1.0))
		final_ls33 = ls33.duplicate(true)

	var observed := probe.finish()
	if not bool(observed.get("success", false)):
		return {}

	var measured_count := float(int(config["measured_generations"]))
	var timings := {
		"wall_ms": float(observed.get("wall_ms", -1.0)),
		"generation_total_ms": float(timing_sums["generation_total_ms"]) / measured_count,
		"ls33_total_ms": float(timing_sums["ls33_total_ms"]) / measured_count,
		"stream_total_ms": float(timing_sums["stream_total_ms"]) / measured_count,
		"candidate_build_ms": float(timing_sums["candidate_build_ms"]) / measured_count,
		"route_build_ms": float(timing_sums["route_build_ms"]) / measured_count,
		"recruitment_eval_ms": float(timing_sums["recruitment_eval_ms"]) / measured_count,
		"audit_ms": float(timing_sums["audit_ms"]) / measured_count,
	}
	for value in timings.values():
		if not _finite_nonnegative(value):
			return {}

	var snapshot: Dictionary = wb.get_workbench_snapshot()
	var ecology_snapshot: Dictionary = wb.get_ecology_snapshot()
	if snapshot.is_empty() or ecology_snapshot.is_empty():
		return {}

	var telemetry := {
		"stream_calls": 0,
		"chunks_processed": 0,
		"serial_audit_calls": 0,
		"oracle_elided_generations": 0,
	}
	var chunk_count := 0
	var max_parent_chunk := 0
	var max_candidate_chunk := 0
	if execution_mode == "STREAM1":
		var raw_telemetry: Dictionary = executor.get_telemetry()
		for key in telemetry.keys():
			telemetry[key] = int(raw_telemetry.get(key, 0)) - int(telemetry_before.get(key, 0))
			if int(telemetry[key]) < 0:
				return {}
		chunk_count = int(final_ls33.get("stream_chunk_count", 0))
		max_parent_chunk = int(raw_telemetry.get("max_parent_chunk_seen", 0))
		max_candidate_chunk = int(raw_telemetry.get("max_candidate_chunk_seen", 0))

	var memory: Dictionary = Dictionary(observed.get("memory_bytes", {}))
	var sample := {
		"schema": Contract.SAMPLE_SCHEMA,
		"version": Contract.VERSION,
		"revision": Contract.REVISION,
		"run_id": "perf2-1-%s-%s-r%d" % [recipe.to_lower(), execution_mode.to_lower(), repetition],
		"target": target.duplicate(true),
		"host_fingerprint": host_fingerprint,
		"measurement_method_revision": Contract.REVISION,
		"workload": workload.duplicate(true),
		"workload_hash": Contract.workload_hash(workload),
		"passed": true,
		"canonical_result": {
			"final_workbench_hash": String(snapshot.get("workbench_hash", "")),
			"final_ecology_state_hash": String(snapshot.get("ecology_state_hash", "")),
			"final_population_hash": String(snapshot.get("population_hash", "")),
			"final_classification_hash": String(snapshot.get("classification_hash", "")),
		},
		"metrics": {
			"timings_ms": timings,
			"counts": {
				"generation": int(snapshot.get("generation", -1)),
				"population": int(ecology_snapshot.get("record_count", -1)),
				"parent_count": int(final_ls33.get("parent_count", 0)),
				"candidate_count": int(final_ls33.get("candidate_count", 0)),
				"chunk_count": chunk_count,
				"max_parent_chunk": max_parent_chunk,
				"max_candidate_chunk": max_candidate_chunk,
			},
			"memory_bytes": {
				"engine_static_bytes": int(memory.get("engine_static_bytes", 0)),
				"engine_static_peak_bytes": int(memory.get("engine_static_peak_bytes", 0)),
				"process_rss_bytes": memory.get("process_rss_bytes"),
				"process_peak_rss_bytes": memory.get("process_peak_rss_bytes"),
			},
			"stream": telemetry,
		},
		"flags": {
			"canonical": false,
			"side_channel_only": true,
			"measurement_only": true,
		},
	}
	if not bool(Contract.validate_sample(sample).get("success", false)):
		return {}
	return sample

func _workload(config: Dictionary, recipe: String, execution_mode: String) -> Dictionary:
	return {
		"workload_id": "PERF2_STREAM1_STANDARD_R1",
		"execution_mode": execution_mode,
		"environment_recipe": recipe,
		"warmup_generations": int(config["warmup_generations"]),
		"measured_generations": int(config["measured_generations"]),
		"repetitions": int(config["repetitions"]),
		"initial_records": int(config["initial_records"]),
		"parents_per_chunk": int(config["parents_per_chunk"]) if execution_mode == "STREAM1" else 1,
		"audit_interval_generations": int(config["audit_interval_generations"]) if execution_mode == "STREAM1" else 1,
		"audit_generation_1": bool(config["audit_generation_1"]) if execution_mode == "STREAM1" else false,
		"founder_seed": int(config["founder_seed"]),
		"placement_seed": int(config["placement_seed"]),
		"evolution_seed": int(config["evolution_seed"]),
		"environment_seed": int(config["environment_seed"]),
	}

func _build_summaries(samples: Array[Dictionary], config: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe_value in Array(config["recipes"]):
		var recipe := String(recipe_value)
		for mode in EXECUTION_MODES:
			var group: Array[Dictionary] = []
			for sample in samples:
				var workload: Dictionary = Dictionary(sample.get("workload", {}))
				if String(workload.get("environment_recipe", "")) == recipe and String(workload.get("execution_mode", "")) == mode:
					group.append(sample)
			if group.size() != int(config["repetitions"]) or not Contract.minimum_repetitions_satisfied(group):
				return []
			for metric_path in REQUIRED_METRICS:
				var summary := Contract.summarize(group, metric_path)
				if summary.is_empty():
					return []
				summary["environment_recipe"] = recipe
				summary["execution_mode"] = mode
				summary["simulation_workload_hash"] = Contract.simulation_workload_hash(Dictionary(group[0]["workload"]))
				result.append(summary)
	return result

func _find_sample(samples: Array, recipe: String, execution_mode: String, repetition: int) -> Dictionary:
	var suffix := "-r%d" % repetition
	for value in samples:
		if not value is Dictionary:
			continue
		var sample: Dictionary = value
		var workload: Dictionary = Dictionary(sample.get("workload", {}))
		if String(workload.get("environment_recipe", "")) != recipe:
			continue
		if String(workload.get("execution_mode", "")) != execution_mode:
			continue
		if String(sample.get("run_id", "")).ends_with(suffix):
			return sample
	return {}

func _sample_evidence_hash(sample: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(sample.get("run_id", "")),
		String(sample.get("workload_hash", "")),
		Contract.simulation_workload_hash(Dictionary(sample.get("workload", {}))),
		Contract.canonical_result_fingerprint(sample),
		Contract.comparison_key(sample),
		Contract.execution_comparison_key(sample),
	])).sha256_text()

func _summary_evidence_hash(summary: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(summary.get("environment_recipe", "")),
		String(summary.get("execution_mode", "")),
		String(summary.get("metric_path", "")),
		str(int(summary.get("count", 0))),
		str(float(summary.get("p50", 0.0))),
		str(float(summary.get("p95", 0.0))),
		str(float(summary.get("mean", 0.0))),
		str(float(summary.get("min", 0.0))),
		str(float(summary.get("max", 0.0))),
		String(summary.get("simulation_workload_hash", "")),
	])).sha256_text()

func _config_hash(config: Dictionary) -> String:
	var recipe_parts := PackedStringArray()
	for value in Array(config.get("recipes", [])):
		recipe_parts.append(String(value))
	return "|".join(PackedStringArray([
		"PERF2_1_CONFIG_V1",
		",".join(recipe_parts),
		str(int(config.get("warmup_generations", -1))),
		str(int(config.get("measured_generations", -1))),
		str(int(config.get("repetitions", -1))),
		str(int(config.get("initial_records", -1))),
		str(int(config.get("parents_per_chunk", -1))),
		str(int(config.get("audit_interval_generations", -1))),
		"true" if bool(config.get("audit_generation_1", false)) else "false",
		str(int(config.get("founder_seed", 0))),
		str(int(config.get("placement_seed", 0))),
		str(int(config.get("evolution_seed", 0))),
		str(int(config.get("environment_seed", 0))),
	])).sha256_text()

func _valid_target(target: Dictionary) -> bool:
	return (
		_is_git_sha(String(target.get("head", "")))
		and _is_git_sha(String(target.get("tree", "")))
		and String(target.get("godot_version", "")) == Contract.EXPECTED_GODOT
	)

func _is_git_sha(value: String) -> bool:
	if value.length() != 40:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true

func _finite_nonnegative(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0

func _failure(code: String, detail) -> Dictionary:
	return {
		"success": false,
		"failure_code": code,
		"detail": detail,
	}
