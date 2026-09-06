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
		push_error("BRIDGE3-E: " + label)
func _initialize() -> void:
	var f := S.build(500)
	check(f.success, "fixture")
	if not f.success:
		quit(1); return
	var canonical_before := U.canonical_hash(f.subject)
	var run := B.new()
	check(run.start(f.bundle, f.structural.guard.guard_field, f.structural.local.plan, f.full).success, "start")
	for tick in [1, 2]:
		check(run.consider_bake(tick, f.safe).success, "safe window")
	var prepared := run.consider_bake(3, f.safe)
	check(prepared.success and prepared.details.ready, "bake ready")
	check(run.commit(prepared.details.ticket, f.subject.frontier).success, "bake commit")
	var unbaked := run.local_unbake(5, f.danger, f.subject.frontier)
	check(unbaked.success, "local unbake")
	check(run.status().active_full_parts == 20, "local full region")
	var break_bundle := F.make_break(f.subject, f.structural)
	check(break_bundle.success, "canonical mutation fixture")
	var compiled := F.compile_transaction(break_bundle)
	check(compiled.success, "topology transaction compile")
	var old_writer: String = run.status().writer
	var observed := run.observe_canonical_mutation(break_bundle.current_frontier, break_bundle.current_authority,
		break_bundle.event.event_id, break_bundle.event.event_tick)
	check(observed.success and observed.details.old_writer_fenced, "mutation fences old owner")
	check(old_writer != "" and run.status().writer == "", "writer revoked")
	check(not run.execute_boundary(f.subject.frontier).success, "old frontier cannot execute after mutation")
	check(not run.execute_boundary(break_bundle.current_frontier).success, "new frontier waits for rebake")
	check(not run.rebake_after_mutation(compiled.transaction, break_bundle.dependencies, false).success, "premature rebake rejected")
	var rebaked := run.rebake_after_mutation(compiled.transaction, break_bundle.dependencies, true)
	check(rebaked.success, "settled sparse rebake")
	check(rebaked.details.rebaked_component_count == 2, "two components")
	check(rebaked.details.local_part_validations == 20, "only local parts physically validated")
	check(rebaked.details.metadata_parts_touched == 500, "metadata coverage explicit")
	var status := run.status()
	check(status.mode == "REBAKED", "rebaked mode")
	check(status.active_full_parts == 0 and status.active_reduced_bodies == 2, "collapsed to two reduced bodies")
	check(status.transition_count == 3, "full bake unbake rebake transitions")
	check(status.work.reconstructed_parts == 20, "no global physical reconstruction")
	check(status.work.global_physical_rebuilds == 0, "no global physical rebuild")
	check(status.work.duplicate_ownership_count == 0, "no duplicate ownership")
	check(status.work.canonical_mutations_observed == 1 and status.work.stale_owner_fences == 1, "one canonical mutation and fence")
	check(status.work.rebake_local_part_validations == 20, "rebake witnesses bounded")
	check(run.execute_boundary(break_bundle.current_frontier).success, "new rebakes executable")
	var final_full := run.full_snapshot(break_bundle.current_frontier)
	check(final_full.success and final_full.details.full_states.size() == 500, "diagnostic final full coverage")
	var reference := TopologyRuntime.execute(compiled.transaction, f.structural.local.plan,
		f.bundle.aggregate.descriptor, f.bundle.aggregate.reconstruction_mapping, f.structural.guard.guard_field,
		f.state, f.danger, break_bundle.current_frontier, break_bundle.current_authority, break_bundle.dependencies, [])
	check(reference.success, "closed predecessor full reconstruction oracle")
	if reference.success and final_full.success:
		var expected: Dictionary = {}
		var by_id: Dictionary = {}
		for component in compiled.transaction.rebaked_components:
			by_id[component.component_id] = component
		for row in reference.rebaked_component_states:
			var component: Dictionary = by_id[row.component_id]
			var reconstructed := R.reconstruct(component.reconstruction_mapping, row.reduced_state)
			check(reconstructed.success, "reference component reconstruct")
			if reconstructed.success:
				for id in reconstructed.details.full_states:
					expected[id] = reconstructed.details.full_states[id]
		check(expected.size() == 500, "reference full coverage")
		for id in expected:
			check(H.error(expected[id], final_full.details.full_states[id]) < 1.0e-8, "final parity " + id)
	var capsule := run.capture_capsule()
	check(capsule.success and capsule.details.capsule.applied_events == [break_bundle.event.event_id], "event history captured")
	check(not run.rebake_after_mutation(compiled.transaction, break_bundle.dependencies, true).success, "no double rebake")
	check(U.canonical_hash(f.subject) == canonical_before, "fabric did not mutate old canonical source")
	var stable := {"mode": status.mode, "transition_count": status.transition_count, "transition_hash": status.transition_hash,
		"work": status.work, "applied_events": status.applied_events}
	print("BRIDGE3_E_HASH=" + U.canonical_hash(stable))
	print("BRIDGE3_E_WORK=" + JSON.stringify(status.work))
	if not failed:
		print("FABRIC BRIDGE-3-E: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)
