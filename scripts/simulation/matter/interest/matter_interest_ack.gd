extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA: String = "planet_simulator.matter_interest_ack.v1"
const FIELDS: Array[String] = [
	"schema", "client_id", "session_id", "authority_epoch",
	"subscription_id", "interest_revision", "acknowledged_region_sequence",
	"projection_hash", "checksum",
]


static func create(
	client_id: String,
	session_id: String,
	authority_epoch: int,
	subscription_id: String,
	interest_revision: int,
	acknowledged_region_sequence: int,
	projection_hash: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"client_id": client_id.strip_edges().to_lower(),
		"session_id": session_id.strip_edges().to_lower(),
		"authority_epoch": authority_epoch,
		"subscription_id": subscription_id.strip_edges().to_lower(),
		"interest_revision": interest_revision,
		"acknowledged_region_sequence": acknowledged_region_sequence,
		"projection_hash": projection_hash,
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_INTEREST_ACK_SCHEMA")
	for field in ["client_id", "session_id", "subscription_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_ACK_ID", {"field": field})
	for field in ["authority_epoch", "interest_revision", "acknowledged_region_sequence"]:
		if not MatterUtilsScript.is_json_integer(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_ACK_INTEGER", {"field": field})
	if int(value["authority_epoch"]) < 1 or int(value["interest_revision"]) < 1 \
			or int(value["acknowledged_region_sequence"]) < 0:
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_ACK_SEQUENCE")
	if not MatterUtilsScript.is_lower_hex_64(value.get("projection_hash")):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_ACK_HASH")
	return MatterUtilsScript.validate_checksum(value)
