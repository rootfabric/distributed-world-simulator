extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const SubscriptionScript = preload("res://scripts/simulation/matter/interest/matter_interest_subscription.gd")

const SCHEMA: String = "planet_simulator.matter_interest_sync_request.v1"
const FIELDS: Array[String] = [
	"schema", "client_id", "session_id", "authority_epoch",
	"subscription_transport", "known_region_sequence",
	"known_projection_hash", "checksum",
]


static func create(
	client_id: String,
	session_id: String,
	authority_epoch: int,
	subscription: Dictionary,
	known_region_sequence: int,
	known_projection_hash: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"client_id": client_id.strip_edges().to_lower(),
		"session_id": session_id.strip_edges().to_lower(),
		"authority_epoch": authority_epoch,
		"subscription_transport": PersistenceCodecScript.encode_persistence_json(subscription),
		"known_region_sequence": known_region_sequence,
		"known_projection_hash": known_projection_hash,
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_INTEREST_SYNC_SCHEMA")
	for field in ["client_id", "session_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SYNC_ID", {"field": field})
	if not MatterUtilsScript.is_json_integer(value.get("authority_epoch")) \
			or int(value["authority_epoch"]) < 1 \
			or not MatterUtilsScript.is_json_integer(value.get("known_region_sequence")) \
			or int(value["known_region_sequence"]) < 0:
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SYNC_SEQUENCE")
	if typeof(value.get("subscription_transport")) != TYPE_STRING \
			or String(value["subscription_transport"]).is_empty() \
			or not MatterUtilsScript.is_lower_hex_64(value.get("known_projection_hash")):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SYNC_TRANSPORT")
	var subscription: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(value["subscription_transport"])
	)
	if not bool(SubscriptionScript.validate(subscription).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SYNC_SUBSCRIPTION")
	if String(subscription["client_id"]) != String(value["client_id"]) \
			or int(subscription["authority_epoch"]) != int(value["authority_epoch"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_SYNC_BINDING_MISMATCH")
	return MatterUtilsScript.validate_checksum(value)


static func decode_subscription(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	return PersistenceCodecScript.decode_persistence_json(String(value["subscription_transport"]))
