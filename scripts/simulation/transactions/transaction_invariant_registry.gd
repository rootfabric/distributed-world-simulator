extends RefCounted

const ValidatorPortScript = preload("res://scripts/simulation/transactions/transaction_invariant_validator_port.gd")
const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")

var _validators_by_id: Dictionary = {}
var _configured := false


func setup() -> Dictionary:
	_validators_by_id.clear()
	_configured = true
	return TxUtilsScript.success()


func register_validator(validator) -> Dictionary:
	if not _configured:
		return TxUtilsScript.failure("TRANSACTION_INVARIANT_REGISTRY_NOT_CONFIGURED")
	var validation: Dictionary = ValidatorPortScript.validate_validator(validator)
	if not bool(validation.get("success", false)):
		return validation
	var validator_id: String = String(validation["details"]["validator_id"])
	if _validators_by_id.has(validator_id):
		if _validators_by_id[validator_id] == validator:
			return TxUtilsScript.success({"validator_id": validator_id, "replay": true})
		return TxUtilsScript.failure("TRANSACTION_INVARIANT_VALIDATOR_ID_CONFLICT", {"validator_id": validator_id})
	_validators_by_id[validator_id] = validator
	return TxUtilsScript.success({"validator_id": validator_id, "replay": false})


func validate_transaction(current_aggregates: Dictionary, staged_aggregates: Dictionary, batch: Dictionary) -> Dictionary:
	if not _configured:
		return TxUtilsScript.failure("TRANSACTION_INVARIANT_REGISTRY_NOT_CONFIGURED")
	var validator_ids: Array[String] = []
	for raw_id in _validators_by_id.keys():
		validator_ids.append(String(raw_id))
	validator_ids.sort()
	for validator_id in validator_ids:
		var raw_result = _validators_by_id[validator_id].call(
			"validate_transaction",
			current_aggregates.duplicate(true),
			staged_aggregates.duplicate(true),
			batch.duplicate(true)
		)
		if typeof(raw_result) != TYPE_DICTIONARY:
			return TxUtilsScript.failure("TRANSACTION_INVARIANT_VALIDATOR_INVALID_RESULT", {"validator_id": validator_id})
		var result: Dictionary = raw_result
		if not bool(result.get("success", false)):
			return TxUtilsScript.failure("TRANSACTION_INVARIANT_REJECTED", {
				"validator_id": validator_id,
				"cause": result.duplicate(true),
			})
	return TxUtilsScript.success({"validator_count": validator_ids.size(), "validator_ids": validator_ids})


func get_registered_validator_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id in _validators_by_id.keys():
		result.append(String(raw_id))
	result.sort()
	return result
