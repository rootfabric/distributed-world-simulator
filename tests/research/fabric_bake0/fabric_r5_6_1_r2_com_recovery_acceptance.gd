extends SceneTree
## Mandatory R5.6.1 R2 COM publication recovery regression: two legitimate owner revisions
## first leave the point-mass centroid unrepresentable in scalar Float64,
## then restore a safe representation. Neither revision adds/removes matter.
const Index = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_index_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
var checks := 0
var failures: Array = []
var observations := {}
func ck(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures.append(label)
        push_error("REVIEW_R56_R2_COM_RECOVERY: " + label)
func part(index: int, x: float) -> Dictionary:
    return Part.create("part/com-recovery/%d" % index, "item/com-recovery/%d" % index,
        "BEAM", "member", 1.0, [x, 0.0, 0.0])
func state(revision: int, x0: float, x1: float) -> Dictionary:
    return Snapshot.create("construct/com-recovery", "item/com-recovery-root", revision,
        "OPERATIONAL", [part(0,x0),part(1,x1)], [], {})
func _initialize() -> void:
    var origin := 1000000000000.0
    var tiny := 0.0001220703125
    var s0 := state(0, origin, origin + 1.0)
    var s1 := state(1, origin, origin + tiny)
    var s2 := state(2, origin, origin + 1.0)
    ck(Snapshot.validate(s0).success and Snapshot.validate(s1).success and Snapshot.validate(s2).success,
        "all three authoritative construction snapshots valid")
    var index = Index.new()
    var initialized: Dictionary = index.initialize(s0)
    ck(initialized.success, "init from safe centroid")
    var before := index.query_range(0,2)
    ck(before.success, "initial full center safely representable")
    if not initialized.success or not before.success: finish(); return
    var step1: Dictionary = index.apply_owner_verified([{"before":s0.parts[1],"after":s1.parts[1]}],
        String(s0.checksum), String(s1.checksum), 1, 2.0)
    observations["first_update_success"] = step1.success
    ck(step1.success, "owner verified first mutation updates derived index")
    if not step1.success: finish(); return
    var unsafe := index.query_range(0,2)
    observations["unsafe_query_success"] = unsafe.success
    observations["unsafe_error"] = unsafe.get("error_code", "")
    ck(not unsafe.success and String(unsafe.error_code)=="R56_R2_RANGE_CENTER_PRECISION_UNSAFE",
        "badly representable centroid withheld, not fabricated")
    var unsafe_status: Dictionary = index.status().duplicate(true)
    ck(int(unsafe_status.revision) == 1 and int(unsafe_status.accepted_updates) == 1,
        "one owner-verified update advanced the physical source")
    # This recovery path may NOT bypass ordinary mass/source safety.  Reject
    # bad matter mass and stale source before mutating a single Fenwick node.
    var wrong_mass = index.apply_owner_verified([{"before":s1.parts[1],"after":s2.parts[1]}],
        String(s1.checksum), String(s2.checksum), 2, 3.0)
    observations["incorrect_matter_refused"] = not wrong_mass.success
    ck(not wrong_mass.success and String(wrong_mass.error_code)=="R56_R2_MATTER_MASS_MISMATCH",
        "unsafe COM cannot bypass matter mass conservation")
    ck(index.status() == unsafe_status, "rejected matter update leaves all index status unchanged")
    var wrong_source = index.apply_owner_verified([{"before":s1.parts[1],"after":s2.parts[1]}],
        String(s0.checksum), String(s2.checksum), 2, 2.0)
    observations["stale_source_refused"] = not wrong_source.success
    ck(not wrong_source.success and String(wrong_source.error_code)=="R56_R2_INDEX_SOURCE_STALE",
        "unsafe COM cannot bypass owner source/revision fencing")
    ck(index.status() == unsafe_status, "rejected stale update leaves all index status unchanged")
    var step2: Dictionary = index.apply_owner_verified([{"before":s1.parts[1],"after":s2.parts[1]}],
        String(s1.checksum), String(s2.checksum), 2, 2.0)
    observations["recovery_success"] = step2.success
    observations["recovery_error"] = step2.get("error_code", "")
    ck(step2.success, "legitimate recovery to safe centroid must be allowed")
    if step2.success:
        var recovered = index.query_range(0,2)
        ck(recovered.success, "recovered center is safe")
        ck(absf(float(recovered.details.center_of_mass[0]) - (origin+0.5)) <= 0.000001,
            "recovered physical COM matches full oracle")
        ck(absf(float(recovered.details.inertia_tensor_body[1][1]) - 0.5) <= 1.0e-8,
            "recovered physical inertia matches centered full oracle")
        ck(String(index.status().source_checksum) == String(s2.checksum) and
            int(index.status().revision) == 2, "recovered index source is the exact owner successor")
        var recovered_status: Dictionary = index.status().duplicate(true)
        var replay = index.apply_owner_verified([{"before":s1.parts[1],"after":s2.parts[1]}],
            String(s1.checksum), String(s2.checksum), 2, 2.0)
        ck(not replay.success and String(replay.error_code)=="R56_R2_INDEX_SOURCE_STALE",
            "owner successor replay remains rejected")
        ck(index.status() == recovered_status, "replay rejection leaves the published index unchanged")
        ck(int(index.status().accepted_updates) == 2 and
            int(index.status().update_full_moment_scans) == 0,
            "two sparse updates commit without full aggregate rescans")
    observations["final_status"] = index.status()
    finish()
func finish() -> void:
    print("FABRIC_R56_R2_COM_RECOVERY="+JSON.stringify({"schema":"fabric.r56_r2.com_recovery.v1","checks":checks,"failures":failures,"observations":observations}))
    quit(0 if failures.is_empty() else 1)
