extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "distributed_world_simulator.user1_product_seam_state.v1"
const MESSAGE_TYPE := "PRODUCT_SEAM_STATE"
const FIELDS: Array[String] = [
	"schema",
	"logical_player_id",
	"active_authority_id",
	"authority_epoch",
	"region_id",
	"transfer_state",
	"crossings",
	"secondary_entries",
	"roundtrips",
	"last_transfer_id",
	"canonical_state_owned",
	"decision_owner",
	"item_graph_owner",
]


static func create(values: Dictionary) -> Dictionary:
	return {
		"schema": SCHEMA,
		"logical_player_id": String(values.get("logical_player_id", "")).strip_edges().to_lower(),
		"active_authority_id": String(values.get("active_authority_id", "")).strip_edges(),
		"authority_epoch": int(values.get("authority_epoch", 0)),
		"region_id": String(values.get("region_id", "")).strip_edges().to_lower(),
		"transfer_state": String(values.get("transfer_state", "")).strip_edges().to_upper(),
		"crossings": int(values.get("crossings", 0)),
		"secondary_entries": int(values.get("secondary_entries", 0)),
		"roundtrips": int(values.get("roundtrips", 0)),
		"last_transfer_id": String(values.get("last_transfer_id", "")).strip_edges().to_lower(),
		"canonical_state_owned": false,
		"decision_owner": "SM1_AUTHORITY_TRANSFER_COORDINATOR",
		"item_graph_owner": "PRIMARY_PRODUCT_M4",
	}


static func validate(value: Dictionary) -> Dictionary:
	var actual: Array[String] = []
	for key_value in value.keys():
		actual.append(String(key_value))
	actual.sort()
	var expected := FIELDS.duplicate()
	expected.sort()
	if actual != expected:
		return _failure("USER1_SEAM_STATE_FIELD_SET_MISMATCH")
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("USER1_SEAM_STATE_SCHEMA_MISMATCH")
	var player_id := String(value.get("logical_player_id", ""))
	var authority_id := String(value.get("active_authority_id", ""))
	var region_id := String(value.get("region_id", ""))
	var transfer_state := String(value.get("transfer_state", ""))
	if (
		player_id.is_empty()
		or player_id != player_id.strip_edges().to_lower()
		or authority_id.strip_edges().is_empty()
		or region_id not in ["region/user1/a", "region/user1/b"]
		or transfer_state not in [
			"ACTIVE",
			"SOURCE_FROZEN",
			"TARGET_WARM_VALIDATED",
			"OWNERSHIP_COMMITTED",
			"SOURCE_RETIRED",
		]
	):
		return _failure("USER1_SEAM_STATE_IDENTITY_INVALID")
	for field in ["authority_epoch", "crossings", "secondary_entries", "roundtrips"]:
		var raw = value.get(field)
		if (
			typeof(raw) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(raw))
			or float(raw) != floorf(float(raw))
			or int(raw) < (1 if field == "authority_epoch" else 0)
		):
			return _failure("USER1_SEAM_STATE_COUNTER_INVALID", {"field": field})
	if int(value.get("secondary_entries", 0)) > int(value.get("crossings", 0)):
		return _failure("USER1_SEAM_STATE_COUNTER_ORDER_INVALID")
	if int(value.get("roundtrips", 0)) > int(value.get("secondary_entries", 0)):
		return _failure("USER1_SEAM_STATE_ROUNDTRIP_ORDER_INVALID")
	if bool(value.get("canonical_state_owned", true)):
		return _failure("USER1_SEAM_STATE_PRIVATE_TRUTH_FORBIDDEN")
	if String(value.get("decision_owner", "")) != "SM1_AUTHORITY_TRANSFER_COORDINATOR":
		return _failure("USER1_SEAM_STATE_DECISION_OWNER_INVALID")
	if String(value.get("item_graph_owner", "")) != "PRIMARY_PRODUCT_M4":
		return _failure("USER1_SEAM_STATE_ITEM_OWNER_INVALID")
	var safe := Utils.canonicalize(value, "$.user1_product_seam_state")
	if not bool(safe.get("success", false)):
		return _failure("USER1_SEAM_STATE_NOT_JSON_SAFE")
	return _success()


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
