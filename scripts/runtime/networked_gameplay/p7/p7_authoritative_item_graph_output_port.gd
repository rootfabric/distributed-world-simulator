extends RefCounted

## P7 stateless port over the existing NetworkedGameplayService aggregate.
## The service owns aggregate authoritative revision/tick. The canonical M4 Item
## Graph remains the only inventory/replay owner. This port owns no state.

var _configured := false
var _gameplay_service = null


func configure(gameplay_service) -> Dictionary:
	if _configured:
		return _failure("P7_AUTHORITATIVE_ITEM_GRAPH_PORT_ALREADY_CONFIGURED")
	if gameplay_service == null \
		or not gameplay_service.has_method("get_canonical_item_graph_port") \
		or not gameplay_service.has_method("preflight_canonical_server_output") \
		or not gameplay_service.has_method("apply_canonical_server_output"):
		return _failure("P7_AUTHORITATIVE_GAMEPLAY_OUTPUT_PORT_REQUIRED")
	var graph = gameplay_service.get_canonical_item_graph_port()
	if graph == null \
		or not graph.has_method("create_snapshot") \
		or not graph.has_method("preflight_server_output") \
		or not graph.has_method("apply_server_output"):
		return _failure("P7_CANONICAL_ITEM_GRAPH_REQUIRED")
	_gameplay_service = gameplay_service
	_configured = true
	return _success(contract_report())


func preflight_server_output(
	operation_id: String,
	logical_player_id: String,
	definition_id: String,
	quantity: int,
	source_id: String = ""
) -> Dictionary:
	if not _configured:
		return _failure("P7_AUTHORITATIVE_ITEM_GRAPH_PORT_NOT_CONFIGURED")
	return _gameplay_service.preflight_canonical_server_output(
		operation_id, logical_player_id, definition_id, quantity, source_id
	)


func apply_server_output(
	operation_id: String,
	logical_player_id: String,
	definition_id: String,
	quantity: int,
	source_id: String = ""
) -> Dictionary:
	if not _configured:
		return _failure("P7_AUTHORITATIVE_ITEM_GRAPH_PORT_NOT_CONFIGURED")
	return _gameplay_service.apply_canonical_server_output(
		operation_id, logical_player_id, definition_id, quantity, source_id
	)


func create_snapshot() -> Dictionary:
	if not _configured:
		return {}
	var graph = _gameplay_service.get_canonical_item_graph_port()
	return graph.create_snapshot() if graph != null else {}


func contract_report() -> Dictionary:
	return {
		"configured": _configured,
		"aggregate_authority_owner": "NETWORKED_GAMEPLAY_SERVICE",
		"item_owner": "CANONICAL_ITEM_GRAPH",
		"exactly_once_owner": "CANONICAL_ITEM_GRAPH_REPLAY_LEDGER",
		"canonical_state_owned": false,
		"delivery_receipt_store": false,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
