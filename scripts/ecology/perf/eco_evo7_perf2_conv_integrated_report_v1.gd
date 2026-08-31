extends RefCounted

## ECO.EVO7 PERF2.CONV R1 — integrated STREAM1 + VIS4 load report.
##
## This is measurement-only evidence. Timings never enter ecology identity.

const SCHEMA := "distributed_world_simulator.ecology.evo7_perf2_conv.integrated_report.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-PERF2.CONV-R1"

const WARMUP_GENERATIONS := 2
const MEASURED_GENERATIONS := 12
const REPETITIONS := 3
const TOTAL_SAMPLES := MEASURED_GENERATIONS * REPETITIONS

const MAX_P50_COMBINED_TO_SIM_RATIO := 2.50
const MAX_P95_COMBINED_TO_SIM_RATIO := 4.00
const MAX_SINGLE_COMBINED_GENERATION_MS := 5000.0
const MAX_CACHE_ENTRIES_PER_RECORD := 5
const MIN_FOREGROUND_FRAMES_PER_GENERATION := 1

const AUTHORITIES := {
	"canonical": false,
	"measurement_only": true,
	"side_channel_only": true,
	"ecology_truth_write": false,
	"biology_write": false,
	"presentation_truth_write": false,
	"persistence_write": false,
	"network_write": false,
}


static func build(samples: Array, repetition_summaries: Array, target: Dictionary) -> Dictionary:
	if samples.size() != TOTAL_SAMPLES or repetition_summaries.size() != REPETITIONS:
		return {}
	if String(target.get("head", "")).length() != 40 or String(target.get("tree", "")).length() != 40:
		return {}

	var typed_samples: Array[Dictionary] = []
	var ratios: Array[float] = []
	var combined_values: Array[float] = []
	var simulation_values: Array[float] = []
	var overhead_values: Array[float] = []
	var max_cache_entries := 0
	var max_records := 0
	var min_foreground_frames := 1 << 30

	for value in samples:
		if not value is Dictionary:
			return {}
		var sample: Dictionary = value
		if not _validate_sample(sample):
			return {}
		typed_samples.append(sample.duplicate(true))
		ratios.append(float(sample["combined_to_sim_ratio"]))
		combined_values.append(float(sample["combined_ms"]))
		simulation_values.append(float(sample["simulation_ms"]))
		overhead_values.append(float(sample["presentation_overhead_ms"]))
		max_cache_entries = maxi(max_cache_entries, int(sample["cache_entries"]))
		max_records = maxi(max_records, int(sample["record_count"]))
		min_foreground_frames = mini(min_foreground_frames, int(sample["foreground_frames"]))

	var p50_ratio := _percentile(ratios, 0.50)
	var p95_ratio := _percentile(ratios, 0.95)
	var p50_combined := _percentile(combined_values, 0.50)
	var p95_combined := _percentile(combined_values, 0.95)
	var p50_sim := _percentile(simulation_values, 0.50)
	var p95_sim := _percentile(simulation_values, 0.95)
	var p50_overhead := _percentile(overhead_values, 0.50)
	var p95_overhead := _percentile(overhead_values, 0.95)
	var max_combined := _max_value(combined_values)

	var stream_contract_green := true
	var cache_bounded_green := true
	var source_seals_green := true
	var single_flight_green := true
	var foreground_progress_green := true
	var eviction_observed := false

	for value in repetition_summaries:
		if not value is Dictionary:
			return {}
		var summary: Dictionary = value
		if not _validate_repetition_summary(summary):
			return {}
		stream_contract_green = stream_contract_green and bool(summary["optimized_stream_contract"])
		cache_bounded_green = cache_bounded_green and bool(summary["cache_bounded"])
		source_seals_green = source_seals_green and bool(summary["source_seals"])
		single_flight_green = single_flight_green and bool(summary["single_flight"])
		foreground_progress_green = foreground_progress_green and bool(summary["foreground_progress"])
		eviction_observed = eviction_observed or int(summary.get("cache_eviction_count", 0)) > 0

	var timing_budget_green := (
		p50_ratio <= MAX_P50_COMBINED_TO_SIM_RATIO
		and p95_ratio <= MAX_P95_COMBINED_TO_SIM_RATIO
		and max_combined <= MAX_SINGLE_COMBINED_GENERATION_MS
	)

	var claims := {
		"perf2_5_vis4_materialization_profiling": true,
		"perf2_6_ph5_lod_cache_bounded": cache_bounded_green and eviction_observed,
		"perf2_7_stream1_vis4_integrated_load": (
			stream_contract_green
			and source_seals_green
			and single_flight_green
			and foreground_progress_green
		),
		"perf2_8_play1_performance_acceptance": (
			timing_budget_green
			and stream_contract_green
			and cache_bounded_green
			and eviction_observed
			and source_seals_green
			and single_flight_green
			and foreground_progress_green
		),
	}

	var report := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"mode": "STREAM1_OPTIMIZED_PLUS_VIS4",
		"target": target.duplicate(true),
		"authorities": AUTHORITIES.duplicate(true),
		"policy": {
			"warmup_generations": WARMUP_GENERATIONS,
			"measured_generations": MEASURED_GENERATIONS,
			"repetitions": REPETITIONS,
			"total_samples": TOTAL_SAMPLES,
			"max_p50_combined_to_sim_ratio": MAX_P50_COMBINED_TO_SIM_RATIO,
			"max_p95_combined_to_sim_ratio": MAX_P95_COMBINED_TO_SIM_RATIO,
			"max_single_combined_generation_ms": MAX_SINGLE_COMBINED_GENERATION_MS,
			"max_cache_entries_per_record": MAX_CACHE_ENTRIES_PER_RECORD,
			"min_foreground_frames_per_generation": MIN_FOREGROUND_FRAMES_PER_GENERATION,
			"timings_noncanonical": true,
			"same_run_simulation_baseline": true,
		},
		"samples": typed_samples,
		"repetition_summaries": repetition_summaries.duplicate(true),
		"summary": {
			"p50_combined_to_sim_ratio": p50_ratio,
			"p95_combined_to_sim_ratio": p95_ratio,
			"p50_combined_ms": p50_combined,
			"p95_combined_ms": p95_combined,
			"p50_simulation_ms": p50_sim,
			"p95_simulation_ms": p95_sim,
			"p50_presentation_overhead_ms": p50_overhead,
			"p95_presentation_overhead_ms": p95_overhead,
			"max_combined_ms": max_combined,
			"max_cache_entries": max_cache_entries,
			"max_record_count": max_records,
			"min_foreground_frames": min_foreground_frames,
			"stream_contract_green": stream_contract_green,
			"cache_bounded_green": cache_bounded_green,
			"cache_eviction_observed": eviction_observed,
			"source_seals_green": source_seals_green,
			"single_flight_green": single_flight_green,
			"foreground_progress_green": foreground_progress_green,
			"timing_budget_green": timing_budget_green,
		},
		"claims": claims,
	}
	report["report_hash"] = compute_hash(report)
	return report if validate(report) else {}


static func validate(report: Dictionary) -> bool:
	if String(report.get("schema", "")) != SCHEMA:
		return false
	if String(report.get("version", "")) != VERSION or String(report.get("revision", "")) != REVISION:
		return false
	if String(report.get("mode", "")) != "STREAM1_OPTIMIZED_PLUS_VIS4":
		return false
	if Dictionary(report.get("authorities", {})) != AUTHORITIES:
		return false

	var policy_value = report.get("policy")
	if not policy_value is Dictionary:
		return false
	var policy: Dictionary = policy_value
	if int(policy.get("warmup_generations", -1)) != WARMUP_GENERATIONS:
		return false
	if int(policy.get("measured_generations", -1)) != MEASURED_GENERATIONS:
		return false
	if int(policy.get("repetitions", -1)) != REPETITIONS:
		return false
	if int(policy.get("total_samples", -1)) != TOTAL_SAMPLES:
		return false
	if not is_equal_approx(float(policy.get("max_p50_combined_to_sim_ratio", NAN)), MAX_P50_COMBINED_TO_SIM_RATIO):
		return false
	if not is_equal_approx(float(policy.get("max_p95_combined_to_sim_ratio", NAN)), MAX_P95_COMBINED_TO_SIM_RATIO):
		return false
	if not is_equal_approx(float(policy.get("max_single_combined_generation_ms", NAN)), MAX_SINGLE_COMBINED_GENERATION_MS):
		return false
	if int(policy.get("max_cache_entries_per_record", -1)) != MAX_CACHE_ENTRIES_PER_RECORD:
		return false
	if int(policy.get("min_foreground_frames_per_generation", -1)) != MIN_FOREGROUND_FRAMES_PER_GENERATION:
		return false
	if not bool(policy.get("timings_noncanonical", false)) or not bool(policy.get("same_run_simulation_baseline", false)):
		return false

	var samples_value = report.get("samples")
	var reps_value = report.get("repetition_summaries")
	if not samples_value is Array or not reps_value is Array:
		return false
	var samples: Array = samples_value
	var reps: Array = reps_value
	if samples.size() != TOTAL_SAMPLES or reps.size() != REPETITIONS:
		return false
	for sample in samples:
		if not sample is Dictionary or not _validate_sample(sample):
			return false
	for summary in reps:
		if not summary is Dictionary or not _validate_repetition_summary(summary):
			return false

	var summary_value = report.get("summary")
	if not summary_value is Dictionary:
		return false
	var summary: Dictionary = summary_value
	for key in [
		"p50_combined_to_sim_ratio",
		"p95_combined_to_sim_ratio",
		"p50_combined_ms",
		"p95_combined_ms",
		"p50_simulation_ms",
		"p95_simulation_ms",
		"p50_presentation_overhead_ms",
		"p95_presentation_overhead_ms",
		"max_combined_ms",
	]:
		var number := float(summary.get(key, NAN))
		if not is_finite(number) or number < 0.0:
			return false

	var claims_value = report.get("claims")
	if not claims_value is Dictionary:
		return false
	var claims: Dictionary = claims_value
	for key in [
		"perf2_5_vis4_materialization_profiling",
		"perf2_6_ph5_lod_cache_bounded",
		"perf2_7_stream1_vis4_integrated_load",
		"perf2_8_play1_performance_acceptance",
	]:
		if typeof(claims.get(key)) != TYPE_BOOL:
			return false

	if bool(claims["perf2_8_play1_performance_acceptance"]):
		if not bool(summary.get("timing_budget_green", false)):
			return false
		if not bool(summary.get("stream_contract_green", false)):
			return false
		if not bool(summary.get("cache_bounded_green", false)):
			return false
		if not bool(summary.get("cache_eviction_observed", false)):
			return false
		if not bool(summary.get("source_seals_green", false)):
			return false
		if not bool(summary.get("single_flight_green", false)):
			return false
		if not bool(summary.get("foreground_progress_green", false)):
			return false

	return String(report.get("report_hash", "")) == compute_hash(report)


static func compute_hash(report: Dictionary) -> String:
	var parts := PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		String(Dictionary(report.get("target", {})).get("head", "")),
		String(Dictionary(report.get("target", {})).get("tree", "")),
	])

	for value in Array(report.get("samples", [])):
		if value is Dictionary:
			var sample: Dictionary = value
			parts.append("|".join(PackedStringArray([
				str(int(sample.get("repetition", -1))),
				str(int(sample.get("measured_index", -1))),
				str(int(sample.get("generation", -1))),
				String(sample.get("ecology_state_hash", "")),
				String(sample.get("presentation_source_hash", "")),
				_stable_float(float(sample.get("simulation_ms", 0.0))),
				_stable_float(float(sample.get("combined_ms", 0.0))),
				_stable_float(float(sample.get("combined_to_sim_ratio", 0.0))),
				str(int(sample.get("foreground_frames", 0))),
				str(int(sample.get("record_count", 0))),
				str(int(sample.get("cache_entries", 0))),
				str(int(sample.get("stream_calls", 0))),
				str(int(sample.get("optimized_generation_calls", 0))),
			])))

	for value in Array(report.get("repetition_summaries", [])):
		if value is Dictionary:
			var rep: Dictionary = value
			parts.append("|".join(PackedStringArray([
				str(int(rep.get("repetition", -1))),
				String(rep.get("final_ecology_state_hash", "")),
				str(int(rep.get("stream_calls", 0))),
				str(int(rep.get("chunks_processed", 0))),
				str(int(rep.get("cache_entries", 0))),
				str(int(rep.get("cache_eviction_count", 0))),
			])))

	var summary: Dictionary = Dictionary(report.get("summary", {}))
	for key in [
		"p50_combined_to_sim_ratio",
		"p95_combined_to_sim_ratio",
		"p50_combined_ms",
		"p95_combined_ms",
		"p50_presentation_overhead_ms",
		"p95_presentation_overhead_ms",
	]:
		parts.append("%s=%s" % [key, _stable_float(float(summary.get(key, 0.0)))])

	var claims: Dictionary = Dictionary(report.get("claims", {}))
	var claim_keys: Array = claims.keys()
	claim_keys.sort()
	for key in claim_keys:
		parts.append("%s=%s" % [String(key), str(bool(claims[key]))])

	return "
".join(parts).sha256_text()


static func _validate_sample(sample: Dictionary) -> bool:
	for key in [
		"repetition",
		"measured_index",
		"generation",
		"foreground_frames",
		"record_count",
		"cache_entries",
		"cache_lookup_entries",
		"stream_calls",
		"optimized_generation_calls",
		"max_parent_chunk_seen",
		"max_candidate_chunk_seen",
	]:
		if not _is_integral_number(sample.get(key)) or int(sample.get(key)) < 0:
			return false
	for key in ["simulation_ms", "combined_ms", "presentation_overhead_ms", "combined_to_sim_ratio"]:
		var number := float(sample.get(key, NAN))
		if not is_finite(number) or number < 0.0:
			return false
	if float(sample.get("simulation_ms", 0.0)) <= 0.0 or float(sample.get("combined_ms", 0.0)) <= 0.0:
		return false
	if float(sample.get("combined_to_sim_ratio", 0.0)) <= 0.0:
		return false
	if int(sample.get("foreground_frames", 0)) < MIN_FOREGROUND_FRAMES_PER_GENERATION:
		return false
	if String(sample.get("ecology_state_hash", "")).length() != 64:
		return false
	if String(sample.get("presentation_source_hash", "")) != String(sample.get("ecology_state_hash", "")):
		return false
	if int(sample.get("record_count", 0)) <= 0:
		return false
	if int(sample.get("cache_entries", 0)) > int(sample.get("record_count", 0)) * MAX_CACHE_ENTRIES_PER_RECORD:
		return false
	if int(sample.get("cache_lookup_entries", -1)) != int(sample.get("cache_entries", -2)):
		return false
	if int(sample.get("max_parent_chunk_seen", 0)) > 64:
		return false
	return true


static func _validate_repetition_summary(summary: Dictionary) -> bool:
	if int(summary.get("repetition", -1)) < 0:
		return false
	if String(summary.get("final_ecology_state_hash", "")).length() != 64:
		return false
	for key in [
		"stream_calls",
		"optimized_generation_calls",
		"legacy_generation_calls",
		"chunks_processed",
		"chunk_local_parent_sorts",
		"chunk_local_candidate_sorts",
		"chunk_local_route_sorts",
		"chunk_local_recruitment_sorts",
		"recruitment_context_builds",
		"generation_boundary_sorts",
		"cache_entries",
		"cache_lookup_entries",
		"cache_eviction_count",
		"record_count",
	]:
		if not _is_integral_number(summary.get(key)) or int(summary.get(key)) < 0:
			return false
	for key in [
		"optimized_stream_contract",
		"cache_bounded",
		"source_seals",
		"single_flight",
		"foreground_progress",
	]:
		if typeof(summary.get(key)) != TYPE_BOOL:
			return false
	return true


static func _percentile(values: Array[float], p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	if sorted.size() == 1:
		return float(sorted[0])
	var position := clampf(p, 0.0, 1.0) * float(sorted.size() - 1)
	var lower := int(floor(position))
	var upper := int(ceil(position))
	if lower == upper:
		return float(sorted[lower])
	var weight := position - float(lower)
	return lerpf(float(sorted[lower]), float(sorted[upper]), weight)


static func _max_value(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result


static func _stable_float(value: float) -> String:
	return "%.9f" % value


static func _is_integral_number(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number)
