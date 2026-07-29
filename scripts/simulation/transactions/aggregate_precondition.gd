extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")

const SCHEMA: String = "planet_simulator.aggregate_precondition.v1"
const FIELDS: Array[String] = [
	"schema", "aggregate_id", "aggregate_kind", "state_schema", "expected_exists",
	"expected_authority_owner_id", "expected_authority_epoch", "expected_revision",
]


static func create(
	aggregate_id: String,
	aggregate_kind: String,
	state_schema: String,
	expected_exists: bool,
	expected_authority_owner_id: String,
	expected_authority_epoch: int,
	expected_revision: int
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"aggregate_id": aggregate_id,
		"aggregate_kind": aggregate_kind,
		"state_schema": state_schema,
		"expected_exists": expected_exists,
		"expected_authority_owner_id": expected_authority_owner_id,
		"expected_authority_epoch": expected_authority_epoch,
		"expected_revision": expected_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return TxUtilsScript.failure("UNSUPPORTED_AGGREGATE_PRECONDITION_SCHEMA")
	if not TxUtilsScript.is_identifier(String(value.get("aggregate_id", "")), "aggregate/"):
		return TxUtilsScript.failure("INVALID_PRECONDITION_AGGREGATE_ID")
	if not TxUtilsScript.is_upper_kind(String(value.get("aggregate_kind", ""))):
		return TxUtilsScript.failure("INVALID_PRECONDITION_AGGREGATE_KIND")
	if not TxUtilsScript.is_versioned_schema(String(value.get("state_schema", ""))):
		return TxUtilsScript.failure("INVALID_PRECONDITION_STATE_SCHEMA")
	if typeof(value.get("expected_exists")) != TYPE_BOOL:
		return TxUtilsScript.failure("INVALID_PRECONDITION_EXISTS_FLAG")
	for field in ["expected_authority_epoch", "expected_revision"]:
		if not UtilsScript.is_json_integer(value.get(field)):
			return TxUtilsScript.failure("INVALID_PRECONDITION_INTEGER", {"field": field})
	if bool(value["expected_exists"]):
		if not TxUtilsScript.is_identifier(String(value.get("expected_authority_owner_id", ""))):
			return TxUtilsScript.failure("INVALID_PRECONDITION_AUTHORITY_OWNER")
		if int(value["expected_authority_epoch"]) < 1 or int(value["expected_revision"]) < 0:
			return TxUtilsScript.failure("INVALID_EXISTING_AGGREGATE_PRECONDITION")
	else:
		if String(value.get("expected_authority_owner_id", "")) != "" or int(value["expected_authority_epoch"]) != 0 or int(value["expected_revision"]) != -1:
			return TxUtilsScript.failure("INVALID_ABSENT_AGGREGATE_PRECONDITION")
	return TxUtilsScript.success()
