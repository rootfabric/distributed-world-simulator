extends SceneTree

const Contract = preload("res://scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd")
const Perf21 = preload("res://scripts/ecology/perf/eco_evo7_perf21_generation_profiler_v1.gd")
const Profiler = preload("res://scripts/ecology/perf/eco_evo7_perf22_working_set_memory_profiler_v1.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var head := OS.get_environment("ECO_PERF2_TARGET_HEAD").strip_edges()
	var tree := OS.get_environment("ECO_PERF2_TARGET_TREE").strip_edges()
	var host := OS.get_environment("ECO_PERF2_HOST_FINGERPRINT").strip_edges()
	_check(_is_git_sha(head), "runner provides exact PERF2.2 target HEAD")
	_check(_is_git_sha(tree), "runner provides exact PERF2.2 target TREE")
	_check(_is_hash(host), "runner provides exact hashed host fingerprint")
	if not failures.is_empty():
		_finish()
		return

	_check(Contract.REVISION == "ECO.EVO7-PERF2.0-R1", "PERF2.0 measurement contract remains frozen")
	_check(Perf21.REVISION == "ECO.EVO7-PERF2.1-R2", "accepted PERF2.1 profiler revision remains frozen")

	var source_path := "res://artifacts/perf2/perf2-1-generation-profile-r2.json"
	_check(FileAccess.file_exists(source_path), "transitive PERF2.1 report artifact exists")
	if not FileAccess.file_exists(source_path):
		_finish()
		return

	var parsed_source = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	_check(parsed_source is Dictionary, "PERF2.1 source artifact parses as JSON")
	if not parsed_source is Dictionary:
		_finish()
		return
	var source_report: Dictionary = Dictionary(parsed_source)

	var perf21 = Perf21.new()
	_check(perf21.validate_report(source_report), "PERF2.1 source artifact passes full accepted validation")
	_check(String(Dictionary(source_report.get("target", {})).get("head", "")) == head, "source PERF2.1 report binds current exact HEAD")
	_check(String(Dictionary(source_report.get("target", {})).get("tree", "")) == tree, "source PERF2.1 report binds current exact TREE")
	_check(String(source_report.get("host_fingerprint", "")) == host, "source PERF2.1 report binds current host fingerprint")
	_check(Array(source_report.get("samples", [])).size() == 12, "source PERF2.1 report contains 12 samples")
	_check(Array(source_report.get("comparisons", [])).size() == 3, "source PERF2.1 report contains three exact chunk comparisons")

	var profiler = Profiler.new()
	var report: Dictionary = profiler.build_report(source_report)
	_check(not report.is_empty(), "PERF2.2 working-set/memory report builds from accepted PERF2.1 evidence")
	if report.is_empty():
		_finish()
		return

	_check(profiler.validate_report(report), "PERF2.2 report validates")
	_check(String(report.get("schema", "")) == Profiler.SCHEMA, "PERF2.2 report declares exact schema")
	_check(String(report.get("revision", "")) == Profiler.REVISION, "PERF2.2 report declares R1 revision")
	_check(String(report.get("accepted_measurement_contract_revision", "")) == Contract.REVISION, "PERF2.2 report binds frozen PERF2.0 revision")
	_check(String(report.get("accepted_measurement_contract_blob_sha", "")) == Profiler.FROZEN_PERF2_CONTRACT_BLOB_SHA, "PERF2.2 report binds frozen PERF2.0 blob")
	_check(Dictionary(report.get("working_set_semantics", {})) == Profiler.WORKING_SET_SEMANTICS, "working-set semantics are explicit and frozen")
	_check(Dictionary(report.get("memory_semantics", {})) == Profiler.MEMORY_SEMANTICS, "memory semantics are explicit and honest")
	_check(_all_authorities_safe(Dictionary(report.get("authorities", {}))), "PERF2.2 remains noncanonical measurement-only side channel")

	var source_binding: Dictionary = Dictionary(report.get("source_perf2_1", {}))
	_check(String(source_binding.get("report_hash", "")) == String(source_report.get("report_hash", "")), "PERF2.2 binds exact source PERF2.1 report hash")
	_check(String(Dictionary(source_binding.get("target", {})).get("head", "")) == head, "PERF2.2 source binding carries exact target HEAD")
	_check(String(Dictionary(source_binding.get("target", {})).get("tree", "")) == tree, "PERF2.2 source binding carries exact target TREE")
	_check(String(source_binding.get("host_fingerprint", "")) == host, "PERF2.2 source binding carries host fingerprint")

	var working_rows: Array = Array(report.get("working_set_rows", []))
	var memory_rows: Array = Array(report.get("memory_rows", []))
	var comparisons: Array = Array(report.get("comparisons", []))
	_check(working_rows.size() == 4, "PERF2.2 emits one working-set row for each execution configuration")
	_check(memory_rows.size() == 4, "PERF2.2 emits one memory row for each execution configuration")
	_check(comparisons.size() == 3, "PERF2.2 emits one serial↔STREAM1 comparison per chunk size")

	var seen_configs := {}
	for value in working_rows:
		var row: Dictionary = value
		var configuration_id := String(row.get("configuration_id", ""))
		_check(configuration_id in Profiler.EXECUTION_CONFIG_IDS, "working-set configuration is recognized: %s" % configuration_id)
		seen_configs[configuration_id] = true
		_check(int(row.get("repetitions", 0)) == 3, "working-set row retains all three repetitions")
		_check(bool(row.get("bound_proven", false)), "working-set row proves structural bound")
		_check(not bool(row.get("bytes_claim", true)), "record proxy is never mislabeled as bytes")
		for key in [
			"max_parent_chunk_records", "max_candidate_chunk_records",
			"record_proxy_upper_bound", "final_parent_count", "final_candidate_count",
		]:
			_check(_summary_valid(Dictionary(row.get(key, {}))), "working-set summary is valid: %s %s" % [configuration_id, key])

		if configuration_id == "SERIAL_REFERENCE":
			_check(String(row.get("execution_mode", "")) == "SERIAL_REFERENCE", "serial row preserves serial mode")
			_check(int(row.get("stream_chunk_size", -1)) == 0, "serial row has zero stream chunk size")
		else:
			var chunk_size := int(row.get("stream_chunk_size", 0))
			_check(String(row.get("execution_mode", "")) == "STREAM1", "stream row preserves STREAM1 mode")
			_check(chunk_size in [1, 7, 64], "stream row carries frozen chunk size")
			_check(float(Dictionary(row["max_parent_chunk_records"]).get("max", 0.0)) <= float(chunk_size), "STREAM1 max parent record pressure stays within chunk bound")
			_check(float(Dictionary(row["max_candidate_chunk_records"]).get("max", 0.0)) <= float(chunk_size * 2), "STREAM1 max candidate record pressure stays within 2x chunk bound")
	_check(seen_configs.size() == 4, "all four working-set configurations are present")

	for value in memory_rows:
		var row: Dictionary = value
		var configuration_id := String(row.get("configuration_id", ""))
		_check(configuration_id in Profiler.EXECUTION_CONFIG_IDS, "memory configuration is recognized: %s" % configuration_id)
		_check(int(row.get("repetitions", 0)) == 3, "memory row retains all three repetitions")
		_check(_summary_valid(Dictionary(row.get("engine_static_end_bytes", {}))), "engine static terminal memory summary is valid")
		_check(_summary_valid(Dictionary(row.get("engine_static_peak_bytes", {}))), "engine process high-water summary is valid")
		_check(float(Dictionary(row["engine_static_peak_bytes"]).get("p50", 0.0)) >= float(Dictionary(row["engine_static_end_bytes"]).get("p50", 0.0)), "p50 engine high-water is not below terminal static memory")
		_check(String(row.get("engine_static_end_claim", "")) == "DIAGNOSTIC_ONLY", "terminal allocator memory is diagnostic-only")
		_check(String(row.get("engine_static_peak_claim", "")) == "PROCESS_LIFETIME_HIGH_WATERMARK_DIAGNOSTIC_ONLY", "engine peak is explicitly process-lifetime diagnostic")
		_check(not bool(row.get("memory_reduction_claim", true)), "PERF2.2 makes no allocator-memory reduction claim")
		var rss_available := int(row.get("process_rss_available_samples", -1))
		var peak_rss_available := int(row.get("process_peak_rss_available_samples", -1))
		_check(rss_available >= 0 and rss_available <= 3, "optional process RSS availability count is bounded")
		_check(peak_rss_available >= 0 and peak_rss_available <= 3, "optional process peak RSS availability count is bounded")

	var exact_pairs := 0
	for value in comparisons:
		var comparison: Dictionary = value
		var chunk_size := int(comparison.get("stream_chunk_size", 0))
		_check(chunk_size in [1, 7, 64], "comparison chunk is recognized")
		_check(int(comparison.get("exact_pairs", 0)) == 3, "comparison carries 3/3 exact canonical pairs")
		exact_pairs += int(comparison.get("exact_pairs", 0))
		_check(_finite_positive(comparison.get("parent_record_reduction_factor_serial_over_stream")), "parent record reduction factor is finite/positive")
		_check(_finite_positive(comparison.get("candidate_record_reduction_factor_serial_over_stream")), "candidate record reduction factor is finite/positive")
		_check(_finite_positive(comparison.get("record_proxy_reduction_factor_serial_over_stream")), "combined record proxy reduction factor is finite/positive")
		_check(float(comparison.get("record_proxy_reduction_factor_serial_over_stream", 0.0)) >= 1.0, "STREAM1 structural record proxy never exceeds serial")
		_check(_finite_positive(comparison.get("engine_static_end_ratio_serial_over_stream")), "engine terminal static ratio is finite/positive")
		_check(String(comparison.get("engine_static_end_ratio_interpretation", "")) == "DIAGNOSTIC_ONLY_PROCESS_LOCAL", "allocator ratio interpretation remains diagnostic-only")
		_check(bool(comparison.get("working_set_bound_claim", false)), "structural working-set bound claim is allowed")
		_check(not bool(comparison.get("memory_reduction_claim", true)), "memory reduction claim remains forbidden")
		_check(not bool(comparison.get("optimization_claim", true)), "optimization claim remains forbidden")
		print("PERF2.2 PROFILE chunk=%d parent_reduction=%.6f candidate_reduction=%.6f proxy_reduction=%.6f engine_static_ratio=%.6f" % [
			chunk_size,
			float(comparison.get("parent_record_reduction_factor_serial_over_stream", 0.0)),
			float(comparison.get("candidate_record_reduction_factor_serial_over_stream", 0.0)),
			float(comparison.get("record_proxy_reduction_factor_serial_over_stream", 0.0)),
			float(comparison.get("engine_static_end_ratio_serial_over_stream", 0.0)),
		])
	_check(exact_pairs == 9, "PERF2.2 preserves 9/9 source canonical pairs")
	print("PERF2.2 source exact canonical pairs: %d/9" % exact_pairs)

	var report_path := "res://artifacts/perf2/perf2-2-working-set-memory-r1.json"
	_check(profiler.write_report(report, report_path), "machine-local PERF2.2 report writes successfully")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	_check(parsed is Dictionary, "written PERF2.2 report parses as JSON")
	if parsed is Dictionary:
		var parsed_report: Dictionary = Dictionary(parsed)
		_check(String(parsed_report.get("report_hash", "")) == String(report.get("report_hash", "")), "written PERF2.2 artifact preserves stored report hash")
		_check(profiler.report_hash(parsed_report) == String(report.get("report_hash", "")), "PERF2.2 report hash survives JSON numeric round-trip")
		_check(profiler.validate_report(parsed_report), "written PERF2.2 artifact round-trips through full validation")

		var tampered: Dictionary = parsed_report.duplicate(true)
		var tampered_comparisons: Array = Array(tampered["comparisons"])
		var first: Dictionary = Dictionary(tampered_comparisons[0])
		first["record_proxy_reduction_factor_serial_over_stream"] = float(first["record_proxy_reduction_factor_serial_over_stream"]) + 0.001
		tampered_comparisons[0] = first
		tampered["comparisons"] = tampered_comparisons
		_check(not profiler.validate_report(tampered), "working-set evidence tamper fails closed")

	_source_guards()
	_finish()


func _all_authorities_safe(authorities: Dictionary) -> bool:
	return (
		authorities == Profiler.AUTHORITIES
		and not bool(authorities.get("canonical", true))
		and not bool(authorities.get("world_write", true))
		and not bool(authorities.get("ecology_truth_write", true))
		and not bool(authorities.get("generation_commit", true))
		and bool(authorities.get("measurement_only", false))
		and bool(authorities.get("side_channel_only", false))
	)


func _source_guards() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ecology/perf/eco_evo7_perf22_working_set_memory_profiler_v1.gd")
	var lower := source.to_lower()
	_check(not lower.contains("advance_generations("), "PERF2.2 never advances ecology directly")
	_check(not lower.contains("scripts/ecology/shadow/"), "PERF2.2 has no direct shadow-runtime dependency")
	_check(not lower.contains("set_generation_stream_executor("), "PERF2.2 cannot alter STREAM1 execution")
	_check(not lower.contains("os.get_static_memory"), "PERF2.2 does not invent a second allocator probe")
	_check(source.contains("Perf21.validate_report") or source.contains("perf21.validate_report"), "PERF2.2 consumes validated PERF2.1 evidence")
	_check(source.contains('"PROCESS_LIFETIME_HIGH_WATERMARK_DIAGNOSTIC"'), "PERF2.2 explicitly labels process peak semantics")
	_check(source.contains('"memory_reduction_claim_allowed": false'), "PERF2.2 forbids memory-reduction claims")
	var perf21_source := FileAccess.get_file_as_string("res://scripts/ecology/perf/eco_evo7_perf21_generation_profiler_v1.gd")
	_check(perf21_source.contains('const REVISION := "ECO.EVO7-PERF2.1-R2"'), "accepted PERF2.1 implementation remains at R2")


func _summary_valid(summary: Dictionary) -> bool:
	if summary.size() != 6:
		return false
	if int(summary.get("count", 0)) <= 0:
		return false
	for key in ["p50", "p95", "mean", "min", "max"]:
		if not _finite_nonnegative(summary.get(key)):
			return false
	return (
		float(summary.get("min", 0.0)) <= float(summary.get("p50", 0.0))
		and float(summary.get("p50", 0.0)) <= float(summary.get("p95", 0.0))
		and float(summary.get("p95", 0.0)) <= float(summary.get("max", 0.0)) + 1e-9
	)


func _finite_nonnegative(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0


func _finite_positive(value) -> bool:
	return _finite_nonnegative(value) and float(value) > 0.0


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


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % label)
		return
	failures.append(label)
	push_error("PERF2.2 CHECK FAIL: %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 PERF2.2 Working-set / Memory R1: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("PERF2.2 FAIL: %s" % failure)
	print("ECO.EVO7 PERF2.2 Working-set / Memory R1: FAIL (%d/%d assertions failed)" % [failures.size(), assertions])
	quit(1)
