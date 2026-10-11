extends SceneTree
## R5.5 R3 strict boundary falsifier; 10 moments x 5 endpoints x +/- delta.
## Both prefix-only and jointly-forged prefix + runtime seal must fail closed.
const Machine = preload("res://scripts/research/fabric_bake0/r5_5_incremental_successor_machine_v1.gd")
const Guard = preload("res://scripts/research/fabric_bake0/r5_5_guarded_index_lifecycle_v1.gd")
const Source = preload("res://scripts/research/fabric_bake0/complex3_streaming_canonical_structure_v1.gd")
const FIELDS := ["mass", "sx", "sy", "sz", "jxx", "jxy", "jxz", "jyy", "jyz", "jzz"]
var checks := 0
var failures: Array = []
var rejected_mutations := 0
var rejected_joint_mutations := 0

func expect(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures.append(label)
        push_error("R5.5 strict prefix: " + label)

func _initialize() -> void:
    var machine = Machine.new()
    var init: Dictionary = machine.initialize()
    expect(init.success, "canonical machine initializes")
    if not init.success:
        finish()
        return
    var count := int(machine.structural_source.spec.part_count)
    var first := Source.target_region_start(count)
    var last := mini(first + Source.REGION_SIZE, count)
    var cut := Source.break_index(count)
    var endpoints := [0, first, last, cut, count]
    expect(machine._trusted_endpoint_seals.size() == 5, "five sealed boundaries")
    var guard = Guard.new()
    guard.configure_seals(machine._trusted_endpoint_seals)
    # Call the real guarded query; the prefix index is deliberately scratch-owned.
    guard._r5_range_index = machine._private_stage_index
    var baseline_hash := machine.machine_hash()
    var baseline_status: Dictionary = machine.status().duplicate(true)
    for field in FIELDS:
        for endpoint in endpoints:
            for delta in [1.25, -1.25]:
                var values: PackedFloat64Array = machine._private_stage_index.prefix[field]
                var original := float(values[endpoint])
                values[endpoint] = original + delta
                machine._private_stage_index.prefix[field] = values
                var range_first := 0
                var range_end: int = int(endpoint)
                if endpoint == 0:
                    range_end = count
                var got: Dictionary = guard._r5_query(machine.structural_source.spec, range_first, range_end)
                var detected: bool = not bool(got.get("success", false)) and String(got.get("error_code", "")) == "R5_5_PREFIX_INTEGRITY_MISMATCH" and int(got.get("details", {}).get("endpoint", -1)) == endpoint
                expect(detected, "detected %s at %d delta %s" % [field, endpoint, str(delta)])
                if detected:
                    rejected_mutations += 1
                # R2's authentic falsifier: adversary also rewrites the mutable
                # runtime seal to perfectly match the poisoned prefix. A code-
                # anchored independent witness must still reject the query.
                var key := str(endpoint)
                var original_claim: String = String(guard._trusted_endpoint_seals[key])
                var forged_claim: String = Guard.endpoint_seal(machine._private_stage_index, endpoint)
                guard._trusted_endpoint_seals[key] = forged_claim
                machine._trusted_endpoint_seals[key] = forged_claim
                var forged: Dictionary = guard._r5_query(machine.structural_source.spec, range_first, range_end)
                var joint_detected: bool = not bool(forged.get("success", false)) and String(forged.get("error_code", "")) == "R5_5_PREFIX_INTEGRITY_MISMATCH" and int(forged.get("details", {}).get("endpoint", -1)) == endpoint
                expect(joint_detected, "detected joint %s at %d delta %s" % [field, endpoint, str(delta)])
                if joint_detected:
                    rejected_joint_mutations += 1
                guard._trusted_endpoint_seals[key] = original_claim
                machine._trusted_endpoint_seals[key] = original_claim
                values = machine._private_stage_index.prefix[field]
                values[endpoint] = original
                machine._private_stage_index.prefix[field] = values
    expect(rejected_mutations == 100, "all 100 consumed endpoint mutations rejected")
    expect(rejected_joint_mutations == 100, "all 100 coordinated prefix-plus-seal mutations rejected")
    expect(machine.machine_hash() == baseline_hash, "live machine identity unchanged")
    expect(machine.status() == baseline_status, "live runtime status unchanged")
    # Truly unsealed endpoints fail closed, never using unsupported range data.
    var unsealed: Dictionary = guard._r5_query(machine.structural_source.spec, 9, 17)
    expect(not unsealed.success and unsealed.error_code == "R5_5_PREFIX_INTEGRITY_MISMATCH", "unsealed endpoints rejected")
    var false_spec: Dictionary = machine.structural_source.spec.duplicate(true)
    false_spec.expanded_part_digest = "0".repeat(64)
    var wrong_source: Dictionary = guard._r5_query(false_spec, 0, count)
    expect(not wrong_source.success and wrong_source.error_code == "R5_5_PREFIX_SOURCE_ANCHOR_MISMATCH", "noncanonical source binding fails closed")
    # The original end-to-end rollback/retry falsifier remains mandatory in focused acceptance.
    finish()

func finish() -> void:
    print("FABRIC_R5_5_PREFIX_MATRIX=" + JSON.stringify({"checks": checks, "rejected_mutations": rejected_mutations, "rejected_joint_mutations": rejected_joint_mutations, "failures": failures}))
    quit(0 if failures.is_empty() else 1)
