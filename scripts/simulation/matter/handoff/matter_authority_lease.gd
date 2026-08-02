extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const RegionScript = preload("res://scripts/simulation/matter/handoff/matter_authority_region.gd")

const SCHEMA: String = "planet_simulator.matter_authority_lease.v1"
const STATUSES: Array[String] = ["ACTIVE", "PREPARING"]
const FIELDS: Array[String] = [
	"schema", "region_transport", "owner_id", "authority_epoch", "lease_revision",
	"status", "transfer_id", "target_owner_id", "target_authority_epoch",
	"prepared_package_checksum", "prepared_state_hash", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"region_transport": String(data.get("region_transport", "")),
		"owner_id": String(data.get("owner_id", "")).strip_edges().to_lower(),
		"authority_epoch": int(data.get("authority_epoch", 0)),
		"lease_revision": int(data.get("lease_revision", 0)),
		"status": String(data.get("status", "")).strip_edges().to_upper(),
		"transfer_id": String(data.get("transfer_id", "")).strip_edges().to_lower(),
		"target_owner_id": String(data.get("target_owner_id", "")).strip_edges().to_lower(),
		"target_authority_epoch": int(data.get("target_authority_epoch", 0)),
		"prepared_package_checksum": String(data.get("prepared_package_checksum", "")).strip_edges().to_lower(),
		"prepared_state_hash": String(data.get("prepared_state_hash", "")).strip_edges().to_lower(),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_AUTHORITY_LEASE_SCHEMA")
	if typeof(value.get("region_transport")) != TYPE_STRING or String(value["region_transport"]).is_empty():
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_LEASE_REGION_TRANSPORT")
	var region_raw: Dictionary = PersistenceCodecScript.decode_persistence_json(String(value["region_transport"]))
	if not bool(RegionScript.validate(region_raw).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_LEASE_REGION")
	if not MatterUtilsScript.is_canonical_id(value.get("owner_id"), 2):
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_LEASE_OWNER")
	for field in ["authority_epoch", "lease_revision", "target_authority_epoch"]:
		if not MatterUtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_LEASE_INTEGER", {"field": field})
	if int(value["authority_epoch"]) < 1 or int(value["lease_revision"]) < 1:
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_LEASE_REVISION")
	if not String(value.get("status", "")) in STATUSES:
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_LEASE_STATUS")
	if String(value["status"]) == "ACTIVE":
		if not String(value["transfer_id"]).is_empty() \
				or not String(value["target_owner_id"]).is_empty() \
				or int(value["target_authority_epoch"]) != 0 \
				or not String(value["prepared_package_checksum"]).is_empty() \
				or not String(value["prepared_state_hash"]).is_empty():
			return MatterUtilsScript.failure("ACTIVE_MATTER_AUTHORITY_LEASE_HAS_HANDOFF_STATE")
	else:
		if not MatterUtilsScript.is_canonical_id(value.get("transfer_id"), 2) \
				or not MatterUtilsScript.is_canonical_id(value.get("target_owner_id"), 2) \
				or int(value["target_authority_epoch"]) <= int(value["authority_epoch"]):
			return MatterUtilsScript.failure("INVALID_PREPARING_MATTER_AUTHORITY_LEASE")
		var package_checksum: String = String(value["prepared_package_checksum"])
		var state_hash: String = String(value["prepared_state_hash"])
		if not package_checksum.is_empty() and not MatterUtilsScript.is_lower_hex_64(package_checksum):
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_PACKAGE_CHECKSUM")
		if not state_hash.is_empty() and not MatterUtilsScript.is_lower_hex_64(state_hash):
			return MatterUtilsScript.failure("INVALID_MATTER_HANDOFF_PREPARED_STATE_HASH")
		if package_checksum.is_empty() != state_hash.is_empty():
			return MatterUtilsScript.failure("INCOMPLETE_MATTER_HANDOFF_PREPARED_PROOF")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_authority_lease")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func decode_region(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	return PersistenceCodecScript.decode_persistence_json(String(value["region_transport"]))
