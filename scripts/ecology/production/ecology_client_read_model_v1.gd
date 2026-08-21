extends RefCounted

const RegionOwnership = preload("res://scripts/ecology/production/ecology_region_ownership_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p4_6_client_read_model.v1"
const VERSION := "1.0.0"
const INTEREST_SCHEMA := "distributed_world_simulator.ecology.p4_6_interest_projection.v1"
const INTEREST_VERSION := "1.0.0"
const PARENT_P4_5_AGGREGATE := "c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419"

const SUMMARY_FIELDS := [
    "schema", "version", "parent_p4_5_aggregate", "region_id", "owner_server_id",
    "ownership_epoch", "source_ownership_hash", "source_snapshot_hash", "ecology_generation",
    "last_simulated_world_time", "observed_target_world_time", "fully_caught_up",
    "remaining_due_steps", "patch_count", "lineage_biomass", "total_biomass_kg",
    "dominant_lineage_id", "dominant_lineage_biomass_kg", "summary_hash",
]

const INTEREST_FIELDS := [
    "schema", "version", "parent_p4_5_aggregate", "requested_region_ids", "summaries",
    "missing_region_ids", "summary_count", "missing_count", "interest_hash",
]

static func build_region_summary(ownership_state: Dictionary) -> Dictionary:
    if not bool(RegionOwnership.validate_ownership(ownership_state).get("success", false)):
        return {}
    var snapshot: Dictionary = Dictionary(ownership_state.get("snapshot", {}))
    var catchup: Dictionary = Dictionary(snapshot.get("catchup_state", {}))
    var region: Dictionary = Dictionary(catchup.get("region_state", {}))
    var p3_state: Dictionary = Dictionary(region.get("p3_state", {}))
    var current: Dictionary = Dictionary(p3_state.get("current_p3_7_result", {}))
    var community_value = current.get("next_community", [])
    if typeof(community_value) != TYPE_ARRAY:
        return {}
    var community: Array = Array(community_value)
    var lineages := _collect_lineages(community)
    if lineages.is_empty() and not community.is_empty():
        return {}
    var total := 0.0
    var dominant_id := ""
    var dominant_mass := 0.0
    for lineage_value in lineages:
        var lineage: Dictionary = lineage_value
        var mass := float(lineage["biomass_kg"])
        total += mass
        var id := String(lineage["id"])
        if dominant_id.is_empty() or mass > dominant_mass or (mass == dominant_mass and id < dominant_id):
            dominant_id = id
            dominant_mass = mass
    var summary := {
        "schema": SCHEMA,
        "version": VERSION,
        "parent_p4_5_aggregate": PARENT_P4_5_AGGREGATE,
        "region_id": String(ownership_state.get("region_id", "")),
        "owner_server_id": String(ownership_state.get("owner_server_id", "")),
        "ownership_epoch": int(ownership_state.get("ownership_epoch", -1)),
        "source_ownership_hash": String(ownership_state.get("ownership_hash", "")),
        "source_snapshot_hash": String(ownership_state.get("snapshot_hash", "")),
        "ecology_generation": int(region.get("ecology_generation", -1)),
        "last_simulated_world_time": float(region.get("last_simulated_world_time", NAN)),
        "observed_target_world_time": float(catchup.get("observed_target_world_time", NAN)),
        "fully_caught_up": bool(catchup.get("fully_caught_up", false)),
        "remaining_due_steps": int(catchup.get("remaining_due_steps", -1)),
        "patch_count": community.size(),
        "lineage_biomass": lineages,
        "total_biomass_kg": total,
        "dominant_lineage_id": dominant_id,
        "dominant_lineage_biomass_kg": dominant_mass,
    }
    summary["summary_hash"] = compute_summary_hash(summary)
    if not bool(validate_region_summary(summary).get("success", false)):
        return {}
    return summary

static func validate_region_summary(summary: Dictionary) -> Dictionary:
    if not _exact_fields(summary, SUMMARY_FIELDS):
        return _failure("SUMMARY_FIELDS_MISMATCH")
    if String(summary.get("schema", "")) != SCHEMA or String(summary.get("version", "")) != VERSION:
        return _failure("SUMMARY_SCHEMA_OR_VERSION_MISMATCH")
    if String(summary.get("parent_p4_5_aggregate", "")) != PARENT_P4_5_AGGREGATE:
        return _failure("SUMMARY_PARENT_P4_5_MISMATCH")
    if typeof(summary.get("region_id")) != TYPE_STRING or String(summary.get("region_id", "")).is_empty():
        return _failure("SUMMARY_REGION_ID_INVALID")
    if typeof(summary.get("owner_server_id")) != TYPE_STRING or String(summary.get("owner_server_id", "")).is_empty():
        return _failure("SUMMARY_OWNER_ID_INVALID")
    if typeof(summary.get("ownership_epoch")) != TYPE_INT or int(summary.get("ownership_epoch", -1)) < 0:
        return _failure("SUMMARY_EPOCH_INVALID")
    if not _is_hash(String(summary.get("source_ownership_hash", ""))) or not _is_hash(String(summary.get("source_snapshot_hash", ""))):
        return _failure("SUMMARY_SOURCE_HASH_INVALID")
    if typeof(summary.get("ecology_generation")) != TYPE_INT or int(summary.get("ecology_generation", -1)) < 0:
        return _failure("SUMMARY_GENERATION_INVALID")
    for key in ["last_simulated_world_time", "observed_target_world_time", "total_biomass_kg", "dominant_lineage_biomass_kg"]:
        if typeof(summary.get(key)) != TYPE_FLOAT or not is_finite(float(summary.get(key, NAN))):
            return _failure("SUMMARY_FLOAT_INVALID")
    if float(summary["observed_target_world_time"]) < float(summary["last_simulated_world_time"]):
        return _failure("SUMMARY_OBSERVED_BEFORE_SIMULATED")
    if typeof(summary.get("fully_caught_up")) != TYPE_BOOL:
        return _failure("SUMMARY_CAUGHT_UP_TYPE_INVALID")
    if typeof(summary.get("remaining_due_steps")) != TYPE_INT or int(summary["remaining_due_steps"]) < 0:
        return _failure("SUMMARY_REMAINING_INVALID")
    if bool(summary["fully_caught_up"]) != (int(summary["remaining_due_steps"]) == 0):
        return _failure("SUMMARY_CAUGHT_UP_DERIVED_MISMATCH")
    if typeof(summary.get("patch_count")) != TYPE_INT or int(summary["patch_count"]) < 0:
        return _failure("SUMMARY_PATCH_COUNT_INVALID")
    if typeof(summary.get("lineage_biomass")) != TYPE_ARRAY:
        return _failure("SUMMARY_LINEAGE_LIST_INVALID")
    var previous := ""
    var sum := 0.0
    var dominant_id := ""
    var dominant_mass := 0.0
    for value in Array(summary["lineage_biomass"]):
        if typeof(value) != TYPE_DICTIONARY:
            return _failure("SUMMARY_LINEAGE_ENTRY_INVALID")
        var lineage: Dictionary = value
        if not _exact_fields(lineage, ["id", "biomass_kg"]):
            return _failure("SUMMARY_LINEAGE_FIELDS_MISMATCH")
        if typeof(lineage.get("id")) != TYPE_STRING or String(lineage["id"]).is_empty():
            return _failure("SUMMARY_LINEAGE_ID_INVALID")
        var id := String(lineage["id"])
        if not previous.is_empty() and id <= previous:
            return _failure("SUMMARY_LINEAGE_ORDER_INVALID")
        previous = id
        if typeof(lineage.get("biomass_kg")) != TYPE_FLOAT or not is_finite(float(lineage["biomass_kg"])) or float(lineage["biomass_kg"]) < 0.0:
            return _failure("SUMMARY_LINEAGE_BIOMASS_INVALID")
        var mass := float(lineage["biomass_kg"])
        sum += mass
        if dominant_id.is_empty() or mass > dominant_mass or (mass == dominant_mass and id < dominant_id):
            dominant_id = id
            dominant_mass = mass
    if sum != float(summary["total_biomass_kg"]):
        return _failure("SUMMARY_TOTAL_BIOMASS_MISMATCH")
    if String(summary["dominant_lineage_id"]) != dominant_id or float(summary["dominant_lineage_biomass_kg"]) != dominant_mass:
        return _failure("SUMMARY_DOMINANT_DERIVED_MISMATCH")
    var expected := compute_summary_hash(summary)
    if String(summary.get("summary_hash", "")) != expected or not _is_hash(expected):
        return _failure("SUMMARY_HASH_MISMATCH")
    return {"success": true, "error": "", "summary_hash": expected}

static func compute_summary_hash(summary: Dictionary) -> String:
    var lineages := []
    if typeof(summary.get("lineage_biomass")) == TYPE_ARRAY:
        for value in Array(summary["lineage_biomass"]):
            if typeof(value) == TYPE_DICTIONARY:
                var lineage: Dictionary = value
                lineages.append([String(lineage.get("id", "")), lineage.get("biomass_kg", NAN)])
    var canonical := [
        String(summary.get("schema", "")), String(summary.get("version", "")),
        String(summary.get("parent_p4_5_aggregate", "")), String(summary.get("region_id", "")),
        String(summary.get("owner_server_id", "")), summary.get("ownership_epoch", -1),
        String(summary.get("source_ownership_hash", "")), String(summary.get("source_snapshot_hash", "")),
        summary.get("ecology_generation", -1), summary.get("last_simulated_world_time", NAN),
        summary.get("observed_target_world_time", NAN), summary.get("fully_caught_up", false),
        summary.get("remaining_due_steps", -1), summary.get("patch_count", -1), lineages,
        summary.get("total_biomass_kg", NAN), String(summary.get("dominant_lineage_id", "")),
        summary.get("dominant_lineage_biomass_kg", NAN),
    ]
    return JSON.stringify(canonical).sha256_text()

static func project_interest(ownership_states: Array, requested_region_ids: Array) -> Dictionary:
    var requested := _canonical_region_ids(requested_region_ids)
    if requested.is_empty() and not requested_region_ids.is_empty():
        return {}
    var by_id := {}
    for state_value in ownership_states:
        if typeof(state_value) != TYPE_DICTIONARY:
            return {}
        var state: Dictionary = state_value
        if not bool(RegionOwnership.validate_ownership(state).get("success", false)):
            return {}
        var region_id := String(state.get("region_id", ""))
        if by_id.has(region_id):
            return {}
        by_id[region_id] = state
    var summaries := []
    var missing := []
    for region_id in requested:
        if not by_id.has(region_id):
            missing.append(region_id)
            continue
        var summary := build_region_summary(Dictionary(by_id[region_id]))
        if summary.is_empty():
            return {}
        summaries.append(summary)
    var projection := {
        "schema": INTEREST_SCHEMA,
        "version": INTEREST_VERSION,
        "parent_p4_5_aggregate": PARENT_P4_5_AGGREGATE,
        "requested_region_ids": requested,
        "summaries": summaries,
        "missing_region_ids": missing,
        "summary_count": summaries.size(),
        "missing_count": missing.size(),
    }
    projection["interest_hash"] = compute_interest_hash(projection)
    if not bool(validate_interest_projection(projection).get("success", false)):
        return {}
    return projection

static func validate_interest_projection(projection: Dictionary) -> Dictionary:
    if not _exact_fields(projection, INTEREST_FIELDS):
        return _failure("INTEREST_FIELDS_MISMATCH")
    if String(projection.get("schema", "")) != INTEREST_SCHEMA or String(projection.get("version", "")) != INTEREST_VERSION:
        return _failure("INTEREST_SCHEMA_OR_VERSION_MISMATCH")
    if String(projection.get("parent_p4_5_aggregate", "")) != PARENT_P4_5_AGGREGATE:
        return _failure("INTEREST_PARENT_P4_5_MISMATCH")
    if typeof(projection.get("requested_region_ids")) != TYPE_ARRAY or typeof(projection.get("summaries")) != TYPE_ARRAY or typeof(projection.get("missing_region_ids")) != TYPE_ARRAY:
        return _failure("INTEREST_COLLECTION_TYPE_INVALID")
    var requested: Array = projection["requested_region_ids"]
    if _canonical_region_ids(requested) != requested:
        return _failure("INTEREST_REQUEST_ORDER_INVALID")
    var seen := {}
    var summary_ids := []
    for value in Array(projection["summaries"]):
        if typeof(value) != TYPE_DICTIONARY or not bool(validate_region_summary(Dictionary(value)).get("success", false)):
            return _failure("INTEREST_SUMMARY_INVALID")
        var id := String(Dictionary(value)["region_id"])
        if seen.has(id) or not requested.has(id):
            return _failure("INTEREST_SUMMARY_REGION_INVALID")
        seen[id] = true
        summary_ids.append(id)
    if _canonical_region_ids(summary_ids) != summary_ids:
        return _failure("INTEREST_SUMMARY_ORDER_INVALID")
    var missing: Array = projection["missing_region_ids"]
    if _canonical_region_ids(missing) != missing:
        return _failure("INTEREST_MISSING_ORDER_INVALID")
    var expected_missing := []
    for id in requested:
        if not seen.has(id):
            expected_missing.append(id)
    if missing != expected_missing:
        return _failure("INTEREST_MISSING_DERIVED_MISMATCH")
    if typeof(projection.get("summary_count")) != TYPE_INT or int(projection["summary_count"]) != Array(projection["summaries"]).size():
        return _failure("INTEREST_SUMMARY_COUNT_MISMATCH")
    if typeof(projection.get("missing_count")) != TYPE_INT or int(projection["missing_count"]) != missing.size():
        return _failure("INTEREST_MISSING_COUNT_MISMATCH")
    var expected_hash := compute_interest_hash(projection)
    if String(projection.get("interest_hash", "")) != expected_hash or not _is_hash(expected_hash):
        return _failure("INTEREST_HASH_MISMATCH")
    return {"success": true, "error": "", "interest_hash": expected_hash}

static func compute_interest_hash(projection: Dictionary) -> String:
    var summary_hashes := []
    if typeof(projection.get("summaries")) == TYPE_ARRAY:
        for value in Array(projection["summaries"]):
            if typeof(value) == TYPE_DICTIONARY:
                summary_hashes.append(String(Dictionary(value).get("summary_hash", "")))
    var canonical := [
        String(projection.get("schema", "")), String(projection.get("version", "")),
        String(projection.get("parent_p4_5_aggregate", "")), projection.get("requested_region_ids", []),
        summary_hashes, projection.get("missing_region_ids", []), projection.get("summary_count", -1),
        projection.get("missing_count", -1),
    ]
    return JSON.stringify(canonical).sha256_text()

static func accept_client_update(current_summary: Dictionary, incoming_summary: Dictionary) -> Dictionary:
    if not bool(validate_region_summary(incoming_summary).get("success", false)):
        return {}
    if current_summary.is_empty():
        return incoming_summary.duplicate(true)
    if not bool(validate_region_summary(current_summary).get("success", false)):
        return {}
    if String(current_summary["region_id"]) != String(incoming_summary["region_id"]):
        return {}
    var current_epoch := int(current_summary["ownership_epoch"])
    var incoming_epoch := int(incoming_summary["ownership_epoch"])
    if incoming_epoch < current_epoch:
        return {}
    if incoming_epoch > current_epoch:
        return incoming_summary.duplicate(true)
    var current_generation := int(current_summary["ecology_generation"])
    var incoming_generation := int(incoming_summary["ecology_generation"])
    if incoming_generation < current_generation:
        return {}
    if incoming_generation > current_generation:
        return incoming_summary.duplicate(true)
    var current_observed := float(current_summary["observed_target_world_time"])
    var incoming_observed := float(incoming_summary["observed_target_world_time"])
    if incoming_observed < current_observed:
        return {}
    if incoming_observed > current_observed:
        return incoming_summary.duplicate(true)
    if String(current_summary["summary_hash"]) == String(incoming_summary["summary_hash"]):
        return current_summary.duplicate(true)
    return {}

static func _collect_lineages(community: Array) -> Array:
    var totals := {}
    for patch_value in community:
        if typeof(patch_value) != TYPE_DICTIONARY:
            return []
        var patch: Dictionary = patch_value
        if typeof(patch.get("plants")) != TYPE_ARRAY:
            return []
        for plant_value in Array(patch["plants"]):
            if typeof(plant_value) != TYPE_DICTIONARY:
                return []
            var plant: Dictionary = plant_value
            if typeof(plant.get("id")) != TYPE_STRING or String(plant["id"]).is_empty():
                return []
            if typeof(plant.get("biomass_kg")) != TYPE_FLOAT and typeof(plant.get("biomass_kg")) != TYPE_INT:
                return []
            var mass := float(plant["biomass_kg"])
            if not is_finite(mass) or mass < 0.0:
                return []
            var id := String(plant["id"])
            totals[id] = float(totals.get(id, 0.0)) + mass
    var ids := totals.keys()
    ids.sort()
    var result := []
    for id_value in ids:
        var id := String(id_value)
        result.append({"id": id, "biomass_kg": float(totals[id])})
    return result

static func _canonical_region_ids(values: Array) -> Array:
    var seen := {}
    for value in values:
        if typeof(value) != TYPE_STRING:
            return []
        var id := String(value)
        if id.is_empty() or id != id.strip_edges():
            return []
        seen[id] = true
    var result := seen.keys()
    result.sort()
    return result

static func _is_hash(value: String) -> bool:
    if value.length() != 64:
        return false
    for index in range(value.length()):
        var code := value.unicode_at(index)
        if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
            return false
    return true

static func _exact_fields(value: Dictionary, expected: Array) -> bool:
    if value.size() != expected.size():
        return false
    for key in expected:
        if not value.has(key):
            return false
    return true

static func _failure(error: String) -> Dictionary:
    return {"success": false, "error": "ECO_P4_6_" + error}
