extends SceneTree

const Source = preload("res://scripts/research/fabric_bake0/complex3_streaming_canonical_structure_v1.gd")
const Life = preload("res://scripts/research/fabric_bake0/r5_indexed_sparse_damage_lifecycle_v1.gd")
const RangeIndex = preload("res://scripts/research/fabric_bake0/r5_range_aggregate_index_v1.gd")
const Ownership = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const Measure = preload("res://scripts/research/fabric_bake0/r5_measurement_harness_v1.gd")
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const ALLOWED_COUNTS := [5000, 20000, 100000]
const BOUNDARY_EXECUTIONS_PER_PHASE := 64

var checks := 0
var failed := false

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("R5.1-SCALE: " + label + " " + JSON.stringify(details))

func fingerprint(run: Object) -> Dictionary:
	var s: Dictionary = run.status()
	return {
		"mode": s.mode,
		"transition_count": s.transition_count,
		"transition_hash": s.transition_hash,
		"active_full_parts": s.active_full_parts,
		"active_reduced_bodies": s.active_reduced_bodies,
		"applied_events": s.applied_events,
		"work": s.work,
		"source_checksum": s.source_checksum,
	}

func max_matrix_error(a: Array, b: Array) -> float:
	var e := 0.0
	for i in range(3):
		for j in range(3):
			e = maxf(e, absf(float(a[i][j]) - float(b[i][j])))
	return e

func max_matrix_abs(a: Array) -> float:
	var m := 0.0
	for i in range(3):
		for j in range(3):
			m = maxf(m, absf(float(a[i][j])))
	return m

func boundary_hot_loop(run: Object, subject: Dictionary, count: int) -> Dictionary:
	var mode := ""
	for index in range(count):
		var result: Dictionary = run.execute_boundary(subject)
		if not result.success:
			return U.failure("R5_1_BOUNDARY_EXECUTION_FAILED", {"index": index, "result": result})
		mode = str(result.details.mode)
	return U.success({"calls": count, "mode": mode})

func begin_stage(m: Object, name: String) -> void:
	var r: Dictionary = m.begin_stage(name)
	check(r.success, "measurement begin " + name, r)

func end_stage(m: Object, name: String) -> void:
	var r: Dictionary = m.end_stage(name)
	check(r.success, "measurement end " + name, r)

func _initialize() -> void:
	var count := 5000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			count = int(arg.get_slice("=", 1))
	check(ALLOWED_COUNTS.has(count), "authorized scale", {"count": count})
	if failed:
		_finish_failed(count)
		return

	var m = Measure.new("R5.1-SCALE-%06d-R1" % count)
	check(m.sample("initial").success, "initial measurement sample")

	begin_stage(m, "source_create_with_expanded_digests")
	var base := Source.create_subject(count, false)
	end_stage(m, "source_create_with_expanded_digests")
	check(base.success, "base canonical source", base)
	if not base.success:
		_finish_failed(count)
		return
	var canonical_before := U.canonical_hash(base)

	begin_stage(m, "source_full_rehash_validation")
	var rehashed := Source.validate_subject(base, true)
	end_stage(m, "source_full_rehash_validation")
	check(rehashed.success, "full canonical rehash validation", rehashed)

	begin_stage(m, "parent_aggregate_compile")
	var parent := Source.aggregate_span(base.spec, 0, count)
	end_stage(m, "parent_aggregate_compile")
	check(parent.success and int(parent.details.parts_scanned) == count, "parent aggregate scans N", parent)
	if not parent.success:
		_finish_failed(count)
		return

	var state := Source.reference_state()
	var run := Life.new()
	begin_stage(m, "bake_start")
	var started := run.start_baked(base, indexed_parent.details.descriptor, state)
	end_stage(m, "bake_start")
	check(started.success, "start certified bake", started)
	check(run.execute_boundary(base).success, "initial bake executable")
	var initial := run.status()
	check(initial.active_full_parts == 0 and initial.active_reduced_bodies == 1, "initial one baked body", initial)
	check(Ownership.validate(initial.ownership).success, "initial ownership")

	begin_stage(m, "baked_boundary_hot_loop_before")
	var hot_before := boundary_hot_loop(run, base, BOUNDARY_EXECUTIONS_PER_PHASE)
	end_stage(m, "baked_boundary_hot_loop_before")
	check(hot_before.success, "baked boundary hot loop before mutation", hot_before)

	begin_stage(m, "local_unbake_20")
	var local := run.local_unbake(1, Life.IMPACT_LOAD)
	end_stage(m, "local_unbake_20")
	check(local.success, "certified local unbake", local)
	if not local.success:
		_finish_failed(count)
		return
	var local_status := run.status()
	check(local_status.active_full_parts == Source.REGION_SIZE, "FULL peak stays one 20-part region", local_status)
	check(local_status.active_reduced_bodies == 2, "two residual reduced bodies", local_status)
	check(local_status.work.local_reconstructed_parts == Source.REGION_SIZE, "only 20 parts reconstructed", local_status.work)
	check(local_status.work.global_physical_rebuilds == 0, "no global physical rebuild during local event", local_status.work)
	check(float(local.details.continuity.boundary_error) < 1.0e-8, "local boundary continuity", local.details.continuity)
	check(Ownership.validate(local_status.ownership).success, "local ownership")
	check(m.sample("local_full").success, "local FULL measurement sample")

	begin_stage(m, "local_capsule_capture")
	var local_capsule := run.capture_capsule()
	end_stage(m, "local_capsule_capture")
	check(local_capsule.success, "capture local capsule", local_capsule)
	var local_fingerprint := U.canonical_hash(fingerprint(run))
	var restarted := Life.new()
	begin_stage(m, "local_capsule_restore")
	var local_restore := restarted.restore_capsule(base, local_capsule.details.capsule)
	end_stage(m, "local_capsule_restore")
	check(local_restore.success, "restore local capsule", local_restore)
	check(U.canonical_hash(fingerprint(restarted)) == local_fingerprint, "local restore exact")
	run = restarted

	begin_stage(m, "canonical_successor_create")
	var successor := Source.create_subject(count, true)
	end_stage(m, "canonical_successor_create")
	check(successor.success and Source.is_successor(base, successor), "canonical successor", successor)

	var event_id := "topology-event/r5-1-%06d-break" % count
	begin_stage(m, "canonical_mutation_fence")
	var observed := run.observe_canonical_break(successor, event_id, 2)
	end_stage(m, "canonical_mutation_fence")
	check(observed.success and observed.details.old_writer_fenced, "canonical mutation fences old writer", observed)
	check(not run.execute_boundary(base).success and not run.execute_boundary(successor).success, "execution forbidden while fenced")

	begin_stage(m, "fenced_capsule_capture")
	var fenced_capsule := run.capture_capsule()
	end_stage(m, "fenced_capsule_capture")
	check(fenced_capsule.success, "capture fenced capsule", fenced_capsule)
	var fenced := Life.new()
	begin_stage(m, "fenced_capsule_restore")
	var fenced_restore := fenced.restore_capsule(successor, fenced_capsule.details.capsule)
	end_stage(m, "fenced_capsule_restore")
	check(fenced_restore.success and fenced.status().writer == "", "restore mutation-fenced capsule", fenced_restore)

	begin_stage(m, "local_rebake_after_settle")
	var rebaked := fenced.rebake_after_settle(true)
	end_stage(m, "local_rebake_after_settle")
	check(rebaked.success and int(rebaked.details.component_count) == 2, "local settled rebake", rebaked)
	if not rebaked.success:
		_finish_failed(count)
		return
	var final_status := fenced.status()
	check(final_status.mode == "REBAKED", "final mode REBAKED", final_status)
	check(final_status.active_full_parts == 0 and final_status.active_reduced_bodies == 2, "final sparse representation", final_status)
	check(final_status.work.active_full_peak == Source.REGION_SIZE, "FULL peak exactly 20", final_status.work)
	check(final_status.work.local_reconstructed_parts == Source.REGION_SIZE, "local reconstruction exactly 20", final_status.work)
	check(final_status.work.rebake_local_validations == Source.REGION_SIZE, "local rebake validations exactly 20", final_status.work)
	check(final_status.work.metadata_parts_scanned == 0, "indexed lifecycle performs no full residual part scans", final_status.work)
\tcheck(int(final_status.work.get("range_query_count", -1)) == 4, "exactly four indexed residual queries", final_status.work)
\tcheck(int(final_status.work.get("range_query_prefix_reads", -1)) == 80, "indexed residual queries use bounded prefix reads", final_status.work)
	check(final_status.work.global_physical_rebuilds == 0, "no global physical rebuild", final_status.work)
	check(final_status.work.duplicate_ownership_count == 0, "no duplicate ownership", final_status.work)
	check(Ownership.validate(final_status.ownership).success, "final ownership")
	check(m.sample("rebaked").success, "rebaked measurement sample")

	begin_stage(m, "baked_boundary_hot_loop_after")
	var hot_after := boundary_hot_loop(fenced, successor, BOUNDARY_EXECUTIONS_PER_PHASE)
	end_stage(m, "baked_boundary_hot_loop_after")
	check(hot_after.success, "baked boundary hot loop after mutation", hot_after)

	begin_stage(m, "final_capsule_capture")
	var final_capsule := fenced.capture_capsule()
	end_stage(m, "final_capsule_capture")
	check(final_capsule.success, "capture final capsule", final_capsule)
	var final_fingerprint := U.canonical_hash(fingerprint(fenced))
	var final_restart := Life.new()
	begin_stage(m, "final_capsule_restore")
	var final_restore := final_restart.restore_capsule(successor, final_capsule.details.capsule)
	end_stage(m, "final_capsule_restore")
	check(final_restore.success, "restore final capsule", final_restore)
	check(U.canonical_hash(fingerprint(final_restart)) == final_fingerprint, "final restore exact")
	check(U.canonical_hash(base) == canonical_before, "FABRIC did not mutate canonical base source")

	# Explicit global-control pass. This is intentionally not called a naturally
	# propagating physical event: it forces a whole-source derived rebuild so R5.1
	# can contrast O(N) global work with the bounded local physical path.
	begin_stage(m, "global_control_full_aggregate")
	var global_control := Source.aggregate_span(successor.spec, 0, count)
	end_stage(m, "global_control_full_aggregate")
	check(global_control.success and int(global_control.details.parts_scanned) == count, "global control scans whole source", global_control)

	var residual: Dictionary = final_capsule.details.capsule.checkpoint.cell.payload.residual
	var component_counts: Array = []
	var component_hashes: Array = []
	for key in residual:
		component_counts.append(int(residual[key].descriptor.part_count))
		component_hashes.append(str(residual[key].descriptor.checksum))
	component_counts.sort()
	component_hashes.sort()

	var deterministic := {
		"schema": "planet_simulator.fabric_r5_1_quantitative_scale_case.v1",
		"part_count": count,
		"bond_count_before": count - 1,
		"source_base_checksum": base.spec.checksum,
		"source_successor_checksum": successor.spec.checksum,
		"parent_aggregate_checksum": parent.details.descriptor.checksum,
\t\t"indexed_parent_checksum": indexed_parent.details.descriptor.checksum,
\t\t"range_index_summary_hash": range_index.summary_hash,
\t\t"range_index_build_parts_scanned": count,
\t\t"range_index_mass_error": mass_error,
\t\t"range_index_com_error": com_error,
\t\t"range_index_inertia_error": inertia_error,
		"global_control_aggregate_checksum": global_control.details.descriptor.checksum,
		"active_full_peak": int(final_status.work.active_full_peak),
		"local_reconstructed_parts": int(final_status.work.local_reconstructed_parts),
		"residual_bodies_peak": 2,
		"final_baked_bodies": 2,
		"component_counts": component_counts,
		"component_hashes": component_hashes,
		"metadata_parts_scanned_lifecycle": int(final_status.work.metadata_parts_scanned),
\t\t"range_query_count": int(final_status.work.get("range_query_count", -1)),
\t\t"range_query_prefix_reads": int(final_status.work.get("range_query_prefix_reads", -1)),
		"global_control_parts_scanned": int(global_control.details.parts_scanned),
		"rebake_local_validations": int(final_status.work.rebake_local_validations),
		"global_physical_rebuilds": int(final_status.work.global_physical_rebuilds),
		"duplicate_ownership_count": int(final_status.work.duplicate_ownership_count),
		"transition_count": int(final_status.transition_count),
		"transition_hash": str(final_status.transition_hash),
		"applied_events": final_status.applied_events,
		"boundary_execute_calls": BOUNDARY_EXECUTIONS_PER_PHASE * 2,
	}
	m.set_counter("canonical_parts", count)
	m.set_counter("canonical_bonds_before", count - 1)
	m.set_counter("parent_compile_parts_scanned", count)
	m.set_counter("lifecycle_metadata_parts_scanned", int(final_status.work.metadata_parts_scanned))
	m.set_counter("global_control_parts_scanned", int(global_control.details.parts_scanned))
	m.set_counter("active_full_peak", int(final_status.work.active_full_peak))
	m.set_counter("local_reconstructed_parts", int(final_status.work.local_reconstructed_parts))
	m.set_counter("rebake_local_validations", int(final_status.work.rebake_local_validations))
	m.set_counter("global_physical_rebuilds", int(final_status.work.global_physical_rebuilds))
	m.set_counter("duplicate_ownership_count", int(final_status.work.duplicate_ownership_count))
	m.set_counter("boundary_execute_calls", BOUNDARY_EXECUTIONS_PER_PHASE * 2)
	var applicability := {
		"active_dynamic_solver": {"applicable": false, "reason": "R5.1 reuses structural BAKE/local-refinement to isolate N scaling; active DAE/ROM solver scaling starts in R5.2."},
		"natural_global_physical_event": {"applicable": false, "reason": "global_control_full_aggregate is an explicit whole-source control, not a claim that this fixture contains a naturally propagating global event."},
		"timing_thresholds": {"applicable": false, "reason": "stage timings and RSS are observational scaling evidence, never correctness thresholds."},
	}
	var measured := m.finish(deterministic, applicability)
	check(measured.success, "measurement finalize", measured)
	if not measured.success:
		_finish_failed(count)
		return

	print("FABRIC_R5_1_COUNT=%d" % count)
	print("FABRIC_R5_1_DETERMINISTIC_HASH=" + str(measured.details.deterministic_hash))
	print("FABRIC_R5_1_SCALE=" + JSON.stringify(measured.details))
	if not failed:
		print("FABRIC R5.1 QUANTITATIVE SCALE: PASS (%d assertions) count=%d" % [checks, count])
	quit(1 if failed else 0)

func _finish_failed(count: int) -> void:
	print("FABRIC R5.1 QUANTITATIVE SCALE: FAIL (%d assertions) count=%d" % [checks, count])
	quit(1)
