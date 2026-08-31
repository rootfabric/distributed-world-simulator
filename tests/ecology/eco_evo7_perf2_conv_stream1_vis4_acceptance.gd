extends SceneTree

const Playground = preload(
	"res://scripts/labs/ecology/eco_evo7_play0_live_planet_playground.gd"
)
const Composition = preload(
	"res://scripts/ecology/perf/eco_evo7_perf2_conv_play0_stream1_vis4_composition_v1.gd"
)
const Report = preload(
	"res://scripts/ecology/perf/eco_evo7_perf2_conv_integrated_report_v1.gd"
)

const ARTIFACT_PATH := "res://artifacts/perf2/perf2-conv-stream1-vis4-r1.json"

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _run() -> void:
	_controlled_contract_checks()

	var samples: Array = []
	var repetition_summaries: Array = []
	var final_hashes: Array[String] = []

	for repetition in range(Report.REPETITIONS):
		var playground = Playground.new()
		playground.auto_initialize = false
		root.add_child(playground)
		await process_frame
		await process_frame

		_check(playground.initialize_runtime(), "PERF2.CONV repetition %d PLAY0 initializes" % repetition)
		if not playground.ready_success:
			playground.queue_free()
			await process_frame
			_finish()
			return

		var composition = Composition.new()
		_check(
			composition.setup(playground, {
				"parents_per_chunk": 64,
				"audit_interval": 10,
				"audit_generation_1": true,
			}),
			"PERF2.CONV repetition %d optimized STREAM1 composition installs" % repetition
		)
		if not composition.is_configured():
			playground.queue_free()
			await process_frame
			_finish()
			return

		var contract: Dictionary = composition.get_contract()
		_check(String(contract.get("mode", "")) == Composition.MODE, "PERF2.CONV composition mode exact")
		_check(String(contract.get("pipeline_mode", "")) == "OPTIMIZED_GENERATION_BOUNDARY_CANONICALIZATION", "PERF2.CONV optimized pipeline exact")
		_check(String(contract.get("accepted_stream1_head", "")) == Composition.ACCEPTED_STREAM1_HEAD, "PERF2.CONV accepted STREAM1 anchor exact")
		_check(String(contract.get("vis4_9_executable_head", "")) == Composition.VIS49_ACCEPTED_EXECUTABLE_HEAD, "PERF2.CONV VIS4.9 executable anchor exact")
		_check(String(contract.get("ancestry_merge_head", "")) == Composition.ANCESTRY_MERGE_HEAD, "PERF2.CONV ancestry merge anchor exact")

		for _warmup in range(Report.WARMUP_GENERATIONS):
			var warmup_result: Dictionary = await _advance_one(playground, false)
			_check(bool(warmup_result.get("success", false)), "PERF2.CONV repetition %d warmup generation completes" % repetition)
			if not bool(warmup_result.get("success", false)):
				playground.queue_free()
				await process_frame
				_finish()
				return

		var source_seals_green := true
		var single_flight_green := true
		var foreground_progress_green := true

		for measured_index in range(Report.MEASURED_GENERATIONS):
			var before_generation := int(playground.get_published_snapshot().get("generation", -1))
			var before_rejections := playground.get_generation_rejections()

			_check(
				playground.request_generation(),
				"PERF2.CONV rep %d measured %d generation starts" % [repetition, measured_index]
			)
			var concurrent_rejected := not playground.request_generation()
			_check(
				concurrent_rejected,
				"PERF2.CONV rep %d measured %d concurrent generation rejected" % [repetition, measured_index]
			)

			var foreground_frames := 0
			var deadline := Time.get_ticks_msec() + 60000
			while playground.is_generation_running() and Time.get_ticks_msec() < deadline:
				foreground_frames += 1
				await process_frame

			var completed := not playground.is_generation_running()
			_check(completed, "PERF2.CONV rep %d measured %d generation completes" % [repetition, measured_index])
			_check(
				foreground_frames >= Report.MIN_FOREGROUND_FRAMES_PER_GENERATION,
				"PERF2.CONV rep %d measured %d foreground frames progress" % [repetition, measured_index]
			)
			_check(
				playground.get_generation_rejections() == before_rejections + 1,
				"PERF2.CONV rep %d measured %d exactly one single-flight rejection" % [repetition, measured_index]
			)
			if not completed:
				playground.queue_free()
				await process_frame
				_finish()
				return

			var after_generation := int(playground.get_published_snapshot().get("generation", -1))
			_check(after_generation == before_generation + 1, "PERF2.CONV generation advances exactly once")

			var integrated: Dictionary = composition.get_integrated_snapshot()
			var integrated_valid := not integrated.is_empty() and composition.validate_integrated_snapshot(integrated)
			_check(integrated_valid, "PERF2.CONV integrated snapshot validates")
			if not integrated_valid:
				playground.queue_free()
				await process_frame
				_finish()
				return

			var workbench = playground.get_workbench()
			var profile: Dictionary = workbench.get_last_generation_profile()
			var simulation_ms := float(profile.get("total_ms", -1.0))
			var combined_ms := playground.get_last_generation_duration_ms()
			var simulation_valid := is_finite(simulation_ms) and simulation_ms > 0.0
			var combined_valid := is_finite(combined_ms) and combined_ms > 0.0
			_check(simulation_valid, "PERF2.CONV simulation timing valid")
			_check(combined_valid, "PERF2.CONV combined timing valid")
			if not simulation_valid or not combined_valid:
				playground.queue_free()
				await process_frame
				_finish()
				return

			var overhead_ms := maxf(0.0, combined_ms - simulation_ms)
			var ratio := combined_ms / simulation_ms

			var perf: Dictionary = Dictionary(integrated.get("vis4_performance", {}))
			var stream: Dictionary = Dictionary(integrated.get("stream_telemetry", {}))
			var record_count := int(perf.get("record_count", 0))
			var cache_entries := int(perf.get("materialization_cache_entries", -1))
			var cache_lookup_entries := int(perf.get("materialization_cache_lookup_entries", -1))
			var ecology_hash := String(integrated.get("ecology_state_hash", ""))
			var presentation_hash := String(integrated.get("presentation_source_hash", ""))

			var source_seal_ok := (
				ecology_hash.length() == 64
				and presentation_hash == ecology_hash
				and String(perf.get("source_ecology_hash", "")) == ecology_hash
				and String(playground.get_published_morphology_descriptors().get("source_ecology_state_hash", "")) == ecology_hash
			)
			source_seals_green = source_seals_green and source_seal_ok
			single_flight_green = single_flight_green and concurrent_rejected
			foreground_progress_green = foreground_progress_green and foreground_frames >= Report.MIN_FOREGROUND_FRAMES_PER_GENERATION

			_check(source_seal_ok, "PERF2.CONV ecology/presentation/morphology source seal exact")
			_check(String(stream.get("pipeline_mode", "")) == "OPTIMIZED_GENERATION_BOUNDARY_CANONICALIZATION", "PERF2.CONV measured generation uses optimized STREAM1")
			_check(int(stream.get("legacy_generation_calls", -1)) == 0, "PERF2.CONV legacy STREAM1 path unused")
			_check(int(stream.get("chunk_local_parent_sorts", -1)) == 0, "PERF2.CONV chunk-local parent sorts eliminated")
			_check(int(stream.get("chunk_local_candidate_sorts", -1)) == 0, "PERF2.CONV chunk-local candidate sorts eliminated")
			_check(int(stream.get("chunk_local_route_sorts", -1)) == 0, "PERF2.CONV chunk-local route sorts eliminated")
			_check(int(stream.get("chunk_local_recruitment_sorts", -1)) == 0, "PERF2.CONV chunk-local recruitment sorts eliminated")
			_check(int(stream.get("max_parent_chunk_seen", 0)) <= 64, "PERF2.CONV parent working set bounded to 64")
			_check(record_count > 0, "PERF2.CONV VIS4 live record count positive")
			_check(cache_entries >= 0 and cache_entries <= record_count * Report.MAX_CACHE_ENTRIES_PER_RECORD, "PERF2.CONV PH5 cache bounded by current live records")
			_check(cache_lookup_entries == cache_entries, "PERF2.CONV PH5 cache lookup/materialization entries aligned")
			_check(bool(perf.get("timings_diagnostic_only", false)), "PERF2.CONV VIS4 timings remain diagnostic-only")
			_check(bool(perf.get("fps_observational_only", false)), "PERF2.CONV frame/FPS evidence remains observational-only")

			samples.append({
				"repetition": repetition,
				"measured_index": measured_index,
				"generation": after_generation,
				"ecology_state_hash": ecology_hash,
				"presentation_source_hash": presentation_hash,
				"simulation_ms": simulation_ms,
				"combined_ms": combined_ms,
				"presentation_overhead_ms": overhead_ms,
				"combined_to_sim_ratio": ratio,
				"foreground_frames": foreground_frames,
				"single_flight_rejected": concurrent_rejected,
				"record_count": record_count,
				"cache_entries": cache_entries,
				"cache_lookup_entries": cache_lookup_entries,
				"stream_calls": int(stream.get("stream_calls", 0)),
				"optimized_generation_calls": int(stream.get("optimized_generation_calls", 0)),
				"max_parent_chunk_seen": int(stream.get("max_parent_chunk_seen", 0)),
				"max_candidate_chunk_seen": int(stream.get("max_candidate_chunk_seen", 0)),
			})

		var final_integrated: Dictionary = composition.get_integrated_snapshot()
		var final_stream: Dictionary = composition.get_stream_telemetry()
		var final_perf: Dictionary = Dictionary(final_integrated.get("vis4_performance", {}))
		var expected_calls := Report.WARMUP_GENERATIONS + Report.MEASURED_GENERATIONS

		var optimized_stream_contract := (
			int(final_stream.get("stream_calls", -1)) == expected_calls
			and int(final_stream.get("optimized_generation_calls", -1)) == expected_calls
			and int(final_stream.get("legacy_generation_calls", -1)) == 0
			and int(final_stream.get("chunk_local_parent_sorts", -1)) == 0
			and int(final_stream.get("chunk_local_candidate_sorts", -1)) == 0
			and int(final_stream.get("chunk_local_route_sorts", -1)) == 0
			and int(final_stream.get("chunk_local_recruitment_sorts", -1)) == 0
			and int(final_stream.get("recruitment_context_builds", -1)) == expected_calls
			and int(final_stream.get("generation_boundary_sorts", -1)) == expected_calls * 3
			and int(final_stream.get("max_parent_chunk_seen", 0)) <= 64
		)
		var final_record_count := int(final_perf.get("record_count", 0))
		var final_cache_entries := int(final_perf.get("materialization_cache_entries", -1))
		var final_cache_lookup_entries := int(final_perf.get("materialization_cache_lookup_entries", -1))
		var cache_bounded := (
			final_record_count > 0
			and final_cache_entries >= 0
			and final_cache_entries <= final_record_count * Report.MAX_CACHE_ENTRIES_PER_RECORD
			and final_cache_lookup_entries == final_cache_entries
		)

		_check(optimized_stream_contract, "PERF2.CONV repetition %d optimized STREAM1 operation contract exact" % repetition)
		_check(cache_bounded, "PERF2.CONV repetition %d final PH5 cache bounded" % repetition)
		_check(int(final_perf.get("materialization_cache_eviction_count", 0)) > 0, "PERF2.CONV repetition %d stale PH5 cache entries evicted" % repetition)
		_check(source_seals_green, "PERF2.CONV repetition %d all source seals exact" % repetition)
		_check(single_flight_green, "PERF2.CONV repetition %d single-flight invariant green" % repetition)
		_check(foreground_progress_green, "PERF2.CONV repetition %d foreground progress invariant green" % repetition)

		var final_hash := String(final_integrated.get("ecology_state_hash", ""))
		final_hashes.append(final_hash)
		repetition_summaries.append({
			"repetition": repetition,
			"final_ecology_state_hash": final_hash,
			"stream_calls": int(final_stream.get("stream_calls", 0)),
			"optimized_generation_calls": int(final_stream.get("optimized_generation_calls", 0)),
			"legacy_generation_calls": int(final_stream.get("legacy_generation_calls", 0)),
			"chunks_processed": int(final_stream.get("chunks_processed", 0)),
			"chunk_local_parent_sorts": int(final_stream.get("chunk_local_parent_sorts", 0)),
			"chunk_local_candidate_sorts": int(final_stream.get("chunk_local_candidate_sorts", 0)),
			"chunk_local_route_sorts": int(final_stream.get("chunk_local_route_sorts", 0)),
			"chunk_local_recruitment_sorts": int(final_stream.get("chunk_local_recruitment_sorts", 0)),
			"recruitment_context_builds": int(final_stream.get("recruitment_context_builds", 0)),
			"generation_boundary_sorts": int(final_stream.get("generation_boundary_sorts", 0)),
			"cache_entries": final_cache_entries,
			"cache_lookup_entries": final_cache_lookup_entries,
			"cache_eviction_count": int(final_perf.get("materialization_cache_eviction_count", 0)),
			"record_count": final_record_count,
			"optimized_stream_contract": optimized_stream_contract,
			"cache_bounded": cache_bounded,
			"source_seals": source_seals_green,
			"single_flight": single_flight_green,
			"foreground_progress": foreground_progress_green,
		})

		playground.queue_free()
		await process_frame
		await process_frame

	_check(final_hashes.size() == Report.REPETITIONS, "PERF2.CONV captured all repetition final hashes")
	if final_hashes.size() == Report.REPETITIONS:
		for hash_value in final_hashes:
			_check(hash_value == final_hashes[0], "PERF2.CONV fresh repetitions end at exact same ecology hash")

	var target := {
		"head": OS.get_environment("ECO_PERF2_CONV_TARGET_HEAD"),
		"tree": OS.get_environment("ECO_PERF2_CONV_TARGET_TREE"),
	}
	_check(String(target["head"]).length() == 40, "PERF2.CONV target HEAD supplied by runner")
	_check(String(target["tree"]).length() == 40, "PERF2.CONV target TREE supplied by runner")

	var report: Dictionary = Report.build(samples, repetition_summaries, target)
	_check(not report.is_empty() and Report.validate(report), "PERF2.CONV integrated report validates")
	if report.is_empty():
		_finish()
		return

	var summary: Dictionary = Dictionary(report.get("summary", {}))
	var claims: Dictionary = Dictionary(report.get("claims", {}))
	_check(bool(summary.get("timing_budget_green", false)), "PERF2.CONV combined timing budget GREEN")
	_check(float(summary.get("p50_combined_to_sim_ratio", INF)) <= Report.MAX_P50_COMBINED_TO_SIM_RATIO, "PERF2.CONV p50 combined/simulation ratio within budget")
	_check(float(summary.get("p95_combined_to_sim_ratio", INF)) <= Report.MAX_P95_COMBINED_TO_SIM_RATIO, "PERF2.CONV p95 combined/simulation ratio within budget")
	_check(float(summary.get("max_combined_ms", INF)) <= Report.MAX_SINGLE_COMBINED_GENERATION_MS, "PERF2.CONV no combined generation exceeds hard stall budget")
	_check(bool(summary.get("cache_bounded_green", false)), "PERF2.CONV cache bounded across all repetitions")
	_check(bool(summary.get("cache_eviction_observed", false)), "PERF2.CONV stale-generation cache eviction observed")
	_check(bool(claims.get("perf2_5_vis4_materialization_profiling", false)), "PERF2.5 materialization profiling claim GREEN")
	_check(bool(claims.get("perf2_6_ph5_lod_cache_bounded", false)), "PERF2.6 PH5 LOD/cache claim GREEN")
	_check(bool(claims.get("perf2_7_stream1_vis4_integrated_load", false)), "PERF2.7 integrated load claim GREEN")
	_check(bool(claims.get("perf2_8_play1_performance_acceptance", false)), "PERF2.8 PLAY1 performance acceptance claim GREEN")

	_check(_write_and_revalidate_artifact(report), "PERF2.CONV JSON artifact round-trip validates")
	_tamper_guards(report)
	_source_guard()

	print("PERF2.CONV p50 combined/sim ratio: %.3f" % float(summary.get("p50_combined_to_sim_ratio", 0.0)))
	print("PERF2.CONV p95 combined/sim ratio: %.3f" % float(summary.get("p95_combined_to_sim_ratio", 0.0)))
	print("PERF2.CONV p95 combined generation ms: %.3f" % float(summary.get("p95_combined_ms", 0.0)))
	print("PERF2.CONV p95 presentation overhead ms: %.3f" % float(summary.get("p95_presentation_overhead_ms", 0.0)))
	print("PERF2.CONV max PH5 cache entries: %d" % int(summary.get("max_cache_entries", 0)))
	print("PERF2.CONV report hash: %s" % String(report.get("report_hash", "")))
	print("ECO.EVO7 PERF2.CONV STREAM1 + VIS4 integrated load: PASS")

	_finish()


func _advance_one(playground, measured: bool) -> Dictionary:
	var before_generation := int(playground.get_published_snapshot().get("generation", -1))
	if not playground.request_generation():
		return {"success": false}
	var frames := 0
	var deadline := Time.get_ticks_msec() + 60000
	while playground.is_generation_running() and Time.get_ticks_msec() < deadline:
		frames += 1
		await process_frame
	if playground.is_generation_running():
		return {"success": false}
	var after_generation := int(playground.get_published_snapshot().get("generation", -1))
	return {
		"success": after_generation == before_generation + 1,
		"foreground_frames": frames,
		"measured": measured,
	}


func _controlled_contract_checks() -> void:
	_check(Report.WARMUP_GENERATIONS >= 1, "PERF2.CONV warmup satisfies PERF2.0 minimum")
	_check(Report.MEASURED_GENERATIONS >= 12, "PERF2.CONV measured generations satisfy PERF2.0 minimum")
	_check(Report.REPETITIONS >= 3, "PERF2.CONV repetitions satisfy PERF2.0 minimum")
	_check(Report.MAX_CACHE_ENTRIES_PER_RECORD == 5, "PERF2.CONV cache bound equals PH5 tier count")
	_check(Report.MAX_P50_COMBINED_TO_SIM_RATIO == 2.50, "PERF2.CONV p50 budget frozen")
	_check(Report.MAX_P95_COMBINED_TO_SIM_RATIO == 4.00, "PERF2.CONV p95 budget frozen")
	_check(Composition.DEFAULT_PARENTS_PER_CHUNK == 64, "PERF2.CONV STREAM1 chunk size frozen at 64")


func _write_and_revalidate_artifact(report: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(ARTIFACT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "	"))
	file.close()

	var text_value := FileAccess.get_file_as_string(absolute)
	var parsed = JSON.parse_string(text_value)
	if not parsed is Dictionary:
		return false
	return Report.validate(Dictionary(parsed))


func _tamper_guards(report: Dictionary) -> void:
	var bad_source: Dictionary = report.duplicate(true)
	var bad_samples: Array = Array(bad_source["samples"])
	var first: Dictionary = Dictionary(bad_samples[0]).duplicate(true)
	first["presentation_source_hash"] = "f".repeat(64)
	bad_samples[0] = first
	bad_source["samples"] = bad_samples
	_check(not Report.validate(bad_source), "PERF2.CONV rejects source-seal tamper")

	var bad_cache: Dictionary = report.duplicate(true)
	var cache_samples: Array = Array(bad_cache["samples"])
	var cache_first: Dictionary = Dictionary(cache_samples[0]).duplicate(true)
	cache_first["cache_entries"] = int(cache_first["record_count"]) * Report.MAX_CACHE_ENTRIES_PER_RECORD + 1
	cache_samples[0] = cache_first
	bad_cache["samples"] = cache_samples
	_check(not Report.validate(bad_cache), "PERF2.CONV rejects unbounded-cache tamper")

	var bad_claim: Dictionary = report.duplicate(true)
	var claims: Dictionary = Dictionary(bad_claim["claims"]).duplicate(true)
	claims["perf2_8_play1_performance_acceptance"] = false
	bad_claim["claims"] = claims
	_check(not Report.validate(bad_claim), "PERF2.CONV report hash seals claims")


func _source_guard() -> void:
	var composition_source := FileAccess.get_file_as_string(
		"res://scripts/ecology/perf/eco_evo7_perf2_conv_play0_stream1_vis4_composition_v1.gd"
	).to_lower()
	var report_source := FileAccess.get_file_as_string(
		"res://scripts/ecology/perf/eco_evo7_perf2_conv_integrated_report_v1.gd"
	).to_lower()
	var renderer_source := FileAccess.get_file_as_string(
		"res://scripts/labs/ecology/eco_evo7_vis4_4_play0_ph5_renderer.gd"
	).to_lower()

	_check(composition_source.contains("set_generation_stream_executor"), "PERF2.CONV uses public STREAM1 Workbench seam")
	_check(composition_source.contains("pipeline_optimized"), "PERF2.CONV composition selects optimized STREAM1 pipeline")
	_check(not composition_source.contains("workbench.ecology") and not composition_source.contains(".core."), "PERF2.CONV composition does not tunnel into ecology internals")
	_check(report_source.contains("timings_noncanonical"), "PERF2.CONV timings declared noncanonical")
	_check(report_source.contains("same_run_simulation_baseline"), "PERF2.CONV uses same-run simulation baseline")
	_check(renderer_source.contains("_begin_cache_transaction"), "PERF2.CONV PH5 cache uses snapshot transaction")
	_check(renderer_source.contains("_prune_cache_to_current_generation"), "PERF2.CONV PH5 cache prunes stale generations")
	_check(not composition_source.contains("persistence") or composition_source.contains(""persistence_write": false"), "PERF2.CONV has no persistence authority")
	_check(not composition_source.contains("multiplayer"), "PERF2.CONV has no network execution path")


func _watchdog() -> void:
	var deadline := Time.get_ticks_msec() + 300000
	while Time.get_ticks_msec() < deadline and not _finished:
		await process_frame
	if not _finished:
		push_error("ECO.EVO7 PERF2.CONV watchdog timeout")
		print("ECO.EVO7 PERF2.CONV: FAIL (watchdog timeout)")
		quit(1)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("PERF2.CONV: " + label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if failures.is_empty():
		print("ECO.EVO7 PERF2.CONV: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("FAIL: " + failure)
	print("ECO.EVO7 PERF2.CONV: FAIL (%d/%d)" % [failures.size(), assertions])
	quit(1)
