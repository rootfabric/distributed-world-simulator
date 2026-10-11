extends SceneTree
## R5.5 R1 focused acceptance. Do not label exact until executed on canonical Godot.
const Old = preload("res://scripts/research/fabric_bake0/r5_4_mixed_complexity_machine_v1.gd")
const New = preload("res://scripts/research/fabric_bake0/r5_5_incremental_successor_machine_v1.gd")
const Guard = preload("res://scripts/research/fabric_bake0/r5_5_guarded_index_lifecycle_v1.gd")

var checks := 0
var failures: Array = []

func check(ok: bool, what: String) -> void:
    checks += 1
    if not ok:
        failures.append(what)
        push_error("R5.5: " + what)

func _initialize() -> void:
    var old = Old.new()
    var new_machine = New.new()
    var initial_old: Dictionary = old.initialize()
    var initial_new: Dictionary = new_machine.initialize()
    check(initial_old.success and initial_new.success, "baseline initialization")
    if not initial_old.success or not initial_new.success:
        finish(); return
    check(old.machine_hash() == new_machine.machine_hash(), "identical baseline identity")
    check(int(new_machine.status().r5_5_successor_full_builds) == 1, "one canonical prebuild")
    check(int(new_machine.status().r5_5_successor_attempt_full_builds) == 0, "no event-path full builds")
    check(bool(new_machine.status().r5_5_stage_index_isolated), "scratch prefix index is independent")
    check(int(new_machine.status().r5_5_sealed_prefix_endpoints) == 5, "five canonical prefix boundaries sealed")
    # Original silent-corruption falsifier: mutate a consumed interior prefix.
    # The derived descriptor used to be silently wrong while machine_hash
    # remained canonical. Now admission must reject before any live commit.
    var corrupted = New.new()
    check(corrupted.initialize().success, "prefix tamper fixture initializes")
    if not corrupted.structural_source.is_empty():
        var boundary := int(corrupted.structural_source.spec.break_index)
        var before_hash := corrupted.machine_hash()
        var before_status: Dictionary = corrupted.status().duplicate(true)
        var before_capsule: Dictionary = corrupted.structural_runtime.capture_capsule()
        corrupted._private_stage_index.prefix.mass[boundary] += 12.5
        var denied: Dictionary = corrupted.local_damage_and_refine()
        check(not denied.success and denied.error_code == "R5_4_STRUCTURAL_REBAKE_FAILED", "corrupted used prefix rejects rebake")
        if not denied.success:
            check(denied.get("details", {}).get("cause", {}).get("error_code", "") == "R5_5_PREFIX_INTEGRITY_MISMATCH", "failure preserves exact prefix integrity cause")
        check(corrupted.machine_hash() == before_hash, "prefix rejection preserves live machine identity")
        check(corrupted.status() == before_status, "prefix rejection preserves live work and events")
        check(corrupted.structural_runtime.capture_capsule() == before_capsule, "prefix rejection preserves live capsule")
        corrupted._private_stage_index.prefix.mass[boundary] -= 12.5
        var recovered: Dictionary = corrupted.local_damage_and_refine()
        check(recovered.success, "restored prefix permits legitimate retry")
        check(int(corrupted.status().local_event_count) == 1 and int(corrupted.structural_source.spec.source_revision) == 1, "recovered transaction publishes exactly once")
    # R3 product falsifier: coordinated attack on the *used* physical moment
    # and the runtime seal must reject before publishing any structural or
    # recursive state, despite the forged seal matching the forged data.
    var joint = New.new()
    check(joint.initialize().success, "joint prefix+seal tamper fixture initializes")
    var split := int(joint.structural_source.spec.break_index)
    var original_seal: String = String(joint._trusted_endpoint_seals[str(split)])
    var before_joint_hash: String = joint.machine_hash()
    var before_joint_status: Dictionary = joint.status().duplicate(true)
    var before_joint_capsule: Dictionary = joint.structural_runtime.capture_capsule()
    var before_joint_sessions: Dictionary = joint.recursive_runtime._sessions.duplicate(true)
    joint._private_stage_index.prefix.mass[split] += 12.5
    joint._trusted_endpoint_seals[str(split)] = Guard.endpoint_seal(joint._private_stage_index, split)
    check(String(joint._trusted_endpoint_seals[str(split)]) != original_seal, "joint adversary forged a different matching runtime seal")
    var joint_rejected: Dictionary = joint.local_damage_and_refine()
    check(not joint_rejected.success and joint_rejected.error_code == "R5_4_STRUCTURAL_REBAKE_FAILED", "joint tamper rejected before commit")
    if not joint_rejected.success:
        check(String(joint_rejected.get("details", {}).get("cause", {}).get("error_code", "")) == "R5_5_PREFIX_INTEGRITY_MISMATCH", "joint rejection has exact integrity cause")
    check(joint.machine_hash() == before_joint_hash and joint.status() == before_joint_status, "joint rejection leaves live identity and counters unchanged")
    check(joint.structural_runtime.capture_capsule() == before_joint_capsule and joint.recursive_runtime._sessions == before_joint_sessions, "joint rejection preserves live structural and recursive snapshots")
    joint._private_stage_index.prefix.mass[split] -= 12.5
    # Restoring only the data, but NOT the forged seal, must still fail closed.
    var seals_only_rejected: Dictionary = joint.local_damage_and_refine()
    check(not seals_only_rejected.success and seals_only_rejected.error_code == "R5_4_STRUCTURAL_REBAKE_FAILED", "poisoned runtime seal alone cannot authorize query")
    check(joint.machine_hash() == before_joint_hash and joint.status() == before_joint_status, "seals-only rejection preserves live identity")
    joint._trusted_endpoint_seals[str(split)] = original_seal
    var joint_recovered: Dictionary = joint.local_damage_and_refine()
    check(joint_recovered.success and int(joint.status().local_event_count) == 1, "fully repaired joint state commits exactly once")
    # A non-sealed query boundary is never implicitly trusted.
    var guarded_stage = new_machine._new_structural_stage()
    var unchecked: Dictionary = guarded_stage._r5_query(new_machine.structural_source.spec, 9, 17)
    check(not unchecked.success and unchecked.error_code == "R5_5_PREFIX_INTEGRITY_MISMATCH", "unsealed endpoints fail closed")
    var rejected: Dictionary = new_machine.global_reconfigure()
    check(not rejected.success, "early global attempt rejected")
    var old_local: Dictionary = old.local_damage_and_refine()
    var new_local: Dictionary = new_machine.local_damage_and_refine()
    check(old_local.success and new_local.success, "canonical local transition")
    if not old_local.success or not new_local.success:
        finish(); return
    check(old.machine_hash() == new_machine.machine_hash(), "identical local physical hash")
    check(old.structural_source == new_machine.structural_source, "canonical successor byte-equivalent")
    check(int(new_machine.status().r5_5_successor_cached_attempts) == 1, "one committed cached event")
    check(int(new_machine.status().r5_5_successor_attempt_full_builds) == 0, "still zero full builds at event")
    var old_global: Dictionary = old.global_reconfigure()
    var new_global: Dictionary = new_machine.global_reconfigure()
    check(old_global.success and new_global.success, "recursive global refresh")
    check(old.machine_hash() == new_machine.machine_hash(), "identical final physical hash")
    # Independent fresh subject for an adversarial cache tamper.
    var tampered = New.new()
    check(tampered.initialize().success, "tamper fixture initializes")
    tampered._prepared_successor.spec.source_revision = 17
    var prior: Dictionary = tampered.status()
    var fail: Dictionary = tampered.local_damage_and_refine()
    check(not fail.success and fail.error_code == "R5_5_SUCCESSOR_CACHE_MUTATED", "tampered successor fails closed")
    check(tampered.status() == prior, "rejected cache leaves live state unchanged")
    finish()

func finish() -> void:
    print("FABRIC_R5_5_RESULT=" + JSON.stringify({"checks": checks, "failures": failures}))
    quit(0 if failures.is_empty() else 1)
