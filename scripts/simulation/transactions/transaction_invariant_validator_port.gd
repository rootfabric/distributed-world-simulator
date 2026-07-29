extends RefCounted

const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")

const REQUIRED_METHODS: Array[String] = ["get_validator_id", "validate_transaction"]


static func validate_validator(validator) -> Dictionary:
	if validator == null:
		return TxUtilsScript.failure("TRANSACTION_INVARIANT_VALIDATOR_REQUIRED")
	for method_name in REQUIRED_METHODS:
		if not validator.has_method(method_name):
			return TxUtilsScript.failure("TRANSACTION_INVARIANT_VALIDATOR_METHOD_MISSING", {"method": method_name})
	var validator_id = validator.call("get_validator_id")
	if typeof(validator_id) != TYPE_STRING or not TxUtilsScript.is_identifier(String(validator_id), "validator/"):
		return TxUtilsScript.failure("INVALID_TRANSACTION_INVARIANT_VALIDATOR_ID")
	return TxUtilsScript.success({"validator_id": String(validator_id)})
