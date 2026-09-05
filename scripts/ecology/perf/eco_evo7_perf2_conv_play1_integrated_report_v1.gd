extends RefCounted

## PERF2.CONV / PLAY1 integrated report.
## Joins already accepted PERF2.CONV R3 evidence with the exact-closed VIS5.5
## composition lifecycle. All timings here are measurement-only side-channel data.

const SCHEMA := "distributed_world_simulator.ecology.evo7_perf2_conv.play1_integrated_report.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-PERF2.CONV-PLAY1-R1"

const REPETITIONS := 3
const MAX_SINGLE_BOUNDED_OPERATION_MS := 5000.0

const PERF2_CONV_RUNTIME_HEAD := "81a0b3fa60664684b02d8387e4693c5f328dbe28"
const PERF2_CONV_RUNTIME_TREE := "a192950483267dd428baf2d1daa25de915df2370"
const PERF2_CONV_ACCEPTED_CONTROL_HEAD := "b4f73a4073ac16b2a1de535acd64ae16641d4588"
const PERF2_CONV_REPORT_HASH := "1064567c83c1bd023589fdf9e36f8436b9624eeb928e8b7d413b92ce3254c3f6"
const PERF2_CONV_P50_RATIO := 1.517
const PERF2_CONV_P95_RATIO := 1.590
const PERF2_CONV_MAX_COMBINED_MS := 2501.0

const VIS5_5_EXECUTABLE_HEAD := "fb1a7ac21037e02033eae6d7e778ed8757514e19"
const VIS5_5_EXECUTABLE_TREE := "89551693f0cbac555a5026424d36b50cd35b8804"
const VIS5_5_CLOSURE_HEAD := "a73cccb8064fdfb4df266338d3d20e24ac9f082b"
const VIS5_5_SOURCE_SHA256 := "59ec27aa62b159ebeffc3897230406faa62c5d6204019f783318d7d64c91b021"
const VIS5_5_CAPTURE_BUNDLE_HASH := "cff5f4fadd14f056075f39697458ffcd4e427a7473db7f27c922db411218cd98"
const VIS5_5_MANIFEST_SHA256 := "31d533824b8cafbd182b970b13acc4876b8137e8f5540075be49253a221d988d"
const VIS5_5_HANDOFF_HASH := "bc6cc2f5a2301e0832d8ddb53a8145ce83dc83fb0d2313fe1b3cc1e5d49a5df9"

const AUTHORITIES := {
	"canonical": false,
	"measurement_only": true,
	"side_channel_only": true,
	"ecology_truth_write": false,
	"terrain_truth_write": false,
	"presentation_truth_write": false,
	"network_write": false,
	"persistence_write": false,
	"perf_threshold_write": false,
}


static func build(samples: Array, target: Dictionary, immutable_evidence: Dictionary) -> Dictionary:
	if samples.size() != REPETITIONS:
		return {}
	if String(target.get("head", "")).length() != 40 or String(target.get("tree", "")).length() != 40:
		return {}
	if not _validate_immutable_evidence(immutable_evidence):
		return {}

	var init_values: Array[float] = []
	var view_values: Array[float] = []
	var lifecycle_values: Array[float] = []
	var max_operation_ms := 0.0
	var lifecycle_green := true
	var truth_green := true
	var deterministic_source_green := true
	var source_hash := ""
	var composition_hash := ""

	for value in samples:
		if not value is Dictionary:
			return {}
		var sample: Dictionary = value
		if not _validate_sample(sample):
			return {}
		init_values.append(float(sample["initialize_ms"]))
		view_values.append(float(sample["view_sequence_ms"]))
		lifecycle_values.append(float(sample["lifecycle_ms"]))
		max_operation_ms = maxf(max_operation_ms, float(sample["max_bounded_operation_ms"]))
		lifecycle_green = lifecycle_green and bool(sample["lifecycle_green"])
		truth_green = truth_green and bool(sample["truth_green"])
		if source_hash.is_empty():
			source_hash = String(sample["source_ecology_hash"])
			composition_hash = String(sample["composition_hash"])
		else:
			deterministic_source_green = deterministic_source_green and String(sample["source_ecology_hash"]) == source_hash
			deterministic_source_green = deterministic_source_green and String(sample["composition_hash"]) == composition_hash

	var hard_stall_green := max_operation_ms <= MAX_SINGLE_BOUNDED_OPERATION_MS
	var immutable_perf2_green := bool(immutable_evidence.get("perf2_conv_accepted", false))
	var immutable_vis5_green := bool(immutable_evidence.get("vis5_5_closed", false))
	var integrated_green := (
		immutable_perf2_green
		and immutable_vis5_green
		and lifecycle_green
		and truth_green
		and deterministic_source_green
		and hard_stall_green
	)

	var report := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"mode": "ACCEPTED_PERF2_CONV_PLUS_VIS5_5_REAL_LIFECYCLE",
		"target": target.duplicate(true),
		"authorities": AUTHORITIES.duplicate(true),
		"policy": {
			"repetitions": REPETITIONS,
			"max_single_bounded_operation_ms": MAX_SINGLE_BOUNDED_OPERATION_MS,
			"hard_stall_budget_inherited_from_perf2_conv": true,
			"perf2_p50_ratio_budget_unchanged": 2.50,
			"perf2_p95_ratio_budget_unchanged": 4.00,
			"perf2_cache_bound_unchanged": 5,
			"timings_noncanonical": true,
			"fps_observational_only": true,
			"gpu_acceptance_not_inferred_from_llvmpipe": true,
			"accepted_perf2_campaign_not_rerolled": true,
		},
		"immutable_evidence": immutable_evidence.duplicate(true),
		"samples": samples.duplicate(true),
		"summary": {
			"p50_initialize_ms": _percentile(init_values, 0.50),
			"p95_initialize_ms": _percentile(init_values, 0.95),
			"p50_view_sequence_ms": _percentile(view_values, 0.50),
			"p95_view_sequence_ms": _percentile(view_values, 0.95),
			"p50_lifecycle_ms": _percentile(lifecycle_values, 0.50),
			"p95_lifecycle_ms": _percentile(lifecycle_values, 0.95),
			"max_bounded_operation_ms": max_operation_ms,
			"lifecycle_green": lifecycle_green,
			"truth_green": truth_green,
			"deterministic_source_green": deterministic_source_green,
			"hard_stall_green": hard_stall_green,
		},
		"claims": {
			"perf2_conv_immutable_accepted": immutable_perf2_green,
			"vis5_5_immutable_closed": immutable_vis5_green,
			"play1_visual_composition_correctness": lifecycle_green and truth_green and deterministic_source_green,
			"play1_lifecycle_hard_stall_green": hard_stall_green,
			"play1_integrated_acceptance": integrated_green,
		},
	}
	report["report_hash"] = compute_hash(report)
	return report if validate(report) else {}


static func validate(report: Dictionary) -> bool:
	if String(report.get("schema", "")) != SCHEMA or String(report.get("version", "")) != VERSION or String(report.get("revision", "")) != REVISION:
		return false
	if String(report.get("mode", "")) != "ACCEPTED_PERF2_CONV_PLUS_VIS5_5_REAL_LIFECYCLE":
		return false
	if Dictionary(report.get("authorities", {})) != AUTHORITIES:
		return false
	var policy: Dictionary = Dictionary(report.get("policy", {}))
	if int(policy.get("repetitions", -1)) != REPETITIONS:
		return false
	if not is_equal_approx(float(policy.get("max_single_bounded_operation_ms", NAN)), MAX_SINGLE_BOUNDED_OPERATION_MS):
		return false
	if not bool(policy.get("hard_stall_budget_inherited_from_perf2_conv", false)):
		return false
	if not is_equal_approx(float(policy.get("perf2_p50_ratio_budget_unchanged", NAN)), 2.50):
		return false
	if not is_equal_approx(float(policy.get("perf2_p95_ratio_budget_unchanged", NAN)), 4.00):
		return false
	if int(policy.get("perf2_cache_bound_unchanged", -1)) != 5:
		return false
	for key in ["timings_noncanonical", "fps_observational_only", "gpu_acceptance_not_inferred_from_llvmpipe", "accepted_perf2_campaign_not_rerolled"]:
		if not bool(policy.get(key, false)):
			return false
	var immutable_evidence: Dictionary = Dictionary(report.get("immutable_evidence", {}))
	if not _validate_immutable_evidence(immutable_evidence):
		return false
	var samples_value = report.get("samples", [])
	if not samples_value is Array or samples_value.size() != REPETITIONS:
		return false
	var samples: Array = samples_value
	var max_operation_ms := 0.0
	var lifecycle_green := true
	var truth_green := true
	var deterministic_source_green := true
	var source_hash := ""
	var composition_hash := ""
	for sample_value in samples:
		if not sample_value is Dictionary or not _validate_sample(sample_value):
			return false
		var sample: Dictionary = sample_value
		max_operation_ms = maxf(max_operation_ms, float(sample["max_bounded_operation_ms"]))
		lifecycle_green = lifecycle_green and bool(sample["lifecycle_green"])
		truth_green = truth_green and bool(sample["truth_green"])
		if source_hash.is_empty():
			source_hash = String(sample["source_ecology_hash"])
			composition_hash = String(sample["composition_hash"])
		else:
			deterministic_source_green = deterministic_source_green and String(sample["source_ecology_hash"]) == source_hash and String(sample["composition_hash"]) == composition_hash
	var hard_stall_green := max_operation_ms <= MAX_SINGLE_BOUNDED_OPERATION_MS
	var claims: Dictionary = Dictionary(report.get("claims", {}))
	var expected_accept := bool(immutable_evidence["perf2_conv_accepted"]) and bool(immutable_evidence["vis5_5_closed"]) and lifecycle_green and truth_green and deterministic_source_green and hard_stall_green
	if bool(claims.get("perf2_conv_immutable_accepted", false)) != bool(immutable_evidence["perf2_conv_accepted"]):
		return false
	if bool(claims.get("vis5_5_immutable_closed", false)) != bool(immutable_evidence["vis5_5_closed"]):
		return false
	if bool(claims.get("play1_visual_composition_correctness", false)) != (lifecycle_green and truth_green and deterministic_source_green):
		return false
	if bool(claims.get("play1_lifecycle_hard_stall_green", false)) != hard_stall_green:
		return false
	if bool(claims.get("play1_integrated_acceptance", false)) != expected_accept:
		return false
	return String(report.get("report_hash", "")) == compute_hash(report)


static func compute_hash(report: Dictionary) -> String:
	var copy := report.duplicate(true)
	copy.erase("report_hash")
	# Canonicalize through Godot JSON once before hashing. JSON.parse_string()
	# normalizes numeric values (for example int 3 -> float 3.0), so hashing the
	# normalized representation keeps the report identity stable after artifact
	# write/read round-trips without changing any acceptance semantics.
	var normalized = JSON.parse_string(JSON.stringify(copy))
	if not normalized is Dictionary:
		return ""
	return JSON.stringify(normalized).sha256_text()


static func _validate_immutable_evidence(value: Dictionary) -> bool:
	return (
		bool(value.get("perf2_conv_accepted", false))
		and String(value.get("perf2_conv_runtime_head", "")) == PERF2_CONV_RUNTIME_HEAD
		and String(value.get("perf2_conv_runtime_tree", "")) == PERF2_CONV_RUNTIME_TREE
		and String(value.get("perf2_conv_accepted_control_head", "")) == PERF2_CONV_ACCEPTED_CONTROL_HEAD
		and String(value.get("perf2_conv_report_hash", "")) == PERF2_CONV_REPORT_HASH
		and is_equal_approx(float(value.get("perf2_conv_p50_ratio", NAN)), PERF2_CONV_P50_RATIO)
		and is_equal_approx(float(value.get("perf2_conv_p95_ratio", NAN)), PERF2_CONV_P95_RATIO)
		and is_equal_approx(float(value.get("perf2_conv_max_combined_ms", NAN)), PERF2_CONV_MAX_COMBINED_MS)
		and bool(value.get("vis5_5_closed", false))
		and String(value.get("vis5_5_executable_head", "")) == VIS5_5_EXECUTABLE_HEAD
		and String(value.get("vis5_5_executable_tree", "")) == VIS5_5_EXECUTABLE_TREE
		and String(value.get("vis5_5_closure_head", "")) == VIS5_5_CLOSURE_HEAD
		and String(value.get("vis5_5_source_sha256", "")) == VIS5_5_SOURCE_SHA256
		and String(value.get("vis5_5_capture_bundle_hash", "")) == VIS5_5_CAPTURE_BUNDLE_HASH
		and String(value.get("vis5_5_manifest_sha256", "")) == VIS5_5_MANIFEST_SHA256
		and String(value.get("vis5_5_handoff_hash", "")) == VIS5_5_HANDOFF_HASH
	)


static func _validate_sample(sample: Dictionary) -> bool:
	for key in ["initialize_ms", "view_sequence_ms", "lifecycle_ms", "max_bounded_operation_ms"]:
		var v := float(sample.get(key, NAN))
		if not is_finite(v) or v < 0.0:
			return false
	if String(sample.get("source_ecology_hash", "")).length() != 64 or String(sample.get("composition_hash", "")).length() != 64:
		return false
	if not bool(sample.get("lifecycle_green", false)) or not bool(sample.get("truth_green", false)):
		return false
	if bool(sample.get("ecology_identity_drift", true)):
		return false
	if int(sample.get("macro_records", 0)) <= 0 or int(sample.get("ground_cover", 0)) <= 0 or int(sample.get("rocks", 0)) <= 0:
		return false
	if int(sample.get("render_recenter_count", 0)) < 2 or int(sample.get("earth_rebuild_count", 0)) < 2 or int(sample.get("region_roundtrip_count", 0)) < 1:
		return false
	return true


static func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return NAN
	var sorted := values.duplicate()
	sorted.sort()
	if sorted.size() == 1:
		return sorted[0]
	var position := clampf(fraction, 0.0, 1.0) * float(sorted.size() - 1)
	var lower := int(floor(position))
	var upper := int(ceil(position))
	if lower == upper:
		return sorted[lower]
	return lerpf(sorted[lower], sorted[upper], position - float(lower))
