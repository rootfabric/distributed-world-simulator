extends RefCounted

const TicketScript = preload("res://scripts/network/contracts/handoff_ticket.gd")
const StateMachineScript = preload("res://scripts/network/handoff/handoff_state_machine.gd")
const AggregateScript = preload("res://scripts/simulation/entities/world_entity_aggregate.gd")

var aggregate
var machine


func setup(aggregate_value, ticket_value: Dictionary) -> Dictionary:
	if aggregate_value == null or not aggregate_value is Object:
		return _failure("INVALID_AGGREGATE")
	if aggregate_value.get_script() != AggregateScript:
		return _failure("UNSUPPORTED_AGGREGATE_TYPE")
	for method_name in ["to_snapshot", "setup_from_snapshot", "transfer_authority"]:
		if not aggregate_value.has_method(method_name):
			return _failure("INVALID_AGGREGATE")
	var aggregate_snapshot = aggregate_value.call("to_snapshot")
	if typeof(aggregate_snapshot) != TYPE_DICTIONARY:
		return _failure("INVALID_AGGREGATE")
	var aggregate_validator = AggregateScript.new()
	if not bool(aggregate_validator.validate_snapshot_payload(aggregate_snapshot).get("success", false)):
		return _failure("INVALID_AGGREGATE")
	var validation: Dictionary = TicketScript.validate(ticket_value)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_TICKET")))
	if String(aggregate_snapshot["entity_id"]) != String(ticket_value["entity_id"]):
		return _failure("ENTITY_ID_MISMATCH")
	if String(aggregate_snapshot["authority_owner_id"]) != String(ticket_value["source_node_id"]):
		return _failure("NOT_SOURCE_AUTHORITY")
	if int(aggregate_snapshot["authority_epoch"]) != int(ticket_value["source_authority_epoch"]):
		return _failure("STALE_AUTHORITY_EPOCH")
	if int(aggregate_snapshot["state_revision"]) != int(ticket_value["expected_state_revision"]):
		return _failure("REVISION_CONFLICT")
	var next_machine = StateMachineScript.new()
	var setup_result: Dictionary = next_machine.setup(ticket_value)
	if not bool(setup_result.get("success", false)):
		return setup_result
	aggregate = aggregate_value
	machine = next_machine
	return {"success": true}


func transition(next_state: String, context: Dictionary = {}) -> Dictionary:
	if aggregate == null or machine == null:
		return _failure("HANDOFF_NOT_INITIALIZED")
	if next_state != "COMMITTED":
		return machine.transition(next_state, context)
	var prepared: Dictionary = machine.prepare_transition(next_state, context)
	if not bool(prepared.get("success", false)):
		return prepared
	if not bool(prepared.get("changed", false)):
		return machine.commit_prepared(prepared)
	var ticket: Dictionary = prepared["candidate"]
	if String(aggregate.authority_owner_id) != String(ticket["source_node_id"]):
		return _failure("NOT_SOURCE_AUTHORITY")
	if int(aggregate.authority_epoch) != int(ticket["source_authority_epoch"]):
		return _failure("STALE_AUTHORITY_EPOCH")
	if int(aggregate.state_revision) != int(ticket["expected_state_revision"]):
		return _failure("REVISION_CONFLICT")
	var original_snapshot: Dictionary = aggregate.to_snapshot()
	var staged = AggregateScript.new()
	if not staged.setup_from_snapshot(original_snapshot):
		return _failure("AGGREGATE_STAGE_FAILED")
	var transfer: Dictionary = staged.transfer_authority(
		String(ticket["target_node_id"]),
		int(ticket["target_authority_epoch"])
	)
	if not bool(transfer.get("success", false)):
		return transfer
	if not aggregate.setup_from_snapshot(staged.to_snapshot()):
		return _failure("AGGREGATE_COMMIT_FAILED")
	var machine_commit: Dictionary = machine.commit_prepared(prepared)
	if not bool(machine_commit.get("success", false)):
		if not aggregate.setup_from_snapshot(original_snapshot):
			return _failure("AGGREGATE_ROLLBACK_FAILED")
		return machine_commit
	machine_commit["authority_owner_id"] = aggregate.authority_owner_id
	machine_commit["authority_epoch"] = aggregate.authority_epoch
	machine_commit["state_revision"] = aggregate.state_revision
	return machine_commit


func create_result(completed_at_tick: int) -> Dictionary:
	if aggregate == null or machine == null:
		return {}
	return machine.create_result(completed_at_tick, int(aggregate.state_revision))


func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code}
