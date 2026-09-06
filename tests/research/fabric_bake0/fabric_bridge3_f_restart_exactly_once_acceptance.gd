extends SceneTree
const S = preload("res://tests/research/fabric_bake0/bridge3_test_support_v1.gd")
const F = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")
const B = preload("res://scripts/research/fabric_bake0/bridge3_mutation_recovery_lifecycle_v1.gd")
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
var checks := 0
var failed := false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("BRIDGE3-F: " + label)
func fingerprint(run: Object) -> Dictionary:
	var s: Dictionary = run.status()
	return {"mode": s.mode, "writer": s.writer, "transition_epoch": s.transition_epoch,
		"transition_count": s.transition_count, "transition_hash": s.transition_hash,
		"active_full_parts": s.active_full_parts, "active_reduced_bodies": s.active_reduced_bodies,
		"work": s.work, "applied_events": s.get("applied_events", [])}
func restored(f: Dictionary, capsule: Dictionary, frontier: Dictionary, authority: Dictionary) -> Dictionary:
	var run := B.new()
	var result := run.restore_capsule(f.bundle, f.structural.guard.guard_field, f.structural.local.plan,
		capsule, frontier, authority)
	return {"runtime": run, "result": result}
func _initialize() -> void:
	var f := S.build(500)
	check(f.success, "fixture")
	if not f.success:
		quit(1); return
	var run := B.new()
	check(run.start(f.bundle, f.structural.guard.guard_field, f.structural.local.plan, f.full).success, "start")
	var full_capsule_result := run.capture_capsule()
	check(full_capsule_result.success, "FULL capsule")
	var full_capsule: Dictionary = full_capsule_result.details.capsule
	var full_writer: String = run.status().writer
	var rr := restored(f, full_capsule, f.subject.frontier, f.subject.authority)
	check(rr.result.success and rr.runtime.status().writer == full_writer and rr.runtime.status().mode == "FULL", "FULL restart exact")
	for tick in [1, 2]:
		check(run.consider_bake(tick, f.safe).success, "pre-crash safe tick")
	var prepared := run.consider_bake(3, f.safe)
	check(prepared.success and prepared.details.ready, "pre-crash prepared bake")
	check(not run.capture_capsule().success, "pending prepare cannot become durable")
	var replay := restored(f, full_capsule, f.subject.frontier, f.subject.authority)
	check(replay.result.success, "replay from committed FULL")
	var run2: Object = replay.runtime
	for tick in [1, 2]:
		check(run2.consider_bake(tick, f.safe).success, "replayed safe tick")
	var prepared2: Dictionary = run2.consider_bake(3, f.safe)
	check(prepared2.success and prepared2.details.ready, "replayed bake prepared")
	check(run2.commit(prepared2.details.ticket, f.subject.frontier).success, "replayed bake commit")
	check(run2.status().transition_count == 1, "one committed bake")
	var baked_capsule_result: Dictionary = run2.capture_capsule()
	check(baked_capsule_result.success, "BAKE capsule")
	var baked_capsule: Dictionary = baked_capsule_result.details.capsule
	var baked_hash := U.canonical_hash(fingerprint(run2))
	var baked_restart := restored(f, baked_capsule, f.subject.frontier, f.subject.authority)
	check(baked_restart.result.success and U.canonical_hash(fingerprint(baked_restart.runtime)) == baked_hash, "BAKE restart exact")
	var duplicate_commit: Dictionary = baked_restart.runtime.commit(prepared2.details.ticket, f.subject.frontier)
	check(duplicate_commit.success and not duplicate_commit.details.applied, "committed transition remains exactly once")
	check(baked_restart.runtime.status().transition_count == 1, "duplicate commit count unchanged")
	var run3: Object = baked_restart.runtime
	var local: Dictionary = run3.local_unbake(5, f.danger, f.subject.frontier)
	check(local.success and run3.status().mode == "LOCAL_FULL", "local unbake after restart")
	var local_capsule_result: Dictionary = run3.capture_capsule()
	check(local_capsule_result.success, "LOCAL_FULL capsule")
	var local_capsule: Dictionary = local_capsule_result.details.capsule
	var local_hash := U.canonical_hash(fingerprint(run3))
	var local_restart := restored(f, local_capsule, f.subject.frontier, f.subject.authority)
	check(local_restart.result.success and U.canonical_hash(fingerprint(local_restart.runtime)) == local_hash, "LOCAL_FULL restart exact")
	var break_bundle := F.make_break(f.subject, f.structural)
	var compiled := F.compile_transaction(break_bundle)
	check(break_bundle.success and compiled.success, "canonical mutation compiled")
	var run4: Object = local_restart.runtime
	check(run4.observe_canonical_mutation(break_bundle.current_frontier, break_bundle.current_authority,
		break_bundle.event.event_id, break_bundle.event.event_tick).success, "mutation observed")
	check(run4.status().writer == "", "old writer fenced before rebake")
	var fenced_capsule_result: Dictionary = run4.capture_capsule()
	check(fenced_capsule_result.success and fenced_capsule_result.details.capsule.phase == "MUTATION_FENCED", "fenced mutation capsule")
	var stale_restore := restored(f, local_capsule, break_bundle.current_frontier, break_bundle.current_authority)
	check(not stale_restore.result.success, "old source capsule cannot resurrect")
	var fenced_restart := restored(f, fenced_capsule_result.details.capsule, break_bundle.current_frontier, break_bundle.current_authority)
	check(fenced_restart.result.success and fenced_restart.result.details.mode == "MUTATION_FENCED", "mutation-fenced restart")
	check(fenced_restart.runtime.status().writer == "", "fenced restart remains non-executable")
	check(not fenced_restart.runtime.execute_boundary(f.subject.frontier).success, "old frontier remains fenced")
	check(not fenced_restart.runtime.execute_boundary(break_bundle.current_frontier).success, "new frontier waits for rebake")
	var rebaked: Dictionary = fenced_restart.runtime.rebake_after_mutation(compiled.transaction, break_bundle.dependencies, true)
	check(rebaked.success, "resume rebake after crash")
	check(fenced_restart.runtime.status().transition_count == 3, "transition chain preserved across crash")
	var rebaked_capsule_result: Dictionary = fenced_restart.runtime.capture_capsule()
	check(rebaked_capsule_result.success, "REBAKED capsule")
	var rebaked_hash := U.canonical_hash(fingerprint(fenced_restart.runtime))
	var final_restart := restored(f, rebaked_capsule_result.details.capsule, break_bundle.current_frontier, break_bundle.current_authority)
	check(final_restart.result.success and U.canonical_hash(fingerprint(final_restart.runtime)) == rebaked_hash, "REBAKED restart exact")
	check(final_restart.runtime.execute_boundary(break_bundle.current_frontier).success, "rebaked execution survives restart")
	var final_capsule: Dictionary = final_restart.runtime.capture_capsule().details.capsule
	check(final_capsule.applied_events == [break_bundle.event.event_id], "event history exactly once")
	var corrupt: Dictionary = final_capsule.duplicate(true)
	corrupt.slot_checkpoint.cell.transition_count += 1
	var corrupt_restore := restored(f, corrupt, break_bundle.current_frontier, break_bundle.current_authority)
	check(not corrupt_restore.result.success, "corrupt capsule discarded")
	var stale_again := restored(f, final_capsule, f.subject.frontier, f.subject.authority)
	check(not stale_again.result.success, "new-source capsule cannot bind old source")
	print("BRIDGE3_F_HASH=" + U.canonical_hash(fingerprint(final_restart.runtime)))
	print("BRIDGE3_F_CAPSULE_HASH=" + U.canonical_hash(final_capsule))
	if not failed:
		print("FABRIC BRIDGE-3-F: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)
