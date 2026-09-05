extends SceneTree
const S = preload("res://tests/research/fabric_bake0/bridge3_test_support_v1.gd")
const B = preload("res://scripts/research/fabric_bake0/bridge3_structural_lifecycle_v1.gd")
const H = preload("res://scripts/research/fabric_bake0/bridge3_rigid_handoff_v1.gd")
const Old = preload("res://scripts/research/fabric_bake0/structural_local_unbake_runtime_v1.gd")
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
var checks := 0
var failed := false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("BRIDGE3-BCD: " + label)
func _initialize() -> void:
	var stage := "D"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):
			stage = arg.get_slice("=", 1)
	var f := S.build(500)
	check(f.success, "fixture " + str(f.get("error_code", "")))
	if not f.success:
		quit(1)
		return
	var before := U.canonical_hash(f.subject)
	var run := B.new()
	check(run.start(f.bundle, f.structural.guard.guard_field, f.structural.local.plan, f.full).success, "start")
	var malformed: Dictionary = f.structural.local.plan.duplicate(true)
	malformed.parent_structural_descriptor_hash = "0".repeat(64)
	malformed.checksum = U.compute_checksum(malformed)
	check(not B.new().start(f.bundle, f.structural.guard.guard_field, malformed, f.full).success, "rehashed foreign plan rejected")
	var nonrigid: Dictionary = f.full.duplicate(true)
	nonrigid[nonrigid.keys()[0]].linear_velocity[0] += 1.0
	check(not B.new().start(f.bundle, f.structural.guard.guard_field, f.structural.local.plan, nonrigid).success, "nonrigid source cannot bake")
	check(not B.new().consider_bake(1, {}).success, "uninitialized fail closed")
	check(run.status().active_full_parts == 500, "full initially real detailed state")
	for tick in [1, 2]:
		var waiting := run.consider_bake(tick, f.safe)
		check(waiting.success and not waiting.details.ready, "consecutive safe window")
	var prepared := run.consider_bake(3, f.safe)
	check(prepared.success and prepared.details.ready, "prepare bake")
	check(run.status().mode == "FULL", "preparation not active bake")
	var old_writer: String = run.status().writer
	var committed := run.commit(prepared.details.ticket, f.subject.frontier)
	check(committed.success and committed.details.applied, "commit full to bake")
	check(run.status().active_full_parts == 0 and run.status().active_reduced_bodies == 1, "full state freed")
	check(run.status().writer != old_writer, "old writer fenced")
	check(not run.commit(prepared.details.ticket, f.subject.frontier).details.applied, "duplicate bake no transition")
	check(run.execute_boundary(f.subject.frontier).success, "real accepted physical artifact executes")
	var stale: Dictionary = f.subject.frontier.duplicate(true)
	stale.frontier_hash = "0".repeat(64)
	check(not run.execute_boundary(stale).success, "stale boundary cannot execute")
	var restored := run.full_snapshot(f.subject.frontier)
	check(restored.success, "baked observation")
	var max_error := 0.0
	for id in f.full:
		max_error = maxf(max_error, H.error(f.full[id], restored.details.full_states[id]))
	check(max_error < 1.0e-8, "full bake observation continuity")
	if stage in ["C", "D"]:
		# Advance a genuinely moving/rotated reduced state through the solver output port.
		var moved: Dictionary = f.state.duplicate(true)
		moved.position[0] += 1.125
		moved.position[2] -= 0.75
		moved.orientation = H.aq(Quaternion(Vector3.UP, 0.2) * H.q(moved.orientation))
		moved.linear_velocity[1] += 0.25
		var previous: String = run.status().writer
		check(not run.accept_baked_solver_state(previous, moved, 4, f.safe, f.subject.frontier).success, "outdated guard dynamics rejected")
		var valid_context := S.context(f.subject, f.structural, moved, false)
		check(run.accept_baked_solver_state(previous, moved, 4, valid_context, f.subject.frontier).success, "live reduced motion accepted")
		check(not run.accept_baked_solver_state(previous, moved, 5, valid_context, f.subject.frontier).success, "superseded writer cannot overwrite motion")
		f.state = moved
		f.full = S.R.reconstruct(f.bundle.aggregate.reconstruction_mapping, moved).details.full_states
		f.safe = valid_context
		f.danger = S.context(f.subject, f.structural, moved, true)
		check(not run.local_unbake(5, f.safe, f.subject.frontier).success, "untriggered guard rejected")
		var work_before: Dictionary = run.status().work
		var unbaked := run.local_unbake(5, f.danger, f.subject.frontier)
		check(unbaked.success, "immediate local unbake " + str(unbaked.get("error_code", "")))
		if not unbaked.success:
			print(unbaked)
			quit(1)
			return
		check(run.status().active_full_parts == 20, "only target materialized")
		check(run.status().active_reduced_bodies == 2, "two residuals remain reduced")
		check(run.status().work.reconstructed_parts - work_before.reconstructed_parts == 20, "bounded reconstruction work")
		check(run.status().work.residual_state_transfers - work_before.residual_state_transfers == 2, "bounded residual transfers")
		check(run.status().work.full_snapshot_parts == work_before.full_snapshot_parts, "no hidden global snapshot")
		check(run.status().transition_count == 2 and run.status().transition_epoch == 5, "two exactly once transitions")
		check(not run.local_unbake(5, f.danger, f.subject.frontier).success, "same danger not reapplied")
		if stage == "D":
			var reference := Old.execute(f.structural.local.plan, f.bundle.aggregate.descriptor,
				f.bundle.aggregate.reconstruction_mapping, f.structural.guard.guard_field, f.state, f.danger)
			check(reference.success, "independent predecessor reconstruction oracle")
			check(run.execute_boundary(f.subject.frontier).success == false, "old parent bake no longer executable")
			var all := run.full_snapshot(f.subject.frontier)
			check(all.success and all.details.full_states.size() == 500, "complete unique part coverage")
			for id in f.full:
				check(H.error(f.full[id], all.details.full_states[id]) < 1.0e-8, "part continuity " + id)
			check(unbaked.details.continuity.boundary_error < 1.0e-8, "boundary anchors continuous")
			for field in unbaked.details.continuity.conservation_error:
				check(unbaked.details.continuity.conservation_error[field] < 1.0e-7, "no artificial " + field)
	check(U.canonical_hash(f.subject) == before, "canonical source unchanged")
	var status := run.status()
	print("BRIDGE3_%s_HASH=" % stage + U.canonical_hash(status))
	print("BRIDGE3_%s_WORK=" % stage + JSON.stringify(status.work))
	if not failed:
		print("FABRIC BRIDGE-3-%s: PASS (%d assertions)" % [stage, checks])
	quit(1 if failed else 0)
