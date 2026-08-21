extends SceneTree

const ReadModel = preload("res://scripts/ecology/production/ecology_client_read_model_v1.gd")

const EXPECTED_PARENT := "c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419"

var assertions := 0
var failed := false

func _init() -> void:
    _check(ReadModel.PARENT_P4_5_AGGREGATE == EXPECTED_PARENT, "P4.5 aggregate pinned")

    var a := _summary("planet:region-a", "server-a", 4, 10, 100.0, 100.4, true, 0, [["oak", 5.0], ["pine", 6.0]], 3)
    var b := _summary("planet:region-b", "server-b", 8, 3, 50.0, 51.25, false, 1, [["fern", 2.0], ["moss", 2.0]], 2)
    _check(bool(ReadModel.validate_region_summary(a).get("success", false)), "summary A validates")
    _check(bool(ReadModel.validate_region_summary(b).get("success", false)), "summary B validates")
    _check(String(a["dominant_lineage_id"]) == "pine", "dominant lineage exact")
    _check(String(b["dominant_lineage_id"]) == "fern", "dominant tie lexical")
    _check(float(a["total_biomass_kg"]) == 11.0, "biomass total exact")

    var projection := _projection(["planet:missing", "planet:region-a", "planet:region-b"], [a, b], ["planet:missing"])
    _check(bool(ReadModel.validate_interest_projection(projection).get("success", false)), "interest projection validates")
    _check(int(projection["summary_count"]) == 2 and int(projection["missing_count"]) == 1, "interest counts exact")

    var newer_generation := _summary("planet:region-a", "server-a", 4, 11, 101.0, 101.2, true, 0, [["oak", 5.0], ["pine", 7.0]], 3)
    _check(String(ReadModel.accept_client_update(a, newer_generation)["summary_hash"]) == String(newer_generation["summary_hash"]), "higher generation accepted")
    _check(ReadModel.accept_client_update(newer_generation, a).is_empty(), "generation rollback rejected")

    var higher_epoch := _summary("planet:region-a", "server-c", 5, 10, 100.0, 100.4, true, 0, [["oak", 5.0], ["pine", 6.0]], 3)
    _check(String(ReadModel.accept_client_update(a, higher_epoch)["summary_hash"]) == String(higher_epoch["summary_hash"]), "higher ownership epoch accepted")
    _check(ReadModel.accept_client_update(higher_epoch, newer_generation).is_empty(), "older epoch fenced")
    _check(String(ReadModel.accept_client_update(a, a)["summary_hash"]) == String(a["summary_hash"]), "duplicate idempotent")

    var later_observed := _summary("planet:region-a", "server-a", 4, 10, 100.0, 100.8, true, 0, [["oak", 5.0], ["pine", 6.0]], 3)
    _check(not ReadModel.accept_client_update(a, later_observed).is_empty(), "later observation accepted")
    _check(ReadModel.accept_client_update(later_observed, a).is_empty(), "observation rollback rejected")

    var wrong_region := _summary("planet:region-z", "server-a", 4, 11, 101.0, 101.2, true, 0, [["oak", 5.0]], 1)
    _check(ReadModel.accept_client_update(a, wrong_region).is_empty(), "cross-region cache update rejected")

    var tampered := a.duplicate(true)
    tampered["summary_hash"] = "0".repeat(64)
    _check(not bool(ReadModel.validate_region_summary(tampered).get("success", false)), "summary hash tamper rejected")
    tampered = a.duplicate(true)
    tampered["total_biomass_kg"] = 12.0
    _check(not bool(ReadModel.validate_region_summary(tampered).get("success", false)), "derived total tamper rejected")
    tampered = a.duplicate(true)
    Array(tampered["lineage_biomass"]).reverse()
    tampered["summary_hash"] = ReadModel.compute_summary_hash(tampered)
    _check(not bool(ReadModel.validate_region_summary(tampered).get("success", false)), "non-canonical lineage order rejected")
    tampered = a.duplicate(true)
    tampered["unexpected"] = true
    _check(not bool(ReadModel.validate_region_summary(tampered).get("success", false)), "extra summary field rejected")

    var projection_tampered := projection.duplicate(true)
    projection_tampered["interest_hash"] = "0".repeat(64)
    _check(not bool(ReadModel.validate_interest_projection(projection_tampered).get("success", false)), "interest hash tamper rejected")
    projection_tampered = projection.duplicate(true)
    projection_tampered["missing_region_ids"] = []
    projection_tampered["missing_count"] = 0
    projection_tampered["interest_hash"] = ReadModel.compute_interest_hash(projection_tampered)
    _check(not bool(ReadModel.validate_interest_projection(projection_tampered).get("success", false)), "derived missing set tamper rejected")

    seed(112233)
    var rng_before := [randi(), randi(), randi()]
    seed(112233)
    ReadModel.validate_region_summary(a)
    ReadModel.validate_interest_projection(projection)
    ReadModel.accept_client_update(a, newer_generation)
    var rng_after := [randi(), randi(), randi()]
    _check(rng_before == rng_after, "P4.6 consumes no global RNG")

    var aggregate := (String(a["summary_hash"]) + "\n" + String(projection["interest_hash"]) + "\n" + ReadModel.PARENT_P4_5_AGGREGATE).sha256_text()
    _check(aggregate.length() == 64, "aggregate generated")

    if failed:
        quit(1)
        return
    print("ECO.P4.6 Interest + Client Read Model: PASS (%d assertions)" % assertions)
    print("aggregate_hash=" + aggregate)
    print("summary_hash=" + String(a["summary_hash"]))
    print("interest_hash=" + String(projection["interest_hash"]))
    print("parent_p4_5=" + ReadModel.PARENT_P4_5_AGGREGATE)
    quit(0)

func _summary(region_id: String, owner_id: String, epoch: int, generation: int, simulated: float, observed: float, caught_up: bool, remaining: int, lineage_pairs: Array, patch_count: int) -> Dictionary:
    var lineages := []
    var total := 0.0
    var dominant_id := ""
    var dominant_mass := 0.0
    for pair_value in lineage_pairs:
        var pair: Array = pair_value
        var id := String(pair[0])
        var mass := float(pair[1])
        lineages.append({"id": id, "biomass_kg": mass})
        total += mass
        if dominant_id.is_empty() or mass > dominant_mass or (mass == dominant_mass and id < dominant_id):
            dominant_id = id
            dominant_mass = mass
    lineages.sort_custom(func(x, y): return String(x["id"]) < String(y["id"]))
    var snapshot_hash := (region_id + ":snapshot:" + str(epoch) + ":" + str(generation) + ":" + str(observed)).sha256_text()
    var ownership_hash := (region_id + ":owner:" + owner_id + ":" + str(epoch) + ":" + snapshot_hash).sha256_text()
    var summary := {
        "schema": ReadModel.SCHEMA,
        "version": ReadModel.VERSION,
        "parent_p4_5_aggregate": ReadModel.PARENT_P4_5_AGGREGATE,
        "region_id": region_id,
        "owner_server_id": owner_id,
        "ownership_epoch": epoch,
        "source_ownership_hash": ownership_hash,
        "source_snapshot_hash": snapshot_hash,
        "ecology_generation": generation,
        "last_simulated_world_time": simulated,
        "observed_target_world_time": observed,
        "fully_caught_up": caught_up,
        "remaining_due_steps": remaining,
        "patch_count": patch_count,
        "lineage_biomass": lineages,
        "total_biomass_kg": total,
        "dominant_lineage_id": dominant_id,
        "dominant_lineage_biomass_kg": dominant_mass,
    }
    summary["summary_hash"] = ReadModel.compute_summary_hash(summary)
    return summary

func _projection(requested: Array, summaries: Array, missing: Array) -> Dictionary:
    var projection := {
        "schema": ReadModel.INTEREST_SCHEMA,
        "version": ReadModel.INTEREST_VERSION,
        "parent_p4_5_aggregate": ReadModel.PARENT_P4_5_AGGREGATE,
        "requested_region_ids": requested,
        "summaries": summaries,
        "missing_region_ids": missing,
        "summary_count": summaries.size(),
        "missing_count": missing.size(),
    }
    projection["interest_hash"] = ReadModel.compute_interest_hash(projection)
    return projection

func _check(condition: bool, message: String) -> void:
    assertions += 1
    if condition:
        return
    failed = true
    push_error("ECO.P4.6 FAIL: " + message)
