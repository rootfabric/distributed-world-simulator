extends RefCounted

## SM1.7 deterministic fault-injection helper for the existing SM1.2 coordinator.
##
## This helper owns no canonical state. It only constructs deterministic test
## evidence around the already-existing SM1 coordinator and SM1.6 process
## workers. Production ownership, Item Graph, Construction, replay and
## persistence remain with their existing owners.

const Coordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const SCHEMA := "distributed_world_simulator.v0_sm1_7_fault_trace.v1"

var trace: Array[Dictionary] = []
var _sequence := 0


func fresh_coordinator(initial_authority_id: String = Support.AUTHORITY_A, initial_epoch: int = 1):
	var coordinator = Coordinator.new()
	var configured: Dictionary = coordinator.configure(initial_authority_id, initial_epoch, Support.canonical_state())
	record("CONFIGURE", "", coordinator.snapshot(), configured)
	return coordinator


func warm_report(transfer_id: String, state: Dictionary = {}) -> Dictionary:
	var candidate := state.duplicate(true) if not state.is_empty() else Support.canonical_state()
	return {
		"transfer_id": transfer_id,
		"mode": "SHADOW",
		"checksum": Support.checksum(candidate),
		"private_canonical_truth": false,
		"persistence_owner": "EXTERNAL",
		"counters": {"write_attempts": 1, "write_rejections": 1},
	}


func begin_to_warm(coordinator, transfer_id: String, source: String, target: String, source_epoch: int) -> Dictionary:
	var begun: Dictionary = coordinator.begin_transfer(transfer_id, source, target, source_epoch)
	record("FREEZE", transfer_id, coordinator.snapshot(), begun)
	if not bool(begun.get("success", false)):
		return begun
	var warm: Dictionary = coordinator.validate_warm_target(transfer_id, target, warm_report(transfer_id))
	record("WARM", transfer_id, coordinator.snapshot(), warm)
	return warm


func complete_transfer(coordinator, transfer_id: String, source: String, target: String, source_epoch: int) -> Dictionary:
	var warm := begin_to_warm(coordinator, transfer_id, source, target, source_epoch)
	if not bool(warm.get("success", false)):
		return warm
	var target_epoch := source_epoch + 1
	var committed: Dictionary = coordinator.commit_ownership(transfer_id, source, target, source_epoch, target_epoch)
	record("COMMIT", transfer_id, coordinator.snapshot(), committed)
	if not bool(committed.get("success", false)):
		return committed
	var token := String(committed.get("details", {}).get("commit_token", ""))
	var retired: Dictionary = coordinator.retire_source(transfer_id, source, token)
	record("RETIRE", transfer_id, coordinator.snapshot(), retired)
	if not bool(retired.get("success", false)):
		return retired
	var activated: Dictionary = coordinator.activate_target(transfer_id, target, target_epoch, token)
	record("ACTIVATE", transfer_id, coordinator.snapshot(), activated)
	return activated


func record(message_type: String, transfer_id: String, snapshot: Dictionary, result: Dictionary) -> void:
	_sequence += 1
	trace.append({
		"schema": SCHEMA,
		"seq": _sequence,
		"message_type": message_type,
		"transfer_id": transfer_id,
		"state_after": String(snapshot.get("state", "")),
		"active_authority_id": String(snapshot.get("active_authority_id", "")),
		"authority_epoch": int(snapshot.get("authority_epoch", 0)),
		"success": bool(result.get("success", false)),
		"error_code": String(result.get("error_code", "")),
		"result": String(result.get("details", {}).get("result", "")),
	})


func trace_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"events": trace.duplicate(true),
		"event_count": trace.size(),
	}
