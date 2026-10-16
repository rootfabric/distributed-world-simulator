extends SceneTree
## R5.5 R4: RED(R3)->GREEN(R4) successor provenance admission.
## Tests an attacker rewriting both the mutable cached subject and its hash.
## No production test flags, no changes to R5.1/R5.3/R5.4 contracts.
const Source = preload("res://scripts/research/fabric_bake0/complex3_streaming_canonical_structure_v1.gd")
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Guard = preload("res://scripts/research/fabric_bake0/r5_5_guarded_index_lifecycle_v1.gd")

class CountingMachine:
    extends "res://scripts/research/fabric_bake0/r5_5_incremental_successor_machine_v1.gd"
    var started_stages := 0
    func _new_structural_stage():
        started_stages += 1
        return super._new_structural_stage()

var checks := 0
var failures: Array = []
var rejected_attacks := 0
var canonical_rederived := false

func ck(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures.append(label)
        push_error("R5.5 R4: " + label)

func live_snapshot(m) -> Dictionary:
    return {
        "source": m.structural_source.duplicate(true),
        "capsule": m.structural_runtime.capture_capsule(),
        "root": m.recursive_root.duplicate(true),
        "sessions": m.recursive_runtime._sessions.duplicate(true),
        "bundles": m.recursive_runtime._bundles.duplicate(true),
        "hashes": m.recursive_runtime._hashes.duplicate(true),
        "recursive_stats": m.recursive_runtime.stats(),
        "status": m.status(),
        "machine_hash": m.machine_hash(),
        "last_machine_hash": m.last_machine_hash,
        "started_stages": m.started_stages,
    }

func _initialize() -> void:
    var m = CountingMachine.new()
    var initialized: Dictionary = m.initialize()
    ck(initialized.success, "canonical initialisation accepted")
    if not initialized.success:
        done()
        return
    var trusted_subject: Dictionary = m._prepared_successor.duplicate(true)
    var trusted_hash: String = String(m._prepared_successor_hash)
    var baseline_hash: String = m.machine_hash()
    ck(trusted_hash == Guard.canonical_successor_subject_hash(), "prepared full successor has independent canonical identity")
    ck(String(trusted_subject.spec.checksum) == Guard.canonical_successor_spec_checksum(), "successor spec checksum bound")
    ck(String(trusted_subject.spec.expanded_bond_digest) == Guard.canonical_successor_bond_digest(), "canonical expanded bond digest bound")
    ck(U.canonical_hash(trusted_subject) == trusted_hash, "canonical cached subject matches independently pinned identity")

    for attack in ["bond-digest-plus-hash", "frontier-plus-hash", "spec-count-plus-hash", "mutable-witness-only"]:
        m._prepared_successor = trusted_subject.duplicate(true)
        m._prepared_successor_hash = trusted_hash
        match attack:
            "bond-digest-plus-hash":
                m._prepared_successor.spec.expanded_bond_digest = "f".repeat(64)
                m._prepared_successor.spec.checksum = U.compute_checksum(m._prepared_successor.spec)
                m._prepared_successor_hash = U.canonical_hash(m._prepared_successor)
                ck(Source.validate_subject(m._prepared_successor, false).success and Source.is_successor(m.structural_source, m._prepared_successor), "original R3 source preflight would accept the forged bond digest")
            "frontier-plus-hash":
                m._prepared_successor.frontier["checksum"] = "f".repeat(64)
                m._prepared_successor_hash = U.canonical_hash(m._prepared_successor)
            "spec-count-plus-hash":
                m._prepared_successor.spec.bond_count = 123
                m._prepared_successor.spec.checksum = U.compute_checksum(m._prepared_successor.spec)
                m._prepared_successor_hash = U.canonical_hash(m._prepared_successor)
            "mutable-witness-only":
                m._prepared_successor_hash = "f".repeat(64)
        var before: Dictionary = live_snapshot(m)
        var denied: Dictionary = m.local_damage_and_refine()
        var expected_error := "R5_5_SUCCESSOR_CACHE_MUTATED" if attack == "mutable-witness-only" else "R5_5_SUCCESSOR_PROVENANCE_MISMATCH"
        var rejected: bool = not bool(denied.get("success", false)) and String(denied.get("error_code", "")) == expected_error
        ck(rejected, "admission rejects " + attack + " (expected " + expected_error + ")")
        ck(live_snapshot(m) == before, "rejected " + attack + " leaves complete live representations unchanged")
        ck(m.started_stages == 0 and int(m.status().local_event_count) == 0 and int(m.status().r5_5_successor_cached_attempts) == 0, "rejected " + attack + " never enters structural staging or counts a commit")
        if rejected:
            rejected_attacks += 1

    # Restore both sides, not just the mutable witness; canonical retry once.
    m._prepared_successor = trusted_subject.duplicate(true)
    m._prepared_successor_hash = trusted_hash
    ck(m.machine_hash() == baseline_hash, "restored candidate keeps baseline machine identity")
    var committed: Dictionary = m.local_damage_and_refine()
    ck(committed.success, "fully restored canonical event commits")
    if committed.success:
        var verified: Dictionary = Source.validate_subject(m.structural_source, true)
        canonical_rederived = bool(verified.get("success", false))
        ck(canonical_rederived, "committed successor passes full independent 100k digest rederivation")
        ck(String(m.structural_source.spec.expanded_bond_digest) == Guard.canonical_successor_bond_digest(), "committed successor bond digest is code anchored")
        ck(int(m.status().local_event_count) == 1 and int(m.status().r5_5_successor_cached_attempts) == 1 and m.started_stages == 1, "one and only one staged commit")
        ck(int(m.status().r5_5_successor_attempt_full_builds) == 0, "no event-path full successor builds")
        var replay: Dictionary = m.local_damage_and_refine()
        ck(not replay.success and replay.error_code == "R5_4_LOCAL_EVENT_ORDER_INVALID", "replay fails closed")
        ck(int(m.status().local_event_count) == 1 and int(m.status().r5_5_successor_cached_attempts) == 1, "replay does not double commit")
    ck(rejected_attacks == 4, "all four independent source provenance attacks rejected")
    done()

func done() -> void:
    print("FABRIC_R5_5_R4_SOURCE_RESULT=" + JSON.stringify({
        "checks": checks,
        "failures": failures,
        "rejected_attacks": rejected_attacks,
        "full_rederived_success": canonical_rederived,
    }))
    quit(0 if failures.is_empty() else 1)
