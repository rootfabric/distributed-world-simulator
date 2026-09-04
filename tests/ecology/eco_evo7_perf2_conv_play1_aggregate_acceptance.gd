extends SceneTree

const Report = preload("res://scripts/ecology/perf/eco_evo7_perf2_conv_play1_integrated_report_v1.gd")
const Perf2Report = preload("res://scripts/ecology/perf/eco_evo7_perf2_conv_integrated_report_v1.gd")

const PERF2_ACCEPTANCE_PATH := "res://docs/checkpoints/2026-09-04_ECO_EVO7_PERF2_CONV_R3_ACCEPTED_RU.md"
const VIS55_CLOSURE_PATH := "res://docs/checkpoints/2026-09-04_ECO_EVO7_VIS5_5_VISUAL_EVIDENCE_INTEGRATED_PLAY1_HANDOFF_EXACT_VERIFIED_CLOSED_R1_RU.md"
const VIS55_HANDOFF_CONTRACT_PATH := "res://config/ecology/eco-evo7-vis5-5-play1-handoff.v1.json"
const ARTIFACT_PATH := "res://artifacts/perf2/perf2-conv-play1-integrated-r1.json"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(Report.MAX_SINGLE_BOUNDED_OPERATION_MS == Perf2Report.MAX_SINGLE_COMBINED_GENERATION_MS, "PLAY1 hard-stall ceiling reuses frozen PERF2.CONV 5000ms value")
	_check(Perf2Report.MAX_P50_COMBINED_TO_SIM_RATIO == 2.50, "PLAY1 preserves PERF2.CONV p50 budget")
	_check(Perf2Report.MAX_P95_COMBINED_TO_SIM_RATIO == 4.00, "PLAY1 preserves PERF2.CONV p95 budget")
	_check(Perf2Report.MAX_CACHE_ENTRIES_PER_RECORD == 5, "PLAY1 preserves PERF2.CONV cache bound")

	var immutable := _immutable_evidence()
	_check(not immutable.is_empty(), "PLAY1 immutable accepted evidence resolves")
	var samples := _load_samples()
	_check(samples.size() == Report.REPETITIONS, "PLAY1 has three fresh-process samples")
	if immutable.is_empty() or samples.size() != Report.REPETITIONS:
		_finish()
		return

	var first_source := String(samples[0].get("source_ecology_hash", ""))
	var first_composition := String(samples[0].get("composition_hash", ""))
	for i in range(samples.size()):
		var sample: Dictionary = samples[i]
		_check(int(sample.get("repetition", -1)) == i, "PLAY1 sample %d repetition identity exact" % i)
		_check(bool(sample.get("lifecycle_green", false)), "PLAY1 sample %d lifecycle GREEN" % i)
		_check(bool(sample.get("truth_green", false)), "PLAY1 sample %d truth boundary GREEN" % i)
		_check(not bool(sample.get("ecology_identity_drift", true)), "PLAY1 sample %d ecology identity stable" % i)
		_check(float(sample.get("max_bounded_operation_ms", INF)) <= Report.MAX_SINGLE_BOUNDED_OPERATION_MS, "PLAY1 sample %d atomic hard-stall guard GREEN" % i)
		_check(bool(sample.get("composite_initialize_timing_observational_only", false)), "PLAY1 sample %d composite initialize timing observational only" % i)
		_check(bool(sample.get("composite_lifecycle_timing_observational_only", false)), "PLAY1 sample %d composite lifecycle timing observational only" % i)
		_check(String(sample.get("source_ecology_hash", "")) == first_source, "PLAY1 sample %d deterministic ecology source" % i)
		_check(String(sample.get("composition_hash", "")) == first_composition, "PLAY1 sample %d deterministic composition" % i)

	var target := {
		"head": OS.get_environment("ECO_PLAY1_TARGET_HEAD"),
		"tree": OS.get_environment("ECO_PLAY1_TARGET_TREE"),
	}
	_check(String(target["head"]).length() == 40, "PLAY1 target HEAD supplied")
	_check(String(target["tree"]).length() == 40, "PLAY1 target TREE supplied")

	var report := Report.build(samples, target, immutable)
	_check(not report.is_empty(), "PLAY1 integrated report builds")
	_check(Report.validate(report), "PLAY1 integrated report validates")
	if report.is_empty():
		_finish()
		return
	var summary: Dictionary = report["summary"]
	var claims: Dictionary = report["claims"]
	_check(bool(summary.get("lifecycle_green", false)), "PLAY1 lifecycle summary GREEN")
	_check(bool(summary.get("truth_green", false)), "PLAY1 truth summary GREEN")
	_check(bool(summary.get("deterministic_source_green", false)), "PLAY1 deterministic source summary GREEN")
	_check(bool(summary.get("hard_stall_green", false)), "PLAY1 atomic hard-stall summary GREEN")
	_check(bool(claims.get("perf2_conv_immutable_accepted", false)), "PLAY1 joins immutable accepted PERF2.CONV")
	_check(bool(claims.get("vis5_5_immutable_closed", false)), "PLAY1 joins exact-closed VIS5.5")
	_check(bool(claims.get("play1_visual_composition_correctness", false)), "PLAY1 visual composition correctness GREEN")
	_check(bool(claims.get("play1_lifecycle_hard_stall_green", false)), "PLAY1 lifecycle atomic hard-stall GREEN")
	_check(bool(claims.get("play1_integrated_acceptance", false)), "PLAY1 INTEGRATED ACCEPTANCE TRUE")
	_check(_write_artifact(report), "PLAY1 report artifact round-trip validates")
	_tamper_guards(report)

	print("PLAY1 p50 initialize observation ms: %.3f" % float(summary.get("p50_initialize_ms", 0.0)))
	print("PLAY1 p95 lifecycle observation ms: %.3f" % float(summary.get("p95_lifecycle_ms", 0.0)))
	print("PLAY1 max atomic bounded operation ms: %.3f / %.1f" % [float(summary.get("max_bounded_operation_ms", 0.0)), Report.MAX_SINGLE_BOUNDED_OPERATION_MS])
	print("PLAY1 report hash: %s" % String(report.get("report_hash", "")))
	print("ECO.EVO7 PERF2.CONV / PLAY1 INTEGRATED ACCEPTANCE: PASS")
	_finish()


func _immutable_evidence() -> Dictionary:
	var perf := FileAccess.get_file_as_string(PERF2_ACCEPTANCE_PATH)
	var vis := FileAccess.get_file_as_string(VIS55_CLOSURE_PATH)
	var handoff := FileAccess.get_file_as_string(VIS55_HANDOFF_CONTRACT_PATH)
	if perf.is_empty() or vis.is_empty() or handoff.is_empty():
		return {}
	for token in [Report.PERF2_CONV_RUNTIME_HEAD, Report.PERF2_CONV_RUNTIME_TREE, Report.PERF2_CONV_ACCEPTED_CONTROL_HEAD, Report.PERF2_CONV_REPORT_HASH, "1.517", "1.590", "2501.0"]:
		if not perf.contains(token):
			return {}
	for token in [Report.VIS5_5_EXECUTABLE_HEAD, Report.VIS5_5_EXECUTABLE_TREE, Report.VIS5_5_SOURCE_SHA256, Report.VIS5_5_CAPTURE_BUNDLE_HASH, Report.VIS5_5_MANIFEST_SHA256, Report.VIS5_5_HANDOFF_HASH]:
		if not vis.contains(token):
			return {}
	if not handoff.contains("VIS5.5 GREEN + PERF2.CONV GREEN -> PLAY1 integrated acceptance"):
		return {}
	return {
		"perf2_conv_accepted": true,
		"perf2_conv_runtime_head": Report.PERF2_CONV_RUNTIME_HEAD,
		"perf2_conv_runtime_tree": Report.PERF2_CONV_RUNTIME_TREE,
		"perf2_conv_accepted_control_head": Report.PERF2_CONV_ACCEPTED_CONTROL_HEAD,
		"perf2_conv_report_hash": Report.PERF2_CONV_REPORT_HASH,
		"perf2_conv_p50_ratio": Report.PERF2_CONV_P50_RATIO,
		"perf2_conv_p95_ratio": Report.PERF2_CONV_P95_RATIO,
		"perf2_conv_max_combined_ms": Report.PERF2_CONV_MAX_COMBINED_MS,
		"vis5_5_closed": true,
		"vis5_5_executable_head": Report.VIS5_5_EXECUTABLE_HEAD,
		"vis5_5_executable_tree": Report.VIS5_5_EXECUTABLE_TREE,
		"vis5_5_closure_head": Report.VIS5_5_CLOSURE_HEAD,
		"vis5_5_source_sha256": Report.VIS5_5_SOURCE_SHA256,
		"vis5_5_capture_bundle_hash": Report.VIS5_5_CAPTURE_BUNDLE_HASH,
		"vis5_5_manifest_sha256": Report.VIS5_5_MANIFEST_SHA256,
		"vis5_5_handoff_hash": Report.VIS5_5_HANDOFF_HASH,
	}


func _load_samples() -> Array:
	var directory := OS.get_environment("ECO_PLAY1_SAMPLE_DIR")
	if directory.is_empty():
		return []
	var result: Array = []
	for i in range(Report.REPETITIONS):
		var path := directory.path_join("sample-%d.json" % i)
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			return []
		result.append(parsed)
	return result


func _write_artifact(report: Dictionary) -> bool:
	var path := ProjectSettings.globalize_path(ARTIFACT_PATH)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed is Dictionary and Report.validate(parsed)


func _tamper_guards(report: Dictionary) -> void:
	var bad_perf := report.duplicate(true)
	var i1: Dictionary = bad_perf["immutable_evidence"].duplicate(true)
	i1["perf2_conv_report_hash"] = "f".repeat(64)
	bad_perf["immutable_evidence"] = i1
	_check(not Report.validate(bad_perf), "PLAY1 rejects PERF2.CONV evidence tamper")
	var bad_vis := report.duplicate(true)
	var i2: Dictionary = bad_vis["immutable_evidence"].duplicate(true)
	i2["vis5_5_handoff_hash"] = "0".repeat(64)
	bad_vis["immutable_evidence"] = i2
	_check(not Report.validate(bad_vis), "PLAY1 rejects VIS5.5 evidence tamper")
	var bad_claim := report.duplicate(true)
	var c: Dictionary = bad_claim["claims"].duplicate(true)
	c["play1_integrated_acceptance"] = false
	bad_claim["claims"] = c
	_check(not Report.validate(bad_claim), "PLAY1 rejects final claim tamper")


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
		push_error("FAIL: %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 PERF2.CONV / PLAY1 AGGREGATE: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("ECO.EVO7 PERF2.CONV / PLAY1 AGGREGATE: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
