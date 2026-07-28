extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.item_move_to_container_payload.v1"
const FIELDS: Array[String] = [
	"schema",
	"session_id",
	"authority_owner_id",
	"item_id",
	"source_container_id",
	"destination_container_id",
	"expected_item_revision",
]


static func create(
	session_id: String,
	authority_owner_id: String,
	item_id: String,
	source_container_id: String,
	destination_container_id: String,
	expected_item_revision: int
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"session_id": session_id,
		"authority_owner_id": authority_owner_id,
		"item_id": item_id,
		"source_container_id": source_container_id,
		"destination_container_id": destination_container_id,
		"expected_item_revision": expected_item_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var fields_validation: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(fields_validation.get("success", false)):
		return fields_validation
	var check: Dictionary = UtilsScript.require_string(value, "schema")
	if not bool(check.get("success", false)):
		return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected item move payload schema")
	for field in ["session_id", "authority_owner_id", "item_id", "source_container_id", "destination_container_id"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
		if not _is_canonical_identifier(String(value[field])):
			return UtilsScript.validation_failure("INVALID_IDENTIFIER", "%s is not canonical" % field)
	if String(value["source_container_id"]) == String(value["destination_container_id"]):
		return UtilsScript.validation_failure("SAME_CONTAINER", "Source and destination containers must differ")
	check = UtilsScript.require_json_integer(value, "expected_item_revision")
	if not bool(check.get("success", false)):
		return check
	if int(value["expected_item_revision"]) < 0:
		return UtilsScript.validation_failure("INVALID_ITEM_REVISION", "expected_item_revision cannot be negative")
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = UtilsScript.json_round_trip(value)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}


static func _is_canonical_identifier(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges():
		return false
	for character in value:
		if not (
			(character >= "a" and character <= "z")
			or (character >= "0" and character <= "9")
			or character in ["/", "_", ".", "-"]
		):
			return false
	return true
