extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const SubscriptionScript = preload("res://scripts/simulation/matter/interest/matter_interest_subscription.gd")
const BrickSnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")

const SCHEMA: String = "planet_simulator.matter_interest_snapshot.v1"
const FIELDS: Array[String] = [
	"schema", "body_id", "body_definition_hash", "grid_profile_hash",
	"authority_owner_id", "authority_epoch", "subscription_transport",
	"interest_revision", "region_sequence", "source_global_stream_sequence",
	"snapshot_transports", "persistent_snapshot_count", "projection_hash", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"body_definition_hash": String(data.get("body_definition_hash", "")),
		"grid_profile_hash": String(data.get("grid_profile_hash", "")),
		"authority_owner_id": String(data.get("authority_owner_id", "")).strip_edges().to_lower(),
		"authority_epoch": int(data.get("authority_epoch", 0)),
		"subscription_transport": String(data.get("subscription_transport", "")),
		"interest_revision": int(data.get("interest_revision", 0)),
		"region_sequence": int(data.get("region_sequence", -1)),
		"source_global_stream_sequence": int(data.get("source_global_stream_sequence", -1)),
		"snapshot_transports": Array(data.get("snapshot_transports", [])).duplicate(),
		"persistent_snapshot_count": int(data.get("persistent_snapshot_count", -1)),
		"projection_hash": String(data.get("projection_hash", "")),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_INTEREST_SNAPSHOT_SCHEMA")
	for field in ["body_id", "authority_owner_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SNAPSHOT_ID", {"field": field})
	for field in ["body_definition_hash", "grid_profile_hash", "projection_hash"]:
		if not MatterUtilsScript.is_lower_hex_64(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SNAPSHOT_HASH", {"field": field})
	for field in ["authority_epoch", "interest_revision", "region_sequence", "source_global_stream_sequence", "persistent_snapshot_count"]:
		if not MatterUtilsScript.is_json_integer(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SNAPSHOT_INTEGER", {"field": field})
	if int(value["authority_epoch"]) < 1 or int(value["interest_revision"]) < 1 \
			or int(value["region_sequence"]) < 0 \
			or int(value["source_global_stream_sequence"]) < 0 \
			or int(value["persistent_snapshot_count"]) < 0:
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SNAPSHOT_SEQUENCE")
	if typeof(value.get("subscription_transport")) != TYPE_STRING \
			or String(value["subscription_transport"]).is_empty() \
			or typeof(value.get("snapshot_transports")) != TYPE_ARRAY:
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SNAPSHOT_TRANSPORT")
	var subscription: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(value["subscription_transport"])
	)
	if not bool(SubscriptionScript.validate(subscription).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SNAPSHOT_SUBSCRIPTION")
	if int(subscription["authority_epoch"]) != int(value["authority_epoch"]) \
			or int(subscription["interest_revision"]) != int(value["interest_revision"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_SNAPSHOT_SUBSCRIPTION_MISMATCH")
	if value["snapshot_transports"].size() != int(value["persistent_snapshot_count"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_SNAPSHOT_COUNT_MISMATCH")
	var previous_address_id: String = ""
	for index in range(value["snapshot_transports"].size()):
		var raw_transport = value["snapshot_transports"][index]
		if typeof(raw_transport) != TYPE_STRING or String(raw_transport).is_empty():
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_BRICK_TRANSPORT", {"index": index})
		var raw_snapshot: Dictionary = PersistenceCodecScript.decode_persistence_json(String(raw_transport))
		var snapshot: Dictionary = PersistenceCodecScript.rehydrate_snapshot(raw_snapshot)
		if snapshot.is_empty() or not bool(BrickSnapshotScript.validate(snapshot).get("success", false)) \
				or int(snapshot["state_revision"]) < 1:
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_BRICK", {"index": index})
		var address_id: String = String(snapshot["address"]["address_id"])
		if not previous_address_id.is_empty() and address_id <= previous_address_id:
			return MatterUtilsScript.failure("MATTER_INTEREST_SNAPSHOT_BRICKS_NOT_SORTED")
		previous_address_id = address_id
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_interest_snapshot")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func decode_subscription(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	return PersistenceCodecScript.decode_persistence_json(String(value["subscription_transport"]))
