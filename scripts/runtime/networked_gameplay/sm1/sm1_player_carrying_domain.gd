extends RefCounted

## SM1.3 derived Player Carrying Domain.
##
## This adapter owns NO canonical player, replay, Item Graph, Construction or
## persistence truth. It freezes a transfer manifest from current P6 identity
## and durable-operation views, binds that manifest into the WARM checksum used
## by SM1.2's ownership commit, and proves continuity after activation.

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "distributed_world_simulator.v0_sm1_player_carrying_domain.v1"
const MANIFEST_SCHEMA := "distributed_world_simulator.v0_sm1_player_carrying_manifest.v1"
const WARM_SCHEMA := "distributed_world_simulator.v0_sm1_composite_warm_report.v1"

var _registry = null
var _ledger = null
var _closure_adapter = null
var _transfer_coordinator = null
var _prepared: Dictionary = {}
var _completed: Dictionary = {}
var _counters := {
	"captures": 0,
	"prepared": 0,
	"warm_bindings": 0,
	"continuity_passes": 0,
	"aborts": 0,
	"rejections": 0,
}


func configure(p_registry, p_ledger, p_closure_adapter, p_transfer_coordinator) -> Dictionary:
	if p_registry == null or not p_registry.has_method("resolve_by_session"):
		return _reject("SM1_CARRY_INVALID_IDENTITY_REGISTRY")
	if (
		p_ledger == null
		or not p_ledger.has_method("snapshot")
		or not p_ledger.has_method("is_applied")
		or not p_ledger.has_method("is_pending")
	):
		return _reject("SM1_CARRY_INVALID_OPERATION_LEDGER")
	if p_closure_adapter == null or not p_closure_adapter.has_method("build_closure_view"):
		return _reject("SM1_CARRY_INVALID_CLOSURE_ADAPTER")
	if (
		p_transfer_coordinator == null
		or not p_transfer_coordinator.has_method("snapshot")
		or not p_transfer_coordinator.has_method("get_completed_transfer")
	):
		return _reject("SM1_CARRY_INVALID_TRANSFER_COORDINATOR")
	_registry = p_registry
	_ledger = p_ledger
	_closure_adapter = p_closure_adapter
	_transfer_coordinator = p_transfer_coordinator
	return _success({"result": "CONFIGURED"})


func capture_manifest(client_session_id: String, input_sequence: int, last_operation_id: String) -> Dictionary:
	if _registry == null or _ledger == null or _closure_adapter == null:
		return _reject("SM1_CARRY_NOT_CONFIGURED")
	if input_sequence < 0:
		return _reject("SM1_CARRY_INPUT_SEQUENCE_INVALID")
	if last_operation_id.strip_edges().is_empty():
		return _reject("SM1_CARRY_OPERATION_ID_REQUIRED")

	var resolved: Dictionary = _registry.resolve_by_session(client_session_id)
	if not bool(resolved.get("success", false)):
		return _reject("SM1_CARRY_SESSION_UNKNOWN", {"client_session_id": client_session_id})
	var binding: Dictionary = Dictionary(resolved.get("details", {}).get("binding", {}))
	var logical_player_id := String(binding.get("logical_player_id", ""))
	var player_entity_id := String(binding.get("player_entity_id", ""))
	if logical_player_id.is_empty() or player_entity_id.is_empty():
		return _reject("SM1_CARRY_IDENTITY_INVALID")
	if not _ledger.is_applied(logical_player_id, last_operation_id):
		return _reject("SM1_CARRY_LAST_OPERATION_NOT_APPLIED", {"operation_id": last_operation_id})

	var pending: Dictionary = Dictionary(_ledger.snapshot().get("pending", {}))
	for key_value in pending.keys():
		var full_key := String(key_value)
		if full_key.begins_with(logical_player_id + "|"):
			return _reject("SM1_CARRY_OPERATION_PENDING_AT_FREEZE", {"operation_key": full_key})

	var closure_result: Dictionary = _closure_adapter.build_closure_view(logical_player_id)
	if not bool(closure_result.get("success", false)):
		return _reject("SM1_CARRY_CLOSURE_BUILD_FAILED")
	var closure_view: Dictionary = Dictionary(closure_result.get("details", {}).get("view", {})).duplicate(true)
	var manifest := {
		"schema": MANIFEST_SCHEMA,
		"logical_player_id": logical_player_id,
		"player_entity_id": player_entity_id,
		"identity_binding_revision": int(binding.get("binding_revision", 0)),
		"last_input_sequence": input_sequence,
		"last_operation_id": last_operation_id,
		"closure_view": closure_view,
		"canonical_identity_owner": "networked-gameplay/player-ownership",
		"canonical_replay_owner": "replay/m6-durable-replay",
		"canonical_input_owner": "nx/input-sequence",
		"derived_only": true,
		"private_canonical_truth": false,
	}
	manifest["manifest_checksum"] = _manifest_checksum(manifest)
	_counters["captures"] = int(_counters["captures"]) + 1
	return _success({"manifest": manifest})


func prepare_transfer(transfer_id: String, client_session_id: String, input_sequence: int, last_operation_id: String) -> Dictionary:
	if transfer_id.strip_edges().is_empty():
		return _reject("SM1_CARRY_TRANSFER_ID_REQUIRED")
	if _prepared.has(transfer_id) or _completed.has(transfer_id):
		return _reject("SM1_CARRY_TRANSFER_ALREADY_TRACKED", {"transfer_id": transfer_id})

	# Transfer manifests are valid only after the source writer is frozen. This
	# closes the capture-before-freeze race: no client command may be accepted
	# between the last observed OperationId/input watermark and the manifest.
	var freeze_before: Dictionary = _source_freeze_proof(transfer_id)
	if not bool(freeze_before.get("success", false)):
		return freeze_before
	var transfer_before: Dictionary = Dictionary(freeze_before.get("details", {}).get("transfer", {}))

	var captured: Dictionary = capture_manifest(client_session_id, input_sequence, last_operation_id)
	if not bool(captured.get("success", false)):
		return captured

	var freeze_after: Dictionary = _source_freeze_proof(transfer_id)
	if not bool(freeze_after.get("success", false)):
		return freeze_after
	var transfer_after: Dictionary = Dictionary(freeze_after.get("details", {}).get("transfer", {}))
	if NetworkUtils.payload_hash(transfer_before) != NetworkUtils.payload_hash(transfer_after):
		return _reject("SM1_CARRY_FREEZE_CHANGED_DURING_CAPTURE")

	var manifest: Dictionary = Dictionary(captured.get("details", {}).get("manifest", {})).duplicate(true)
	manifest["transfer_id"] = transfer_id
	manifest["source_authority_id"] = String(transfer_before.get("source_authority_id", ""))
	manifest["target_authority_id"] = String(transfer_before.get("target_authority_id", ""))
	manifest["source_epoch"] = int(transfer_before.get("source_epoch", 0))
	manifest["target_epoch"] = int(transfer_before.get("target_epoch", 0))
	manifest["captured_after_source_freeze"] = true
	manifest["manifest_checksum"] = _manifest_checksum(manifest)
	_prepared[transfer_id] = {
		"manifest": manifest,
		"composite_warm_checksum": "",
	}
	_counters["prepared"] = int(_counters["prepared"]) + 1
	return _success({
		"result": "PLAYER_CARRY_PREPARED",
		"transfer_id": transfer_id,
		"manifest": manifest.duplicate(true),
	})


## Build the first SM1 WARM layer over the accepted P6 SHADOW report. Later
## derived layers (SM1.5 world continuity) may wrap this checksum, but they must
## retain an explicit previous_warm_checksum edge so this manifest can still be
## proven to participate in the final commit chain.
func build_composite_warm_report(transfer_id: String, p6_shadow_report: Dictionary) -> Dictionary:
	if not _prepared.has(transfer_id):
		return _reject("SM1_CARRY_TRANSFER_NOT_PREPARED", {"transfer_id": transfer_id})
	if String(p6_shadow_report.get("mode", "")) != "SHADOW":
		return _reject("SM1_CARRY_WARM_NOT_SHADOW")
	var p6_checksum := String(p6_shadow_report.get("checksum", ""))
	if p6_checksum.is_empty():
		return _reject("SM1_CARRY_WARM_CHECKSUM_REQUIRED")
	if bool(p6_shadow_report.get("private_canonical_truth", true)):
		return _reject("SM1_CARRY_WARM_PRIVATE_TRUTH_FORBIDDEN")
	if String(p6_shadow_report.get("persistence_owner", "")) != "EXTERNAL":
		return _reject("SM1_CARRY_WARM_PERSISTENCE_OWNER_INVALID")

	var record: Dictionary = Dictionary(_prepared[transfer_id])
	var manifest: Dictionary = Dictionary(record.get("manifest", {}))
	var manifest_checksum := String(manifest.get("manifest_checksum", ""))
	if manifest_checksum.is_empty() or manifest_checksum != _manifest_checksum(manifest):
		return _reject("SM1_CARRY_MANIFEST_CHECKSUM_INVALID")
	var composite_payload := {
		"schema": WARM_SCHEMA,
		"transfer_id": transfer_id,
		"p6_shadow_checksum": p6_checksum,
		"carrying_manifest_checksum": manifest_checksum,
	}
	var composite_checksum := NetworkUtils.payload_hash(composite_payload)
	if composite_checksum.is_empty():
		return _reject("SM1_CARRY_COMPOSITE_CHECKSUM_FAILED")

	var report := p6_shadow_report.duplicate(true)
	report["schema"] = WARM_SCHEMA
	report["checksum"] = composite_checksum
	report["previous_warm_checksum"] = p6_checksum
	report["p6_shadow_checksum"] = p6_checksum
	report["carrying_manifest_checksum"] = manifest_checksum
	report["transfer_id"] = transfer_id
	report["derived_only"] = true
	record["composite_warm_checksum"] = composite_checksum
	_prepared[transfer_id] = record
	_counters["warm_bindings"] = int(_counters["warm_bindings"]) + 1
	return _success({"result": "PLAYER_CARRY_BOUND_TO_WARM", "warm_report": report})


func validate_after_activation(
	transfer_id: String,
	client_session_id: String,
	input_sequence: int,
	last_operation_id: String,
	transfer_coordinator
) -> Dictionary:
	if not _prepared.has(transfer_id):
		return _reject("SM1_CARRY_TRANSFER_NOT_PREPARED", {"transfer_id": transfer_id})
	if transfer_coordinator == null or not transfer_coordinator.has_method("get_completed_transfer") or not transfer_coordinator.has_method("snapshot"):
		return _reject("SM1_CARRY_INVALID_TRANSFER_COORDINATOR")
	var completed_transfer: Dictionary = transfer_coordinator.get_completed_transfer(transfer_id)
	if completed_transfer.is_empty():
		return _reject("SM1_CARRY_TRANSFER_NOT_COMPLETED", {"transfer_id": transfer_id})
	var coordinator_snapshot: Dictionary = transfer_coordinator.snapshot()
	if String(coordinator_snapshot.get("state", "")) != "ACTIVE":
		return _reject("SM1_CARRY_TARGET_NOT_ACTIVE")
	if String(coordinator_snapshot.get("active_authority_id", "")) != String(completed_transfer.get("target_authority_id", "")) \
			or int(coordinator_snapshot.get("authority_epoch", 0)) != int(completed_transfer.get("target_epoch", 0)):
		return _reject("SM1_CARRY_COMPLETED_TARGET_NOT_CURRENT")

	var current_result: Dictionary = capture_manifest(client_session_id, input_sequence, last_operation_id)
	if not bool(current_result.get("success", false)):
		return current_result
	var after: Dictionary = Dictionary(current_result.get("details", {}).get("manifest", {}))
	var record: Dictionary = Dictionary(_prepared[transfer_id])
	var before: Dictionary = Dictionary(record.get("manifest", {}))
	var continuity := _validate_continuity(before, after)
	if not bool(continuity.get("success", false)):
		return continuity

	var player_warm_checksum := String(record.get("composite_warm_checksum", ""))
	if player_warm_checksum.is_empty():
		return _reject("SM1_CARRY_WARM_NOT_BOUND")
	var committed_warm_checksum := String(completed_transfer.get("warm_checksum", ""))
	if committed_warm_checksum.is_empty():
		return _reject("SM1_CARRY_COMMIT_WARM_CHECKSUM_MISSING")

	# Direct SM1.3 composition ends at player_warm_checksum. SM1.5 may wrap one
	# additional world-state layer; in that case prove the retained final report
	# points directly back to this exact player checksum and manifest checksum.
	var warm_chain_mode := "DIRECT_PLAYER_COMMIT"
	if committed_warm_checksum != player_warm_checksum:
		var final_warm_report: Dictionary = Dictionary(completed_transfer.get("warm_report", {}))
		if final_warm_report.is_empty() \
				or String(final_warm_report.get("checksum", "")) != committed_warm_checksum \
				or String(final_warm_report.get("transfer_id", "")) != transfer_id \
				or String(final_warm_report.get("previous_warm_checksum", "")) != player_warm_checksum \
				or String(final_warm_report.get("carrying_manifest_checksum", "")) != String(before.get("manifest_checksum", "")):
			return _reject("SM1_CARRY_COMMIT_WARM_CHAIN_INVALID")
		warm_chain_mode = "DOWNSTREAM_LAYER_BOUND"

	var carried_player: Dictionary = Dictionary(completed_transfer.get("player_snapshot", {}))
	if String(carried_player.get("logical_player_id", "")) != String(before.get("logical_player_id", "")) \
			or String(carried_player.get("player_entity_id", "")) != String(before.get("player_entity_id", "")):
		return _reject("SM1_CARRY_COORDINATOR_IDENTITY_DIVERGED")

	var completed_record := {
		"before": before.duplicate(true),
		"after": after.duplicate(true),
		"composite_warm_checksum": player_warm_checksum,
		"committed_warm_checksum": committed_warm_checksum,
		"warm_chain_mode": warm_chain_mode,
		"target_authority_id": String(completed_transfer.get("target_authority_id", "")),
		"target_epoch": int(completed_transfer.get("target_epoch", 0)),
	}
	_completed[transfer_id] = completed_record
	_prepared.erase(transfer_id)
	_counters["continuity_passes"] = int(_counters["continuity_passes"]) + 1
	return _success({
		"result": "PLAYER_CARRY_CONTINUITY_PASS",
		"transfer_id": transfer_id,
		"before": before.duplicate(true),
		"after": after.duplicate(true),
		"warm_chain_mode": warm_chain_mode,
	})


func abort_transfer(transfer_id: String) -> Dictionary:
	if not _prepared.has(transfer_id):
		return _reject("SM1_CARRY_TRANSFER_NOT_PREPARED", {"transfer_id": transfer_id})
	_prepared.erase(transfer_id)
	_counters["aborts"] = int(_counters["aborts"]) + 1
	return _success({"result": "PLAYER_CARRY_ABORTED", "transfer_id": transfer_id})


func get_completed(transfer_id: String) -> Dictionary:
	if not _completed.has(transfer_id):
		return {}
	return Dictionary(_completed[transfer_id]).duplicate(true)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"prepared_count": _prepared.size(),
		"completed_count": _completed.size(),
		"canonical_identity_owner": "networked-gameplay/player-ownership",
		"canonical_replay_owner": "replay/m6-durable-replay",
		"canonical_input_owner": "nx/input-sequence",
		"derived_only": true,
		"private_canonical_truth": false,
		"counters": _counters.duplicate(true),
	}


func _source_freeze_proof(transfer_id: String) -> Dictionary:
	if _transfer_coordinator == null or not _transfer_coordinator.has_method("snapshot"):
		return _reject("SM1_CARRY_SOURCE_FREEZE_PROOF_REQUIRED")
	var coordinator_snapshot: Dictionary = _transfer_coordinator.snapshot()
	if String(coordinator_snapshot.get("state", "")) != "SOURCE_FROZEN":
		return _reject("SM1_CARRY_SOURCE_NOT_FROZEN", {"state": String(coordinator_snapshot.get("state", ""))})
	var transfer: Dictionary = Dictionary(coordinator_snapshot.get("transfer", {}))
	if String(transfer.get("transfer_id", "")) != transfer_id:
		return _reject("SM1_CARRY_TRANSFER_COORDINATOR_MISMATCH")
	if String(coordinator_snapshot.get("active_authority_id", "")) != String(transfer.get("source_authority_id", "")) \
			or int(coordinator_snapshot.get("authority_epoch", 0)) != int(transfer.get("source_epoch", 0)):
		return _reject("SM1_CARRY_SOURCE_FREEZE_TUPLE_INVALID")
	return _success({"transfer": transfer.duplicate(true)})


func _validate_continuity(before: Dictionary, after: Dictionary) -> Dictionary:
	if String(before.get("logical_player_id", "")) != String(after.get("logical_player_id", "")):
		return _reject("SM1_CARRY_LOGICAL_PLAYER_CHANGED")
	if String(before.get("player_entity_id", "")) != String(after.get("player_entity_id", "")):
		return _reject("SM1_CARRY_PLAYER_ENTITY_CHANGED")
	if int(before.get("identity_binding_revision", 0)) != int(after.get("identity_binding_revision", 0)):
		return _reject("SM1_CARRY_IDENTITY_BINDING_CHANGED")
	if int(after.get("last_input_sequence", -1)) < int(before.get("last_input_sequence", -1)):
		return _reject("SM1_CARRY_INPUT_SEQUENCE_REGRESSED")

	var before_closure: Dictionary = Dictionary(before.get("closure_view", {}))
	var after_closure: Dictionary = Dictionary(after.get("closure_view", {}))
	var before_ops: Array = Array(before_closure.get("carried_operations", [])).duplicate()
	var after_ops: Array = Array(after_closure.get("carried_operations", [])).duplicate()
	for operation_value in before_ops:
		if not after_ops.has(operation_value):
			return _reject("SM1_CARRY_OPERATION_HISTORY_LOST", {"operation_id": String(operation_value)})
	var frozen_last_operation := String(before.get("last_operation_id", ""))
	if not after_ops.has(frozen_last_operation):
		return _reject("SM1_CARRY_FROZEN_OPERATION_LOST", {"operation_id": frozen_last_operation})
	return _success({"result": "CONTINUITY_VALID"})


func _manifest_checksum(manifest: Dictionary) -> String:
	var payload := manifest.duplicate(true)
	payload.erase("manifest_checksum")
	return NetworkUtils.payload_hash(payload)


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}


func _reject(error_code: String, details: Dictionary = {}) -> Dictionary:
	_counters["rejections"] = int(_counters["rejections"]) + 1
	return {"success": false, "error_code": error_code, "details": details}
