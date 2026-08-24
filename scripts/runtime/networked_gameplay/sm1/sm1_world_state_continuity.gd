extends RefCounted

## SM1.5 canonical world-state continuity proof.
##
## This adapter is deliberately READ ONLY with respect to canonical gameplay
## truth. It samples the existing M4 Item Graph, P4 Construction authority,
## P6 read-only outpost composition, and the existing persistence owner. It
## binds their fingerprints into the WARM checksum consumed by SM1.2 and then
## re-reads the SAME owners after activation to prove no canonical state was
## forked, reset, or silently replaced during the authority pivot.

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ConstructionState = preload("res://scripts/construction/authoritative/construction_authoritative_state.gd")

const SCHEMA := "distributed_world_simulator.v0_sm1_world_state_continuity.v1"
const MANIFEST_SCHEMA := "distributed_world_simulator.v0_sm1_world_state_manifest.v1"
const WARM_SCHEMA := "distributed_world_simulator.v0_sm1_world_bound_warm_report.v1"
const EXISTING_PERSISTENCE_OWNER := "persistence/authoritative-recovery"

var _item_graph_persistence = null
var _construction_authority = null
var _p6_persistence_owner = null
var _p6_projection = null
var _prepared: Dictionary = {}
var _completed: Dictionary = {}
var _counters := {
	"captures": 0,
	"warm_bindings": 0,
	"continuity_passes": 0,
	"aborts": 0,
	"rejections": 0,
}


func configure(item_graph_persistence, construction_authority, p6_persistence_owner, p6_projection) -> Dictionary:
	if item_graph_persistence == null \
			or not item_graph_persistence.has_method("create_snapshot_result") \
			or not item_graph_persistence.has_method("validate_snapshot"):
		return _reject("SM1_WORLD_INVALID_ITEM_GRAPH_PORT")
	if construction_authority == null or not construction_authority.has_method("export_state"):
		return _reject("SM1_WORLD_INVALID_CONSTRUCTION_PORT")
	if p6_persistence_owner == null or not p6_persistence_owner.has_method("get_report"):
		return _reject("SM1_WORLD_INVALID_PERSISTENCE_PORT")
	if p6_projection == null \
			or not p6_projection.has_method("serialize") \
			or not p6_projection.has_method("compute_checksum") \
			or not p6_projection.has_method("get_source"):
		return _reject("SM1_WORLD_INVALID_OUTPOST_PROJECTION")
	_item_graph_persistence = item_graph_persistence
	_construction_authority = construction_authority
	_p6_persistence_owner = p6_persistence_owner
	_p6_projection = p6_projection
	var probe := _capture_live_state()
	if not bool(probe.get("success", false)):
		return probe
	return _success({"result": "CONFIGURED", "owners": _owner_report()})


func prepare_transfer(transfer_id: String) -> Dictionary:
	if transfer_id.strip_edges().is_empty():
		return _reject("SM1_WORLD_TRANSFER_ID_REQUIRED")
	if _prepared.has(transfer_id) or _completed.has(transfer_id):
		return _reject("SM1_WORLD_TRANSFER_ALREADY_TRACKED", {"transfer_id": transfer_id})
	var captured := _capture_live_state()
	if not bool(captured.get("success", false)):
		return captured
	var live: Dictionary = Dictionary(captured.get("details", {}).get("live", {}))
	var manifest := {
		"schema": MANIFEST_SCHEMA,
		"transfer_id": transfer_id,
		"item_graph_fingerprint": String(live.get("item_graph_fingerprint", "")),
		"construction_fingerprint": String(live.get("construction_fingerprint", "")),
		"outpost_projection_checksum": String(live.get("outpost_projection_checksum", "")),
		"persistence_owner_id": String(live.get("persistence_owner_id", "")),
		"item_count": int(live.get("item_count", 0)),
		"container_count": int(live.get("container_count", 0)),
		"construct_count": int(live.get("construct_count", 0)),
		"canonical_item_owner": "item/m4-canonical-item-graph",
		"canonical_construction_owner": "construction/p4-authority",
		"canonical_persistence_owner": EXISTING_PERSISTENCE_OWNER,
		"derived_only": true,
		"private_canonical_truth": false,
	}
	manifest["manifest_checksum"] = _manifest_checksum(manifest)
	_prepared[transfer_id] = {
		"manifest": manifest,
		"canonical_item_graph": Dictionary(live.get("item_graph", {})).duplicate(true),
		"canonical_construction": Dictionary(live.get("construction", {})).duplicate(true),
		"world_bound_warm_checksum": "",
	}
	_counters["captures"] = int(_counters["captures"]) + 1
	return _success({"result": "WORLD_STATE_PREPARED", "manifest": manifest.duplicate(true)})


## Wrap an already valid SM1.3/P6 WARM report. The new checksum commits to the
## previous WARM checksum AND canonical world fingerprints. SM1.2 therefore
## cannot commit a transfer against one player/world closure and activate a
## different one without detection.
func bind_to_warm(transfer_id: String, previous_warm_report: Dictionary) -> Dictionary:
	if not _prepared.has(transfer_id):
		return _reject("SM1_WORLD_TRANSFER_NOT_PREPARED", {"transfer_id": transfer_id})
	if String(previous_warm_report.get("mode", "")) != "SHADOW":
		return _reject("SM1_WORLD_WARM_NOT_SHADOW")
	if bool(previous_warm_report.get("private_canonical_truth", true)):
		return _reject("SM1_WORLD_WARM_PRIVATE_TRUTH_FORBIDDEN")
	if String(previous_warm_report.get("persistence_owner", "")) != "EXTERNAL":
		return _reject("SM1_WORLD_WARM_PERSISTENCE_OWNER_INVALID")
	var previous_checksum := String(previous_warm_report.get("checksum", ""))
	if previous_checksum.is_empty():
		return _reject("SM1_WORLD_PREVIOUS_WARM_CHECKSUM_REQUIRED")
	var record: Dictionary = Dictionary(_prepared[transfer_id])
	var manifest: Dictionary = Dictionary(record.get("manifest", {}))
	var manifest_checksum := String(manifest.get("manifest_checksum", ""))
	if manifest_checksum.is_empty() or manifest_checksum != _manifest_checksum(manifest):
		return _reject("SM1_WORLD_MANIFEST_CHECKSUM_INVALID")
	var payload := {
		"schema": WARM_SCHEMA,
		"transfer_id": transfer_id,
		"previous_warm_checksum": previous_checksum,
		"world_manifest_checksum": manifest_checksum,
	}
	var checksum := NetworkUtils.payload_hash(payload)
	if checksum.is_empty():
		return _reject("SM1_WORLD_WARM_BINDING_HASH_FAILED")
	var report := previous_warm_report.duplicate(true)
	report["schema"] = WARM_SCHEMA
	report["checksum"] = checksum
	report["previous_warm_checksum"] = previous_checksum
	report["world_manifest_checksum"] = manifest_checksum
	report["item_graph_fingerprint"] = String(manifest.get("item_graph_fingerprint", ""))
	report["construction_fingerprint"] = String(manifest.get("construction_fingerprint", ""))
	report["outpost_projection_checksum"] = String(manifest.get("outpost_projection_checksum", ""))
	report["derived_only"] = true
	record["world_bound_warm_checksum"] = checksum
	_prepared[transfer_id] = record
	_counters["warm_bindings"] = int(_counters["warm_bindings"]) + 1
	return _success({"result": "WORLD_STATE_BOUND_TO_WARM", "warm_report": report})


func validate_after_activation(transfer_id: String, transfer_coordinator) -> Dictionary:
	if not _prepared.has(transfer_id):
		return _reject("SM1_WORLD_TRANSFER_NOT_PREPARED", {"transfer_id": transfer_id})
	if transfer_coordinator == null \
			or not transfer_coordinator.has_method("get_completed_transfer") \
			or not transfer_coordinator.has_method("snapshot"):
		return _reject("SM1_WORLD_INVALID_TRANSFER_COORDINATOR")
	var completed_transfer: Dictionary = transfer_coordinator.get_completed_transfer(transfer_id)
	if completed_transfer.is_empty():
		return _reject("SM1_WORLD_TRANSFER_NOT_COMPLETED")
	var coordinator_snapshot: Dictionary = transfer_coordinator.snapshot()
	if String(coordinator_snapshot.get("state", "")) != "ACTIVE":
		return _reject("SM1_WORLD_TARGET_NOT_ACTIVE")
	var record: Dictionary = Dictionary(_prepared[transfer_id])
	var expected_checksum := String(record.get("world_bound_warm_checksum", ""))
	if expected_checksum.is_empty():
		return _reject("SM1_WORLD_WARM_NOT_BOUND")
	if String(completed_transfer.get("warm_checksum", "")) != expected_checksum:
		return _reject("SM1_WORLD_COMMIT_NOT_BOUND_TO_MANIFEST")

	var current_result := _capture_live_state()
	if not bool(current_result.get("success", false)):
		return current_result
	var current: Dictionary = Dictionary(current_result.get("details", {}).get("live", {}))
	var before_manifest: Dictionary = Dictionary(record.get("manifest", {}))
	if String(current.get("item_graph_fingerprint", "")) != String(before_manifest.get("item_graph_fingerprint", "")):
		return _reject("SM1_WORLD_ITEM_GRAPH_DIVERGED")
	if String(current.get("construction_fingerprint", "")) != String(before_manifest.get("construction_fingerprint", "")):
		return _reject("SM1_WORLD_CONSTRUCTION_DIVERGED")
	if String(current.get("outpost_projection_checksum", "")) != String(before_manifest.get("outpost_projection_checksum", "")):
		return _reject("SM1_WORLD_OUTPOST_PROJECTION_DIVERGED")
	if String(current.get("persistence_owner_id", "")) != String(before_manifest.get("persistence_owner_id", "")):
		return _reject("SM1_WORLD_PERSISTENCE_OWNER_CHANGED")
	if NetworkUtils.canonical_json(current.get("item_graph", {})) != NetworkUtils.canonical_json(record.get("canonical_item_graph", {})):
		return _reject("SM1_WORLD_ITEM_GRAPH_CANONICAL_BYTES_CHANGED")
	if NetworkUtils.canonical_json(current.get("construction", {})) != NetworkUtils.canonical_json(record.get("canonical_construction", {})):
		return _reject("SM1_WORLD_CONSTRUCTION_CANONICAL_BYTES_CHANGED")

	var result := {
		"transfer_id": transfer_id,
		"target_authority_id": String(completed_transfer.get("target_authority_id", "")),
		"target_epoch": int(completed_transfer.get("target_epoch", 0)),
		"manifest": before_manifest.duplicate(true),
		"item_graph_result": "ITEM_GRAPH_CANONICAL_CONTINUITY_PASS",
		"construction_result": "CONSTRUCTION_CANONICAL_CONTINUITY_PASS",
		"outpost_result": "OUTPOST_PERSISTENCE_COMPOSITION_CONTINUITY_PASS",
	}
	_completed[transfer_id] = result.duplicate(true)
	_prepared.erase(transfer_id)
	_counters["continuity_passes"] = int(_counters["continuity_passes"]) + 1
	return _success({
		"result": "SM1_5_CANONICAL_WORLD_STATE_CONTINUITY_PASS",
		"details": result,
	})


func abort_transfer(transfer_id: String) -> Dictionary:
	if not _prepared.has(transfer_id):
		return _reject("SM1_WORLD_TRANSFER_NOT_PREPARED", {"transfer_id": transfer_id})
	_prepared.erase(transfer_id)
	_counters["aborts"] = int(_counters["aborts"]) + 1
	return _success({"result": "WORLD_STATE_TRANSFER_ABORTED", "transfer_id": transfer_id})


func get_completed(transfer_id: String) -> Dictionary:
	if not _completed.has(transfer_id):
		return {}
	return Dictionary(_completed[transfer_id]).duplicate(true)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"prepared_count": _prepared.size(),
		"completed_count": _completed.size(),
		"owners": _owner_report(),
		"derived_only": true,
		"private_item_graph": false,
		"private_construction_truth": false,
		"private_persistence_owner": false,
		"private_outpost_truth": false,
		"counters": _counters.duplicate(true),
	}


func _capture_live_state() -> Dictionary:
	if _item_graph_persistence == null or _construction_authority == null or _p6_persistence_owner == null or _p6_projection == null:
		return _reject("SM1_WORLD_NOT_CONFIGURED")
	var item_result: Dictionary = _item_graph_persistence.create_snapshot_result({})
	if not bool(item_result.get("success", false)):
		return _reject("SM1_WORLD_ITEM_GRAPH_SNAPSHOT_FAILED", {"cause": item_result})
	var item_snapshot: Dictionary = Dictionary(item_result.get("snapshot", {})).duplicate(true)
	var item_validation: Dictionary = _item_graph_persistence.validate_snapshot(item_snapshot)
	if not bool(item_validation.get("success", false)):
		return _reject("SM1_WORLD_ITEM_GRAPH_SNAPSHOT_INVALID", {"cause": item_validation})
	# Metadata is transport/persistence bookkeeping, not canonical Item Graph
	# gameplay truth. Remove it from the continuity fingerprint to avoid false
	# divergence from unrelated save annotations.
	var item_canonical := item_snapshot.duplicate(true)
	item_canonical["metadata"] = {}
	var item_fingerprint := NetworkUtils.payload_hash(item_canonical)

	var construction_snapshot: Dictionary = _construction_authority.export_state()
	var construction_validation: Dictionary = ConstructionState.validate(construction_snapshot)
	if not bool(construction_validation.get("success", false)):
		return _reject("SM1_WORLD_CONSTRUCTION_SNAPSHOT_INVALID", {"cause": construction_validation})
	var construction_fingerprint := NetworkUtils.payload_hash(construction_snapshot)

	var persistence_report: Dictionary = _p6_persistence_owner.get_report()
	if bool(persistence_report.get("private_persistence_owner", true)):
		return _reject("SM1_WORLD_PRIVATE_PERSISTENCE_OWNER_FORBIDDEN")
	var persistence_owner_id := String(persistence_report.get("existing_persistence_owner", ""))
	if persistence_owner_id != EXISTING_PERSISTENCE_OWNER:
		return _reject("SM1_WORLD_PERSISTENCE_OWNER_MISMATCH", {"owner": persistence_owner_id})

	var projection_serialized: Dictionary = _p6_projection.serialize()
	var projection_checksum := String(_p6_projection.compute_checksum())
	if projection_checksum.is_empty() or String(projection_serialized.get("checksum", "")) != projection_checksum:
		return _reject("SM1_WORLD_OUTPOST_PROJECTION_INVALID")
	# Prove that the read model references the same canonical source snapshots
	# sampled above. It remains evidence only and cannot become a truth owner.
	var projection_item: Dictionary = _p6_projection.get_source("item_graph")
	var projection_construction: Dictionary = _p6_projection.get_source("construction")
	if NetworkUtils.payload_hash(projection_item) != item_fingerprint:
		return _reject("SM1_WORLD_OUTPOST_ITEM_SOURCE_DIVERGED")
	if NetworkUtils.payload_hash(projection_construction) != construction_fingerprint:
		return _reject("SM1_WORLD_OUTPOST_CONSTRUCTION_SOURCE_DIVERGED")

	return _success({"live": {
		"item_graph": item_canonical,
		"construction": construction_snapshot.duplicate(true),
		"item_graph_fingerprint": item_fingerprint,
		"construction_fingerprint": construction_fingerprint,
		"outpost_projection_checksum": projection_checksum,
		"persistence_owner_id": persistence_owner_id,
		"item_count": int(Dictionary(item_canonical.get("items", {})).get("items", []).size()) if item_canonical.get("items", {}) is Dictionary else 0,
		"container_count": int(Dictionary(item_canonical.get("containers", {})).get("containers", []).size()) if item_canonical.get("containers", {}) is Dictionary else 0,
		"construct_count": int(Dictionary(construction_snapshot.get("construct_store", {})).get("constructs", []).size()) if construction_snapshot.get("construct_store", {}) is Dictionary else 0,
	}})


func _owner_report() -> Dictionary:
	return {
		"item_graph": "item/m4-canonical-item-graph",
		"construction": "construction/p4-authority",
		"persistence": EXISTING_PERSISTENCE_OWNER,
		"outpost_projection": "p6/read-only-composition",
	}


func _manifest_checksum(manifest: Dictionary) -> String:
	var payload := manifest.duplicate(true)
	payload.erase("manifest_checksum")
	return NetworkUtils.payload_hash(payload)


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}


func _reject(error_code: String, details: Dictionary = {}) -> Dictionary:
	_counters["rejections"] = int(_counters["rejections"]) + 1
	return {"success": false, "error_code": error_code, "details": details}
