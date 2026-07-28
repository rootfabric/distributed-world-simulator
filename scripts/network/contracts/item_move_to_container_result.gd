extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.item_move_to_container_result.v1"
const COMMAND_TYPE: String = "item.move_to_container"
const FIELDS: Array[String] = [
	"schema",
	"command_type",
	"entity_id",
	"item_id",
	"source_container_id",
	"destination_container_id",
	"result_item_revision",
	"delta_id",
	"result_snapshot_checksum",
	"server_tick",
	"mutation_committed",
]


static func create(
	entity_id: String,
	item_id: String,
	source_container_id: String,
	destination_container_id: String,
	result_item_revision: int,
	delta_id: String,
	result_snapshot_checksum: String,
	server_tick: int
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"command_type": COMMAND_TYPE,
		"entity_id": entity_id,
		"item_id": item_id,
		"source_container_id": source_container_id,
		"destination_container_id": destination_container_id,
		"result_item_revision": result_item_revision,
		"delta_id": delta_id,
		"result_snapshot_checksum": result_snapshot_checksum,
		"server_tick": server_tick,
		"mutation_committed": true,
	}


static func validate(value: Dictionary) -> Dictionary:
	var fields_validation: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(fields_validation.get("success", false)):
		return fields_validation
	for field in [
		"schema", "command_type", "entity_id", "item_id", "source_container_id",
		"destination_container_id", "delta_id", "result_snapshot_checksum",
	]:
		var check: Dictionary = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected item move result schema")
	if String(value["command_type"]) != COMMAND_TYPE:
		return UtilsScript.validation_failure("COMMAND_TYPE_MISMATCH", "Unexpected item move result command type")
	for field in ["entity_id", "item_id", "source_container_id", "destination_container_id", "delta_id"]:
		if not _is_canonical_identifier(String(value[field])):
			return UtilsScript.validation_failure("INVALID_IDENTIFIER", "%s is not canonical" % field)
	if String(value["source_container_id"]) == String(value["destination_container_id"]):
		return UtilsScript.validation_failure("SAME_CONTAINER", "Source and destination containers must differ")
	for field in ["result_item_revision", "server_tick"]:
		var check: Dictionary = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
		if int(value[field]) < 0:
			return UtilsScript.validation_failure("INVALID_COUNTER", "%s cannot be negative" % field)
	var bool_check: Dictionary = UtilsScript.require_boolean(value, "mutation_committed")
	if not bool(bool_check.get("success", false)):
		return bool_check
	if not bool(value["mutation_committed"]):
		return UtilsScript.validation_failure("MUTATION_NOT_COMMITTED", "Successful result must describe a committed mutation")
	if not _is_lower_hex_64(String(value["result_snapshot_checksum"])):
		return UtilsScript.validation_failure("INVALID_CHECKSUM", "result_snapshot_checksum must be lowercase SHA-256")
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


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


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if not ((character >= "0" and character <= "9") or (character >= "a" and character <= "f")):
			return false
	return true
