extends RefCounted

const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")

const VALIDATOR_ID: String = "validator/test-item-location-conservation"


func get_validator_id() -> String:
	return VALIDATOR_ID


func validate_transaction(_current_aggregates: Dictionary, staged_aggregates: Dictionary, _batch: Dictionary) -> Dictionary:
	var containers: Dictionary = {}
	var items: Dictionary = {}
	for aggregate_id in staged_aggregates:
		var snapshot = staged_aggregates[aggregate_id]
		if typeof(snapshot) != TYPE_DICTIONARY or typeof(snapshot.get("state")) != TYPE_DICTIONARY:
			return TxUtilsScript.failure("INVALID_CONSERVATION_SNAPSHOT")
		var state: Dictionary = snapshot["state"]
		match String(state.get("role", "")):
			"CONTAINER": containers[String(aggregate_id)] = state
			"ITEM": items[String(aggregate_id)] = state
	for item_id in items:
		var item_state: Dictionary = items[item_id]
		var container_id: String = String(item_state.get("container_id", ""))
		if container_id.is_empty():
			continue
		if not containers.has(container_id):
			return TxUtilsScript.failure("ITEM_CONTAINER_NOT_FOUND", {"item_id": item_id, "container_id": container_id})
		if not bool(containers[container_id].get("members_by_id", {}).get(item_id, false)):
			return TxUtilsScript.failure("ITEM_CONTAINER_BACK_REFERENCE_MISSING", {"item_id": item_id, "container_id": container_id})
	for container_id in containers:
		var members: Dictionary = containers[container_id].get("members_by_id", {})
		for item_id in members:
			if not items.has(item_id):
				return TxUtilsScript.failure("CONTAINER_ITEM_NOT_FOUND", {"item_id": item_id, "container_id": container_id})
			if String(items[item_id].get("container_id", "")) != String(container_id):
				return TxUtilsScript.failure("CONTAINER_ITEM_FORWARD_REFERENCE_MISMATCH", {"item_id": item_id, "container_id": container_id})
	return TxUtilsScript.success()
