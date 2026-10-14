extends SceneTree
## Reviewer-owned independent falsifier, untracked. No write to production files.
const Machine = preload("res://scripts/research/fabric_bake0/r5_5_incremental_successor_machine_v1.gd")
const Source = preload("res://scripts/research/fabric_bake0/complex3_streaming_canonical_structure_v1.gd")
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
var checks := 0
var failures: Array = []
var observation := {}
func ck(v: bool, message: String) -> void:
    checks += 1
    if not v:
        failures.append(message)
        push_error(message)
func _initialize() -> void:
    var m = Machine.new()
    var init: Dictionary = m.initialize()
    ck(init.success, "initialization succeeds")
    if not init.success:
        finish(); return
    var before_digest: String = String(m._prepared_successor.spec.expanded_bond_digest)
    var before_checksum: String = String(m._prepared_successor.spec.checksum)
    var before_hash: String = m.machine_hash()
    observation["canonical_cached_hash"] = m._prepared_successor_hash
    observation["canonical_broken_spec_checksum"] = before_checksum
    var capsule_before: Dictionary = m.structural_runtime.capture_capsule()
    var sessions_before: Dictionary = m.recursive_runtime._sessions.duplicate(true)
    m._prepared_successor.spec.expanded_bond_digest = "f".repeat(64)
    m._prepared_successor.spec.checksum = U.compute_checksum(m._prepared_successor.spec)
    # Attacker controls both mutable payload and mutable cached hash witness.
    m._prepared_successor_hash = U.canonical_hash(m._prepared_successor)
    var admitted: bool = Source.validate_subject(m._prepared_successor, false).success
    var is_next: bool = Source.is_successor(m.structural_source, m._prepared_successor)
    observation["source_validate_false"] = admitted
    observation["is_successor"] = is_next
    ck(before_digest != String(m._prepared_successor.spec.expanded_bond_digest), "bond digest actually replaced")
    ck(before_checksum != String(m._prepared_successor.spec.checksum), "spec checksum was coherently updated")
    ck(admitted and is_next, "forged subject passes current preflight")
    var event: Dictionary = m.local_damage_and_refine()
    observation["event_success"] = event.success
    var rederived: Dictionary = {}
    if event.success:
        rederived = Source.validate_subject(m.structural_source, true)
    observation["rederived_success"] = rederived.get("success", null)
    observation["rederived_error"] = rederived.get("error_code", "")
    ck(not event.success, "source digest tamper MUST be rejected before commit")
    observation["event_error"] = event.get("error_code", "")
    observation["event_cause"] = event.get("details", {}).get("cause", {}).get("error_code", "")
    observation["committed_bond_digest"] = String(m.structural_source.spec.expanded_bond_digest)
    observation["old_bond_digest"] = before_digest
    observation["machine_hash_drift"] = m.machine_hash() != before_hash
    observation["live_capsule_changed"] = m.structural_runtime.capture_capsule() != capsule_before
    observation["recursive_sessions_changed"] = m.recursive_runtime._sessions != sessions_before
    # This probe is a characterization: do not force failure before evaluating.
    if event.success:
        ck(m.structural_source.spec.expanded_bond_digest == "f".repeat(64), "forged digest committed")
        ck(int(m.status().local_event_count) == 1, "local commit performed")
    else:
        ck(int(m.status().local_event_count) == 0, "rejection preserved event count")
    finish()
func finish() -> void:
    print("FABRIC_R55_REVIEW_SUCCESSOR_BINDING_FALSIFIER=" + JSON.stringify({"checks": checks, "failures": failures, "observations": observation}))
    quit(0 if failures.is_empty() else 1)
