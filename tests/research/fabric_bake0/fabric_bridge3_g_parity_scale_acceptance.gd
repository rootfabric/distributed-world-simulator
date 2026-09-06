extends SceneTree
const S = preload("res://tests/research/fabric_bake0/bridge3_test_support_v1.gd")
const F = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")
const B = preload("res://scripts/research/fabric_bake0/bridge3_mutation_recovery_lifecycle_v1.gd")
const H = preload("res://scripts/research/fabric_bake0/bridge3_rigid_handoff_v1.gd")
const TopologyRuntime = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_runtime_v1.gd")
const R = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
var checks := 0
var failed := false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("BRIDGE3-G: " + label)
func _initialize() -> void:
	var count := 500
	var verify_full_reference := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			count = int(arg.get_slice("=", 1))
		elif arg == "--full-reference":
			verify_full_reference = true
	check(count in [500, 1000, 2000], "allowed scale")
	check(verify_full_reference == (count == 500), "reference only on 500")
	if failed:
		quit(1); return
	var f := S.build(count)
	check(f.success, "%d fixture" % count)
	if not f.success:
		quit(1); return
	var run := B.new()
	check(run.start(f.bundle, f.structural.guard.guard_field, f.structural.local.plan, f.full).success, "%d start" % count)
	for tick in [1, 2]:
		var waiting: Dictionary = run.consider_bake(tick, f.safe)
		check(waiting.success and not waiting.details.ready, "%d safe window" % count)
	var prepared: Dictionary = run.consider_bake(3, f.safe)
	check(prepared.success and prepared.details.ready, "%d bake ready" % count)
	check(run.commit(prepared.details.ticket, f.subject.frontier).success, "%d bake commit" % count)
	var local: Dictionary = run.local_unbake(5, f.danger, f.subject.frontier)
	check(local.success, "%d local unbake" % count)
	var break_bundle := F.make_break(f.subject, f.structural)
	var compiled := F.compile_transaction(break_bundle)
	check(break_bundle.success and compiled.success, "%d mutation compile" % count)
	check(run.observe_canonical_mutation(break_bundle.current_frontier, break_bundle.current_authority,
		break_bundle.event.event_id, break_bundle.event.event_tick).success, "%d mutation fence" % count)
	var rebaked: Dictionary = run.rebake_after_mutation(compiled.transaction, break_bundle.dependencies, true)
	check(rebaked.success, "%d sparse rebake" % count)
	var status: Dictionary = run.status()
	check(status.mode == "REBAKED" and status.active_reduced_bodies == 2 and status.active_full_parts == 0, "%d final representation" % count)
	check(status.work.reconstructed_parts == 20 and status.work.residual_state_transfers == 2, "%d bounded physical reveal" % count)
	check(status.work.rebake_local_part_validations == 20, "%d bounded rebake validation" % count)
	check(status.work.global_physical_rebuilds == 0 and status.work.duplicate_ownership_count == 0, "%d no global rebuild/duplicate" % count)
	check(status.work.metadata_parts_indexed == count and status.work.rebake_metadata_parts_touched == count, "%d explicit O(N) metadata" % count)
	var capsule_result: Dictionary = run.capture_capsule()
	check(capsule_result.success, "%d final capsule" % count)
	var capsule: Dictionary = capsule_result.details.capsule
	var residual_hash := U.canonical_hash(capsule.slot_checkpoint.cell.payload.residual)
	var max_subject_error := 0.0
	var max_reference_error := 0.0
	if verify_full_reference:
		var final_full := run.full_snapshot(break_bundle.current_frontier)
		check(final_full.success and final_full.details.full_states.size() == count, "%d diagnostic final full" % count)
		var reference := TopologyRuntime.execute(compiled.transaction, f.structural.local.plan,
			f.bundle.aggregate.descriptor, f.bundle.aggregate.reconstruction_mapping, f.structural.guard.guard_field,
			f.state, f.danger, break_bundle.current_frontier, break_bundle.current_authority, break_bundle.dependencies, [])
		check(reference.success, "%d FULL reference topology runtime" % count)
		var expected: Dictionary = {}
		if reference.success:
			var by_id: Dictionary = {}
			for component in compiled.transaction.rebaked_components:
				by_id[component.component_id] = component
			for row in reference.rebaked_component_states:
				var component: Dictionary = by_id[row.component_id]
				var restored := R.reconstruct(component.reconstruction_mapping, row.reduced_state)
				check(restored.success, "%d reference component" % count)
				if restored.success:
					for id in restored.details.full_states:
						expected[id] = restored.details.full_states[id]
		check(expected.size() == count, "%d reference coverage" % count)
		for id in expected:
			max_reference_error = maxf(max_reference_error, H.error(expected[id], final_full.details.full_states[id]))
			max_subject_error = maxf(max_subject_error, H.error(f.full[id], final_full.details.full_states[id]))
		check(max_reference_error < 1.0e-8, "%d reduced/full reference parity" % count)
		check(max_subject_error < 1.0e-8, "%d FULL all-the-way event-instant parity" % count)
	var sizes: Array = []
	for component in compiled.transaction.rebaked_components:
		sizes.append(component.part_ids.size())
	sizes.sort()
	var summary := {"parts": count, "full_reference_checked": verify_full_reference, "full_at_event": 20,
		"residual_bodies": 2, "final_baked_bodies": 2, "component_sizes": sizes,
		"transition_count": status.transition_count, "transition_hash": status.transition_hash,
		"residual_state_hash": residual_hash, "work": status.work.duplicate(true),
		"max_full_parity_error": max_subject_error, "max_reference_error": max_reference_error}
	print("BRIDGE3_G_CASE=" + JSON.stringify(summary))
	print("BRIDGE3_G_CASE_HASH=" + U.canonical_hash(summary))
	if not failed:
		print("FABRIC BRIDGE-3-G CASE: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)
