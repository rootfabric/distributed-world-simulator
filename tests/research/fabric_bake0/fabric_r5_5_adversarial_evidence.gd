extends SceneTree
## R5.5 R1 adversarial evidence + falsifier probes (research only).
## Proves separately: mutation prevention, tamper detection, transaction rollback.
## Wall-time is recorded as measurement only; it is never a complexity proof.
const Old = preload("res://scripts/research/fabric_bake0/r5_4_mixed_complexity_machine_v1.gd")
const New = preload("res://scripts/research/fabric_bake0/r5_5_incremental_successor_machine_v1.gd")
const Life = preload("res://scripts/research/fabric_bake0/r5_indexed_sparse_damage_lifecycle_v1.gd")

var checks := 0
var failures: Array = []
var out: Dictionary = {}

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures.append(what)
		push_error("R5.5ADV: " + what)

func _initialize() -> void:
	# --- A. Real committed event cost: parity + timing measurement ------------
	var old = Old.new()
	var m = New.new()
	check(old.initialize().success and m.initialize().success, "A: initialization")
	var t0 := Time.get_ticks_usec()
	var r54: Dictionary = old.local_damage_and_refine()
	var t54 := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	var r55: Dictionary = m.local_damage_and_refine()
	var t55 := Time.get_ticks_usec() - t0
	check(r54.success and r55.success, "A: committed local events")
	check(old.machine_hash() == m.machine_hash(), "A: committed hash parity")
	out["timing"] = {"r54_local_event_usec": t54, "r55_local_event_usec": t55,
		"note": "measurement only, not a complexity proof"}
	out["r55_status_after_commit"] = m.status()
	var work: Dictionary = m.structural_runtime.status().get("work", {})
	out["committed_work"] = work
	# Committed event did bounded local work only.
	check(int(work.get("local_reconstructed_parts", -1)) == 20, "A: 20 locally reconstructed parts")
	check(int(work.get("range_query_count", -1)) == 4, "A: 4 indexed range queries")
	check(int(work.get("range_query_prefix_reads", -1)) == 80, "A: 80 prefix reads (4x20)")
	check(int(m.status().r5_5_successor_attempt_full_builds) == 0, "A: zero event-path full builds")
	# --- B. Repeated rejected attempt: no hidden O(N) rebuild -----------------
	var before: Dictionary = m.status()
	t0 = Time.get_ticks_usec()
	var rejected: Dictionary = m.local_damage_and_refine()
	var t_rej := Time.get_ticks_usec() - t0
	check(not rejected.success, "B: replay attempt rejected")
	check(m.status() == before, "B: rejected attempt leaves live state untouched")
	check(int(m.status().r5_5_successor_attempt_full_builds) == 0, "B: rejected attempt adds no full build")
	out["timing"]["rejected_attempt_usec"] = t_rej
	# --- C. Prepared successor field tampers all fail closed ------------------
	for field in ["spec", "frontier", "authority"]:
		var probe = New.new()
		check(probe.initialize().success, "C: probe init %s" % field)
		var prior: Dictionary = probe.status()
		if field == "spec":
			probe._prepared_successor.spec.source_revision = 17
		elif field == "frontier":
			probe._prepared_successor.frontier["checksum"] = "0".repeat(64)
		else:
			probe._prepared_successor.authority["checksum"] = "0".repeat(64)
		var fail: Dictionary = probe.local_damage_and_refine()
		check(not fail.success and fail.error_code == "R5_5_SUCCESSOR_CACHE_MUTATED",
			"C: %s tamper fails closed" % field)
		check(probe.status() == prior, "C: %s tamper preserves live state" % field)
	# --- D. Stage prefix-array tamper: detection vs silent corruption ---------
	var canonical = New.new()
	check(canonical.initialize().success and canonical.local_damage_and_refine().success, "D: canonical post-event fixture")
	var tm = New.new()
	check(tm.initialize().success, "D: tamper fixture init")
	var baseline_hash: String = tm.machine_hash()
	var mass: PackedFloat64Array = tm._private_stage_index.prefix.mass
	mass[5] = float(mass[5]) + 100.0
	tm._private_stage_index.prefix.mass = mass
	var staged_fail: Dictionary = tm.local_damage_and_refine()
	# Characterization, not an assertion of detection: scratch prefix tampering is
	# mutation-prevented only by ownership. If it commits, canonical identity must
	# still match (corruption is confined to derived descriptors). If it fails, the
	# transaction must roll back to the exact pre-event identity.
	if staged_fail.success:
		out["prefix_tamper"] = {"committed": true, "error_code": "", "detection": "NOT_DETECTED",
			"note": "residual limitation: scratch prefix integrity is trust-based; derived descriptors can be corrupted silently while canonical identity stays blind"}
		check(tm.machine_hash() == canonical.machine_hash(), "D: committed tamper keeps canonical identity")
	else:
		out["prefix_tamper"] = {"committed": false, "error_code": String(staged_fail.get("error_code", "")), "detection": "FAIL_CLOSED"}
		check(tm.machine_hash() == baseline_hash, "D: failed transaction preserves live identity")
	# --- E. Live range-index tamper cannot leak into the staged event ---------
	var lv = New.new()
	check(lv.initialize().success, "E: live tamper fixture init")
	var live_baseline: String = lv.machine_hash()
	var live_mass: PackedFloat64Array = lv.structural_index.prefix.mass
	live_mass[500] = float(live_mass[500]) + 50.0
	lv.structural_index.prefix.mass = live_mass
	var live_event: Dictionary = lv.local_damage_and_refine()
	check(live_event.success, "E: staged event unaffected by live-index tamper")
	check(lv.machine_hash() == canonical.machine_hash(), "E: staged result matches canonical hash")
	out["live_index_tamper"] = {"event_committed": true,
		"note": "live index is not read on the event path; stage uses scratch-owned copy"}
	# --- F. Staged capsule tamper fails closed on restore ---------------------
	var cap_machine = New.new()
	check(cap_machine.initialize().success, "F: capsule fixture init")
	var captured: Dictionary = cap_machine.structural_runtime.capture_capsule()
	check(captured.success, "F: capsule captured")
	var capsule: Dictionary = captured.details.capsule
	capsule.work["local_reconstructed_parts"] = 999999
	var stage = Life.new()
	var restored: Dictionary = stage.restore_capsule(cap_machine.structural_source, capsule)
	check(not restored.success, "F: tampered capsule rejected on restore")
	out["capsule_tamper_error"] = String(restored.get("error_code", ""))
	# --- G. Recursive identity is derived, not independently executable -------
	var rec = New.new()
	check(rec.initialize().success, "G: recursive probe init")
	var rec_before: String = rec.machine_hash()
	rec.recursive_root.node_hash = "f".repeat(64)
	check(rec.machine_hash() != rec_before, "G: recursive node hash participates in identity")
	var stale: Dictionary = rec.execute_steady([])
	out["recursive_tamper_execute"] = {"success": bool(stale.success), "error_code": String(stale.get("error_code", "")),
		"note": "recorded outcome; recursive ROM execution contract is owned by closed R5.3"}
	finish()

func finish() -> void:
	out["checks"] = checks
	out["failures"] = failures
	print("FABRIC_R5_5_ADVERSARIAL=" + JSON.stringify(out))
	quit(0 if failures.is_empty() else 1)
