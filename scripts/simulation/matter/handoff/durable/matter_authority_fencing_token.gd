extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA := "planet_simulator.matter_authority_fencing_token.v1"
const FIELDS: Array[String] = [
	"schema", "region_id", "owner_id", "authority_epoch", "lease_revision",
	"transition_id", "issued_tick", "expires_at_tick", "token_hash", "checksum",
]


static func create(
	region_id: String,
	owner_id: String,
	authority_epoch: int,
	lease_revision: int,
	transition_id: String,
	issued_tick: int,
	expires_at_tick: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"region_id": region_id.strip_edges().to_lower(),
		"owner_id": owner_id.strip_edges().to_lower(),
		"authority_epoch": authority_epoch,
		"lease_revision": lease_revision,
		"transition_id": transition_id.strip_edges().to_lower(),
		"issued_tick": issued_tick,
		"expires_at_tick": expires_at_tick,
		"token_hash": "",
		"checksum": "",
	}
	value["token_hash"] = MatterUtils.payload_hash({
		"schema": SCHEMA,
		"region_id": value["region_id"],
		"owner_id": value["owner_id"],
		"authority_epoch": authority_epoch,
		"lease_revision": lease_revision,
		"transition_id": value["transition_id"],
		"issued_tick": issued_tick,
		"expires_at_tick": expires_at_tick,
	})
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_AUTHORITY_FENCING_TOKEN_SCHEMA")
	for field in ["region_id", "owner_id", "transition_id"]:
		if not MatterUtils.is_canonical_id(value.get(field), 2):
			return MatterUtils.failure("INVALID_MATTER_AUTHORITY_FENCING_TOKEN_ID", {"field": field})
	for field in ["authority_epoch", "lease_revision", "issued_tick", "expires_at_tick"]:
		if not MatterUtils.is_json_integer(value.get(field)):
			return MatterUtils.failure("INVALID_MATTER_AUTHORITY_FENCING_TOKEN_INTEGER", {"field": field})
	if int(value["authority_epoch"]) < 1 or int(value["lease_revision"]) < 1 \
		or int(value["issued_tick"]) < 0 or int(value["expires_at_tick"]) <= int(value["issued_tick"]):
		return MatterUtils.failure("INVALID_MATTER_AUTHORITY_FENCING_TOKEN_FRONTIER")
	if not MatterUtils.is_lower_hex_64(value.get("token_hash")):
		return MatterUtils.failure("INVALID_MATTER_AUTHORITY_FENCING_TOKEN_HASH")
	var expected_hash: String = MatterUtils.payload_hash({
		"schema": SCHEMA,
		"region_id": value["region_id"],
		"owner_id": value["owner_id"],
		"authority_epoch": int(value["authority_epoch"]),
		"lease_revision": int(value["lease_revision"]),
		"transition_id": value["transition_id"],
		"issued_tick": int(value["issued_tick"]),
		"expires_at_tick": int(value["expires_at_tick"]),
	})
	if String(value["token_hash"]) != expected_hash:
		return MatterUtils.failure("MATTER_AUTHORITY_FENCING_TOKEN_HASH_MISMATCH")
	return MatterUtils.validate_checksum(value)
