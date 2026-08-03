extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const RegionScript = preload("res://scripts/simulation/matter/handoff/matter_authority_region.gd")

const SCHEMA: String = "planet_simulator.matter_client_handoff_ticket.v1"
const FIELDS: Array[String] = [
	"schema", "ticket_id", "transfer_id", "client_id", "body_id",
	"region_transport", "source_owner_id", "source_authority_epoch",
	"target_owner_id", "target_authority_epoch", "target_endpoint_id",
	"directory_revision", "package_checksum", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"ticket_id": String(data.get("ticket_id", "")).strip_edges().to_lower(),
		"transfer_id": String(data.get("transfer_id", "")).strip_edges().to_lower(),
		"client_id": String(data.get("client_id", "")).strip_edges().to_lower(),
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"region_transport": String(data.get("region_transport", "")),
		"source_owner_id": String(data.get("source_owner_id", "")).strip_edges().to_lower(),
		"source_authority_epoch": int(data.get("source_authority_epoch", 0)),
		"target_owner_id": String(data.get("target_owner_id", "")).strip_edges().to_lower(),
		"target_authority_epoch": int(data.get("target_authority_epoch", 0)),
		"target_endpoint_id": String(data.get("target_endpoint_id", "")).strip_edges().to_lower(),
		"directory_revision": int(data.get("directory_revision", 0)),
		"package_checksum": String(data.get("package_checksum", "")).strip_edges().to_lower(),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_CLIENT_HANDOFF_TICKET_SCHEMA")
	for field in [
		"ticket_id", "transfer_id", "client_id", "body_id", "source_owner_id",
		"target_owner_id", "target_endpoint_id",
	]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_CLIENT_HANDOFF_TICKET_ID", {"field": field})
	for field in ["source_authority_epoch", "target_authority_epoch", "directory_revision"]:
		if not MatterUtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return MatterUtilsScript.failure("INVALID_MATTER_CLIENT_HANDOFF_TICKET_INTEGER", {"field": field})
	if int(value["target_authority_epoch"]) <= int(value["source_authority_epoch"]):
		return MatterUtilsScript.failure("INVALID_MATTER_CLIENT_HANDOFF_TICKET_EPOCH")
	if not MatterUtilsScript.is_lower_hex_64(value.get("package_checksum")) \
			or typeof(value.get("region_transport")) != TYPE_STRING:
		return MatterUtilsScript.failure("INVALID_MATTER_CLIENT_HANDOFF_TICKET_PROOF")
	var region: Dictionary = decode_region(value)
	if region.is_empty() or String(region["body_id"]) != String(value["body_id"]):
		return MatterUtilsScript.failure("INVALID_MATTER_CLIENT_HANDOFF_TICKET_REGION")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_client_handoff_ticket")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func decode_region(value: Dictionary) -> Dictionary:
	var raw: Dictionary = PersistenceCodecScript.decode_persistence_json(String(value.get("region_transport", "")))
	return raw if bool(RegionScript.validate(raw).get("success", false)) else {}
