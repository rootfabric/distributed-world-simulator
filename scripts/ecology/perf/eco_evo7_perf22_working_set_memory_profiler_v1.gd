extends RefCounted

## ECO.EVO7 PERF2.2 R1 — Working-set / Memory report builder.
##
## This stage is measurement-only. It consumes a validated PERF2.1 R2 report and
## derives two deliberately separate evidence classes:
##
## 1. deterministic structural working-set pressure, expressed as bounded record
##    proxy upper bounds from max_parent_chunk + max_candidate_chunk;
## 2. process-local Godot allocator telemetry already captured by PERF2.1.
##
## The structural proxy is not bytes and does not claim both maxima occur at the
## same instant. The engine peak metric is a process-lifetime high-water mark and
## is therefore diagnostic-only for cross-configuration comparison.

const Contract = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
const Perf21 = preload("res://scripts/ecology/perf/eco_evo7_perf21_generation_profiler_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_perf2_2.working_set_memory_report.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-PERF2.2-R1"
const MODE := "RESEARCH_SHADOW_PERFORMANCE_ONLY"
const FROZEN_PERF21_REVISION := "ECO.EVO7-PERF2.1-R2"
const FROZEN_PERF2_CONTRACT_BLOB_SHA := "b076784f6b4016a0191e937c4e6ada1fe90c783b"

const EXECUTION_CONFIG_IDS: Array[String] = [
	"SERIAL_REFERENCE",
	"STREAM1_CHUNK_1",
	"STREAM1_CHUNK_7",
	"STREAM1_CHUNK_64",
]
const STREAM_CHUNK_SIZES: Array[int] = [1, 7, 64]

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

const WORKING_SET_SEMANTICS := {
	"unit": "RECORD_PROXY_UPPER_BOUND",
	"formula": "max_parent_chunk + max_candidate_chunk",
	"simultaneous_allocation_claim": false,
	"bytes_claim": false,
	"deterministic_from_perf2_1_counts": true,
}

const MEMORY_SEMANTICS := {
	"engine_static_end": "PROCESS_LOCAL_GODOT_STATIC_MEMORY_AT_SAMPLE_END",
	"engine_static_peak": "PROCESS_LIFETIME_HIGH_WATERMARK_DIAGNOSTIC",
	"engine_static_peak_cross_config_comparable": false,
	"engine_static_end_cross_config_claim": "DIAGNOSTIC_ONLY",
	"process_rss": "OPTIONAL_EXTERNAL_FIELD_FROM_FROZEN_PERF2_0_CONTRACT",
	"memory_reduction_claim_allowed": false,
}


func build_report(perf21_report: Dictionary) -> Dictionary:
	var perf21 = Perf21.new()
	if not perf21.validate_report(perf21_report):
		return _failure("PERF2_1_REPORT_INVALID", [])
	if String(perf21_report.get("revision", "")) != FROZEN_PERF21_REVISION:
		return _failure("PERF2_1_REVISION_DRIFT", [])
	if String(perf21_report.get("accepted_measurement_contract_blob_sha", "")) != FROZEN_PERF2_CONTRACT_BLOB_SHA:
		return _failure("PERF2_CONTRACT_BLOB_DRIFT", [])

	var samples: Array = Array(perf21_report.get("samples", []))
	if samples.size() != 12:
		return _failure("PERF2_1_SAMPLE_COUNT", [samples.size()])

	var grouped := _group_samples(samples)
	if grouped.is_empty():
		return _failure("SAMPLE_GROUPING_FAILED", [])

	var working_rows: Array[Dictionary] = []
	var memory_rows: Array[Dictionary] = []
	for configuration_id in EXECUTION_CONFIG_IDS:
		var group: Array = Array(grouped.get(configuration_id, []))
		if group.size() != 3:
			return _failure("REPETITION_COUNT", [configuration_id, group.size()])
		var working_row := _working_set_row(configuration_id, group)
		var memory_row := _memory_row(configuration_id, group)
		if working_row.is_empty() or memory_row.is_empty():
			return _failure("ROW_BUILD_FAILED", [configuration_id])
		working_rows.append(working_row)
		memory_rows.append(memory_row)

	var comparisons := _build_comparisons(perf21_report, working_rows, memory_rows)
	if comparisons.size() != 3:
		return _failure("COMPARISON_BUILD_FAILED", [])

	var source_target: Dictionary = Dictionary(perf21_report.get("target", {}))
	var report := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"mode": MODE,
		"source_perf2_1": {
			"revision": String(perf21_report.get("revision", "")),
			"profile_schema": String(perf21_report.get("profile_schema", "")),
			"report_hash": String(perf21_report.get("report_hash", "")),
			"target": source_target.duplicate(true),
			"host_fingerprint": String(perf21_report.get("host_fingerprint", "")),
			"campaign_context_hash": String(perf21_report.get("campaign_context_hash", "")),
		},
		"accepted_measurement_contract_revision": Contract.REVISION,
		"accepted_measurement_contract_blob_sha": FROZEN_PERF2_CONTRACT_BLOB_SHA,
		"working_set_semantics": WORKING_SET_SEMANTICS.duplicate(true),
		"memory_semantics": MEMORY_SEMANTICS.duplicate(true),
		"working_set_rows": working_rows,
		"memory_rows": memory_rows,
		"comparisons": comparisons,
		"authorities": AUTHORITIES.duplicate(true),
	}
	report["report_hash"] = report_hash(report)
	if not validate_report(report):
		return _failure("REPORT_VALIDATION_FAILED", [])
	return report


func validate_report(report: Dictionary) -> bool:
	var required := [
		"schema", "version", "revision", "mode", "source_perf2_1",
		"accepted_measurement_contract_revision", "accepted_measurement_contract_blob_sha",
		"working_set_semantics", "memory_semantics",
		"working_set_rows", "memory_rows", "comparisons", "authorities", "report_hash",
	]
	if report.size() != required.size():
		return false
	for key in required:
		if not report.has(key):
			return false

	if String(report["schema"]) != SCHEMA:
		return false
	if String(report["version"]) != VERSION or String(report["revision"]) != REVISION or String(report["mode"]) != MODE:
		return false
	if String(report["accepted_measurement_contract_revision"]) != Contract.REVISION:
		return false
	if String(report["accepted_measurement_contract_blob_sha"]) != FROZEN_PERF2_CONTRACT_BLOB_SHA:
		return false
	if Dictionary(report["working_set_semantics"]) != WORKING_SET_SEMANTICS:
		return false
	if Dictionary(report["memory_semantics"]) != MEMORY_SEMANTICS:
		return false
	if Dictionary(report["authorities"]) != AUTHORITIES:
		return false

	var source: Dictionary = Dictionary(report["source_perf2_1"])
	if source.size() != 6:
		return false
	if String(source.get("revision", "")) != FROZEN_PERF21_REVISION:
		return false
	if String(source.get("profile_schema", "")) != Perf21.PROFILE_SCHEMA:
		return false
	if not _is_hash(String(source.get("report_hash", ""))):
		return false
	if not _valid_target(Dictionary(source.get("target", {}))):
		return false
	if not _is_hash(String(source.get("host_fingerprint", ""))):
		return false
	if not _is_hash(String(source.get("campaign_context_hash", ""))):
		return false

	var working_rows: Array = Array(report["working_set_rows"])
	var memory_rows: Array = Array(report["memory_rows"])
	var comparisons: Array = Array(report["comparisons"])
	if working_rows.size() != 4 or memory_rows.size() != 4 or comparisons.size() != 3:
		return false

	var seen_working := {}
	for value in working_rows:
		if not value is Dictionary:
			return false
		var row: Dictionary = value
		if not _validate_working_row(row):
			return false
		var configuration_id := String(row.get("configuration_id", ""))
		if seen_working.has(configuration_id):
			return false
		seen_working[configuration_id] = true
	if seen_working.size() != EXECUTION_CONFIG_IDS.size():
		return false

	var seen_memory := {}
	for value in memory_rows:
		if not value is Dictionary:
			return false
		var row: Dictionary = value
		if not _validate_memory_row(row):
			return false
		var configuration_id := String(row.get("configuration_id", ""))
		if seen_memory.has(configuration_id):
			return false
		seen_memory[configuration_id] = true
	if seen_memory.size() != EXECUTION_CONFIG_IDS.size():
		return false

	var seen_chunks := {}
	for value in comparisons:
		if not value is Dictionary:
			return false
		var comparison: Dictionary = value
		if not _validate_comparison(comparison):
			return false
		var chunk_size := int(comparison.get("stream_chunk_size", 0))
		if seen_chunks.has(chunk_size):
			return false
		seen_chunks[chunk_size] = true
	for chunk_size in STREAM_CHUNK_SIZES:
		if not seen_chunks.has(chunk_size):
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
	var source: Dictionary = Dictionary(report.get("source_perf2_1", {}))
	var working_hashes := PackedStringArray()
	for value in Array(report.get("working_set_rows", [])):
		working_hashes.append(_working_row_hash(Dictionary(value)))
	var memory_hashes := PackedStringArray()
	for value in Array(report.get("memory_rows", [])):
		memory_hashes.append(_memory_row_hash(Dictionary(value)))
	var comparison_hashes := PackedStringArray()
	for value in Array(report.get("comparisons", [])):
		comparison_hashes.append(_comparison_hash(Dictionary(value)))
	return "|".join(PackedStringArray([
		"PERF2_2_REPORT_R1",
		String(Dictionary(source.get("target", {})).get("head", "")),
		String(Dictionary(source.get("target", {})).get("tree", "")),
		String(Dictionary(source.get("target", {})).get("godot_version", "")),
		String(source.get("host_fingerprint", "")),
		String(source.get("campaign_context_hash", "")),
		String(source.get("report_hash", "")),
		Contract.REVISION,
		FROZEN_PERF2_CONTRACT_BLOB_SHA,
		REVISION,
		";".join(working_hashes),
		";".join(memory_hashes),
		";".join(comparison_hashes),
	])).sha256_text()


func _group_samples(samples: Array) -> Dictionary:
	var grouped := {}
	for configuration_id in EXECUTION_CONFIG_IDS:
		grouped[configuration_id] = []
	for value in samples:
		if not value is Dictionary:
			return {}
		var sample: Dictionary = value
		var flags: Dictionary = Dictionary(sample.get("flags", {}))
		var configuration_id := String(flags.get("configuration_id", ""))
		if not grouped.has(configuration_id):
			return {}
		var group: Array = grouped[configuration_id]
		group.append(sample)
		grouped[configuration_id] = group
	return grouped


func _working_set_row(configuration_id: String, samples: Array) -> Dictionary:
	var parent_values: Array[int] = []
	var candidate_values: Array[int] = []
	var proxy_values: Array[int] = []
	var parent_count_values: Array[int] = []
	var candidate_count_values: Array[int] = []

	for value in samples:
		if not value is Dictionary:
			return {}
		var sample: Dictionary = value
		var counts: Dictionary = Dictionary(Dictionary(sample.get("metrics", {})).get("counts", {}))
		var max_parent := int(counts.get("max_parent_chunk", -1))
		var max_candidate := int(counts.get("max_candidate_chunk", -1))
		var parent_count := int(counts.get("parent_count", -1))
		var candidate_count := int(counts.get("candidate_count", -1))
		if max_parent <= 0 or max_candidate <= 0 or parent_count <= 0 or candidate_count <= 0:
			return {}
		parent_values.append(max_parent)
		candidate_values.append(max_candidate)
		proxy_values.append(max_parent + max_candidate)
		parent_count_values.append(parent_count)
		candidate_count_values.append(candidate_count)

	var execution_mode := "SERIAL_REFERENCE" if configuration_id == "SERIAL_REFERENCE" else "STREAM1"
	var chunk_size := 0
	if execution_mode == "STREAM1":
		chunk_size = int(configuration_id.trim_prefix("STREAM1_CHUNK_"))
		if chunk_size not in STREAM_CHUNK_SIZES:
			return {}
		for index in range(parent_values.size()):
			if parent_values[index] > chunk_size or candidate_values[index] > chunk_size * 2:
				return {}

	return {
		"configuration_id": configuration_id,
		"execution_mode": execution_mode,
		"stream_chunk_size": chunk_size,
		"repetitions": samples.size(),
		"max_parent_chunk_records": _summary_int(parent_values),
		"max_candidate_chunk_records": _summary_int(candidate_values),
		"record_proxy_upper_bound": _summary_int(proxy_values),
		"final_parent_count": _summary_int(parent_count_values),
		"final_candidate_count": _summary_int(candidate_count_values),
		"bound_proven": true,
		"bytes_claim": false,
	}


func _memory_row(configuration_id: String, samples: Array) -> Dictionary:
	var static_end: Array[int] = []
	var static_peak: Array[int] = []
	var rss: Array[int] = []
	var peak_rss: Array[int] = []

	for value in samples:
		if not value is Dictionary:
			return {}
		var sample: Dictionary = value
		var memory: Dictionary = Dictionary(Dictionary(sample.get("metrics", {})).get("memory_bytes", {}))
		var end_bytes := int(memory.get("engine_static_bytes", -1))
		var peak_bytes := int(memory.get("engine_static_peak_bytes", -1))
		if end_bytes < 0 or peak_bytes < 0 or peak_bytes < end_bytes:
			return {}
		static_end.append(end_bytes)
		static_peak.append(peak_bytes)
		if memory.get("process_rss_bytes") != null:
			var rss_value := int(memory["process_rss_bytes"])
			if rss_value < 0:
				return {}
			rss.append(rss_value)
		if memory.get("process_peak_rss_bytes") != null:
			var peak_rss_value := int(memory["process_peak_rss_bytes"])
			if peak_rss_value < 0:
				return {}
			peak_rss.append(peak_rss_value)

	return {
		"configuration_id": configuration_id,
		"repetitions": samples.size(),
		"engine_static_end_bytes": _summary_int(static_end),
		"engine_static_peak_bytes": _summary_int(static_peak),
		"process_rss_available_samples": rss.size(),
		"process_peak_rss_available_samples": peak_rss.size(),
		"process_rss_bytes": _summary_int(rss) if not rss.is_empty() else null,
		"process_peak_rss_bytes": _summary_int(peak_rss) if not peak_rss.is_empty() else null,
		"engine_static_end_claim": "DIAGNOSTIC_ONLY",
		"engine_static_peak_claim": "PROCESS_LIFETIME_HIGH_WATERMARK_DIAGNOSTIC_ONLY",
		"memory_reduction_claim": false,
	}


func _build_comparisons(perf21_report: Dictionary, working_rows: Array[Dictionary], memory_rows: Array[Dictionary]) -> Array[Dictionary]:
	var serial_working := _find_row(working_rows, "SERIAL_REFERENCE")
	var serial_memory := _find_row(memory_rows, "SERIAL_REFERENCE")
	if serial_working.is_empty() or serial_memory.is_empty():
		return []

	var source_comparisons: Array = Array(perf21_report.get("comparisons", []))
	var result: Array[Dictionary] = []
	for chunk_size in STREAM_CHUNK_SIZES:
		var configuration_id := "STREAM1_CHUNK_%d" % chunk_size
		var stream_working := _find_row(working_rows, configuration_id)
		var stream_memory := _find_row(memory_rows, configuration_id)
		var source_comparison := _find_source_comparison(source_comparisons, chunk_size)
		if stream_working.is_empty() or stream_memory.is_empty() or source_comparison.is_empty():
			return []
		if int(source_comparison.get("exact_pairs", 0)) != 3:
			return []

		var serial_parent := float(Dictionary(serial_working["max_parent_chunk_records"]).get("p50", 0.0))
		var stream_parent := float(Dictionary(stream_working["max_parent_chunk_records"]).get("p50", 0.0))
		var serial_candidate := float(Dictionary(serial_working["max_candidate_chunk_records"]).get("p50", 0.0))
		var stream_candidate := float(Dictionary(stream_working["max_candidate_chunk_records"]).get("p50", 0.0))
		var serial_proxy := float(Dictionary(serial_working["record_proxy_upper_bound"]).get("p50", 0.0))
		var stream_proxy := float(Dictionary(stream_working["record_proxy_upper_bound"]).get("p50", 0.0))
		var serial_static := float(Dictionary(serial_memory["engine_static_end_bytes"]).get("p50", 0.0))
		var stream_static := float(Dictionary(stream_memory["engine_static_end_bytes"]).get("p50", 0.0))
		if stream_parent <= 0.0 or stream_candidate <= 0.0 or stream_proxy <= 0.0 or stream_static <= 0.0:
			return []

		result.append({
			"configuration_id": configuration_id,
			"stream_chunk_size": chunk_size,
			"exact_pairs": 3,
			"parent_record_reduction_factor_serial_over_stream": serial_parent / stream_parent,
			"candidate_record_reduction_factor_serial_over_stream": serial_candidate / stream_candidate,
			"record_proxy_reduction_factor_serial_over_stream": serial_proxy / stream_proxy,
			"engine_static_end_ratio_serial_over_stream": serial_static / stream_static,
			"engine_static_end_ratio_interpretation": "DIAGNOSTIC_ONLY_PROCESS_LOCAL",
			"working_set_bound_claim": true,
			"memory_reduction_claim": false,
			"optimization_claim": false,
		})
	return result


func _validate_working_row(row: Dictionary) -> bool:
	var required := [
		"configuration_id", "execution_mode", "stream_chunk_size", "repetitions",
		"max_parent_chunk_records", "max_candidate_chunk_records", "record_proxy_upper_bound",
		"final_parent_count", "final_candidate_count", "bound_proven", "bytes_claim",
	]
	if row.size() != required.size():
		return false
	for key in required:
		if not row.has(key):
			return false
	var configuration_id := String(row["configuration_id"])
	if configuration_id not in EXECUTION_CONFIG_IDS:
		return false
	if not _integer_value_equals(row["repetitions"], 3):
		return false
	if not bool(row["bound_proven"]) or bool(row["bytes_claim"]):
		return false
	for key in [
		"max_parent_chunk_records", "max_candidate_chunk_records", "record_proxy_upper_bound",
		"final_parent_count", "final_candidate_count",
	]:
		if not _validate_int_summary(Dictionary(row[key]), 3):
			return false
	var execution_mode := String(row["execution_mode"])
	var chunk_size := int(row["stream_chunk_size"])
	if configuration_id == "SERIAL_REFERENCE":
		if execution_mode != "SERIAL_REFERENCE" or chunk_size != 0:
			return false
	else:
		if execution_mode != "STREAM1" or chunk_size not in STREAM_CHUNK_SIZES:
			return false
		if float(Dictionary(row["max_parent_chunk_records"]).get("max", 0.0)) > float(chunk_size):
			return false
		if float(Dictionary(row["max_candidate_chunk_records"]).get("max", 0.0)) > float(chunk_size * 2):
			return false
	return true


func _validate_memory_row(row: Dictionary) -> bool:
	var required := [
		"configuration_id", "repetitions", "engine_static_end_bytes", "engine_static_peak_bytes",
		"process_rss_available_samples", "process_peak_rss_available_samples",
		"process_rss_bytes", "process_peak_rss_bytes",
		"engine_static_end_claim", "engine_static_peak_claim", "memory_reduction_claim",
	]
	if row.size() != required.size():
		return false
	for key in required:
		if not row.has(key):
			return false
	if String(row["configuration_id"]) not in EXECUTION_CONFIG_IDS:
		return false
	if not _integer_value_equals(row["repetitions"], 3):
		return false
	if not _validate_int_summary(Dictionary(row["engine_static_end_bytes"]), 3):
		return false
	if not _validate_int_summary(Dictionary(row["engine_static_peak_bytes"]), 3):
		return false
	if String(row["engine_static_end_claim"]) != "DIAGNOSTIC_ONLY":
		return false
	if String(row["engine_static_peak_claim"]) != "PROCESS_LIFETIME_HIGH_WATERMARK_DIAGNOSTIC_ONLY":
		return false
	if bool(row["memory_reduction_claim"]):
		return false

	for availability_key in ["process_rss_available_samples", "process_peak_rss_available_samples"]:
		if not _is_integral_number(row[availability_key]):
			return false
		var available := int(row[availability_key])
		if available < 0 or available > 3:
			return false
	var rss_available := int(row["process_rss_available_samples"])
	var peak_rss_available := int(row["process_peak_rss_available_samples"])
	if rss_available == 0:
		if row["process_rss_bytes"] != null:
			return false
	else:
		if not row["process_rss_bytes"] is Dictionary or not _validate_int_summary(Dictionary(row["process_rss_bytes"]), rss_available):
			return false
	if peak_rss_available == 0:
		if row["process_peak_rss_bytes"] != null:
			return false
	else:
		if not row["process_peak_rss_bytes"] is Dictionary or not _validate_int_summary(Dictionary(row["process_peak_rss_bytes"]), peak_rss_available):
			return false
	return true


func _validate_comparison(comparison: Dictionary) -> bool:
	var required := [
		"configuration_id", "stream_chunk_size", "exact_pairs",
		"parent_record_reduction_factor_serial_over_stream",
		"candidate_record_reduction_factor_serial_over_stream",
		"record_proxy_reduction_factor_serial_over_stream",
		"engine_static_end_ratio_serial_over_stream",
		"engine_static_end_ratio_interpretation",
		"working_set_bound_claim", "memory_reduction_claim", "optimization_claim",
	]
	if comparison.size() != required.size():
		return false
	for key in required:
		if not comparison.has(key):
			return false
	var chunk_size := int(comparison["stream_chunk_size"])
	if chunk_size not in STREAM_CHUNK_SIZES:
		return false
	if String(comparison["configuration_id"]) != "STREAM1_CHUNK_%d" % chunk_size:
		return false
	if not _integer_value_equals(comparison["exact_pairs"], 3):
		return false
	for key in [
		"parent_record_reduction_factor_serial_over_stream",
		"candidate_record_reduction_factor_serial_over_stream",
		"record_proxy_reduction_factor_serial_over_stream",
		"engine_static_end_ratio_serial_over_stream",
	]:
		if not _finite_positive(comparison[key]):
			return false
	if String(comparison["engine_static_end_ratio_interpretation"]) != "DIAGNOSTIC_ONLY_PROCESS_LOCAL":
		return false
	if not bool(comparison["working_set_bound_claim"]):
		return false
	if bool(comparison["memory_reduction_claim"]) or bool(comparison["optimization_claim"]):
		return false
	return true


func _summary_int(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted_values: Array[int] = values.duplicate()
	sorted_values.sort()
	var sum := 0.0
	for value in sorted_values:
		sum += float(value)
	return {
		"count": sorted_values.size(),
		"p50": float(sorted_values[_percentile_index(sorted_values.size(), 0.50)]),
		"p95": float(sorted_values[_percentile_index(sorted_values.size(), 0.95)]),
		"mean": sum / float(sorted_values.size()),
		"min": sorted_values[0],
		"max": sorted_values[sorted_values.size() - 1],
	}


func _validate_int_summary(summary: Dictionary, expected_count: int) -> bool:
	var required := ["count", "p50", "p95", "mean", "min", "max"]
	if summary.size() != required.size():
		return false
	for key in required:
		if not summary.has(key):
			return false
	if not _integer_value_equals(summary["count"], expected_count):
		return false
	for key in ["p50", "p95", "mean"]:
		if not _finite_nonnegative(summary[key]):
			return false
	for key in ["min", "max"]:
		if not _is_integral_number(summary[key]) or int(summary[key]) < 0:
			return false
	if float(summary["min"]) > float(summary["p50"]):
		return false
	if float(summary["p50"]) > float(summary["p95"]):
		return false
	if float(summary["p95"]) > float(summary["max"]) + 1e-9:
		return false
	return true


func _find_row(rows: Array[Dictionary], configuration_id: String) -> Dictionary:
	for row in rows:
		if String(row.get("configuration_id", "")) == configuration_id:
			return row
	return {}


func _find_source_comparison(comparisons: Array, chunk_size: int) -> Dictionary:
	for value in comparisons:
		if value is Dictionary and int(Dictionary(value).get("stream_chunk_size", 0)) == chunk_size:
			return Dictionary(value)
	return {}


func _working_row_hash(row: Dictionary) -> String:
	var parts := PackedStringArray([
		String(row.get("configuration_id", "")),
		String(row.get("execution_mode", "")),
		str(int(row.get("stream_chunk_size", 0))),
		str(int(row.get("repetitions", 0))),
	])
	for key in [
		"max_parent_chunk_records", "max_candidate_chunk_records", "record_proxy_upper_bound",
		"final_parent_count", "final_candidate_count",
	]:
		parts.append(_summary_hash(Dictionary(row.get(key, {}))))
	parts.append("1" if bool(row.get("bound_proven", false)) else "0")
	parts.append("1" if bool(row.get("bytes_claim", true)) else "0")
	return "|".join(parts).sha256_text()


func _memory_row_hash(row: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(row.get("configuration_id", "")),
		str(int(row.get("repetitions", 0))),
		_summary_hash(Dictionary(row.get("engine_static_end_bytes", {}))),
		_summary_hash(Dictionary(row.get("engine_static_peak_bytes", {}))),
		str(int(row.get("process_rss_available_samples", 0))),
		str(int(row.get("process_peak_rss_available_samples", 0))),
		_summary_hash(Dictionary(row.get("process_rss_bytes", {}))) if row.get("process_rss_bytes") is Dictionary else "null",
		_summary_hash(Dictionary(row.get("process_peak_rss_bytes", {}))) if row.get("process_peak_rss_bytes") is Dictionary else "null",
		String(row.get("engine_static_end_claim", "")),
		String(row.get("engine_static_peak_claim", "")),
		"1" if bool(row.get("memory_reduction_claim", true)) else "0",
	])).sha256_text()


func _comparison_hash(comparison: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(comparison.get("configuration_id", "")),
		str(int(comparison.get("stream_chunk_size", 0))),
		str(int(comparison.get("exact_pairs", 0))),
		_stable_float_token(comparison.get("parent_record_reduction_factor_serial_over_stream", 0.0)),
		_stable_float_token(comparison.get("candidate_record_reduction_factor_serial_over_stream", 0.0)),
		_stable_float_token(comparison.get("record_proxy_reduction_factor_serial_over_stream", 0.0)),
		_stable_float_token(comparison.get("engine_static_end_ratio_serial_over_stream", 0.0)),
		String(comparison.get("engine_static_end_ratio_interpretation", "")),
		"1" if bool(comparison.get("working_set_bound_claim", false)) else "0",
		"1" if bool(comparison.get("memory_reduction_claim", true)) else "0",
		"1" if bool(comparison.get("optimization_claim", true)) else "0",
	])).sha256_text()


func _summary_hash(summary: Dictionary) -> String:
	if summary.is_empty():
		return "EMPTY"
	return "|".join(PackedStringArray([
		str(int(summary.get("count", 0))),
		_stable_float_token(summary.get("p50", 0.0)),
		_stable_float_token(summary.get("p95", 0.0)),
		_stable_float_token(summary.get("mean", 0.0)),
		str(int(summary.get("min", 0))),
		str(int(summary.get("max", 0))),
	])).sha256_text()


func _percentile_index(size: int, fraction: float) -> int:
	if size <= 1:
		return 0
	return clampi(int(ceil(float(size - 1) * fraction)), 0, size - 1)


func _stable_float_token(value) -> String:
	if not _finite_nonnegative(value):
		return "INVALID"
	return "%.6f" % float(value)


func _integer_value_equals(value, expected: int) -> bool:
	return _is_integral_number(value) and int(value) == expected


func _is_integral_number(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number)


func _finite_nonnegative(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0


func _finite_positive(value) -> bool:
	return _finite_nonnegative(value) and float(value) > 0.0


func _valid_target(target: Dictionary) -> bool:
	return (
		_is_git_sha(String(target.get("head", "")))
		and _is_git_sha(String(target.get("tree", "")))
		and String(target.get("godot_version", "")) == Contract.EXPECTED_GODOT
	)


func _is_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


func _is_git_sha(value: String) -> bool:
	if value.length() != 40:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


func _failure(code: String, detail) -> Dictionary:
	return {
		"success": false,
		"failure_code": code,
		"detail": detail,
	}
